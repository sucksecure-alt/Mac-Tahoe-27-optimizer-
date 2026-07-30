import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case dashboard = "Обзор"
    case cleaner = "Очистка"
    case performance = "Оптимизация"
    case maintenance = "Обслуживание"
    case privacy = "Приватность"
    case startup = "Автозагрузка"
    case monitor = "Мониторинг"
    case processes = "Процессы"
    case tools = "Инструменты"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .cleaner: return "trash.fill"
        case .performance: return "bolt.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .privacy: return "hand.raised.fill"
        case .startup: return "power"
        case .monitor: return "chart.xyaxis.line"
        case .processes: return "list.bullet.rectangle"
        case .tools: return "folder.fill.badge.gearshape"
        }
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var stats = SystemStats()
    @Published var tab: AppTab = .dashboard
    private var timer: Timer?
    private var cpuSmooth: [Double] = []

    let chip = SystemInfoService.shared.chipName()
    let cores = SystemInfoService.shared.coreCount()
    let osVer = SystemInfoService.shared.osVersion()

    var uptime: String { TimeFormatter.uptime(stats.uptime) }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        Task {
            var s = await Task.detached(priority: .utility) {
                SystemInfoService.shared.getStats()
            }.value
            self.cpuSmooth.append(s.cpuUsage)
            if self.cpuSmooth.count > 20 { self.cpuSmooth.removeFirst() }
            s.cpuUsage = self.cpuSmooth.reduce(0, +) / Double(self.cpuSmooth.count)
            self.stats = s
        }
    }
}

@MainActor
final class CleanerViewModel: ObservableObject {
    @Published var categories: [CleanCategory] = []
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var lastCleaned: Int64 = 0
    @Published var showResult = false

    var totalSize: Int64 {
        categories.reduce(0) { $0 + $1.size }
    }

    var selectedSize: Int64 {
        categories.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }

    var selectedCount: Int {
        categories.filter(\.isSelected).count
    }

    func scan() {
        isScanning = true
        Task {
            var cats = CleanerService.shared.categories()
            await Task.detached(priority: .userInitiated) {
                CleanerService.shared.scanSizes(&cats)
            }.value
            withAnimation(.spring(duration: 0.4)) {
                self.categories = cats
            }
            self.isScanning = false
        }
    }

    func clean() {
        isCleaning = true
        Task {
            let selected = self.categories
            let freed = await Task.detached(priority: .userInitiated) {
                CleanerService.shared.clean(selected)
            }.value
            withAnimation {
                self.lastCleaned = freed
                self.isCleaning = false
                self.showResult = true
            }
            self.scan()
        }
    }

    func selectAll(_ on: Bool) {
        for i in categories.indices {
            categories[i].isSelected = on
        }
    }

    func selectSafe() {
        for i in categories.indices {
            categories[i].isSelected = categories[i].risk == 0
        }
    }
}

@MainActor
final class PerformanceViewModel: ObservableObject {
    @Published var toggles: [OptimizationToggle] = []
    @Published var isLoading = true
    @Published var showConfirm = false

