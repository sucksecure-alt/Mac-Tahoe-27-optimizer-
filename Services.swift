import Foundation
import IOKit

enum Shell {
    @discardableResult
    static func run(_ cmd: String, root: Bool = false) -> (out: String, code: Int32) {
        let p = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        if root {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            let escaped = cmd
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            p.arguments = ["-e",
                "do shell script \"\(escaped)\" with administrator privileges"]
        } else {
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", cmd]
        }

        do {
            try p.run()
            p.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (out, p.terminationStatus)
        } catch {
            return ("", 1)
        }
    }
}

final class SystemInfoService {
    static let shared = SystemInfoService()

    private var prevCpu: (u: Int64, s: Int64, i: Int64, n: Int64)?
    private var prevNet: (i: UInt64, o: UInt64)?
    private var prevTime: Date?

    func getStats() -> SystemStats {
        var st = SystemStats()
        let now = Date()
        let dt = prevTime.map { now.timeIntervalSince($0) } ?? 1.0

        // CPU
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0
        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )
        if kr == KERN_SUCCESS, let info = cpuInfo {
            var u: Int64 = 0
            var s: Int64 = 0
            var i: Int64 = 0
            var n: Int64 = 0
            for j in 0..<Int(numCPUs) {
                let base = Int(CPU_STATE_MAX) * j
                u += Int64(info[base + Int(CPU_STATE_USER)])
                s += Int64(info[base + Int(CPU_STATE_SYSTEM)])
                i += Int64(info[base + Int(CPU_STATE_IDLE)])
                n += Int64(info[base + Int(CPU_STATE_NICE)])
            }
            if let prev = prevCpu {
                let du = u - prev.u
                let ds = s - prev.s
                let di = i - prev.i
                let dn = n - prev.n
                let total = du + ds + di + dn
                if total > 0 {
                    st.cpuUsage = Double(du + ds + dn) / Double(total) * 100
                }
            }
            prevCpu = (u, s, i, n)
            let size = MemoryLayout<integer_t>.stride * Int(numCpuInfo)
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(size)
            )
        }

        // RAM
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size
                / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { intPtr in
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    intPtr,
                    &count
                )
            }
        }
        if result == KERN_SUCCESS {
            let pg = UInt64(pageSize)
            let active = UInt64(vmStats.active_count) * pg
            let wired = UInt64(vmStats.wire_count) * pg
            let compressed = UInt64(vmStats.compressor_page_count) * pg
            let free = UInt64(vmStats.free_count) * pg
            let inactive = UInt64(vmStats.inactive_count) * pg
            let speculative = UInt64(vmStats.speculative_count) * pg

            st.ramUsedGB = Double(active + wired + compressed) / 1_073_741_824
            st.ramWiredGB = Double(wired) / 1_073_741_824
            st.ramCompressedGB = Double(compressed) / 1_073_741_824
            st.ramCachedGB = Double(inactive + speculative) / 1_073_741_824
            st.ramFreeGB = Double(free) / 1_073_741_824
            st.ramTotalGB = Double(
                active + wired + compressed + free + inactive + speculative
            ) / 1_073_741_824
        }

        // Swap
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            st.swapUsedGB = Double(swapUsage.xsu_used) / 1_073_741_824
        }

        // Disk
        if let url = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first,
           let vals = try? url.resourceValues(forKeys: [
               .volumeAvailableCapacityForImportantUsageKey,
               .volumeTotalCapacityKey
           ]),
           let avail = vals.volumeAvailableCapacityForImportantUsage,
           let total = vals.volumeTotalCapacity {
            let totalI64 = Int64(total)
            let availI64 = Int64(avail)
            st.diskUsedGB = Double(totalI64 - availI64) / 1_073_741_824
            st.diskTotalGB = Double(totalI64) / 1_073_741_824
        }

        // Disk I/O
        let iostat = Shell.run("iostat -d -c 2 2>/dev/null | tail -1").out
        let ioParts = iostat.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        if ioParts.count >= 3,
           let rd = Double(ioParts[1]),
           let wr = Double(ioParts[2]) {
            st.diskReadSpeed = rd * 1024
            st.diskWriteSpeed = wr * 1024
        }

        // Network
        let netstat = Shell.run(
            "netstat -ibn 2>/dev/null | grep -m1 'en0'"
        ).out
        let netParts = netstat.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        if netParts.count >= 10,
           let ibytes = UInt64(netParts[6]),
           let obytes = UInt64(netParts[9]) {
            if let prev = prevNet {
                st.netDownload = Double(ibytes - prev.i) / dt
                st.netUpload = Double(obytes - prev.o) / dt
            }
            prevNet = (ibytes, obytes)
        }

        // Uptime
        var bootTime = timeval()
        var len = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &bootTime, &len, nil, 0) == 0 {
            st.uptime = Date().timeIntervalSince1970
                - Double(bootTime.tv_sec)
        }

        // Process count
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var klen = 0
        if sysctl(&mib, 4, nil, &klen, nil, 0) == 0 {
            st.processCount = klen / MemoryLayout<kinfo_proc>.size
        }

        prevTime = now
        return st
    }

    func chipName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let str = String(cString: buf)
        return str.isEmpty ? "Apple Silicon" : str
    }

    func coreCount() -> (perf: Int, eff: Int) {
        var p: Int32 = 0
        var e: Int32 = 0
        var sz = MemoryLayout<Int32>.size
        sysctlbyname("hw.perflevel0.logicalcpu", &p, &sz, nil, 0)
        sysctlbyname("hw.perflevel1.logicalcpu", &e, &sz, nil, 0)
        if p == 0 && e == 0 {
            p = Int32(ProcessInfo.processInfo.processorCount)
        }
        return (Int(p), Int(e))
    }

    func osVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    func topProcesses(limit: Int = 20) -> [ProcessInfo_Custom] {
        let raw = Shell.run(
            "ps aux -r 2>/dev/null | head -\(limit + 1) | tail -\(limit)"
        ).out
        var result: [ProcessInfo_Custom] = []
        for line in raw.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard parts.count >= 11,
                  let pid = Int32(parts[1]),
                  let cpu = Double(parts[2]),
                  let mem = Double(parts[5]) else { continue }
            let name = parts[10...].joined(separator: " ")
            result.append(ProcessInfo_Custom(
                name: (name as NSString).lastPathComponent,
                pid: pid,
                cpuPercent: cpu,
                memMB: mem / 1024
            ))
        }
        return result
    }

    func largeFiles(minMB: Int, limit: Int = 30) -> [LargeFile] {
        let raw = Shell.run(
            "find ~ -type f -size +\(minMB)M " +
            "-exec stat -f '%z %N' {} \\; 2>/dev/null | " +
            "sort -rn | head -\(limit)"
        ).out
        var files: [LargeFile] = []
        for line in raw.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2, let sz = Int64(parts[0]) {
                files.append(LargeFile(path: String(parts[1]), size: sz))
            }
        }
        return files
    }

    func folderUsage() -> [FolderUsage] {
        let dirs = [
            ("~/Library", "Библиотека"),
            ("~/Documents", "Документы"),
            ("~/Downloads", "Загрузки"),
            ("~/Desktop", "Рабочий стол"),
            ("~/Applications", "Приложения"),
            ("~/Movies", "Фильмы"),
            ("~/Music", "Музыка"),
            ("~/Pictures", "Фото"),
            ("~/.Trash", "Корзина"),
            ("/Applications", "Системные приложения"),
            ("/Library", "Системная библиотека"),
            ("/System", "Система"),
        ]
        var result: [FolderUsage] = []
        for (path, label) in dirs {
            let expanded = NSString(string: path).expandingTildeInPath
            let r = Shell.run("du -sk '\(expanded)' 2>/dev/null | cut -f1").out
            if let kb = Int64(r) {
                result.append(FolderUsage(
                    name: label,
                    path: expanded,
                    sizeBytes: kb * 1024
                ))
            }
        }
        return result.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    func ping(_ host: String) -> String {
        Shell.run("ping -c 4 -t 5 '\(host)' 2>&1").out
    }

    func dnsLookup(_ host: String) -> String {
        Shell.run("nslookup '\(host)' 2>&1").out
    }

    func traceroute(_ host: String) -> String {
        Shell.run("traceroute -m 15 -w 2 '\(host)' 2>&1 | head -20").out
    }

    func whois(_ domain: String) -> String {
        Shell.run("whois '\(domain)' 2>&1 | head -30").out
    }
}

