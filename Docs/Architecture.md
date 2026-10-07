# Architecture

How TradingChart is put together: the modules, the way data and touches flow through them, the rules that keep scrolling
smooth and consistent, how the chart is drawn, and the places where Swift Charts had to be worked around. For the numbers
see [Performance.md](Performance.md); for how to use the package see the [README](../README.md) and the DocC catalogs under
`Sources/*/*.docc`.

## Modules

```
TradingChartCore         Foundation + CoreGraphics only
        ▲
TradingChartIndicators   depends on TradingChartCore
        ▲
TradingChart             SwiftUI + Swift Charts + UIKit; depends on both, and re-exports both
```

| Module | Holds | Why separate |
| --- | --- | --- |
| `TradingChartCore` | `Candle`, `PricePoint`, `ChartSeries`, `ChartInterval`, `ViewportMath`, `ChartTransform`, the indicator protocol and output types, the drawing model (`ChartDrawing`, `DrawingTool`, `DrawingEditor`, clipping) | pure value types and functions: unit-tested without a UI, usable in any target |
| `TradingChartIndicators` | `SMA`, `EMA`, `WMA`, `BollingerBands`, `Volume`, `RSI`, `MACD`, `IndicatorMath` | the indicator math is pure and checked against reference values |
| `TradingChart` | `TradingChartModel`, `TradingChartView`, the panes and overlays, the theme and formatters, `IndicatorBar`, `SeriesStylePicker` | everything that needs SwiftUI |

`TradingChart` is the umbrella product (`Exports.swift` re-exports the other two). A host that only needs the data model or
the indicator math depends on a smaller product.

### Platforms

The package declares iOS 16 (`platforms: [.iOS(.v16)]`) so that apps that still support iOS 16 can depend on it.
`TradingChartCore` and `TradingChartIndicators` are plain Swift and have no availability annotations. The chart UI uses
`@Observable`, `@Entry`, `MagnifyGesture` and the iOS 17 Swift Charts scrolling API, so every declaration of the `TradingChart`
module (types, extensions and free functions, internal ones included) is marked `@available(iOS 17.0, *)`. The compiler then
rejects any use of the chart outside an `if #available(iOS 17, *)` or an `@available(iOS 17, *)` context, and the iOS 17
symbols the module uses are referenced weakly, as for any API newer than the deployment target. The test bundle is built for
iOS 17 by Xcode, so the tests carry no annotations (Swift Testing does not accept `@available` on a suite anyway).

Layout of `Sources/TradingChart`:

| Folder | Contents |
| --- | --- |
| `Model/` | `TradingChartModel` and its extensions (render state, scrolling by touch, the time domain, drawings, accessibility), `TradingChartConfiguration`, events |
| `View/` | `TradingChartView`, `MainChartPane`, `IndicatorPane`, `PaneAxes`, `PaneOverlays`, `ChartInputLayer`, `DrawingViews`, the price badge, the legends, `IndicatorBar`, `SeriesStylePicker` |
| `Support/` | pure helpers: render window policy, Y transform maths, autoscale at the edges, axis ticks, label layout, drawing layout, legend naming, palette |
| `Theme/` | `TradingChartTheme`, `PriceFormatter`, `TimeFormatter`, `TradingChartStrings` and its catalog lookup, the environment keys |
| `Resources/` | `TradingChart.xcstrings`: the translations of `TradingChartStrings` in 14 languages |

## Data flow

```
host ──► TradingChartModel ──► render state ──► panes (Swift Charts + Canvas layers)
 ▲            │  ▲                                        │
 │            │  └──── touches (ChartInputLayer) ◄────────┘
 └── onEvent ◄┘
```

1. **The host** calls the model: `setSeries`, `update(...)`, `prependHistory`, assigns `indicators`, `markers`, `drawings`,
   `currentPrice`. It listens to `onEvent` (`approachedHistoryStart`, `liveEdgeChanged`, `crosshairChanged`, `drawing`).
