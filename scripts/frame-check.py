#!/usr/bin/env python3
"""Pixel check of a screen recording of the demo app: counts the frames on which the chart shows something wrong.

The invariants of the rendering code (`ChartDiagnostics`, `-diag`) look at the model, not at what is on the screen, so a
frame on which the chart is blank, shifted or half-drawn passes them. This script looks at the pixels of every frame of a
video of the simulator (`xcrun simctl io recordVideo` writes a frame at every change of the screen).

Checks, per frame, on the main pane (and on the Volume pane under it when there is one):

  empty    (a) the plot has (almost) no candle pixels: it is blank where it has to show bars;
  clip     (b) candles, bands or lines touch the top or the bottom border of the plot (within 2 pt): what is drawn is cut off
           by the edge of the pane, which the autoscale never does: the data left its domain, or the chart is displaced;
  label    (c) the tip of the wick of the highest / lowest candle is not where the line of its price label is (more than
           2.7 pt apart). The labels are drawn by the package at the exact position of the autoscale, the wicks are the chart's:
           when they disagree the picture and the autoscale of this frame are not the same (a vertical jump);
  desync   (d) the bars of the Volume pane are not under the candles of the main pane (coloured by the same rule): the panes
           show different windows.

and over the whole recording

  settle   how long the picture takes to come to rest after a motion (frames and milliseconds from the last visible motion to
           the last change at all), and the isolated changes of a picture that is otherwise at rest ("blips": a relayout that
           moves something, a flash).

A frame is "bad" if any of (a)..(d) fires. The simulator writes several frames within one refresh of the display; what the
display shows is the last of them, so the report gives the count of bad frames among those that are on the screen at 60 Hz
as well as among all of them.

Usage:

  scripts/frame-check.py analyze VIDEO [--after SECONDS] [--json OUT.json] [--dump DIR]
  scripts/frame-check.py scenario NAME [--udid UDID] [--out DIR]      record a scripted run of the demo and analyze it
  (NAME: fling, slow, history, trim, zoom, drawings)

`scenario` launches the installed demo (`io.github.pavellunev.TradingChartDemo`; build and install it first) with the arguments
of the named scenario (see SCENARIOS), records the simulator and analyzes the video. It records the booted simulator; with more than
one booted give `--udid` (or set UDID). `analyze` takes any recording of the same
layout (the demo on an iPhone 16 with SMA, Bollinger Bands, Volume, RSI and MACD on, markers off: `-no-markers`), for instance
one made while an XCUITest swipes the chart. Needs ffmpeg, ffprobe and numpy (PIL only for `--dump`).
Exit code 0 when no frame is bad, 1 when a frame is bad, 2 when the check could not be made: a failed `simctl` or `ffmpeg`, a
recording with no frame, or no frame that shows the chart (a check that looked at nothing is not a pass).
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

BUNDLE_ID = "io.github.pavellunev.TradingChartDemo"
DEFAULT_UDID = "booted"

# Where the panes are in a screenshot of the demo on an iPhone 16 (1179 x 2556 px) with SMA, Bollinger Bands, Volume, RSI and MACD
# on: x0, y0, x1, y1 of the plot, without the legend row above it and the column of price labels to the right of it. Measured
# from the accessibility frames of the demo's compact layout (points x 3): the main plot is 8, 113 pt, 317 x 368 pt, the
# Volume plot 8, 499.3 pt, 317 x 72.7 pt. Another layout needs `--main` and `--volume`.
MAIN_PLOT = (24, 339, 975, 1443)
VOLUME_PLOT = (24, 1498, 975, 1716)

DISPLAY_HZ = 60
PX_PER_PT = 3

COMMON_ARGS = ["-no-ticks", "-no-restore", "-no-markers"]
INDICATORS = "0:hasmore=off;0:indicators=sma20,bb,volume,rsi,macd"

# Scripted scenarios: demo launch arguments, how long to record and from how long after the chart first shows candles the
# frames count (the set-up of the scenario, the indicators appearing, is not part of it), in seconds.
SCENARIOS: dict[str, dict] = {
    # A hard fling to the past and back (5.6 window widths a second), 600 bars: the scenarios of Docs/Performance.md.
    "fling": {
        "args": COMMON_ARGS + ["-script", INDICATORS + ";0:series=600;2:stress=5"],
        "seconds": 9,
        "after": 1.9,
    },
    # A slow scroll: 400 bars out and back in 16 s.
    "slow": {
        "args": COMMON_ARGS + ["-script", INDICATORS + ";0:series=600;2:stress=16,400"],
        "seconds": 20,
        "after": 1.9,
    },
    # Flings into the history with 5 pages of 300 bars loading on the way (0.6 s each): ten flings of about 250 bars.
    "history": {
        "args": ["-no-ticks", "-no-restore", "-no-markers", "-script",
                 "0:indicators=sma20,bb,volume,rsi,macd;" + ";".join(f"{2 + 2 * i}:fling=500" for i in range(10))],
        "seconds": 25,
        "after": 1.9,
    },
    # Scrolling in the history while live bars arrive and the head of the series is trimmed (`-max-live 300`).
    "trim": {
        "args": ["-no-ticks", "-no-restore", "-no-markers", "-max-live", "300", "-script",
                 INDICATORS + ";0:series=600;1:back=120;2:stress=10,200,bg;3:append=5;5:append=5;7:append=5;9:append=5"],
        "seconds": 14,
        "after": 0.9,
    },
    # The hard fling of "fling" with ten drawings spread over the series (a trend line, a ray and a horizontal line each in turn):
    # they come into view and leave it, drawn by the overlay while the charts scroll. The drawings are indigo, so they are not
    # ink for the checks (they must not be taken for candles or lines) and must not break any of them.
    "drawings": {
        "args": COMMON_ARGS + ["-script", INDICATORS + ";0:series=600;0.5:scatter=10;2:stress=5"],
        "seconds": 9,
        "after": 1.9,
    },
    # Zoom in and out while scrolled into the history.
    "zoom": {
        "args": COMMON_ARGS + ["-script",
                               INDICATORS + ";0:series=600;1:back=150;2:zoom=2;3:back=40;4:zoom=0.5;5:back=40;6:zoom=2.5;"
                                            "7:back=30;8:zoom=0.4;9:back=30;10:live"],
        "seconds": 12,
        "after": 0.9,
    },
}

CARD_COLOR = np.array([242, 242, 247], dtype=np.int16)  # secondarySystemBackground: the card behind the chart
EXTREME_LABEL_GRAY = np.array([133, 133, 139], dtype=np.int16)  # `theme.extremeLabel` over the card
CONNECTOR_MIN_RUN = 26  # px: the short line of a high / low label is 12 pt (36 px) long


@dataclass
class Thresholds:
    empty_fraction: float = 0.2  # candle pixels below this share of the median of the run: empty
    empty_min_px: int = 250  # ... or below this many pixels
    clip_band_px: int = 2 * PX_PER_PT  # ink within this many px of the top or bottom border of the plot: cut off
    clip_min_ink: int = 4  # ... at least this many ink pixels in the band
    label_px: int = 9  # a wick tip farther than this from the line of its label: displaced (2.7 pt)
    sync: float = 0.55  # correlation of the candle colours of the main pane with the bars of the Volume pane
    motion_diff: float = 2.0  # mean change of a pixel (0..255) between two frames that counts as visible motion
    change_diff: float = 0.15  # ... as any change at all
    quiet_seconds: float = 0.15  # no change for this long: the picture is at rest


@dataclass
class FrameResult:
    index: int
    time: float
    candle_px: int = 0
    card: float = 0.0
    clip_px: int = 0
    labels: list[int] = field(default_factory=list)
    sync: float | None = None
    diff: float = 0.0
    flags: list[str] = field(default_factory=list)


class CheckError(Exception):
    """The check could not be made (as opposed to the check finding bad frames)."""


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, check=True, capture_output=True, text=True, **kwargs)
    except FileNotFoundError as error:
        raise CheckError(f"{cmd[0]} is not installed ({error})") from error
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or "").strip()
        raise CheckError(f"{' '.join(cmd[:4])} failed with exit {error.returncode}: {detail}") from error


def video_times(path: Path) -> list[float]:
    """The presentation time of every frame, in seconds."""
    out = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "frame=pts_time",
               "-of", "csv=p=0", str(path)]).stdout.split()
    return [float(t.strip(",")) for t in out if t.strip(",")]


def classify(region: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Masks of green, red, all coloured pixels (candles, Bollinger Bands, moving averages) and the strongly coloured ones
    (candles and lines, not the pale fill of a band).

    Grey (grid, labels, spinner) and the blue of the price badge and the price line are not ink.
    """
    r = region[..., 0].astype(np.int16)
    g = region[..., 1].astype(np.int16)
    b = region[..., 2].astype(np.int16)
    green = (g > r + 60) & (g > b + 40)
    red = (r > g + 130) & (r > b + 120)
    top = np.maximum(np.maximum(r, g), b)
    spread = top - np.minimum(np.minimum(r, g), b)
    coloured = spread > 22
    # Hue in degrees, only where it is needed.
    hue = np.zeros(spread.shape, dtype=np.float32)
    ys, xs = np.nonzero(coloured)
    rr, gg, bb, dd, tt = r[ys, xs], g[ys, xs], b[ys, xs], spread[ys, xs].astype(np.float32), top[ys, xs]
    h = np.where(tt == rr, ((gg - bb) / dd) % 6, np.where(tt == gg, (bb - rr) / dd + 2, (rr - gg) / dd + 4)) * 60
    hue[ys, xs] = h
    blue = (hue > 150) & (hue < 255)
    ink = (coloured & ~blue) | green | red
    return green, red, ink, ink & ((spread > 60) | green | red)


