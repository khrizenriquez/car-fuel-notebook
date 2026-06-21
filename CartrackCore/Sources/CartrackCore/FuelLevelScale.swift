import Foundation

enum FuelLevelScale {
    static let defaultMax: Double = 8.0
    static let defaultStep: Double = 0.25

    static func normalize(_ value: Double, maxValue: Double = defaultMax, step: Double = defaultStep) -> Double {
        let clamped = min(max(value, 0), maxValue)
        let steps = (clamped / step).rounded()
        return min(maxValue, max(0, steps * step))
    }

    static func consumed(remaining: Double, maxValue: Double = defaultMax, step: Double = defaultStep) -> Double {
        normalize(maxValue - normalize(remaining, maxValue: maxValue, step: step), maxValue: maxValue, step: step)
    }
}
