import SwiftUI

@main
struct HeartbleedApp: App {
    @StateObject private var dash = DashboardViewModel()
    @StateObject private var clean = CleanerViewModel()
    @StateObject private var perf = PerformanceViewModel()
    @StateObject private var maint = MaintenanceViewModel()
    @StateObject private var priv = PrivacyViewModel()
    @StateObject private var startup = StartupViewModel()
    @StateObject private var mon = MonitorViewModel()
    @StateObject private var procs = ProcessesViewModel()
    @StateObject private var tools = ToolsViewModel()

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.title3)
                            .foregroundStyle(MFTheme.accent)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Heartbleed")
                                .font(.headline)
                            Text("Optimizer")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
                    .padding(.vertical, 12)

                    List(AppTab.allCases,
                         selection: $dash.tab) { tab in
                        Label(tab.rawValue,
                              systemImage: tab.icon)
                            .tag(tab)
                    }
                    .listStyle(.sidebar)

                    VStack(spacing: 4) {
                        Divider()
                        Text("for macOS 27")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 10)
                    }
                }
                .navigationSplitViewColumnWidth(
                    min: 165, ideal: 190, max: 225
                )
            } detail: {
                Group {
                    switch dash.tab {
                    case .dashboard:
                        DashboardView(vm: dash)
                    case .cleaner:
                        CleanerView(vm: clean)
                    case .performance:
                        PerformanceView(vm: perf)
                    case .maintenance:
                        MaintenanceView(vm: maint)
                    case .privacy:
                        PrivacyView(vm: priv)
                    case .startup:
                        StartupView(vm: startup)
                    case .monitor:
                        MonitorView(vm: mon)
                    case .processes:
                        ProcessesView(vm: procs)
                    case .tools:
                        ToolsView(vm: tools)
                    }
                }
                .frame(maxWidth: .infinity,
                       maxHeight: .infinity)
            }
            .frame(minWidth: 780, minHeight: 540)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 880, height: 600)

        MenuBarExtra {
            VStack(spacing: 14) {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(MFTheme.accent)
                    Text("Heartbleed Optimizer")
                        .font(.headline)
                    Spacer()
                    Text("\(dash.stats.score)/100")
                        .font(.system(
                            .body, design: .rounded,
                            weight: .bold
                        ))
                        .foregroundStyle(
                            dash.stats.score >= 70
                                ? MFTheme.success
                                : dash.stats.score >= 40
                                    ? MFTheme.warning
                                    : MFTheme.danger
                        )
                }

                Divider()

                HStack(spacing: 0) {
                    MenuBarStat(
                        l: "CPU",
                        v: "\(Int(dash.stats.cpuUsage))%",
                        c: MFTheme.warning
                    )
                    Divider().frame(height: 30)
                    MenuBarStat(
                        l: "RAM",
                        v: String(format: "%.0f%%",
                            dash.stats.ramPercent),
                        c: MFTheme.accent
                    )
                    Divider().frame(height: 30)
                    MenuBarStat(
                        l: "Диск",
                        v: String(format: "%.0f%%",
                            dash.stats.diskPercent),
                        c: MFTheme.lavender
                    )
                    Divider().frame(height: 30)
                    MenuBarStat(
                        l: "Swap",
                        v: String(format: "%.1fG",
                            dash.stats.swapUsedGB),
                        c: MFTheme.mint
                    )
                }

                Divider()

                HStack(spacing: 8) {
                    Button {
                        NSApp.activate(
                            ignoringOtherApps: true
                        )
                        for w in NSApp.windows {
                            if w.canBecomeMain {
                                w.makeKeyAndOrderFront(nil)
                                break
                            }
                        }
                    } label: {
                        Label("Открыть",
                              systemImage: "macwindow")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(MFTheme.accent)

                    Button {
                        Shell.run("purge", root: true)
                    } label: {
                        Label("Purge",
                              systemImage: "memorychip")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(MFTheme.success)
                }

                Divider()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Выход",
                          systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(MFTheme.danger)
            }
            .padding(16)
            .frame(width: 300)
            .onAppear { dash.start() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                Text("\(dash.stats.score)")
                    .font(.caption2)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarStat: View {
    let l: String
    let v: String
    let c: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(v)
                .font(.system(
                    .caption, design: .rounded,
                    weight: .bold
                ))
                .foregroundStyle(c)
                .monospacedDigit()
            Text(l)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