def label_offsets(main: np.ndarray, green: np.ndarray, red: np.ndarray) -> list[int]:
    """How far the tip of a candle's wick is from the line of its high / low label, in px, for every label found.

    The labels (the highest and the lowest price of the window) and their short lines are drawn by the package over the chart
    at the exact position of the autoscale; the wicks are the chart's. When both agree the wick ends where the line is.
    A label whose line has no wick at either end (hidden by the badge, say) is skipped.
    """
    near = np.abs(main.astype(np.int16) - EXTREME_LABEL_GRAY).sum(axis=2) < 45
    csum = np.pad(np.cumsum(near, axis=1, dtype=np.int32), ((0, 0), (1, 0)))
    window = csum[:, CONNECTOR_MIN_RUN:] - csum[:, :-CONNECTOR_MIN_RUN] == CONNECTOR_MIN_RUN
    rows = np.flatnonzero(window.any(axis=1))
    offsets: list[int] = []
    if rows.size == 0:
        return offsets
    candle = green | red
    for group in np.split(rows, np.nonzero(np.diff(rows) > 1)[0] + 1):
        if group.size > 6:  # not a line: a block of grey (text, a filled area)
            continue
        y = int(group.mean())
        columns = np.flatnonzero(window[group].any(axis=0))
        left = int(columns.min())
        right = int(columns.max()) + CONNECTOR_MIN_RUN - 1
        for end in (left, right):
            lo, hi = max(end - 4, 0), min(end + 5, main.shape[1])
            band = candle[:, lo:hi].any(axis=1)
            top, bottom = max(y - 8, 0), min(y + 9, main.shape[0])
            touching = np.flatnonzero(band[top:bottom])
            if touching.size == 0:
                continue  # no wick at this end
            # The vertical run of wick pixels that contains the row nearest to the line.
            row = top + int(touching[np.abs(top + touching - y).argmin()])
            first = row
            while first > 0 and band[first - 1]:
                first -= 1
            last = row
            while last < len(band) - 1 and band[last + 1]:
                last += 1
            if first < y - 8 and last > y + 8:
                continue  # a wick running through the line: not its tip
            # The wick hangs below the line of the high and rises above the line of the low.
            offsets.append(first - y if (y - first) < (last - y) else last - y)
            break
    return offsets