    var categories: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for t in toggles where !seen.contains(t.category) {
            seen.insert(t.category)
            result.append(t.category)
        }
        return result
    }

    func forCategory(_ cat: String) -> [OptimizationToggle] {
        toggles.filter { $0.category == cat }
    }

    var selectedCount: Int {
        toggles.filter(\.isSelected).count
    }

    init() {
        toggles = PerformanceService.shared.toggles()
    }

    func loadStates() {
        isLoading = true
        Task {
            let ts = self.toggles
            let states = await Task.detached(priority: .userInitiated) {
                ts.map { t -> (UUID, Bool) in
                    if t.isOneShot { return (t.id, false) }
                    return (t.id, PerformanceService.shared.check(t))
                }
            }.value
            for (id, state) in states {
                if let idx = self.toggles.firstIndex(
                    where: { $0.id == id }
                ) {
                    self.toggles[idx].isEnabled = state
                }
            }
            withAnimation { self.isLoading = false }
        }
    }

    func apply(_ t: OptimizationToggle, on: Bool) {
        Task.detached {
            PerformanceService.shared.apply(t, on: on)
        }
    }

    func runOnce(_ t: OptimizationToggle) {
        Task.detached {
            PerformanceService.shared.apply(t, on: true)
        }
    }

    func applySelected() {
        for t in toggles where t.isSelected {
            if t.isOneShot {
                Task.detached {
                    PerformanceService.shared.apply(t, on: true)
                }
            } else {
                let on = !t.isEnabled
                if let idx = toggles.firstIndex(where: { $0.id == t.id }) {
                    toggles[idx].isEnabled = on
                }
                Task.detached {
                    PerformanceService.shared.apply(t, on: on)
                }
            }
        }
    }

    func selectAll(_ on: Bool) {
        for i in toggles.indices {
            toggles[i].isSelected = on
        }
    }
}

@MainActor
final class MaintenanceViewModel: ObservableObject {
    @Published var tasks: [MaintenanceTask] = []
    @Published var runningId: UUID? = nil

    init() {
        tasks = MaintenanceService.shared.tasks()
    }

    func run(_ task: MaintenanceTask) {
        runningId = task.id
        Task {
            let cmd = task.command
            let root = task.needsRoot
            let r = await Task.detached(priority: .userInitiated) {
                Shell.run(cmd, root: root)
            }.value
            if let idx = self.tasks.firstIndex(
                where: { $0.id == task.id }
            ) {
                self.tasks[idx].lastResult =
                    r.code == 0 ? "✅ Выполнено" : "❌ Ошибка"
            }
            self.runningId = nil
        }
    }

    func runSelected() {
        for t in tasks where t.isSelected { run(t) }
    }

    func selectAll(_ on: Bool) {
        for i in tasks.indices { tasks[i].isSelected = on }
    }
}

@MainActor
final class PrivacyViewModel: ObservableObject {
    @Published var tasks: [MaintenanceTask] = []
    @Published var runningId: UUID? = nil

    init() {
        tasks = PrivacyService.shared.tasks()
    }

    func run(_ task: MaintenanceTask) {
        runningId = task.id
        Task {
            let cmd = task.command
            let root = task.needsRoot
            let r = await Task.detached(priority: .userInitiated) {
                Shell.run(cmd, root: root)
            }.value
            if let idx = self.tasks.firstIndex(
                where: { $0.id == task.id }
            ) {
                self.tasks[idx].lastResult =
                    r.code == 0 ? "✅ Выполнено" : "❌ Ошибка"
            }
            self.runningId = nil
        }
    }

    func runSelected() {
        for t in tasks where t.isSelected { run(t) }
    }

    func selectAll(_ on: Bool) {
        for i in tasks.indices { tasks[i].isSelected = on }
    }
}

@MainActor
final class StartupViewModel: ObservableObject {
    @Published var agents: [LaunchAgent] = []
    @Published var isScanning = false
    @Published var searchText = ""

    var filtered: [LaunchAgent] {
        if searchText.isEmpty { return agents }
        return agents.filter {
            $0.label.localizedCaseInsensitiveContains(searchText)
                || $0.shortName.localizedCaseInsensitiveContains(searchText)
        }
    }

