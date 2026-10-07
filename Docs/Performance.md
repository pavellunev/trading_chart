# Performance

How fast TradingChart scrolls and updates, how that was measured, what was found and fixed, and where the limit is.

**Short version.** Everything the package computes itself (indicators, window maths, autoscale) costs microseconds per
scroll step and about a millisecond per live update, also with 5 000 bars. What decides the frame rate is Swift Charts and
SwiftUI: building the marks of a chart. At first every scroll step rebuilt every chart, so a main panel with Bollinger
Bands, Volume, RSI and MACD scrolled at 20 fps. Now a scroll step rebuilds nothing: the charts are built about ten times in
a hard fling (when the window nears the edge of what is built), and everything that has to follow the scroll on every frame
(price axis, autoscale, high/low labels, price line, badge) is a transform of the chart or a small `Canvas`. On the iOS 27
simulator that is **51 fps instead of 19–20 in `s2`/`s3`** (5 indicators, 600 and 5 000 bars), 26 instead of 13 fps with ten
live ticks a second (`s4`), and 57 fps with one panel (`s1`, unchanged). The 55 fps goal is **not met**: the rest is the cost
of laying out about 1 500 marks in four charts each time the window moves, which Swift Charts does not do in less than a few
frames. The price scale still follows the visible bars exactly, on every frame, as before: no steps, no animation.

## What was measured