def column_signal(green: np.ndarray, red: np.ndarray, rows: int) -> np.ndarray:
    """+1 for a column with green pixels, -1 with red ones (at least `rows` of them), 0 without."""
    g = green.sum(axis=0) >= rows
    r = red.sum(axis=0) >= rows
    return g.astype(np.float32) - r.astype(np.float32)


def analyze_frame(rgb: np.ndarray, origin: tuple[int, int], thresholds: Thresholds, has_volume: bool) -> FrameResult:
    mx0, my0, mx1, my1 = MAIN_PLOT
    ox, oy = origin
    main = rgb[my0 - oy:my1 - oy, mx0 - ox:mx1 - ox]
    green, red, _, strong = classify(main)
    result = FrameResult(0, 0.0)
    result.candle_px = int(green.sum() + red.sum())
    result.card = float((np.abs(main.astype(np.int16) - CARD_COLOR).sum(axis=2) < 10).mean())
    band = thresholds.clip_band_px
    result.clip_px = int(strong[:band].sum() + strong[-band:].sum())
    result.labels = label_offsets(main, green, red)
    if has_volume and result.candle_px > 0:
        vx0, vy0, vx1, vy1 = VOLUME_PLOT
        volume = rgb[vy0 - oy:vy1 - oy, vx0 - ox:vx1 - ox]
        vgreen, vred, _, _ = classify(volume)
        a = column_signal(green, red, 3)
        b = column_signal(vgreen, vred, 1)
        denominator = np.linalg.norm(a) * np.linalg.norm(b)
        if denominator > 0:
            result.sync = float(np.dot(a, b) / denominator)
        else:
            result.sync = 1.0 if np.linalg.norm(a) == 0 and np.linalg.norm(b) == 0 else 0.0
    return result