2. **The model** (`@MainActor @Observable`) is the single owner of the state: the `ChartSeries`, the scroll position, the
   visible bar count, the cached indicator outputs, the crosshair time, the drawings, the history flags. Every rule lives here,
   in plain testable code. A group of mutations runs inside `batch`, and the viewport events are reported once, after the group.
3. **The render state** is derived from the model and is what the views actually read: the render window (the time range marks
   are built for), the ticks of the time axis, and per pane the Y domain the chart is laid out for and the Y domain that is
   shown (see [Rendering](#rendering)). It changes much more rarely than the scroll position does.
4. **The panes** (`MainChartPane`, one `IndicatorPane` per indicator that has something to draw) read the render state and
   draw: marks by Swift Charts, everything that has to follow the scroll on every frame by `Canvas`.
5. **Touches** are taken by one transparent UIKit layer per pane (`ChartInputLayer`) and turned into model calls: a scroll
   step, a crosshair time, a drawing tap or drag. The pinch is a SwiftUI gesture on the whole stack.

The views never decide anything about the window, the data or the drawings; they report sizes (`updateLayoutMetrics`) and
touches, and draw what the model holds.

## Patterns that every change has to keep

### The anchor changes atomically with the data

The scroll position (`scrollPosition`, the left edge of the window) is changed in the same synchronous mutation as the series.
`setSeries` with `scroll: .automatic` re-anchors to the live edge when the interval changed or the window was at the live edge
before; a live update that appends a bar moves the window along if it was at the live edge. The view therefore never renders a
frame with new data and the old window (a blank chart or a jump). Events are sent after the whole group.

### A series holds only what can be drawn

`ChartSeries` is the boundary: a candle or a point with a time or a price that is not finite is dropped by every way in (the
initialisers, `upsert`, `apply`), and a candle whose `high`/`low` do not enclose its other prices is repaired. Past that line the
maths can build ranges from the data without a trap, and the places that build a range from indicator output or from a price of
the host (`valueRange`, the Y extent, `candleBodyRange`, the autoscale at the edges) leave non-finite numbers out as well.
`ChartSeries.empty(interval:)` is a series of candles by default (`kind: .points` for a line), so a first tick followed by a page
of candles does not lose the page. A tick, and a `PricePoint` upserted into a series of candles (which is applied as one), opens a
candle; a `Candle` upserted into an empty series of points makes it candles. A series that has bars keeps its kind: live updates
never change it, and `prepend` converts a page of the other kind to it instead of dropping it (candles to points by close;
points to flat candles with no volume, each point moved to the start of its bucket and the points of one bucket merged). An
empty series takes the page as it is, kind included. So the kind of a series that was fed ticks first is the kind it was
created with: a line chart that is to take pages of points as points starts from `kind: .points`.

### Everything derives from the interval of the series

The window, the bucket of a tick, the width of a candle, the axis steps: all come from `series.interval`, never from the
interval chosen in a picker of the host. A `ChartInterval` is a length and the grid it sits on (`origin`, seconds after the
Unix epoch): days start at midnight UTC and weeks on Monday (`.weeks(_:startingOn:)` takes another weekday), and the buckets of
ticks and the snapping of drawings use the same grid. Months are not a fixed length and are not supported. A host may switch its picker at once and replace the series when the data arrives; the
chart stays consistent in between.

### The interval gate

`update(_ candle:interval:)` and `update(_ point:interval:)` take the interval the bar was built for and drop it when it is not
the interval of the series (`UpdateResult.ignored`). A late message of the previous timeframe cannot corrupt the new series.
Ticks (`update(price:at:volume:)`) are bucketed by the series' own interval.

### One effective viewport

`ViewportMath` (Core) is the single source of window geometry: the live-edge anchor, the live-edge test, the X domain, the Y
autoscale, zoom. The model derives one *effective* `ViewportConfiguration` (`ViewportMath.effectiveConfiguration`) and every
call, in the model and in the views, goes through it:

- the gap at the right edge shrinks when zoomed in (at most `maxTrailingPaddingFraction` of the window) and the live-edge
  tolerance is at most a tenth of the window;
- the gap grows when the price badge, which sits on the price axis column, reaches into the plot: the last candle always stays
  clear of the badge (`badgeOverhang`, measured by the view).

The view reports the measured plot width, badge width and axis column width (`updateLayoutMetrics`, with a one point
hysteresis against sub-pixel jitter); a window that was at the live edge is re-anchored in the same mutation.

### Live edge

`isAtLiveEdge` is stored and assigned only when the answer changes, so a view that reads it is not rebuilt by every scroll
step. `liveEdgeChanged` is reported when it changes. A live update at the live edge moves the window; away from it the window
does not move, and the badge turns into a button that scrolls back.

### Autoscale

The Y domain of the main pane is the exact range of everything visible (bars, overlay indicators, the current price when its
bar is in view) plus `verticalPaddingFraction`, recomputed on every scroll step with binary searches, never by a pass over the
series. `AutoscaleEdges` adds what is drawn at the edges of the window without a point inside it: a line enters the window from
a point outside, so at the edge it has an interpolated value; a candle whose centre is a point or two outside is half in view.
Without them candles and lines were cut by the edge of the pane for a few frames. Indicator panes autoscale the same way (or use
`fixedRange`, with padding).

## Rendering

### Layers of a pane

A pane is a stack, bottom to top:

| Layer | Drawn by | What |
| --- | --- | --- |
| `PaneAxes` | `Canvas` | price grid and labels (nice values of the shown domain), time grid and labels (lowest pane) |
| the chart | Swift Charts | candles (`RuleMark` wick + `RectangleMark` body), lines (`LineMark`), area, indicator lines and bands, histograms |
| `ChartInputLayer` | UIKit | the finger: pan, long press, tap |
| `MainMarksOverlay` | `Canvas` | high/low labels, trade markers, the dashed price line |
| `DrawingsOverlay` | `Canvas` | drawings, handles, pending anchors |
| overlays | SwiftUI and `Canvas` | price badge, the crosshair (its dashed lines, labels and tooltip), history spinner |

The legend row sits above the plot of each pane, outside the data area, so it never covers anything.

### Languages and right-to-left

The words of the chart are the strings of `TradingChartStrings`, filled from `Resources/TradingChart.xcstrings`, a String Catalog that
the build compiles into one `TradingChart.strings` per language in the resource bundle of the module (`Package.swift` sets
`defaultLocalization: "en"`). They are looked up *by language*, not by the preferences of the process (`StringCatalog`): `standard`
is the language of the app (`Bundle.main.preferredLocalizations`, matched against the catalog; the preferred languages of the
device only when the app declares none), computed once, and `localized(for:)` the language of the locale it is given, so an app
with an in-app language does not depend on the language of the device. A language is matched with `Bundle.preferredLocalizations`, which accepts
regions, scripts and underscores, and English fills in for what is missing. A test checks that every language has every key with
the placeholders of the English string, and that every string of the struct is a key of the catalog. The table is called
`TradingChart` and not `Localizable`: the compiler fills `Localizable` with the labels of the Swift Charts marks
(`.value("Time", ...)`), which it would write into the catalog on every build. Those labels are names that Swift Charts keeps for
its own accessibility description of the marks; SwiftUI looks them up in the strings of the app, not of the package.

A chart is read left to right whatever the language: `TradingChartView` sets the layout direction of everything it contains to
`.leftToRight` (the Swift Charts axes, the `Canvas` layers, the badge, the crosshair, the legends and the tooltip's place on the plot), so
time never runs backwards and the price scale stays at the right. The direction of the host is passed down in the environment
(`tradingChartHostLayoutDirection`) for one thing: the card of the tooltip is a piece of text and is laid out as the host reads, with
its labels at the right in Arabic. The row labels are short (abbreviated in Russian, for one) because the card is as wide as its longest row.

### Marks are built for a render window, rarely

Building the marks of a chart is the expensive part of a scroll step (Swift Charts lays out every mark), so the charts are not
rebuilt per step. Marks exist for a *render window*, the visible window plus `renderBufferWindows` on each side:

- the window is moved by `RenderWindowPolicy` only when the visible window comes close to its edge, ahead of the motion (in
  a fling it is built wider and shifted in the direction of travel), and at once when the visible window has left it;
- the invariant is that **the render window covers the visible window on every frame**, in every pane, so there is never a blank edge;
- the marks are cut out of the series and the indicator outputs by binary search (`Slicing`, `IndicatorRendering`);
- what the pane bodies read is a *revision*, not the series: a live tick that changes only a bar outside the render window
  (the user looks at history while ticks arrive) does not rebuild the charts (`renderInput`, `renderRevision`).

### The scroll position does not rebuild the chart

Swift Charts reads the scroll binding while the body that applies it is evaluated, so reading `scrollPosition` there would make
every scroll step re-evaluate the whole pane. `ChartScrollBridge`, a modifier of its own, applies `chartScrollPosition(x:)`:
a scroll step re-evaluates that tiny body and nothing else. The charts only follow the position; they never change it (a write
through the binding is ignored).

### The Y domain is a transform of the chart

Changing the Y domain of a chart makes Swift Charts lay everything out again, which cannot happen on every frame. Instead each
chart is laid out for a *base* domain and the autoscaled *target* domain is shown by a GPU transform of the chart layer (a
scale and an offset in Y, `YTransform`):

- the base domain holds the target with a margin of one target height above and below, and the chart is `frameRatio` (3) plot
  heights tall, because Swift Charts draws nothing outside its own frame;
- the transform is exact (the same pixels as laying the chart out for the target) and costs no layout, so the price scale
  follows the visible bars on every frame, with no steps and no animation;
- marks are stretched by the scale, so when it drifts out of `0.6...1.7`, or the target leaves the base, the chart is laid out
  again for the current target (a *rebase*) and the transform resets in the same update. The render window moves rebase the
  charts anyway. When scrolling stops (120 ms without a step) the charts are laid out for the exact domains, so a still chart is
  pixel-identical to one that was never scrolled;
- the chart is clipped to its pane with `.clipped()` on the pane view.

The invariants, checked by `ChartDiagnostics` (SPI) on every frame of the performance runs: the render window covers the visible
window, the chart is laid out for the base the model holds, the shown domain holds the visible data, and the base holds the shown
domain. The target is zero violations.

### What is drawn by hand, and why

Swift Charts' axes would be scaled with the chart by the transform, so the axes are drawn by `Canvas` from the same state: the
price grid and labels at nice values (`YAxisTicks`: multiples of 1, 2, 2.5 or 5 times a power of ten), the time grid and labels
(`TimeAxisTicks`, below), in the same fonts and positions. The same goes for everything that depends on the window: the labels of
the highest and the lowest price (they must be right on every frame, and a mark would have to rebuild the chart to change), the
trade markers, the dashed current price line, and the drawings. Each is a `Canvas`, which redraws in a fraction of a
millisecond, in the same frame as the bars.

Small leaf views (`MainLegend`, `PaneLegend`, `PriceBadgeHost`, `CrosshairLayer`, `HistoryLoadingOverlay`,
`ChartAccessibility`) read the state that changes often (the crosshair, the last bar, the price), so that those changes do not
invalidate the panes. The crosshair is one of them for that reason: its lines are drawn by `Canvas` in `CrosshairLayer`, not as
marks of the chart, so a crosshair that moves from bar to bar does not lay the chart out again. For the same reason the pane
bodies read the width of the window as a stored value (`chartVisibleDuration`, changed by a zoom or another interval) and not
`visibleDuration`, which reads the series: a live tick must not make every pane evaluate its chart again. The tests count the
evaluations of the bodies and of the closure that builds the chart (`ChartDiagnostics`, per model). With no drawings the drawing overlay does not read the scroll position at all.

### Time axis ticks

`AxisMarks(.automatic)` of a scrollable chart creates ticks for the whole scrollable domain, not the window: 335 closure calls
per frame and chart at 5,000 bars against 42 at 600. `TimeAxisTicks` generates them for the render window only (about a dozen
per chart whatever the length of the series): a step from a ladder of round steps so that about `desiredCount` fit the visible
window, on a fixed grid of the local clock (midnights for day steps, month starts for month steps), so ticks do not move while
scrolling and all panes agree. A label that the edge of the plot would cut is left out (the grid stays).

### Candle width, culling and number of marks

Candle bodies have a fixed width computed from the plot width and the visible bar count (`ViewportMath.candleBodyWidth`), so
they follow the zoom. Candles are two marks per bar (a wick and a body); Bollinger Bands are three lines and a band; so a
four-pane configuration builds about 1,500 marks per render window, and that, not the package's own code, decides the frame rate
(see [Performance.md](Performance.md)).

## Touch input

Swift Charts' own scroll gesture does not survive a transform that changes on every frame: the position its scroll view reports
jumps to the start of the series and back during a drag or a fling, and the panes (which share one position) fight over it. So
the charts take no touches (`allowsHitTesting(false)`), and a transparent `ChartInputLayer` (one `UIView` with a pan, a long
press and a tap recogniser, and a second pan for dragging drawings) over the plot of each pane takes the finger:

- **Drag.** `TradingChartModel+Scrolling` turns the translation into a scroll position, clamped from the first bar to the live
  edge, and after the finger lifts a `CADisplayLink` goes on with an exponential deceleration (time constant 0.5 s, like a scroll
  view's normal rate; `ScrollDynamics`). The fling is kept in chart time, so history prepended, a head trimmed or a zoom in the
  middle of it do not disturb it. A new finger, the host writing `scrollPosition`, a zoom, a new series and the chart leaving
  the screen (the input layer leaves its window) end it. There is no rubber band at the ends. One fling runs at a time: a second
  one stops the first, and the display link of a fling ends itself when its owner is gone (the tick answers whether to go on).
- **Long press** (0.3 s) shows the crosshair; a drag after it moves it from bar to bar. The window does not scroll meanwhile.
  With `isCrosshairEnabled == false` the long press does not begin at all, so it cannot hold up the pan.
- **Panes take the finger one at a time.** The recognisers of one input layer are never simultaneous with those of another one
  (two fingers on two panes would scroll the chart twice and start two flings); the pinch, which is the chart view's, goes along
  with all of them.
- **Pinch** is a SwiftUI `MagnifyGesture` on the whole stack: the total magnification is applied to the window as it was when the
  gesture began (no accumulation, no drift at the limits); the newest bar stays put when the window began at the live edge, the
  middle otherwise. The baseline is dropped when the pinch ends and when it is cancelled (`onEnded` is not called for a cancel;
  a `@GestureState` that resets tells the view).
- **Drawing tools** use the same layer on the main pane: a tap places an anchor or selects a drawing; a pan that starts on the
  selected drawing moves it (anchor or body), any other pan scrolls. The tap recogniser waits for the pan and the long press to
  fail, so a tap is a touch that neither moved nor was held.

The scroll step of a fling is the same step that scripted sweeps measure, so the performance numbers are what a fling costs.

## History paging

- `isLoadingHistory` and `hasMoreHistory` are set by the host; `approachedHistoryStart` is sent when the left edge of the window
  is within `historyPrefetchThreshold` of the first bar (one window width by default), only while `!isLoadingHistory &&
  hasMoreHistory`, and at most once per *epoch*. An epoch is new after a new series, a `prependHistory` that added bars, the end of
  a request and `hasMoreHistory` turning `true`; a prepend that adds nothing does not open one (an empty page must not loop).
  `prependHistory` and `setSeries` reset `isLoadingHistory`, so a request can never leave the chart waiting.
- A prepend leaves `scrollPosition` and `visibleTimeRange` as they are (they are dates), and the indicators are recalculated over
  the longer series. Content does not jump.
- **Trim protection.** A live update at `maxLiveBarCount` trims the head of the series, but never a bar newer than
  `visibleTimeRange.lowerBound - renderBufferWindows * visibleDuration`, so the bars the user looks at are not removed under
  them. Back at the live edge the next update brings the series back to `maxLiveBarCount`. (`ChartSeries.upsert(...keepingFrom:)`.)
- **A sticky left end of the time domain.** Swift Charts keeps its scroll offset in points from the left end of its time domain.
  When that end moves (older bars prepended, the head trimmed) the same offset points at another time, and the chart is blank or
  shows another window for a frame or two. So the left end is held back: with `hasMoreHistory` it sits `historyReserveBars`
  (1,000) bars before the first bar, and only moves when the series is replaced or history is prepended beyond the reserve
  (then in steps of a whole reserve, and only while the window is still). The empty reserve cannot be scrolled to (touch
  scrolling stops at the first bar). When the end does move, the binding handed to Charts carries a thousandth of a bar that
  flips (`scrollNudge`), which makes Charts read the position again in the same update.
- A spinner (`HistoryLoadingOverlay`) shows at the left edge of the main plot while `isLoadingHistory` is `true` and the oldest
  bar is in or near the window.
- **No trim while loading.** A page ends at the first bar the host knew when it asked, so while `isLoadingHistory` is `true` a
  live update does not trim the head (`maxLiveBarCount`): a bar cut off meanwhile would leave a hole between the page and the
  series. The next update after the request trims again.
- **A domain that waits for the finger.** History that arrives beyond the reserve while the window moves extends the domain
  when the window stops; the end of a touch without a fling, and its cancellation, check that too.

## Drawings

- **Core owns the decisions.** `DrawingEditor` is a pure state machine: creation (anchors placed, time snapped to the nearest
  bucket start of the interval's grid, price free), selection, hit testing, dragging an anchor or the body (the body moves by one
  snapped shift, so a drawing whose anchors are off the grid keeps its shape), locking, removal. It takes taps and drags with
  a `DrawingContext` (tools, domain, `ChartTransform`, tolerance, interval) and returns `DrawingEvent`s. A `DrawingTool` turns anchors
  into `DrawingPrimitive`s (segment, horizontal line, vertical line); the default hit test works on the primitives, and a tool
  can implement `hitTest` itself (it is a requirement of the protocol, so the editor calls the tool's own).
- **The model is glue.** `TradingChartModel+Drawing` owns the editor, builds the context from the current window and the shown Y
  domain, feeds the editor the touches of the input layer and forwards events to `onEvent`.
- **The overlay draws.** `DrawingLayout` (pure) clips every primitive to the window in data space (Liang-Barsky, `ChartDomain.clip`;
  the window plus a margin in X, the shown range in Y) and only then maps it to the screen, so a ray that runs to the end of the
  series or a line anchored far away never sends huge coordinates to the canvas. `DrawingsOverlay` strokes the result with the
  style of the drawing (`theme.drawingDefault` when there is no colour), a halo and handles for the selected one.

Drawings do not rebuild the charts: adding, selecting and dragging touch only the overlay, and the tests count the bodies of
the panes to prove it. A drawing whose tool is not registered is kept and not drawn.

## Indicators

An indicator is a `Sendable` value with `calculate(_:) -> IndicatorOutput`. The model recalculates all indicators whenever the
series changes and caches the outputs by id (an indicator with a repeated id is dropped). Overlays draw in the main pane and
their values enter the autoscale; a pane indicator with a non-empty output gets a pane of `paneHeight`. Lines without a colour
take theme palette colours, dealt out per indicator in order (`IndicatorPalette`: an indicator takes `max(paletteSlot) + 1`
slots, so Bollinger Bands are one colour and the two lines of MACD differ). The cost of a live update is the full recalculation
(O(n) per indicator, about a millisecond for five indicators on 5,000 bars); an incremental protocol would remove it and is not in
the first version.

## Extending

- **Indicators**: conform to `ChartIndicator`; see the *Extending the chart* article of the DocC catalog.
- **Drawing tools**: conform to `DrawingTool` and `register` in `model.drawingTools`; `DrawingKind` is an open set.
- **Look**: `TradingChartTheme`, `PriceFormatter` (told where the text goes: axis, badge, crosshair, legend, compact) and
  `TimeFormatter`, all through the SwiftUI environment. **Words**: `TradingChartStrings` (VoiceOver, the badge, the spinner, the
  tooltip rows, the style picker), also through the environment; translated by the package itself (see [Languages](#languages-and-right-to-left)).
- **Controls**: `IndicatorBar` and `SeriesStylePicker` are public views that act on the model; the chart does not need them.

## Known limitations of Swift Charts on iOS 27, and what the package does about them

| Finding | Consequence in the package |
| --- | --- |
| `chartPlotStyle { $0.clipped() }` on a scrollable chart removes the time axis labels | the pane view is clipped with `.clipped()`; the axes are drawn by the package anyway |
| `annotation(position:)` of a `PointMark` with a custom symbol is shifted by a constant offset | marker and high/low labels are drawn by `Canvas` |
| `chartPlotStyle { padding }` moves the plot instead of shrinking it | the domain of a fixed-range pane gets its padding in data space |
| `proxy.plotFrame` of a scrollable chart is the whole content, not the visible window | the visible plot is computed from the window and the pane geometry |
| a `PreferenceKey` from `chartOverlay` / `chartBackground` does not reach the outside | sizes are reported with `onGeometryChange` |
| the chart's own scroll gesture breaks under a transform that changes per frame | the charts take no touches; `ChartInputLayer` scrolls |
| nothing is drawn outside the frame of the chart | the chart is three plot heights tall inside a clip |
| the scroll offset is in points from the left end of the domain, which moves at a prepend or a trim | the held-back left end of the domain, and `scrollNudge` |
| `AxisMarks(.automatic)` builds ticks for the whole scrollable domain | `TimeAxisTicks` and `YAxisTicks`, drawn by `Canvas` |
| `.accessibilityLabel` on a `Chart` replaces the labels of everything inside it | the pane is an accessibility container (`children: .contain`) |
| animating the Y domain (`withAnimation`) makes Charts interpolate every mark on every frame, far dearer than a rebuild | the autoscale is the transform, with no animation |

These are findings of the iOS 27 simulator and Xcode 27.1; some may be fixed in later releases.

## Testing and tools

- `scripts/verify.sh` builds the package, runs every test and builds the demo; `--fast` builds the package and the demo without
  running the tests. It is the definition of done and what CI runs.
- Unit tests (Swift Testing): `Tests/TradingChartCoreTests` and `Tests/TradingChartIndicatorsTests` need no UI (the indicator
  math is compared with reference values computed with TA-Lib); `Tests/TradingChartTests` drives the model, and some tests host a
  real `TradingChartView` in a window to count how often the panes are rebuilt. `PerformanceTests` (XCTest `measure`) only
  measure: there are no time assertions, so `verify.sh` cannot fail on timing.
- The demo (`Examples/TradingChartDemo`) takes launch arguments for repeatable runs: `-script` (a timed list of actions: scroll,
  zoom, crosshair, indicators, drawings, a fling), `-perf <scenario>` (frame times, JSON report) and `-diag` (live consistency
  counters on a HUD). `scripts/frame-check.py` records the simulator and checks every frame of the video for blank panes, cut-off
  candles, labels that disagree with the autoscale and panes that disagree with each other: a pixel check that complements the
  model-level invariants. See [Performance.md](Performance.md).
