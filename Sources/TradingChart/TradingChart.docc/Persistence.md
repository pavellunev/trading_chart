# Remembering the user's settings

Restore the style, the indicators and the drawings after a restart, with one setting.

## Overview

A chart that forgets the style the user chose, the indicators they switched on and the lines they drew every time the app starts is a chart that has to be set up again every time. Set ``TradingChartConfiguration/persistence`` and the model does the remembering: it restores what was saved when it is created, before the first frame, and saves again whenever the user changes something.

```swift
var configuration = TradingChartConfiguration()
configuration.stylePicker = StylePickerOptions()
configuration.persistence = ChartPersistence(
    key: "chart",                    // the namespace of everything saved
    indicatorCatalog: catalog,       // the catalog of the IndicatorBar
    drawingsKey: symbol              // nil: the drawings are not saved
)
let model = TradingChartModel(style: .candles, configuration: configuration)
```

The style given to the model is the default of a first launch: a saved style replaces it.

## What is saved

- **The style** (``TradingChartModel/style``), when ``ChartPersistence/persistsStyle`` is on. A saved style that the style picker does not offer (``StylePickerOptions/availableStyles``) is not restored.
- **The indicators** (``TradingChartModel/indicators``), when ``ChartPersistence/persistsIndicators`` is on. Indicators are code, so what is saved is their ``ChartIndicator/id``s, and the indicators are taken from ``ChartPersistence/indicatorCatalog``, the catalog you give to ``IndicatorBar``. They come back in the order of the catalog, which also fixes their colours, and an id the catalog does not know is ignored. Because the catalog supplies the instance, an indicator comes back with the parameters and the style the catalog gives it.
- **The drawings** (``TradingChartModel/drawings``), when ``ChartPersistence/drawingsKey`` is set. The selection, the tool being used and the scroll position are not saved.

## When it is written

Creating the model and putting saved values back write nothing. The one exception is a change of the drawings' key (and a persistence with another ``ChartPersistence/key``, flags or catalog replacing this one): the drawings on the chart are first saved under the old ``ChartPersistence/drawingsKey``, so that they are not lost. After that:

| What | Written when |
| --- | --- |
| the style | ``TradingChartModel/style`` changes |
| the indicators | ``TradingChartModel/indicators`` change (a different set of ids) |
| the drawings | one is added, changed (at the end of a drag, not on every step of it) or removed, and when ``TradingChartModel/drawings`` is assigned; deleting every drawing is one write |

A value that is set to what it already is writes nothing.

## One chart, several symbols

The drawings belong to ``ChartPersistence/drawingsKey``, which can be the symbol on the chart. When the chart shows another symbol, change the key:

```swift
model.setSeries(series(for: symbol))
model.configuration.persistence?.drawingsKey = symbol
```

The drawings on the chart are saved under the old key, and the ones saved under the new key are shown. When nothing is saved under the new key, the chart is emptied if its drawings belong to another key, but drawings that belong to no key (the chart had no key before) are kept, and the first key adopts them. A drawing that is half placed is dropped, and the tool stays selected.

Do not assign ``TradingChartModel/drawings`` (clearing them included) before you change the key: any assignment is saved under the old key and replaces what was saved there. Setting the key to `nil` leaves the drawings on the chart and stops saving them; they stay the old key's, so another key set afterwards shows its own drawings and does not adopt them.

## Defaults for a first launch

The model keeps what it has for everything that is not saved. So when the first launch should show indicators of your own, set them before the persistence:

```swift
let model = TradingChartModel(style: .candles)
model.indicators = [SMA(period: 20), Volume(movingAveragePeriod: 20)]
model.configuration.persistence = ChartPersistence(key: "chart", indicatorCatalog: catalog)
```

If the user has saved a selection (an empty one included) it replaces yours; otherwise yours stay. Setting ``TradingChartConfiguration/persistence`` later, or changing its ``ChartPersistence/key``, its flags or its catalog, restores the same way, in one update of the chart.

## Where it is saved

The records are kept in a ``ChartPreferencesStore``: ``UserDefaultsChartPreferencesStore`` on `UserDefaults.standard` by default. Pass ``ChartPersistence/store`` another one to use a suite of an app group, a file, the keychain or a database; the protocol has two methods, one that loads `Data` for a key and one that saves it.

Each record is a small JSON object with a `version`. The chart reads a record only when it can: damaged data, data of another shape and a record of a newer version of the package are ignored, as if nothing had been saved, and the next change overwrites them. A saved value never breaks the chart.