final class CleanerService {
    static let shared = CleanerService()
    private let fm = FileManager.default

    func categories() -> [CleanCategory] {
        let h = NSHomeDirectory()
        return [
            CleanCategory(name: "Системные кэши", icon: "archivebox.fill",
                description: "Кэши приложений и системы",
                paths: [h + "/Library/Caches"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Логи приложений", icon: "doc.text.fill",
                description: "Логи и crash-отчёты",
                paths: [h + "/Library/Logs",
                        h + "/Library/Logs/DiagnosticReports"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Корзина", icon: "trash.fill",
                description: "Удалённые файлы",
                paths: [h + "/.Trash"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Xcode DerivedData", icon: "hammer.fill",
                description: "Кэш сборки Xcode",
                paths: [h + "/Library/Developer/Xcode/DerivedData"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Xcode Archives", icon: "shippingbox.fill",
                description: "Архивы сборок",
                paths: [h + "/Library/Developer/Xcode/Archives"],
                isSpecial: false, risk: 1),
            CleanCategory(name: "Xcode DeviceSupport", icon: "iphone.gen2",
                description: "Поддержка старых iOS/watchOS/tvOS",
                paths: [h + "/Library/Developer/Xcode/iOS DeviceSupport",
                        h + "/Library/Developer/Xcode/watchOS DeviceSupport",
                        h + "/Library/Developer/Xcode/tvOS DeviceSupport"],
                isSpecial: false, risk: 1),
            CleanCategory(name: "Xcode CoreSimulator", icon: "iphone.gen1",
                description: "Кэш симуляторов",
                paths: [h + "/Library/Developer/CoreSimulator"],
                isSpecial: false, risk: 1),
            CleanCategory(name: "iOS Backups", icon: "iphone.gen3",
                description: "Бэкапы iPhone/iPad",
                paths: [h + "/Library/Application Support/MobileSync/Backup"],
                isSpecial: false, risk: 2),
            CleanCategory(name: "Homebrew кэш", icon: "mug.fill",
                description: "Пакеты Homebrew",
                paths: [h + "/Library/Caches/Homebrew"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "npm кэш", icon: "cube.fill",
                description: "Кэш Node.js",
                paths: [h + "/.npm/_cacache"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "pip кэш", icon: "chevron.left.forwardslash.chevron.right",
                description: "Кэш Python",
                paths: [h + "/Library/Caches/pip"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "CocoaPods кэш", icon: "leaf.fill",
                description: "Кэш CocoaPods",
                paths: [h + "/Library/Caches/CocoaPods"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Yarn кэш", icon: "wind",
                description: "Кэш Yarn",
                paths: [h + "/Library/Caches/Yarn"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Cargo кэш", icon: "gearshape.fill",
                description: "Кэш Rust",
                paths: [h + "/.cargo/registry/cache"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Gradle кэш", icon: "graduationcap.fill",
                description: "Кэш Gradle",
                paths: [h + "/.gradle/caches"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Maven кэш", icon: "m.square.fill",
                description: "Кэш Maven",
                paths: [h + "/.m2/repository"],
                isSpecial: false, risk: 1),
            CleanCategory(name: "Go кэш", icon: "goforward",
                description: "Кэш Go модулей",
                paths: [h + "/go/pkg/mod/cache"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Mail вложения", icon: "envelope.open.fill",
                description: "Вложения Mail",
                paths: [h + "/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"],
                isSpecial: false, risk: 1),
            CleanCategory(name: "Safari кэш", icon: "safari.fill",
                description: "Кэш Safari",
                paths: [h + "/Library/Caches/com.apple.Safari"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Chrome кэш", icon: "globe",
                description: "Кэш Chrome",
                paths: [h + "/Library/Caches/Google/Chrome"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Firefox кэш", icon: "flame.fill",
                description: "Кэш Firefox",
                paths: [h + "/Library/Caches/Firefox"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "VS Code кэш", icon: "chevron.left.forwardslash.chevron.right",
                description: "Кэш Visual Studio Code",
                paths: [h + "/Library/Application Support/Code/Cache",
                        h + "/Library/Application Support/Code/CachedData"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Slack кэш", icon: "number.square.fill",
                description: "Кэш Slack",
                paths: [h + "/Library/Application Support/Slack/Cache"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Discord кэш", icon: "gamecontroller.fill",
                description: "Кэш Discord",
                paths: [h + "/Library/Application Support/discord/Cache"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Telegram кэш", icon: "paperplane.fill",
                description: "Кэш Telegram",
                paths: [h + "/Library/Group Containers/*.TelegramDesktop"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Docker данные", icon: "container",
                description: "Образы Docker",
                paths: [h + "/Library/Containers/com.docker.docker/Data/vms"],
                isSpecial: false, risk: 2),
            CleanCategory(name: "QuickLook кэш", icon: "eye.fill",
                description: "Кэш предпросмотра",
                paths: [h + "/Library/Caches/com.apple.QuickLook.thumbnailcache"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Spotlight кэш", icon: "magnifyingglass",
                description: "Кэш индексации",
                paths: ["/.Spotlight-V100"],
                isSpecial: false, risk: 1),
            CleanCategory(name: "Кэш шрифтов", icon: "textformat",
                description: "Кэш ATS",
                paths: [h + "/Library/Caches/com.apple.FontRegistry"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Crash Reporter", icon: "exclamationmark.triangle.fill",
                description: "Отчёты о сбоях",
                paths: ["/Library/Logs/DiagnosticReports",
                        h + "/Library/Logs/DiagnosticReports"],
                isSpecial: false, risk: 0),
            CleanCategory(name: "Системные логи", icon: "terminal.fill",
                description: "/var/log (root)",
                paths: ["/var/log"],
                isSpecial: false, risk: 1),
            CleanCategory(name: "Кэш обновлений", icon: "arrow.triangle.2.circlepath",
                description: "Загруженные обновления macOS",
                paths: ["/Library/Updates"],
                isSpecial: false, risk: 1),
            CleanCategory(name: "Кэш CUPS", icon: "printer.fill",
                description: "Кэш печати",
                paths: ["/var/spool/cups/cache"],
                isSpecial: false, risk: 0),
            CleanCategory(name: ".DS_Store", icon: "folder.badge.questionmark",
                description: "Файлы Finder",
                paths: [],
                isSpecial: true, risk: 0),
            CleanCategory(name: "Языковые файлы", icon: "globe.americas.fill",
                description: "Неиспользуемые локализации",
                paths: [],
                isSpecial: true, risk: 1),
        ]
    }

    func dirSize(_ path: String) -> Int64 {
        guard fm.fileExists(atPath: path),
              let enumerator = fm.enumerator(
                  at: URL(fileURLWithPath: path),
                  includingPropertiesForKeys: [.fileSizeKey],
                  options: [.skipsHiddenFiles]
              ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let vals = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey]
            ), let size = vals.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func scanSizes(_ cats: inout [CleanCategory]) {
        for i in cats.indices {
            if cats[i].name == ".DS_Store" {
                let r = Shell.run(
                    "find ~ -name '.DS_Store' -print0 2>/dev/null | " +
                    "xargs -0 stat -f '%z' 2>/dev/null | " +
                    "awk '{s+=$1}END{print s+0}'"
                )
                cats[i].size = Int64(r.out) ?? 0
                continue
            }
            if cats[i].name == "Языковые файлы" {
                let r = Shell.run(
                    "find /Applications -name '*.lproj' " +
                    "-not -name 'en.lproj' -not -name 'ru.lproj' " +
                    "-not -name 'Base.lproj' -print0 2>/dev/null | " +
                    "xargs -0 du -sk 2>/dev/null | " +
                    "awk '{s+=$1}END{print s*1024}'"
                )
                cats[i].size = Int64(r.out) ?? 0
                continue
            }
            var total: Int64 = 0
            for p in cats[i].paths {
                total += dirSize(p)
            }
            cats[i].size = total
        }
    }

    func clean(_ cats: [CleanCategory]) -> Int64 {
        var freed: Int64 = 0
        for cat in cats where cat.isSelected {
            if cat.name == ".DS_Store" {
                Shell.run("find ~ -name '.DS_Store' -delete 2>/dev/null")
                freed += 1_000_000
                continue
            }
            if cat.name == "Языковые файлы" {
                Shell.run(
                    "find /Applications -name '*.lproj' " +
                    "-not -name 'en.lproj' -not -name 'ru.lproj' " +
                    "-not -name 'Base.lproj' -exec rm -rf {} + 2>/dev/null",
                    root: true
                )
                freed += cat.size
                continue
            }
            for p in cat.paths {
                guard fm.fileExists(atPath: p) else { continue }
                let size = dirSize(p)
                if let items = try? fm.contentsOfDirectory(atPath: p) {
                    for item in items {
                        let full = (p as NSString)
                            .appendingPathComponent(item)
                        try? fm.removeItem(atPath: full)
                    }
                }
                freed += size
            }
        }
        return freed
    }
}

final class PerformanceService {
    static let shared = PerformanceService()

    func toggles() -> [OptimizationToggle] {
        [
            // ── Система ──
            OptimizationToggle(title: "Отключить Spotlight", icon: "magnifyingglass",
                description: "mds_stores грузит CPU и SSD при индексации",
                category: "Система",
                checkCommand: "mdutil -s / 2>/dev/null | grep -qi 'indexing disabled'",
                enableCommand: "mdutil -a -i off",
                disableCommand: "mdutil -a -i on",
                needsRoot: true, isOneShot: false, impact: 3),
            OptimizationToggle(title: "Отключить Time Machine", icon: "clock.badge.xmark",
                description: "Фоновое резервное копирование",
                category: "Система",
                checkCommand: "tmutil status 2>/dev/null | grep -q 'Disabled = 1'",
                enableCommand: "tmutil disable",
                disableCommand: "tmutil enable",
                needsRoot: true, isOneShot: false, impact: 2),
            OptimizationToggle(title: "Отключить автообновления", icon: "arrow.triangle.2.circlepath",
                description: "softwareupdate в фоне",
                category: "Система",
                checkCommand: "defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload 2>/dev/null | grep -q '0'",
                enableCommand: "defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false",
                disableCommand: "defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true",
                needsRoot: true, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить отчёты об ошибках", icon: "exclamationmark.bubble",
                description: "Crash Reporter в фоне",
                category: "Система",
                checkCommand: "defaults read com.apple.CrashReporter DialogType 2>/dev/null | grep -q 'none'",
                enableCommand: "defaults write com.apple.CrashReporter DialogType -string none",
                disableCommand: "defaults write com.apple.CrashReporter DialogType -string prompt",
                needsRoot: false, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить Siri", icon: "mic.badge.xmark",
                description: "Фоновое прослушивание",
                category: "Система",
                checkCommand: "defaults read com.apple.Siri StatusMenuVisible 2>/dev/null | grep -q '0'",
                enableCommand: "defaults write com.apple.Siri StatusMenuVisible -bool false && defaults write com.apple.Siri UserHasDeclinedEnable -bool true",
                disableCommand: "defaults write com.apple.Siri StatusMenuVisible -bool true",
                needsRoot: false, isOneShot: false, impact: 2),
            OptimizationToggle(title: "Отключить Handoff", icon: "hand.raised.fill",
                description: "Continuity между устройствами",
                category: "Система",
                checkCommand: "defaults read com.apple.coreservices.useractivityd ActivityAdvertisingAllowed 2>/dev/null | grep -q '0'",
                enableCommand: "defaults write com.apple.coreservices.useractivityd ActivityAdvertisingAllowed -bool false",
                disableCommand: "defaults write com.apple.coreservices.useractivityd ActivityAdvertisingAllowed -bool true",
                needsRoot: false, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить telemetry", icon: "antenna.radiowaves.left.and.right",
                description: "Аналитика Apple",
                category: "Система",
                checkCommand: "defaults read /Library/Application\\ Support/CrashReporter/DiagnosticMessagesHistory AutoSubmit 2>/dev/null | grep -q '0'",
                enableCommand: "defaults write /Library/Application\\ Support/CrashReporter/DiagnosticMessagesHistory AutoSubmit -bool false",
                disableCommand: "defaults write /Library/Application\\ Support/CrashReporter/DiagnosticMessagesHistory AutoSubmit -bool true",
                needsRoot: true, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить Tips", icon: "lightbulb",
                description: "Подсказки macOS",
                category: "Система",
                checkCommand: "defaults read com.apple.tipsd tips-disabled 2>/dev/null | grep -q '1'",
                enableCommand: "defaults write com.apple.tipsd tips-disabled -bool true",
                disableCommand: "defaults write com.apple.tipsd tips-disabled -bool false",
                needsRoot: false, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить Autoplay", icon: "play.slash.fill",
                description: "Автовоспроизведение в Finder",
                category: "Система",
                checkCommand: "defaults read com.apple.finder AutoPlay 2>/dev/null | grep -q '0'",
                enableCommand: "defaults write com.apple.finder AutoPlay -bool false",
                disableCommand: "defaults write com.apple.finder AutoPlay -bool true",
                needsRoot: false, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить Recent Apps в Dock", icon: "dock.rectangle",
                description: "Недавние приложения в Dock",
                category: "Система",
                checkCommand: "defaults read com.apple.dock show-recents 2>/dev/null | grep -q '0'",
                enableCommand: "defaults write com.apple.dock show-recents -bool false && killall Dock",
                disableCommand: "defaults write com.apple.dock show-recents -bool true && killall Dock",
                needsRoot: false, isOneShot: false, impact: 1),
            OptimizationToggle(title: "ОтключитьNotificationCenter", icon: "bell.badge",
                description: "Фоновые уведомления",
                category: "Система",
                checkCommand: "defaults read com.apple.controlcenter 'NSStatusItem Visible FocusModes' 2>/dev/null | grep -q '0'",
                enableCommand: "defaults write com.apple.controlcenter 'NSStatusItem Visible FocusModes' -bool false",
                disableCommand: "defaults write com.apple.controlcenter 'NSStatusItem Visible FocusModes' -bool true",
                needsRoot: false, isOneShot: false, impact: 1),

            // ── Память ──
            OptimizationToggle(title: "Purge RAM", icon: "memorychip",
                description: "Освободить неактивную память",
                category: "Память",
                checkCommand: "false",
                enableCommand: "purge",
                disableCommand: "",
                needsRoot: true, isOneShot: true, impact: 2),
            OptimizationToggle(title: "Очистить DNS кэш", icon: "network",
                description: "Сброс mDNSResponder",
                category: "Память",
                checkCommand: "false",
                enableCommand: "dscacheutil -flushcache && killall -HUP mDNSResponder",
                disableCommand: "",
                needsRoot: true, isOneShot: true, impact: 1),
            OptimizationToggle(title: "Сбросить кэш шрифтов", icon: "textformat",
                description: "Перестроить ATS",
                category: "Память",
                checkCommand: "false",
                enableCommand: "atsutil databases -remove && atsutil server -shutdown && atsutil server -ping",
                disableCommand: "",
                needsRoot: false, isOneShot: true, impact: 1),
            OptimizationToggle(title: "Очистить кэш иконок", icon: "photo.on.rectangle",
                description: "Сброс иконок Finder",
                category: "Память",
                checkCommand: "false",
                enableCommand: "find /private/var/folders/ -name com.apple.iconservices -exec rm -rf {} + 2>/dev/null; killall Dock; echo done",
                disableCommand: "",
                needsRoot: true, isOneShot: true, impact: 1),
            OptimizationToggle(title: "Очистить кэш thumbnail", icon: "photo.stack",
                description: "Миниатюры Finder",
                category: "Память",
                checkCommand: "false",
                enableCommand: "rm -rf ~/Library/Caches/com.apple.finder/Thumbnails 2>/dev/null; killall Finder; echo done",
                disableCommand: "",
                needsRoot: false, isOneShot: true, impact: 1),

            // ── Интерфейс ──
            OptimizationToggle(title: "Ускорить Dock", icon: "dock.rectangle",
                description: "Мгновенный Dock",
                category: "Интерфейс",
                checkCommand: "defaults read com.apple.dock autohide-time-modifier 2>/dev/null | grep -q '0.1'",
                enableCommand: "defaults write com.apple.dock autohide-time-modifier -float 0.1 && defaults write com.apple.dock autohide-delay -float 0 && killall Dock",
                disableCommand: "defaults delete com.apple.dock autohide-time-modifier 2>/dev/null; defaults delete com.apple.dock autohide-delay 2>/dev/null; killall Dock",
                needsRoot: false, isOneShot: false, impact: 2),
            OptimizationToggle(title: "Ускорить Mission Control", icon: "square.on.square",
                description: "Быстрые анимации",
                category: "Интерфейс",
                checkCommand: "defaults read com.apple.dock expose-animation-duration 2>/dev/null | grep -q '0.1'",
                enableCommand: "defaults write com.apple.dock expose-animation-duration -float 0.1 && killall Dock",
                disableCommand: "defaults delete com.apple.dock expose-animation-duration 2>/dev/null; killall Dock",
                needsRoot: false, isOneShot: false, impact: 2),
            OptimizationToggle(title: "Ускорить окна", icon: "macwindow",
                description: "Быстрое открытие/закрытие",
                category: "Интерфейс",
                checkCommand: "defaults read -g NSWindowResizeTime 2>/dev/null | grep -q '0.1'",
                enableCommand: "defaults write -g NSWindowResizeTime -float 0.1 && defaults write -g NSAutomaticWindowAnimationsEnabled -bool false",
                disableCommand: "defaults delete -g NSWindowResizeTime 2>/dev/null; defaults write -g NSAutomaticWindowAnimationsEnabled -bool true",
                needsRoot: false, isOneShot: false, impact: 2),
            OptimizationToggle(title: "Отключить прозрачность", icon: "square.on.square.dashed",
                description: "Меньше нагрузка на GPU",
                category: "Интерфейс",
                checkCommand: "defaults read com.apple.universalaccess reduceTransparency 2>/dev/null | grep -q '1'",
                enableCommand: "defaults write com.apple.universalaccess reduceTransparency -bool true",
                disableCommand: "defaults write com.apple.universalaccess reduceTransparency -bool false",
                needsRoot: false, isOneShot: false, impact: 3),
            OptimizationToggle(title: "Отключить Dashboard", icon: "gauge.with.dots.needle.bottom.50percent",
                description: "Убрать виджеты",
                category: "Интерфейс",
                checkCommand: "defaults read com.apple.dashboard mcx-disabled 2>/dev/null | grep -q '1'",
                enableCommand: "defaults write com.apple.dashboard mcx-disabled -bool true && killall Dock",
                disableCommand: "defaults write com.apple.dashboard mcx-disabled -bool false && killall Dock",
                needsRoot: false, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить spring-loading", icon: "folder.fill",
                description: "Автооткрытие папок",
                category: "Интерфейс",
                checkCommand: "defaults read -g com.apple.springing.enabled 2>/dev/null | grep -q '0'",
                enableCommand: "defaults write -g com.apple.springing.enabled -bool false",
                disableCommand: "defaults write -g com.apple.springing.enabled -bool true",
                needsRoot: false, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Уменьшить иконки Dock", icon: "dock.arrowrectangle",
                description: "Меньше отрисовки",
                category: "Интерфейс",
                checkCommand: "defaults read com.apple.dock tilesize 2>/dev/null | grep -q '36'",
                enableCommand: "defaults write com.apple.dock tilesize -int 36 && killall Dock",
                disableCommand: "defaults write com.apple.dock tilesize -int 48 && killall Dock",
                needsRoot: false, isOneShot: false, impact: 1),

            // ── Ввод ──
            OptimizationToggle(title: "Отключить автокоррекцию", icon: "character.cursor.ibeam",
                description: "Проверка орфографии",
                category: "Ввод",
                checkCommand: "defaults read -g NSAutomaticSpellingCorrectionEnabled 2>/dev/null | grep -q '0'",
                enableCommand: "defaults write -g NSAutomaticSpellingCorrectionEnabled -bool false",
                disableCommand: "defaults write -g NSAutomaticSpellingCorrectionEnabled -bool true",
                needsRoot: false, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить автокапитализацию", icon: "textformat.abc",
                description: "Автозаглавные",
                category: "Ввод",
                checkCommand: "defaults read -g NSAutomaticCapitalizationEnabled 2>/dev/null | grep -q '0'",
                enableCommand: "defaults write -g NSAutomaticCapitalizationEnabled -bool false",
                disableCommand: "defaults write -g NSAutomaticCapitalizationEnabled -bool true",
                needsRoot: false, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить умные кавычки", icon: "text.quote",
                description: "Автозамена кавычек",
                category: "Ввод",
                checkCommand: "defaults read -g NSAutomaticQuoteSubstitutionEnabled 2>/dev/null | grep -q '0'",
                enableCommand: "defaults write -g NSAutomaticQuoteSubstitutionEnabled -bool false",
                disableCommand: "defaults write -g NSAutomaticQuoteSubstitutionEnabled -bool true",
                needsRoot: false, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить умные тире", icon: "minus",
                description: "Автозамена тире",
                category: "Ввод",
                checkCommand: "defaults read -g NSAutomaticDashSubstitutionEnabled 2>/dev/null | grep -q '0'",
                enableCommand: "defaults write -g NSAutomaticDashSubstitutionEnabled -bool false",
                disableCommand: "defaults write -g NSAutomaticDashSubstitutionEnabled -bool true",
                needsRoot: false, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить предиктивный ввод", icon: "keyboard.badge.ellipsis",
                description: "Предложения слов",
                category: "Ввод",
                checkCommand: "defaults read -g NSAutomaticPeriodSubstitutionEnabled 2>/dev/null | grep -q '0'",
                enableCommand: "defaults write -g NSAutomaticPeriodSubstitutionEnabled -bool false",
                disableCommand: "defaults write -g NSAutomaticPeriodSubstitutionEnabled -bool true",
                needsRoot: false, isOneShot: false, impact: 1),

            // ── Сеть ──
            OptimizationToggle(title: "Очистить сетевые кэши", icon: "wifi",
                description: "Сброс сети",
                category: "Сеть",
                checkCommand: "false",
                enableCommand: "dscacheutil -flushcache && killall -HUP mDNSResponder",
                disableCommand: "",
                needsRoot: true, isOneShot: true, impact: 1),
            OptimizationToggle(title: "Отключить IPv6", icon: "globe.badge.chevron.backward",
                description: "Если не используется",
                category: "Сеть",
                checkCommand: "networksetup -getinfo Wi-Fi 2>/dev/null | grep -q 'IPv6: Off'",
                enableCommand: "networksetup -setv6off Wi-Fi",
                disableCommand: "networksetup -setv6automatic Wi-Fi",
                needsRoot: true, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить Wake on LAN", icon: "powerplug",
                description: "Пробуждение по сети",
                category: "Сеть",
                checkCommand: "pmset -g 2>/dev/null | grep -q 'womp.*0'",
                enableCommand: "pmset -a womp 0",
                disableCommand: "pmset -a womp 1",
                needsRoot: true, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить Bonjour", icon: "dot.radiowaves.left.and.right",
                description: "Обнаружение устройств",
                category: "Сеть",
                checkCommand: "defaults read /Library/Preferences/com.apple.mDNSResponder NoMulticastAdvertisements 2>/dev/null | grep -q '1'",
                enableCommand: "defaults write /Library/Preferences/com.apple.mDNSResponder NoMulticastAdvertisements -bool true",
                disableCommand: "defaults write /Library/Preferences/com.apple.mDNSResponder NoMulticastAdvertisements -bool false",
                needsRoot: true, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Очистить ARP кэш", icon: "arrow.triangle.branch",
                description: "Сброс ARP таблицы",
                category: "Сеть",
                checkCommand: "false",
                enableCommand: "arp -ad 2>/dev/null; echo done",
                disableCommand: "",
                needsRoot: true, isOneShot: true, impact: 1),

            // ── Энергия ──
            OptimizationToggle(title: "Отключить Power Nap", icon: "moon.zzz.fill",
                description: "Фоновые задачи во сне",
                category: "Энергия",
                checkCommand: "pmset -g 2>/dev/null | grep -q 'powernap.*0'",
                enableCommand: "pmset -a powernap 0",
                disableCommand: "pmset -a powernap 1",
                needsRoot: true, isOneShot: false, impact: 2),
            OptimizationToggle(title: "Отключить proximity wake", icon: "network.badge.shield.half.filled",
                description: "Пробуждение от устройств",
                category: "Энергия",
                checkCommand: "pmset -g 2>/dev/null | grep -q 'proximitywake.*0'",
                enableCommand: "pmset -a proximitywake 0",
                disableCommand: "pmset -a proximitywake 1",
                needsRoot: true, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить hibernation", icon: "moon.fill",
                description: "Запись RAM на диск",
                category: "Энергия",
                checkCommand: "pmset -g 2>/dev/null | grep -q 'hibernatemode.*0'",
                enableCommand: "pmset -a hibernatemode 0",
                disableCommand: "pmset -a hibernatemode 3",
                needsRoot: true, isOneShot: false, impact: 2),
            OptimizationToggle(title: "Отключить TCP keepalive", icon: "arrow.triangle.pull",
                description: "Сетевые пакеты во сне",
                category: "Энергия",
                checkCommand: "pmset -g 2>/dev/null | grep -q 'tcpkeepalive.*0'",
                enableCommand: "pmset -a tcpkeepalive 0",
                disableCommand: "pmset -a tcpkeepalive 1",
                needsRoot: true, isOneShot: false, impact: 1),
            OptimizationToggle(title: "Отключить wake для сети", icon: "wifi.exclamationmark",
                description: "Пробуждение по Wi-Fi",
                category: "Энергия",
                checkCommand: "pmset -g 2>/dev/null | grep -q 'networkoversleep.*0'",
                enableCommand: "pmset -a networkoversleep 0",
                disableCommand: "pmset -a networkoversleep 1",
                needsRoot: true, isOneShot: false, impact: 1),
        ]
    }

    func check(_ t: OptimizationToggle) -> Bool {
        Shell.run(t.checkCommand).code == 0
    }

    func apply(_ t: OptimizationToggle, on: Bool) {
        let cmd = on ? t.enableCommand : t.disableCommand
        guard !cmd.isEmpty else { return }
        Shell.run(cmd, root: t.needsRoot)
    }
}

final class MaintenanceService {
    static let shared = MaintenanceService()

    func tasks() -> [MaintenanceTask] {
        [
            MaintenanceTask(title: "Rebuild Spotlight", icon: "magnifyingglass",
                description: "Переиндексация Spotlight",
                command: "mdutil -E /", needsRoot: true),
            MaintenanceTask(title: "Rebuild Launch Services", icon: "rocket.fill",
                description: "Перестроить Launch Services",
                command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user",
                needsRoot: false),
            MaintenanceTask(title: "Repair permissions", icon: "lock.shield.fill",
                description: "Восстановить права",
                command: "diskutil resetUserPermissions / $(id -u)",
                needsRoot: true),
            MaintenanceTask(title: "Periodic daily", icon: "calendar",
                description: "Ежедневные скрипты",
                command: "periodic daily", needsRoot: true),
            MaintenanceTask(title: "Periodic weekly", icon: "calendar.badge.clock",
                description: "Еженедельные скрипты",
                command: "periodic weekly", needsRoot: true),
            MaintenanceTask(title: "Periodic monthly", icon: "calendar.badge.checkmark",
                description: "Ежемесячные скрипты",
                command: "periodic monthly", needsRoot: true),
            MaintenanceTask(title: "Rebuild dyld cache", icon: "cpu",
                description: "Кэш линковщика",
                command: "update_dyld_shared_cache -force",
                needsRoot: true),
            MaintenanceTask(title: "Reset QuickLook", icon: "eye",
                description: "Сброс предпросмотра",
                command: "qlmanage -r cache && qlmanage -r",
                needsRoot: false),
            MaintenanceTask(title: "Очистить симуляторы", icon: "iphone.gen1",
                description: "Удалить старые симуляторы",
                command: "xcrun simctl delete unavailable 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить SwiftPM", icon: "swift",
                description: "Кэш Swift пакетов",
                command: "rm -rf ~/Library/Caches/org.swift.swiftpm 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить Composer", icon: "music.note",
                description: "Кэш PHP",
                command: "rm -rf ~/.composer/cache ~/.cache/composer 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить NuGet", icon: "n.circle.fill",
                description: "Кэш .NET",
                command: "rm -rf ~/.nuget/packages 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить Thumbnails", icon: "photo.stack",
                description: "Кэш миниатюр",
                command: "rm -rf ~/Library/Caches/com.apple.finder/Thumbnails 2>/dev/null; killall Finder; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Проверить диск", icon: "cross.case.fill",
                description: "Verify volume",
                command: "diskutil verifyVolume / 2>&1 | tail -3",
                needsRoot: true),
            MaintenanceTask(title: "Очистить CUPS", icon: "printer.fill",
                description: "Кэш печати",
                command: "rm -rf /var/spool/cups/cache/* 2>/dev/null; echo done",
                needsRoot: true),
            MaintenanceTask(title: "Очистить кэш Xcode", icon: "hammer",
                description: "Старые данные Xcode",
                command: "rm -rf ~/Library/Developer/Xcode/iOS\\ DeviceLogs 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить кэш pip", icon: "chevron.left.forwardslash.chevron.right",
                description: "Кэш Python пакетов",
                command: "pip cache purge 2>/dev/null; rm -rf ~/Library/Caches/pip 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить кэш npm", icon: "cube.fill",
                description: "Кэш Node.js пакетов",
                command: "npm cache clean --force 2>/dev/null; echo done",
                needsRoot: false),
        ]
    }
}

final class PrivacyService {
    static let shared = PrivacyService()

    func tasks() -> [MaintenanceTask] {
        [
            MaintenanceTask(title: "Очистить Recent Items", icon: "clock.arrow.circlepath",
                description: "Недавние документы",
                command: "rm -rf ~/Library/Application\\ Support/com.apple.sharedfilelist/* 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить clipboard", icon: "clipboard",
                description: "История буфера",
                command: "rm -rf ~/Library/Caches/com.apple.pasteboard* 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить локации", icon: "location.fill",
                description: "Данные геолокации",
                command: "rm -rf /var/db/locationd/* 2>/dev/null; echo done",
                needsRoot: true),
            MaintenanceTask(title: "Очистить Safari", icon: "safari",
                description: "История Safari",
                command: "rm -rf ~/Library/Safari/History.db ~/Library/Safari/LastSession.plist 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить Spotlight", icon: "magnifyingglass",
                description: "История поиска",
                command: "rm -rf ~/Library/Application\\ Support/com.apple.spotlight.mds 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить App Store", icon: "bag.fill",
                description: "Данные App Store",
                command: "defaults delete com.apple.appstore 2>/dev/null; rm -rf ~/Library/Caches/com.apple.appstore 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить Finder", icon: "folder.fill",
                description: "Недавние папки",
                command: "rm -rf ~/Library/Preferences/com.apple.finder.plist 2>/dev/null; killall Finder; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить Terminal", icon: "terminal",
                description: "История команд",
                command: "rm -rf ~/.zsh_history ~/.bash_history 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить SSH", icon: "key.fill",
                description: "known_hosts",
                command: "rm -rf ~/.ssh/known_hosts 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить AirDrop", icon: "airpods",
                description: "История AirDrop",
                command: "rm -rf ~/Library/Preferences/com.apple.NetworkBrowser.plist 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить Preview", icon: "doc.viewfinder",
                description: "Недавние документы",
                command: "rm -rf ~/Library/Containers/com.apple.Preview/Data/Library/Preferences 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить QuickTime", icon: "play.rectangle.fill",
                description: "Недавние медиа",
                command: "rm -rf ~/Library/Preferences/com.apple.QuickTimePlayerX.plist 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить кэш клавиатуры", icon: "keyboard",
                description: "Данные автокоррекции",
                command: "rm -rf ~/Library/Dictionaries/CoreDataUbiquitySupport 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить кэш Photos", icon: "photo.fill",
                description: "Кэш приложения Фото",
                command: "rm -rf ~/Library/Containers/com.apple.Photos/Data/Library/Caches 2>/dev/null; echo done",
                needsRoot: false),
            MaintenanceTask(title: "Очистить кэш Maps", icon: "map.fill",
                description: "Кэш карт",
                command: "rm -rf ~/Library/Containers/com.apple.Maps/Data/Library/Caches 2>/dev/null; echo done",
                needsRoot: false),
        ]
    }
}

final class LaunchAgentService {
    static let shared = LaunchAgentService()

    func scan() -> [LaunchAgent] {
        var agents: [LaunchAgent] = []
        let dirs: [(String, Bool)] = [
            (NSHomeDirectory() + "/Library/LaunchAgents", false),
            ("/Library/LaunchAgents", false),
            ("/Library/LaunchDaemons", true),
        ]
        for (dir, isDaemon) in dirs {
            guard let files = try? FileManager.default
                .contentsOfDirectory(atPath: dir) else { continue }
            for f in files where f.hasSuffix(".plist") {
                let full = (dir as NSString).appendingPathComponent(f)
                guard let dict = NSDictionary(contentsOfFile: full)
                    as? [String: Any],
                      let label = dict["Label"] as? String else { continue }
                if label.hasPrefix("com.apple.") { continue }
                let program = dict["Program"] as? String
                    ?? (dict["ProgramArguments"] as? [String])?.first
                    ?? "unknown"
                let enabled = Shell.run(
                    "launchctl list 2>/dev/null | grep -q '\(label)'"
                ).code == 0
                agents.append(LaunchAgent(
                    label: label, path: full, isDaemon: isDaemon,
                    isEnabled: enabled, program: program
                ))
            }
        }
        return agents.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label)
                == .orderedAscending
        }
    }

    func toggle(_ agent: LaunchAgent) -> Bool {
        let action = agent.isEnabled ? "unload" : "load"
        let cmd = "launchctl \(action) -w \(agent.path)"
        return Shell.run(cmd, root: agent.isDaemon).code == 0
    }
}
