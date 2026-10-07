import SwiftUI
import TradingChart

/// The demo screen in the dense layout of an exchange app: the interval row, the chart (the style is chosen on the chart itself,
/// with the icon at the top right), the row of indicator switches and the drawing tools, with no cards and little air.
struct ContentView: View {
    @State private var viewModel = DemoViewModel()
    /// The drawings as JSON: `ChartDrawing` is `Codable`, so saving them is a matter of encoding the array.
    @AppStorage("demo.drawings") private var storedDrawings = ""

    var body: some View {
        VStack(spacing: 0) {
            IntervalBar(viewModel: viewModel)
            chart
            IndicatorBar(model: viewModel.model, catalog: DemoViewModel.catalog)
            DrawingToolbar(model: viewModel.model)
        }
        .padding(.horizontal, 8)
        .background(Color(.secondarySystemBackground).ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            if viewModel.perfTag != nil || viewModel.isDiagnosing {
                PerfHUD(recorder: viewModel.recorder)
            }
        }
        .task {
            // `-no-restore`: start without the saved drawings (scripted screenshots and measurements).
            if !ProcessInfo.processInfo.arguments.contains("-no-restore") {
                viewModel.model.drawings = DrawingStore.decode(storedDrawings)
            }
            await viewModel.start()
        }
        // Saved when a drawing is added, changed (at the end of a drag) or removed, not on every step of a drag.
        .onChange(of: viewModel.drawingsRevision) {
            storedDrawings = DrawingStore.encode(viewModel.model.drawings)
        }
    }

    private var chart: some View {
        TradingChartView(model: viewModel.model)
            // The demo app is not localized, so its chart would be English; this one follows the device (`-AppleLanguages`).
            .tradingChartStrings(.localized(for: Locale(identifier: Locale.preferredLanguages.first ?? "en")))
            .opacity(viewModel.isLoading ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.15), value: viewModel.isLoading)
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                }
            }
    }
}

/// The intervals as a row of text, as exchange apps show them: `1m 5m 15m 1h 4h 1D`, the chosen one in the primary colour and
/// semibold. Sized like ``IndicatorBar`` (the theme's font, spacing and height) so that the two rows match.
private struct IntervalBar: View {
    let viewModel: DemoViewModel

    private let theme = TradingChartTheme.standard

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DemoViewModel.intervalOptions) { option in
                let isSelected = viewModel.selectedInterval == option.interval
                Button {
                    viewModel.selectedInterval = option.interval
                } label: {
                    Text(option.title)
                        .font(theme.indicatorBarFont)
                        .fontWeight(isSelected ? .semibold : nil)
                        .foregroundStyle(isSelected ? theme.indicatorBarSelected : theme.indicatorBarUnselected)
                        .padding(.horizontal, theme.indicatorBarSpacing / 2)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityIdentifier("interval.\(option.title)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .frame(height: theme.indicatorBarHeight)
    }
}

#Preview {
    ContentView()
}