def signature(rgb: np.ndarray, origin: tuple[int, int]) -> np.ndarray:
    """The main plot as a coarse grey picture, to measure how much it changes between two frames."""
    mx0, my0, mx1, my1 = MAIN_PLOT
    ox, oy = origin
    main = rgb[my0 - oy:my1 - oy, mx0 - ox:mx1 - ox].astype(np.float32).mean(axis=2)
    h, w = main.shape
    return main[:h // 4 * 4, :w // 4 * 4].reshape(h // 4, 4, w // 4, 4).mean(axis=(1, 3))


def settle_report(live: list[FrameResult], thresholds: Thresholds) -> dict:
    """How the picture comes to rest after a motion, and the isolated changes of a picture at rest."""
    moves = [r for r in live if r.diff > thresholds.change_diff]
    # Clusters of frames with a change, separated by a quiet time.
    clusters: list[list[FrameResult]] = []
    for r in moves:
        if clusters and r.time - clusters[-1][-1].time < thresholds.quiet_seconds:
            clusters[-1].append(r)
        else:
            clusters.append([r])
    tails: list[tuple[int, float]] = []
    blips: list[dict] = []
    for cluster in clusters:
        visible = [r for r in cluster if r.diff > thresholds.motion_diff]
        if len(visible) >= 4:
            last_motion = visible[-1]
            after = [r for r in cluster if r.time > last_motion.time]
            tails.append((len(after), (after[-1].time - last_motion.time) * 1000 if after else 0.0))
        elif visible:
            blips.append({"time": round(visible[0].time, 3), "frames": len(visible),
                          "max_diff": round(max(r.diff for r in visible), 2)})
    return {
        "motion_episodes": sum(1 for c in clusters if len([r for r in c if r.diff > thresholds.motion_diff]) >= 4),
        "settle_tail_frames_max": max((t[0] for t in tails), default=0),
        "settle_tail_ms_max": round(max((t[1] for t in tails), default=0.0), 1),
        "blips": blips,
    }


def analyze(video: Path, thresholds: Thresholds, dump: Path | None, has_volume: bool = True, after: float = 0.0) -> dict:
    times = video_times(video)
    x0, y0 = MAIN_PLOT[0], MAIN_PLOT[1]
    x1, y1 = MAIN_PLOT[2], VOLUME_PLOT[3]
    cw, ch = x1 - x0, y1 - y0
    if not video.exists() or video.stat().st_size == 0:
        raise CheckError(f"{video} does not exist or is empty")
    try:
        ffmpeg = subprocess.Popen(
            ["ffmpeg", "-v", "fatal", "-i", str(video), "-vf", f"format=rgb24,crop={cw}:{ch}:{x0}:{y0}", "-fps_mode",
             "passthrough", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
            stdout=subprocess.PIPE,
        )
    except FileNotFoundError as error:
        raise CheckError(f"ffmpeg is not installed ({error})") from error
    size = cw * ch * 3
    results: list[FrameResult] = []
    kept: dict[int, np.ndarray] = {}
    previous: np.ndarray | None = None
    assert ffmpeg.stdout is not None
    index = 0
    while True:
        raw = ffmpeg.stdout.read(size)
        if len(raw) < size:
            break
        rgb = np.frombuffer(raw, dtype=np.uint8).reshape(ch, cw, 3)
        result = analyze_frame(rgb, (x0, y0), thresholds, has_volume)
        result.index = index
        result.time = times[index] if index < len(times) else float(index)
        sig = signature(rgb, (x0, y0))
        result.diff = float(np.abs(sig - previous).mean()) if previous is not None else 0.0
        previous = sig
        results.append(result)
        if dump is not None:
            kept[index] = rgb.copy()
        index += 1
    ffmpeg.wait()
    if ffmpeg.returncode != 0:
        raise CheckError(f"ffmpeg failed with exit {ffmpeg.returncode} on {video}")
    if not results:
        raise CheckError(f"{video} has no frame")

    # The recording starts before the chart is on the screen (the home screen, the launch animation): count from the first
    # frame that shows the card of the chart with candles on it, and `after` seconds later.
    first = next((r.index for r in results if r.candle_px >= thresholds.empty_min_px and r.card >= 0.3), None)
    if first is None:
        raise CheckError(f"no frame of {video} shows the chart (the card with candles on it): wrong layout or boxes "
                         "(--main, --volume), or the app did not run")
    start = results[first].time + after
    # (and not after the app is gone: the home screen has no card)
    live = [r for r in results if r.index >= first and r.time >= start and r.card >= 0.3]
    if not live:
        raise CheckError(f"no frame of {video} is left to check after the first {after} s of the chart")
    counts = sorted(r.candle_px for r in live)
    median = counts[len(counts) // 2] if counts else 0
    for r in live:
        if r.candle_px < max(thresholds.empty_fraction * median, thresholds.empty_min_px):
            r.flags.append("empty")
            continue
        if r.clip_px >= thresholds.clip_min_ink:
            r.flags.append("clip")
        if any(abs(offset) > thresholds.label_px for offset in r.labels):
            r.flags.append("label")
        if r.sync is not None and r.sync < thresholds.sync:
            r.flags.append("desync")

    bad = [r for r in live if r.flags]
    displayed: dict[int, FrameResult] = {}
    for r in live:
        displayed[int(r.time * DISPLAY_HZ)] = r
    bad_displayed = [r for r in displayed.values() if r.flags]
    names = ("empty", "clip", "label", "desync")
    summary = {
        "video": str(video),
        "frames_total": len(results),
        "frames_checked": len(live),
        "median_candle_px": median,
        "bad_frames": len(bad),
        "by_check": {name: sum(1 for r in bad if name in r.flags) for name in names},
        "frames_displayed": len(displayed),
        "bad_displayed": len(bad_displayed),
        "label_offset_px_max": max((abs(o) for r in live for o in r.labels), default=0),
        "labels_checked": sum(len(r.labels) for r in live),
        "settle": settle_report(live, thresholds),
        "bad": [{"index": r.index, "time": round(r.time, 3), "flags": r.flags, "candle_px": r.candle_px,
                 "clip_px": r.clip_px, "labels": r.labels, "sync": None if r.sync is None else round(r.sync, 2)}
                for r in bad],
        "frames": [{"index": r.index, "time": round(r.time, 3), "candle_px": r.candle_px, "clip_px": r.clip_px,
                    "labels": r.labels, "sync": None if r.sync is None else round(r.sync, 2), "diff": round(r.diff, 3),
                    "flags": r.flags} for r in live],
    }
    if dump is not None:
        dump.mkdir(parents=True, exist_ok=True)
        from PIL import Image
        for r in bad[:60]:
            Image.fromarray(kept[r.index]).save(dump / f"bad-{r.index:04d}-{'+'.join(r.flags)}.png")
    return summary


def print_report(summary: dict) -> None:
    print(f"{summary['video']}: {summary['frames_checked']} frames checked (of {summary['frames_total']}), "
          f"median candle pixels {summary['median_candle_px']}")
    print(f"bad frames: {summary['bad_frames']}   " + "  ".join(f"{k} {v}" for k, v in summary["by_check"].items()))
    print(f"of the {summary['frames_displayed']} frames on the screen at {DISPLAY_HZ} Hz: {summary['bad_displayed']} bad")
    settle = summary["settle"]
    print(f"labels checked {summary['labels_checked']}, largest offset of a wick from its label line "
          f"{summary['label_offset_px_max']} px; {settle['motion_episodes']} motions, the picture needs at most "
          f"{settle['settle_tail_frames_max']} frames / {settle['settle_tail_ms_max']} ms after the last visible motion to come "
          f"to rest; isolated changes at rest: {len(settle['blips'])}"
          + (" " + str(settle["blips"][:5]) if settle["blips"] else ""))
    for item in summary["bad"][:40]:
        print(f"  #{item['index']:4d} t={item['time']:7.3f}s {','.join(item['flags']):14s} candles={item['candle_px']:6d} "
              f"clip={item['clip_px']:3d} labels={item['labels']} sync={item['sync']}")
    if len(summary["bad"]) > 40:
        print(f"  ... and {len(summary['bad']) - 40} more")


def record_scenario(name: str, udid: str, out: Path) -> Path:
    scenario = SCENARIOS[name]
    out.mkdir(parents=True, exist_ok=True)
    video = out / f"{name}.mp4"
    if video.exists():
        video.unlink()
    # Not running is not an error here.
    subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], capture_output=True)
    try:
        recorder = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec=h264", "--force", str(video)],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    except FileNotFoundError as error:
        raise CheckError(f"xcrun is not available ({error})") from error
    time.sleep(1.0)
    if recorder.poll() is not None:
        raise CheckError(f"simctl could not record the simulator '{udid}': {(recorder.stderr.read() or '').strip()}")
    try:
        run(["xcrun", "simctl", "launch", "--terminate-running-process", udid, BUNDLE_ID, *scenario["args"]])
        time.sleep(scenario["seconds"])
    finally:
        recorder.send_signal(signal.SIGINT)
        try:
            recorder.wait(timeout=30)
        except subprocess.TimeoutExpired:
            recorder.kill()
            recorder.wait()
        subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], capture_output=True)
    if not video.exists() or video.stat().st_size == 0:
        raise CheckError(f"simctl recorded no video to {video}")
    return video