| Layer | Tool | What it tells |
| --- | --- | --- |
| Micro-benchmarks | `Tests/TradingChartTests/PerformanceTests.swift` (XCTest `measure`, `XCTClockMetric`) | cost of the package's own work: indicators, a scroll step of the model, per-frame window computations, `update`, `prependHistory` |
| Frame times | demo app, `-perf <scenario>` (`CADisplayLink`, HUD, `Documents/perf-<scenario>.json`) | what a scrolling chart costs end to end: frames, p50/p95/p99/max, hitches, dropped frames, CPU |
| Rebuilds and consistency | the same run: `bodies` and `violations` in the JSON, `-diag` HUD for use by hand | how often the charts were rebuilt, and whether on any frame a pane showed something wrong (see [Consistency checks](#consistency-checks)) |
| Hot spots | Time Profiler (`xctrace`, attached to the demo on the simulator) | where the main thread spends its time |

The micro-benchmarks only measure: there are no baselines and no time assertions, so `scripts/verify.sh` cannot fail on
timing. The budgets below are checked by reading the numbers.

### Budgets

| Budget | Where | Result |
| --- | --- | --- |
| One scroll step of the model < 1 ms (5 000 bars, 5 indicators) | micro-benchmark `testScrollStep5000` | **met**: 0.006 ms Release, 0.060 ms Debug |
| Per-frame window computations < 1 ms (5 000 bars, 5 indicators) | micro-benchmark `testFrameWork5000` | **met**: 0.007 ms Release, 0.080 ms Debug |
| Live update `update(candle)` < 2 ms on 5 000 bars, 5 indicators | micro-benchmark `testLiveUpdate5000` | **met in Release** (1.04 ms), **not in Debug** (22.9 ms: unoptimised generics; not a shipping configuration) |
| 60 fps scrolling, 600 candles, no indicators | scenario 1 | **met**: 57 fps (a dozen hitches at the turnarounds of the sweep) |
| 55 fps scrolling, 600 and 5 000 candles + SMA, Bollinger, Volume, RSI, MACD | scenarios 2 and 3 | **not met**: 51 fps (was 19–20). The rest is the layout of the charts, see [the remaining bottleneck](#the-remaining-bottleneck) |
| 45 fps, the same with 10 live ticks a second | scenario 4 | **not met**: 26 fps (was 13) |

## Methodology

### Micro-benchmarks

`PerformanceTests` times, per iteration of `measure` (10 iterations, the table divides loops out):

* all seven indicators over 600 / 2 000 / 5 000 bars (`IndicatorInput` + `calculate`);
* a scroll step of the model on 5 000 bars with five indicators: `scrollPosition` set, then the render window, the autoscaled
  domains of the main pane and three panes, the live-edge flag and the stop timer (1 000 steps per iteration);
* a "frame" of window work on 5 000 bars: `ViewportMath.xDomain` and `yDomain`, culled slices of five indicators, the
  extremes of the window, the Y domains of three panes (1 000 frames per iteration);
* `ViewportMath.yDomain` and the slice of the visible bars alone (1 000 per iteration);
* `TradingChartModel.update(candle)` end to end with five indicators on 600 and 5 000 bars (the last bar is updated;
  50 per iteration), and the append of a new bar with the trim to `maxLiveBarCount`;
* `prependHistory` of 300 bars into 5 000, without and with five indicators.

Run them with:

```sh
DESTINATION="platform=iOS Simulator,id=<udid>"
xcodebuild -scheme TradingChart-Package -destination "$DESTINATION" test \
    -only-testing:TradingChartTests/PerformanceTests                       # Debug
xcodebuild -scheme TradingChart-Package -destination "$DESTINATION" -configuration Release \
    ENABLE_TESTABILITY=YES test -only-testing:TradingChartTests/PerformanceTests   # Release
```

and read the `measured [Clock Monotonic Time, s] average:` lines.

### Frame-time scenarios

The demo (`Examples/TradingChartDemo`) takes `-perf <scenario>`. It builds the series, switches the indicators on, waits
two seconds for the chart to settle, and then sweeps the window from the live edge 560 bars into the past and back at
the pace of the display (a triangle wave, five seconds, so about 5.6 window widths per second: a hard fling). Every
frame of the sweep is driven from the same `CADisplayLink` callback that measures it, so the work of a scroll step lands
in the frame it belongs to. A frame that takes longer than 1.5 display periods is a *hitch*; dropped frames are
`round(duration / period) - 1` summed over the hitches. The result goes to the screen (HUD) and to
`Documents/perf-<scenario>.json` in the app container, together with the build configuration, the load average of the
Mac, how often the charts were rebuilt (`bodies`) and the consistency findings (`violations`).

| Scenario | Series | Indicators | Live ticks |
| --- | --- | --- | --- |
| `s1` | 600 candles | none | none |
| `s2` | 600 candles | SMA, Bollinger, Volume, RSI, MACD | none |
| `s3` | 5 000 candles | same five | none |
| `s4` | 600 candles | same five | 10 per second |

```sh
xcrun simctl launch --terminate-running-process <udid> io.github.pavellunev.TradingChartDemo -perf s3
# wait ~8 s, then
cat "$(xcrun simctl get_app_container <udid> io.github.pavellunev.TradingChartDemo data)/Documents/perf-s3.json"
```

Ad-hoc runs: `-perf <tag> -no-ticks -script "0:hasmore=off;0:indicators=volume;0:series=5000;2:stress=5"` (also `fling=<bars per second>`:
a fling that decays like a finger's, stopping at the first bar; `-no-markers`, `-reserve <bars>`; also
`ticks=<Hz>`, `stress=<seconds>,<bars>[,bg]`: `bg` lets the next steps of the script, for example a `prepend=300`, run
during the sweep), `-render-buffer <windows>` and `-perf-seconds <n>` (a longer sweep for a profiler to attach to). The
numbers below are the median of three runs per scenario.

### Consistency checks

A fast chart that shows the wrong thing is worse than a slow one, so every sweep also checks, on every frame, through
`ChartDiagnostics.violations(of:)` (SPI, not supported API), that in every pane (the main one and each indicator pane):

* **windowCoverage**: the marks the pane was last built with cover the visible window (no blank edges);
* **staleBase**: the chart is laid out for the Y base domain the model holds (a pane that is behind the model for more than
  one check is counted; one that catches up in the same run-loop turn is not);
* **dataOutsideDomain**: the domain that is shown holds everything that is drawn in the plot: the visible data, and what
  is drawn at the edges of the window without a point inside it (see [Autoscale at the edges](#autoscale-at-the-edges)),
  checked right after the step, before the charts have caught up;
* **targetOutsideBase**: the chart has marks and room for all of the domain that is shown.

The target is zero for all four and a run with a violation is not a result. All runs in this document have zero. `-diag` on the
launch arguments of the demo does the same for use by hand (frame times and the four counters on the HUD, and in
`Documents/diag.json`): fling the chart yourself and watch `viol`.

These checks look at the model, not at the screen, and they passed on a chart that was blank and shifted on the screen
(see [Scrolling by touch](#scrolling-by-touch)). So there is a **pixel check** as well, `scripts/frame-check.py`: it records the simulator while the demo runs a
scenario (or while an XCUITest swipes the chart) and looks at every frame of the video:

| Check | Fires when |
| --- | --- |
| `empty` | the plot has (almost) no candle pixels |
| `clip` | candles, lines or bands touch the top or the bottom border of the plot (within 2 pt): what is drawn is cut off |
| `label` | the tip of the wick of the highest or the lowest candle is more than 2.7 pt from the line of its price label (the label and its line are drawn by the package at the exact autoscaled position, the wick is the chart's: a vertical jump) |
| `desync` | the bars of the Volume pane are not under the candles of the main pane |

and it reports how long the picture takes to come to rest after a motion. The simulator writes a frame at every commit of the
app, several within one refresh of the display, so the report gives the bad frames among all of them and among those that
are on the screen at 60 Hz. `scripts/frame-check.py scenario fling|slow|history|trim|zoom|drawings` records and checks a scripted
run of the demo; `analyze VIDEO --after <s>` takes a recording of real gestures (for example one made while an XCUITest swipes the chart).

### Environment

iPhone 16 simulator, iOS 27.0, Xcode 27.1, on a MacBook Pro (Apple silicon), 60 Hz display period. The simulator runs
the app natively on the Mac's CPU; Core Animation is rendered in software. Other work was running on the same Mac, so
the load average (1 minute) was 2 to 10 during the runs that are reported here; runs at a load of 12 or more were
waited out or discarded (the script waits for it). Repeats of one scenario agree within about 2 fps.

## Results

### Micro-benchmarks (per operation)

| Operation | Debug | Release |
| --- | --- | --- |
| all 7 indicators, 600 bars | 4.0 ms | 0.17 ms |
| all 7 indicators, 2 000 bars | 13 ms | 0.56 ms |
| all 7 indicators, 5 000 bars | 33 ms | 1.3 ms |
| one scroll step of the model, 5 000 bars, 5 indicators | 0.060 ms | 0.006 ms |
| one frame of window work, 5 000 bars, 5 indicators | 0.080 ms | 0.007 ms |
| `yDomain` + visible slice, 5 000 bars | 0.005 ms | 0.0005 ms |
| `update(candle)`, 600 bars, 5 indicators | 2.8 ms | 0.14 ms |
| `update(candle)`, 5 000 bars, 5 indicators | 22.9 ms | **1.04 ms** |
| append + trim to `maxLiveBarCount`, 600 bars, 5 indicators | 2.8 ms | 0.14 ms |
| `prependHistory` 300 bars into 5 000, no indicators | 0.07 ms | 0.04 ms |
| `prependHistory` 300 bars into 5 000, 5 indicators | 24 ms | 1.1 ms |

The cost of a live update is the full recalculation of the indicators (O(n) per indicator); the series itself, the
window and the autoscale are negligible. It scales linearly with the length of the series: 0.14 ms at 600 bars, 1.04 ms
at 5 000. An incremental indicator protocol would remove that, but it is not needed for the budget and is not in v1.

### Frame times while scrolling

Median of three runs, Release build of the demo. *Before* is the first version (every scroll step rebuilt
every chart), *after* the state described in this document. Zero consistency violations in every run.

| Scenario | fps before | **fps after** | p50 | p95 | p99 | max | hitches / frames | dropped | CPU |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `s1` 600, none | 57.8 | **57.1** | 16.7 ms | 23.2 ms | 39.0 ms | 41 ms | 13 / 286 | 14 | 25 % (was 57 %) |
| `s2` 600, 5 indicators | 19.1 | **51.6** | 16.7 ms | 39.9 ms | 61.9 ms | 68 ms | 26 / 258 | 42 | 45 % (was 74 %) |
| `s3` 5 000, 5 indicators | 19.5 | **51.3** | 16.7 ms | 38.0 ms | 56.4 ms | 65 ms | 29 / 257 | 44 | 46 % (was 73 %) |
| `s4` 600, 5 indicators, 10 ticks/s | 12.9 | **26.4** | 25.2 ms | 106.9 ms | 112.2 ms | 115 ms | 67 / 132 | 169 | 68 % (was 80 %) |

Before: `s1` p50 16.7, 11 hitches, 11 dropped; `s2` p50 50.5 ms, 95 hitches of 96 frames, 208 dropped; `s3` p50 50.1 ms, 97 / 98,
204; `s4` p50 74.0 ms, 64 / 65, 234.

Debug build of the demo (the same code, unoptimised):

| Scenario | fps before | **fps after** | p50 | p95 | p99 | max | hitches / frames | dropped | CPU |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `s1` | 58.0 | **57.4** | 16.7 ms | 16.7 ms | 37.3 ms | 40 ms | 12 / 287 | 13 | 25 % |
| `s2` | 19.9 | **49.9** | 16.7 ms | 48.9 ms | 68.1 ms | 71 ms | 32 / 250 | 51 | 46 % |
| `s3` | 19.4 | **49.7** | 16.7 ms | 48.8 ms | 68.6 ms | 73 ms | 32 / 249 | 52 | 47 % |
| `s4` | 14.1 | **25.6** | 24.6 ms | 112.9 ms | 124.4 ms | 125 ms | 61 / 128 | 170 | 71 % |

Release and Debug are alike because the frame time is spent in Charts, SwiftUI and the Swift runtime, which are optimised in
both; the package's own code is 0.5 % of the main thread.

How to read the table: a 60 Hz frame is 16.7 ms, and a frame that misses it waits for the next display refresh, so the
frame rate falls in steps (60, 30, 20 fps). Most frames of a sweep now take 16.7 ms (p50); the hitches are the frames in
which a chart is built. In `s2` there are about a dozen window moves in the sweep, each rebuilding four charts (the slowest frames of a run, p99 and
max, are 60 to 70 ms: three to four frames), plus some rebuilds of one chart for the autoscale; together they account for the
42 dropped frames.
`s1` shows the same effect with one chart, which can be built within a frame or two.

### What each step bought

Release, median of the runs of each step (two or three), fps in `s2` / `s3` / `s4`. Each step is cumulative; `—` means not
measured at that step.

| Step | `s2` | `s3` | `s4` |
| --- | --- | --- | --- |
| 0. before (every scroll step rebuilds every chart) | 19.1 | 19.5 | 12.9 |
| 1. render state in the model: marks built for a render window that moves with hysteresis; ticks, price-line span and live-edge flag stored. Nothing else changes, so the charts are still rebuilt on every frame (Swift Charts reads the scroll binding while the pane body is evaluated) | 20.0 | 19.8 | — |
| 2. the scroll binding is applied by a modifier of its own (`ChartScrollBridge`), so a scroll step no longer re-evaluates the pane. Still a rebuild per frame, now because the Y domain changes on every frame | 24.4 | 22.8 | — |
| 3. the Y domain by a transform of the chart (laid out for a base domain, scaled and moved to the autoscaled one on every frame), without own axes (prototype: axes hidden) | 45.8 | 44.9 | — |
| 4. own axes and overlays (a `Canvas` per pane for the grid and labels, one for the high/low labels, trade markers and price line), chart clipped to its pane | 44.4 | 42.5 | 19.7 |
| 5. render window policy: the charts are laid out anew for the current domain whenever the window moves (free: they are rebuilt anyway), so the transform rarely has to be rebased; the window is built ahead of the motion and wider in a fling | 50.9 | 50.8 | — |
| 6. what follows the newest bar or the price lives in small views, and a tick that changes only bars outside the render window does not rebuild the charts (`renderRevision`) | 52.6 | — | 35.6 |
| 7. correctness: Swift Charts draws nothing outside its own frame, so the chart is three plot heights tall and the transform never shows a part of it that is not there (see below). The final state | **51.6** | **51.3** | **26.4** |

Rejected on the way, because they trade the behaviour of the price scale for speed (numbers from the same build, `s2` / `s3`):

| Experiment | `s2` / `s3` | Why not |
| --- | --- | --- |
| Y domain frozen while scrolling (the floor of "no rebuilds") | 46.2 / 46.0 | candles leave the plot: an empty chart |
| Y domain in steps with hysteresis (commit when the data leaves it, or it is 25 % too wide) | 39.2 / 36.9 | visible steps of the price scale, and still a rebuild every few frames |
| Y domain retargeted with `withAnimation` (0.2 s, at most every 80 ms) | 11.2 / ≈8 (loaded Mac) | Swift Charts interpolates every mark on every frame of the animation: far more expensive than a rebuild |

Step 7 is worth a remark. The first version of steps 4 to 6 used a chart as tall as its plot, and a mid-scroll screenshot
showed it blank in the parts that the transform moved in from outside of the chart: in this arrangement Swift Charts draws
nothing outside its own frame, so a part of the shown domain that sticks out of the base domain is empty (the consistency
check `targetOutsideBase` exists because of this, and the fps of steps 4 to 6 may have been a little higher for the marks
that were not drawn). The chart is now laid out for a domain three times as tall as the one shown, in a frame three plot
heights tall, so the shown domain can move and scale a good deal inside it before the chart has to be laid out again, and a
chart is laid out again at once when the shown domain would stick out; `s2` lost 1 fps, `s4` 9 fps (its rebuilds at the live
edge paint three times the area).

## How a scroll step works now

```
scroll step (ChartInputLayer writes scrollPosition while a finger drags and a fling goes on, or the host sets it)
 └─ model.scrollPosition didSet ── refreshRenderState(.scrolling) ── a few microseconds:
      render window     moves only when the visible window nears its edge (ahead of the motion), at once if it left it
      Y target          the exact autoscaled domain of each pane, for the visible window, on every step
      Y base            the domain each chart is laid out for; rebased (charts rebuilt) when the target leaves it or
                        the scale drifts beyond 0.6…1.7, and whenever the window moves (the charts are rebuilt then anyway)
      isAtLiveEdge, x ticks   assigned only when the answer changes
 └─ what SwiftUI evaluates on every step (small bodies, no marks):
      ChartScrollBridge   the binding Swift Charts reads
      YTransform          scaleEffect + offset of each chart: the autoscale, on the GPU, exactly the same pixels
      PaneAxes            a Canvas: price grid and labels (nice values of the target), time grid and labels
      MainMarksOverlay    a Canvas: high/low labels, trade markers, the dashed price line
      PriceBadge          the Y of the badge
 └─ what is NOT evaluated: the bodies of the panes, which build the marks. They read the render window, the Y base and
    the data (`renderInput`), which change a dozen times in a fling.
 └─ 120 ms without a scroll step: the model "settles": charts laid out for the exact domains again (so a still chart is
    pixel-identical to one that was never scrolled), render window back to the size rest needs.
```

* **The data a body reads is a revision, not the series.** A live tick that changes only a bar the render window does not
  reach (the user looks at the history while ticks arrive) does not invalidate the panes. Ticks at the live edge, new bars,
  `setSeries`, prepends, zoom, style and layout changes do.
* **The chart is three plot heights tall** (`YTransformMath.frameRatio`), laid out for a base domain that holds the target
  with a margin of one target height above and below, and clipped to its pane (`.clipped()` on the pane view, not
  `chartPlotStyle { clipped() }`, which removes the time labels on iOS 27). Marks are stretched by the scale of the
  transform: 0.6…1.7 at most, and exactly 1 whenever the window has just moved or scrolling has stopped; horizontal strokes
  are thicker or thinner by that factor for a moment during a fast fling.
* **Own axes.** Swift Charts' axes would be scaled with the chart, so the price grid and labels and the time grid and labels
  are drawn by a `Canvas` per pane from the same state, in the same fonts and positions (labels in a column of
  `yAxisLabelWidth` + 4 pt, time labels under the lowest pane, a label that the plot edge would cut is left out).
  Tick values are chosen by `YAxisTicks` (multiples of 1, 2, 2.5 or 5 times a power of ten), as `AxisMarks(.automatic)` does.
* **The price line, the high/low labels and the trade markers are drawn by hand**, not as marks: they depend on the window
  (the extremes of the bars on screen), they must be right on every frame, and a mark would have to rebuild the chart to
  change.

### Behaviour that is the same, and what differs

Same as in the first version: the price scale is the exact autoscale of the visible bars (+8 %, the price included at the live
edge) on every frame while scrolling, with no steps and no animation; the high/low labels are right on every frame; the
legends, crosshair, tooltip, badge, history spinner, pinch, interval and style changes work as before (the crosshair and the
scrolling are taken by the input layer, see below).

What differs, all small: the axes are drawn by the package and not by Swift Charts (the same positions and fonts, values on
"nice" numbers chosen by the package); the time strip under the lowest pane is a fixed 16 pt; a doji is drawn with the same
thickness as before; horizontal strokes may be up to 70 % thicker or thinner for a moment in a fast fling; the dashed price
line and the labels are drawn above the candles (they were marks, in the order of the chart); `renderBufferWindows` is
a minimum and a fling builds up to twice that.

## Drawings

Drawings are drawn by a `Canvas` of their own (`DrawingsOverlay`) over the plot, with the same screen transform as the high/low labels
(visible time range, autoscaled price range), so adding, selecting and dragging a drawing rebuilds none of the charts: the model keeps the drawings in
a state that only the overlay reads (the touches are taken by the input layer, which reads nothing while SwiftUI evaluates it; `HostedChartTests` count the bodies: 60 steps of a drag leave `main`,
`panes` and `commits` at 0). With no drawings the overlay does not read the scroll position, so a scroll step does not evaluate it at all. Shapes are
clipped to the window in data space (Liang–Barsky, `ChartDomain.clip`) before they are mapped to the screen.

Release build, `s2` set-up (600 candles, SMA, Bollinger, Volume, RSI, MACD, no ticks), the usual sweep, three runs each (median fps, violations 0 in all):
no drawings 51.2; 10 drawings 52.6; 10 drawings and an anchor moved on every frame (`-wiggle`, what a drag does) 51.0; 100 drawings spread over the
series (about 15 in view) 50.3; 100 drawings and `-wiggle` 51.0. The official `s2` of the same session: 51.1. The differences are within the
run-to-run noise of about 2 fps. Reproduce: `-perf <tag> -no-ticks -no-restore -script "0:hasmore=off;0:indicators=sma20,bb,volume,rsi,macd;0:series=600;0:scatter=100;2:stress=5"`,
add `-wiggle` for the moving anchor.

## Hot spot found and fixed early: the time axis

(Still true, and the reason the time axis ticks are generated by the package.) Scenarios 2 and 3 differ only in
the length of the series, yet 5 000 bars scrolled at 13.5 fps against 17.5 fps for 600. Temporary instrumentation of the
axis closure counted the calls: 42 per frame and chart at 600 bars, **335 per frame and chart at 5 000**.
`AxisMarks(values: .automatic(desiredCount:))` of a scrollable chart creates the ticks for the whole scrollable domain, not
for the window. `TimeAxisTicks` (`Sources/TradingChart/Support/TimeAxisTicks.swift`) generates the ticks itself, for the
render window only: about 12 per chart at any length of the series. The step is chosen from a ladder of round steps so that
about `desiredCount` ticks fit the visible window; ticks sit on a fixed grid of the local clock (multiples of the step,
local midnights for day steps, month starts for month steps), so they do not move while the window scrolls and all panes
agree. A step is never smaller than the label resolution of the interval (a day for bars of an hour or more, a month for
weekly bars). Tests: `TimeAxisTicksTests`.

## Scrolling by touch

The fast scroll described above was measured with scroll steps that the demo writes into the model. A hand on the chart did
something else, and the user saw the chart jump: during a fling the window went back and forth between the position of the
finger and the start of the series, the main pane was blank for several frames while the spinner of the history loading
showed, and the Volume pane showed other bars than the main one.

**Cause.** Swift Charts' own scroll gesture does not survive a transform that changes on every frame: the chart is a
`UIScrollView` inside a view whose `scaleEffect` and `offset` follow the autoscale (that is how the price scale reaches the
screen, see above). While the transform changed during a drag or a fling, the scroll view reported a position near the start of
the series (about four bars after it) in the middle of the motion, and the panes, which share one position, fought over it.
A bare Charts view with a constant transform scrolls fine; one with a transform that changes with the scroll position
(offset alone is enough, also set by a `visualEffect`, a `transformEffect` or a `CALayer`) reproduces it (about 2 900 jumps of more
than 30 bars, nearly all of about 500, in ten swipes). The model-level invariants could not see it: they were checked against the position the model
held, which was wrong in the way that the screen was.

**Fix.** The charts take no touches (`allowsHitTesting(false)`) and only follow `scrollPosition` through the binding (a write
through it is ignored). A transparent layer over the plot of every pane, `ChartInputLayer` (one `UIPanGestureRecognizer`, one
finger; one `UILongPressGestureRecognizer` for the crosshair), moves the window: `TradingChartModel+Scrolling.swift` turns the
translation of the finger into a position, clamped to the first bar and the live edge, and after the finger lifts a
`CADisplayLink` goes on with an exponential deceleration (time constant 0.5 s, as a scroll view's normal rate; `ScrollDynamics.swift`).
The fling is in chart time, so history prepended, a head trimmed or a zoom in the middle of it do not disturb it; a finger that
goes down, the host writing `scrollPosition`, a zoom and a new series end it. A scroll step of a fling is the same step the
sweeps of this document measure, so the numbers above are what a fling costs.

Changes of behaviour: no rubber band at the ends (the chart stops at the first bar and at the live edge); the Charts scroll
view still exists and may still offer accessibility scroll actions; they do nothing.

## Autoscale at the edges

With the finger fixed there were still frames in which candles stuck out of the plot (cut off by the edge of the pane, as if
they flew off the top): 26 of 2 300 in a slow scroll. The autoscale held the points *inside* the window, but the plot also shows
what comes in from outside: a line (an SMA, the edge of the Bollinger band) runs in from the point beyond the edge, so at the
edge it has a value between two points that are not both inside, and a candle whose centre is a point or two outside the
window is half in view (its body, and its whole wick when the centre is closer than the half width of the wick). The domain now
holds those too (`AutoscaleEdges`: the interpolated value of every line and band at both edges, the body or the wick of the
neighbouring bar when it is that close, the bar of a histogram that is half in view). They are exact, not a margin of a bar:
a spike is taken into the autoscale when it appears, not a bar before.

## The time domain: no blank frames at a prepend or a trim

Swift Charts keeps its scroll offset in points, measured from the left end of its time domain. When that end moves the chart
shows another window, or none, until it is made to look at the scroll position again; the binding handed to it carries a
thousandth of a bar that flips (`scrollNudge`) to make it, which takes a frame or two. That was found for a
prepend first, and it also happens when a live update trims the head of the series: with `-max-live 300` the first appended bar
removes 300 bars at once, and a real swipe in the history showed a blank main pane and Volume pane for two frames. Now the left
end of the domain does not move: with more history to load it sits `historyReserveBars` (1 000) bars before the first bar, and it
moves only when the series is replaced or history is prepended beyond the reserve (then in a step of a whole reserve, and
while the window is still: until it stops, the bars the domain does not hold cannot be scrolled to). A prepend inside the
reserve and a trim change nothing the charts lay out. The reserve is empty time that cannot be scrolled to (touch scrolling stops
at the first bar), so the user never sees it.

## What the pixel check found, before and after

Real swipes (XCUITest on an iPhone 16 simulator, recorded; the same swipes before and after), bad frames of all frames /
of the frames on the screen at 60 Hz:

| Scenario | before | after |
| --- | --- | --- |
| slow drags, back and forth | 188 / 180 of 267 | 0 / 0 of 506 |
| flings, 5 each way | 532 / 346 of 491 | 0 / 0 of 327 |
| flings into the history, 5 pages loading | 937 / 495 of 1 209 | 0 / 0 of 644 |
| scrolling in the history with live bars and `-max-live 300` | 947 / 490 of 670 | 0 / 0 of 411 |
| flings at several zoom levels | 610 / 390 of 527 | 0 / 0 of 350 |

Scripted runs of the demo (`scripts/frame-check.py scenario`; the position is written into the model, so they do not meet the
Charts gesture, only the autoscale and the domain): fling 5 / 2 of 249 before, 0 after (3 runs); slow scroll 26 / 10 of 943
before, 0 after; history 6 / 3 of 706, 0; trim 13 / 5 of 582, 0 (2 runs); zoom 0, 0. After a motion the picture comes to rest within
two frames (50 ms); before it needed up to 22 frames (600 ms) in the real runs. Release `-perf` (median of three): `s1` 57.6, `s2` 51.6,
`s3` 50.4, `s4` 25.0 fps against 57.1 / 51.6 / 51.3 / 26.4 before the touch input layer, with no violations.

## The compact layout, one input layer for the finger

The touches for the drawing tools were first in two SwiftUI layers (a drag gesture over the plot while a tool was active or a
drawing selected, a tap gesture otherwise); with the input layer for scrolling under them they got in each other's way: a long press
(the crosshair) did not get through the layer while a drawing was selected or a tool armed. Now `ChartInputLayer` takes every
one-finger touch of the main pane: a tap places an anchor or selects a drawing, a pan that starts on the selected drawing moves it,
any other pan scrolls the chart, a long press shows the crosshair, and the pinch is the chart view's, in every mode of the tools.
A tap is a touch that neither moved nor was held (the tap recogniser waits for the pans and the long press to fail, which they do
at the lift of the finger). With a selection or an armed tool the chart is no longer locked: a drag still scrolls it.

The demo has a compact layout now (the screen is one background, the plot of the main pane is 317 x 368 pt on an iPhone 16 with the
five indicators), so the pixel checker's boxes moved (`MAIN_PLOT`, `VOLUME_PLOT` in `scripts/frame-check.py`) and it has a scenario
with ten drawings, `drawings`: the hard fling of `fling` while ten drawings come into view and leave it.

| Check | Result |
| --- | --- |
| scripted: `fling`, `slow`, `history`, `trim`, `zoom`, `drawings` | 0 bad frames in each (272, 941, 675, 583, 23, 263 frames on the screen at 60 Hz) |
| real touches (XCUITest): slow drags, flings, flings into the history, scrolling with live bars and a trim, flings at several zooms, flings with ten drawings | 0 bad frames in each (506, 336, 586, 306, 315, 295 frames on the screen at 60 Hz) |
| Release `-perf` (median of three): `s1` / `s2` / `s3` / `s4` | 57.0 / 51.4 / 49.9 / 25.3 fps against 57.6 / 51.6 / 50.4 / 25.0 before the drawing layer moved into it, no violations |

## The remaining bottleneck

Where the time goes, `s2` (Release, Time Profiler attached for 8 s of a slower 12 s sweep; the main thread was busy 30 % of the time): libswiftCore
25 % (generic metadata, retain/release, value-witness copies of marks), SwiftUICore 10 %, Charts 8 %, memmove 7 %, kernel
6 %, AttributeGraph 5 %; **the package and the demo together 0.5 %**. The cost is the layout of the marks of the charts:
about 1 500 for the four-pane configuration (candles 2 marks per bar, Bollinger 3 lines and a band, MACD 2 lines and bars,
over the render window), at about 25 µs per mark, each time the window moves or a chart is laid out for a new domain.

* A hard fling (5.6 window widths a second, the test of the sweep) moves the window about twelve times in five seconds; each
  move rebuilds four charts in three to four frames. That is most of the 42 dropped frames of `s2`. A
  larger buffer means fewer moves of more marks: the cost per window width scrolled hardly changes. With the whole series
  built (no moves at all, `-render-buffer 100`, 600 bars, Y domain frozen, measured before the transform existed) the same
  sweep runs at 52 fps, so about 52 is what four scrolling Swift Charts cost in this setup, whatever is done around them.
* The remaining rebuilds of single charts (about 50 in the sweep) are the Y base following the autoscale; they fit within
  a frame, mostly.
* `s4`: every tick at the live edge rebuilds all charts (about 100 ms with a fling's wide window); the badge animation
  and the legends add per tick. Coalescing ticks in the host (four a second instead of ten) is the lever, as before.

Options, none of them taken (each costs behaviour or is a rewrite):

1. **Draw the heavy marks by hand.** The lines of the indicators, and the candles, as `Canvas` paths: the cost of a window
   move, and of every rebase, disappears (a path of 40 bars costs microseconds), at the price of rewriting the rendering
   that this package is built on Swift Charts for. Out of scope here.
2. **Fewer marks** per bar (no Bollinger band fill, a coarser level of detail while a fling is under way): changes what is
   drawn.
3. **Fewer or lighter panes** in the host: every pane costs 4.5 to 7.5 ms to build.
4. **Wider scale tolerance** (`YTransformMath.scaleRange`) and a bigger fling buffer: a few fps more for thicker horizontal
   strokes and a larger rebuild.
5. **Check on a device.** The simulator runs on the CPU of the Mac with Core Animation in software; a device may build marks
   faster or slower, and may be limited by the GPU instead.

## Simulator is not a device

The simulator runs the app on the Mac's CPU with Core Animation rendered in software and shares that CPU with the other
work on the Mac, so these numbers describe relative costs (what scales with what, what a change buys), not what an
iPhone does. The cost found here is CPU work on the main thread, which an iPhone core will probably not do faster than a
Mac core, so the multi-pane scenarios should be expected to be CPU-bound on a device too; that remains to be confirmed.

To repeat on a device:

1. Run the demo from Xcode in the **Release** configuration on the device (Edit Scheme → Run → Build Configuration).
2. Launch with `-perf s2` (or `s3`, `s4`) in the scheme's arguments; read the HUD and
   `Documents/perf-<scenario>.json` (Window → Devices and Simulators → the app → Download Container). Check that
   `violations` are all zero. With `-diag` instead you can fling the chart by hand and watch `viol` on the HUD.
3. For the hitches against the real display: Instruments → **Animation Hitches** (or the SwiftUI template) on the
   device while flinging the chart by hand; check the hitch rate and the *Hitch Time Ratio*, and the main thread in
   **Time Profiler**.
4. Check the thermal state: a warm device throttles, and the numbers fall.