    func scan() {
        isScanning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                LaunchAgentService.shared.scan()
            }.value
            withAnimation(.spring(duration: 0.3)) {
                self.agents = result
            }
            self.isScanning = false
        }
    }

    func toggle(_ agent: LaunchAgent) {
        Task.detached {
            LaunchAgentService.shared.toggle(agent)
        }
    }
}

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published var cpuHistory: [DataPoint] = []
    @Published var ramHistory: [DataPoint] = []
    @Published var netDownHistory: [DataPoint] = []
    @Published var netUpHistory: [DataPoint] = []
    @Published var current = SystemStats()
    private var timer: Timer?
    private var cpuSmooth: [Double] = []

    var uptimeShort: String {
        TimeFormatter.short(current.uptime)
    }

    func start() {
        tick()
        timer = Timer.scheduledTimer(
            withTimeInterval: 2.5, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        Task {
            let s = await Task.detached(priority: .utility) {
                SystemInfoService.shared.getStats()
            }.value
            self.current = s
            let now = Date()
            self.cpuHistory.append(DataPoint(time: now, value: s.cpuUsage))
            self.ramHistory.append(DataPoint(time: now, value: s.ramUsedGB))
            self.netDownHistory.append(DataPoint(time: now, value: s.netDownload / 1_048_576))
            self.netUpHistory.append(DataPoint(time: now, value: s.netUpload / 1_048_576))
            let limit = 80
            if self.cpuHistory.count > limit { self.cpuHistory.removeFirst() }
            if self.ramHistory.count > limit { self.ramHistory.removeFirst() }
            if self.netDownHistory.count > limit { self.netDownHistory.removeFirst() }
            if self.netUpHistory.count > limit { self.netUpHistory.removeFirst() }
        }
    }
}

@MainActor
final class ProcessesViewModel: ObservableObject {
    @Published var processes: [ProcessInfo_Custom] = []
    @Published var isLoading = false
    private var timer: Timer?
    private var cpuSmooth: [Double] = []

    func start() {
        refresh()
        timer = Timer.scheduledTimer(
            withTimeInterval: 3, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        isLoading = true
        Task {
            let procs = await Task.detached(priority: .userInitiated) {
                SystemInfoService.shared.topProcesses(limit: 20)
            }.value
            withAnimation {
                self.processes = procs
                self.isLoading = false
            }
        }
    }

    func kill(pid: Int32) {
        Shell.run("kill -9 \(pid)", root: true)
        refresh()
    }
}

@MainActor
final class ToolsViewModel: ObservableObject {
    @Published var largeFiles: [LargeFile] = []
    @Published var folderUsage: [FolderUsage] = []
    @Published var networkResults: [NetworkResult] = []
    @Published var isScanningFiles = false
    @Published var isScanningFolders = false
    @Published var isRunningNet = false
    @Published var minSizeMB: Int = 500
    @Published var networkTarget: String = "google.com"
    @Published var selectedTool: Int = 0

    func scanLargeFiles() {
        isScanningFiles = true
        let minMB = self.minSizeMB
        Task {
            let files = await Task.detached(priority: .userInitiated) {
                SystemInfoService.shared.largeFiles(
                    minMB: minMB, limit: 30
                )
            }.value
            withAnimation {
                self.largeFiles = files
                self.isScanningFiles = false
            }
        }
    }

    func scanFolders() {
        isScanningFolders = true
        Task {
            let folders = await Task.detached(priority: .userInitiated) {
                SystemInfoService.shared.folderUsage()
            }.value
            withAnimation {
                self.folderUsage = folders
                self.isScanningFolders = false
            }
        }
    }

    func runNetworkTool() {
        isRunningNet = true
        let target = self.networkTarget
        let tool = self.selectedTool
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let svc = SystemInfoService.shared
                let toolName: String
                let output: String
                switch tool {
                case 0:
                    toolName = "Ping"
                    output = svc.ping(target)
                case 1:
                    toolName = "DNS Lookup"
                    output = svc.dnsLookup(target)
                case 2:
                    toolName = "Traceroute"
                    output = svc.traceroute(target)
                default:
                    toolName = "Whois"
                    output = svc.whois(target)
                }
                return (toolName, output)
            }.value
            withAnimation {
                self.networkResults.insert(
                    NetworkResult(
                        tool: result.0,
                        target: target,
                        output: result.1,
                        timestamp: Date()
                    ),
                    at: 0
                )
                self.isRunningNet = false
            }
        }
    }

    func reveal(_ path: String) {
        Shell.run("open -R '\(path)'")
    }
}