def parse_box(text: str) -> tuple[int, int, int, int]:
    x0, y0, x1, y1 = (int(v) for v in text.split(","))
    return x0, y0, x1, y1


def main() -> int:
    global MAIN_PLOT, VOLUME_PLOT
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", type=Path, help="write the full per-frame report here")
    common.add_argument("--dump", type=Path, help="write the bad frames (the main and the Volume pane) as PNG files here")
    common.add_argument("--main", type=parse_box, default=MAIN_PLOT, help="x0,y0,x1,y1 of the main plot in px")
    common.add_argument("--volume", type=parse_box, default=VOLUME_PLOT, help="x0,y0,x1,y1 of the Volume plot in px")
    common.add_argument("--no-volume", action="store_true", help="the video has no Volume pane: skip the sync check")
    common.add_argument("--after", type=float, default=None,
                        help="seconds after the chart first shows candles from which frames count (the set-up of a scenario)")
    common.add_argument("--label-px", type=int, default=Thresholds.label_px)
    common.add_argument("--sync", type=float, default=Thresholds.sync)
    analyze_parser = sub.add_parser("analyze", parents=[common], help="analyze a video")
    analyze_parser.add_argument("video", type=Path)
    scenario_parser = sub.add_parser("scenario", parents=[common], help="record a scripted run of the demo and analyze it")
    scenario_parser.add_argument("name", choices=sorted(SCENARIOS))
    scenario_parser.add_argument("--udid", default=os.environ.get("UDID", DEFAULT_UDID))
    scenario_parser.add_argument("--out", type=Path, default=Path("frame-check-out"))
    args = parser.parse_args()

    MAIN_PLOT = args.main
    VOLUME_PLOT = args.volume
    thresholds = Thresholds(label_px=args.label_px, sync=args.sync)
    after = args.after if args.after is not None else (SCENARIOS[args.name]["after"] if args.command == "scenario" else 0.0)
    try:
        video = args.video if args.command == "analyze" else record_scenario(args.name, args.udid, args.out)
        summary = analyze(video, thresholds, args.dump, has_volume=not args.no_volume, after=after)
    except CheckError as error:
        print(f"frame-check: {error}", file=sys.stderr)
        return 2
    print_report(summary)
    if args.json:
        args.json.write_text(json.dumps(summary, indent=1))
    return 0 if summary["bad_frames"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
