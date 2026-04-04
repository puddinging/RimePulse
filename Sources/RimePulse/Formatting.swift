import Foundation

func compactNumber(_ n: Int) -> String {
    if n >= 100_000_000 {
        return String(format: "%.1f亿", Double(n) / 100_000_000)
    } else if n >= 10_000 {
        return String(format: "%.1f万", Double(n) / 10_000)
    } else if n >= 1_000 {
        return String(format: "%.1f千", Double(n) / 1_000)
    }
    return "\(n)"
}

func formattedDuration(_ minutes: Double) -> String {
    let hours = Int(minutes) / 60
    let mins = Int(minutes) % 60
    if hours > 0 {
        return "\(hours) 时 \(mins) 分"
    }
    return String(format: "%.0f 分钟", minutes)
}
