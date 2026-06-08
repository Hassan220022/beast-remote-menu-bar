import Foundation

// Pure formatting/math helpers shared by the model and views. Kept as free
// functions (no state) so they're trivially unit-testable.

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "--:--" }
    let total = Int(seconds.rounded(.down))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let remaining = total % 60
    if hours > 0 {
        return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", remaining))"
    }
    return "\(minutes):\(String(format: "%02d", remaining))"
}

func parseDuration(_ duration: String?) -> Double? {
    guard let duration else { return nil }
    let parts = duration.split(separator: ":").map { Double($0) }
    guard parts.allSatisfy({ $0 != nil }) else { return nil }
    let values = parts.compactMap { $0 }
    switch values.count {
    case 2:
        return values[0] * 60 + values[1]
    case 3:
        return values[0] * 3600 + values[1] * 60 + values[2]
    default:
        return nil
    }
}

func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
}
