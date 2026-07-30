import Foundation

struct SystemStats {
    var cpuUsage: Double = 0
    var cpuTemp: Double = 0
    var ramUsedGB: Double = 0
    var ramTotalGB: Double = 0
    var ramWiredGB: Double = 0
    var ramCompressedGB: Double = 0
    var ramCachedGB: Double = 0
    var ramFreeGB: Double = 0
    var diskUsedGB: Double = 0
    var diskTotalGB: Double = 0
    var diskReadSpeed: Double = 0
    var diskWriteSpeed: Double = 0
    var netDownload: Double = 0
    var netUpload: Double = 0
    var uptime: TimeInterval = 0
    var processCount: Int = 0
    var swapUsedGB: Double = 0

    var ramPercent: Double {
        ramTotalGB > 0 ? ramUsedGB / ramTotalGB * 100 : 0
    }

    var diskPercent: Double {
        diskTotalGB > 0 ? diskUsedGB / diskTotalGB * 100 : 0
    }

    var diskFreeGB: Double {
        max(0, diskTotalGB - diskUsedGB)
    }

    var diskUsedBytes: Int64 {
        Int64(diskUsedGB * 1_073_741_824)
    }

    var score: Int {
        let cpuScore = max(0, 100 - Int(cpuUsage))
        let ramScore = max(0, 100 - Int(ramPercent))
        let diskScore = max(0, 100 - Int(diskPercent))
        let tempPenalty = cpuTemp > 80 ? 10 : (cpuTemp > 65 ? 5 : 0)
        return max(0, min(100, (cpuScore + ramScore + diskScore) / 3 - tempPenalty))
    }

    var scoreLabel: String {
        if score >= 80 { return "Отлично" }
        if score >= 60 { return "Хорошо" }
        if score >= 40 { return "Средне" }
        return "Требует внимания"
    }
}

struct CleanCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let description: String
    let paths: [String]
    let isSpecial: Bool
    let risk: Int
    var size: Int64 = 0
    var isSelected: Bool = true

    var sizeFormatted: String {
        ByteFormatter.format(size)
    }
}

struct LaunchAgent: Identifiable {
    let id = UUID()
    let label: String
    let path: String
    let isDaemon: Bool
    var isEnabled: Bool
    let program: String

    var shortName: String {
        label.components(separatedBy: ".").last ?? label
    }
}

struct OptimizationToggle: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let description: String
    let category: String
    let checkCommand: String
    let enableCommand: String
    let disableCommand: String
    let needsRoot: Bool
    let isOneShot: Bool
    let impact: Int
    var isEnabled: Bool = false
    var isSelected: Bool = true
}

struct MaintenanceTask: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let description: String
    let command: String
    let needsRoot: Bool
    var lastResult: String? = nil
    var isSelected: Bool = true
}

struct ProcessInfo_Custom: Identifiable {
    let id = UUID()
    let name: String
    let pid: Int32
    let cpuPercent: Double
    let memMB: Double
}

struct DataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
}

struct LargeFile: Identifiable {
    let id = UUID()
    let path: String
    let size: Int64

    var name: String {
        (path as NSString).lastPathComponent
    }

    var sizeFormatted: String {
        ByteFormatter.format(size)
    }
}

struct FolderUsage: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let sizeBytes: Int64

    var sizeFormatted: String {
        ByteFormatter.format(sizeBytes)
    }
}

struct NetworkResult: Identifiable {
    let id = UUID()
    let tool: String
    let target: String
    let output: String
    let timestamp: Date
}

enum ByteFormatter {
    static func format(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 B" }
        let tb = Double(bytes) / 1_099_511_627_776
        if tb >= 1 { return String(format: "%.2f TB", tb) }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        let kb = Double(bytes) / 1024
        if kb >= 1 { return String(format: "%.0f KB", kb) }
        return "\(bytes) B"
    }

    static func formatSpeed(_ bps: Double) -> String {
        if bps >= 1_073_741_824 {
            return String(format: "%.1f GB/s", bps / 1_073_741_824)
        }
        if bps >= 1_048_576 {
            return String(format: "%.0f MB/s", bps / 1_048_576)
        }
        if bps >= 1024 {
            return String(format: "%.0f KB/s", bps / 1024)
        }
        return String(format: "%.0f B/s", bps)
    }
}

enum TimeFormatter {
    static func uptime(_ seconds: TimeInterval) -> String {
        let d = Int(seconds) / 86400
        let h = (Int(seconds) % 86400) / 3600
        let m = (Int(seconds) % 3600) / 60
        if d > 0 { return "\(d)д \(h)ч \(m)м" }
        if h > 0 { return "\(h)ч \(m)м" }
        return "\(m)м"
    }

    static func short(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }
}
