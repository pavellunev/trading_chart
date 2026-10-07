import Charts

@available(iOS 17.0, *)
extension SeriesInterpolation {
    var chartsMethod: InterpolationMethod {
        switch self {
        case .linear: .linear
        case .catmullRom: .catmullRom
        case .monotone: .monotone
        }
    }
}
