import Foundation

public enum ByteFormatters {
    public static func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 o" }
        let units = ["o", "Ko", "Mo", "Go", "To", "Po"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        if index == 0 {
            return "\(Int(value)) o"
        }
        return String(format: value >= 100 ? "%.0f %@" : "%.1f %@", value, units[index])
    }

    public static func formatDecimalTB(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 To" }
        let tb = Double(bytes) / 1_000_000_000_000
        return String(format: "%.1f To", tb)
    }

    public static func formatSpeed(_ bytesPerSec: Int64?) -> String {
        guard let bytesPerSec, bytesPerSec > 0 else { return "0 o/s" }
        return "\(formatBytes(bytesPerSec))/s"
    }

    public static func formatETA(_ seconds: Int) -> String {
        if seconds <= 0 || seconds >= 8_640_000 { return "∞" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    public static func formatTimestamp(_ unixSeconds: Int) -> String {
        guard unixSeconds > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    public static func formatRelativeISO(_ isoString: String?) -> String {
        guard let isoString, !isoString.isEmpty else { return "Jamais" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString)
        guard let date else { return "Récent" }
        let rel = RelativeDateTimeFormatter()
        rel.locale = Locale(identifier: "fr_FR")
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
