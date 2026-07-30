import SwiftUI
import Charts

// MARK: - Gauge Ring
struct GaugeRing: View {
    let value: Double
    let label: String
    let sub: String
    let color: Color
    var size: CGFloat = 110

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.06), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(value, 100) / 100)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.4), color],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(
                            lineWidth: 8, lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(
                        .spring(duration: 0.8, bounce: 0.2),
                        value: value
                    )
                VStack(spacing: 2) {
                    Text("\(Int(value))%")
                        .font(.system(
                            .title3, design: .rounded,
                            weight: .bold
                        ))
                        .monospacedDigit()
                    Text(sub)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: size, height: size)
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Score Ring
struct ScoreRing: View {
    let score: Int
    let label: String

    var color: Color {
        if score >= 70 { return MFTheme.success }
        if score >= 40 { return MFTheme.warning }
        return MFTheme.danger
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.05), lineWidth: 13)
            Circle()
                .trim(from: 0, to: Double(score) / 100)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.25), color],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(
                        lineWidth: 13, lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    .spring(duration: 1.2, bounce: 0.15),
                    value: score
                )
            VStack(spacing: 4) {
                Text("\(score)")
                    .font(.system(
                        size: 44, weight: .bold,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .foregroundStyle(color)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 150, height: 150)
    }
}

// MARK: - Info Card
struct InfoCard: View {
    let icon: String
    let title: String
    let value: String
    var color: Color = MFTheme.accent

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.system(
                    .body, design: .rounded,
                    weight: .semibold
                ))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .mfCard(8, 14)
    }
}

// MARK: - Quick Button
struct QuickBtn: View {
    let title: String
    let sub: String
    let icon: String
    let grad: LinearGradient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(grad, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: MFTheme.cardShadow, radius: 5, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dashboard
struct DashboardView: View {
    @ObservedObject var vm: DashboardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    ScoreRing(
                        score: vm.stats.score,
                        label: vm.stats.scoreLabel
                    )
                    Text("Состояние системы")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)

                HStack(spacing: 24) {
                    GaugeRing(
                        value: vm.stats.cpuUsage,
                        label: "CPU",
                        sub: String(format: "%.0f°C", vm.stats.cpuTemp),
                        color: MFTheme.warning
                    )
                    GaugeRing(
                        value: vm.stats.ramPercent,
                        label: "RAM",
                        sub: String(format: "%.1f/%.0f GB",
                            vm.stats.ramUsedGB, vm.stats.ramTotalGB),
                        color: MFTheme.accent
                    )
                    GaugeRing(
                        value: vm.stats.diskPercent,
                        label: "Диск",
                        sub: String(format: "%.0f GB своб.",
                            vm.stats.diskFreeGB),
                        color: MFTheme.lavender
                    )
                }

                HStack(spacing: 14) {
                    QuickBtn(
                        title: "Очистить",
                        sub: ByteFormatter.format(vm.stats.diskUsedBytes)
                            + " занято",
                        icon: "trash.fill",
                        grad: MFTheme.accentGradient
                    ) { vm.tab = .cleaner }
                    QuickBtn(
                        title: "Оптимизировать",
                        sub: "Ускорить систему",
                        icon: "bolt.fill",
                        grad: MFTheme.warmGradient
                    ) { vm.tab = .performance }
                    QuickBtn(
                        title: "Мониторинг",
                        sub: "Реалтайм",
                        icon: "chart.xyaxis.line",
                        grad: MFTheme.successGradient
                    ) { vm.tab = .monitor }
                }

                HStack(spacing: 12) {
                    InfoCard(icon: "cpu", title: "Чип",
                             value: vm.chip, color: .gray)
                    InfoCard(icon: "circle.grid.3x3", title: "Ядра",
                             value: "\(vm.cores.perf)P + \(vm.cores.eff)E",
                             color: MFTheme.accent)
                    InfoCard(icon: "clock", title: "Аптайм",
                             value: vm.uptime, color: MFTheme.success)
                    InfoCard(icon: "arrow.triangle.swap", title: "Swap",
                             value: String(format: "%.1f GB",
                                vm.stats.swapUsedGB),
                             color: MFTheme.lavender)
                    InfoCard(icon: "apple.logo", title: "macOS",
                             value: vm.osVer, color: MFTheme.mint)
                }

                VStack(alignment: .leading, spacing: 8) {
                    MFSectionHeader(
                        title: "Память",
                        icon: "memorychip",
                        sub: String(format: "%.1f GB из %.0f GB",
                            vm.stats.ramUsedGB, vm.stats.ramTotalGB)
                    )
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            Rectangle()
                                .fill(MFTheme.accent)
                                .frame(width: geo.size.width
                                    * vm.stats.ramUsedGB
                                    / max(vm.stats.ramTotalGB, 1))
                            Rectangle()
                                .fill(MFTheme.lavender.opacity(0.5))
                                .frame(width: geo.size.width
                                    * vm.stats.ramCachedGB
                                    / max(vm.stats.ramTotalGB, 1))
                            Rectangle()
                                .fill(MFTheme.accent.opacity(0.08))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .frame(height: 10)
                    HStack(spacing: 16) {
                        LegendDot(color: MFTheme.accent,
                                  label: "Активная")
                        LegendDot(color: MFTheme.lavender.opacity(0.5),
                                  label: "Кэш")
                        LegendDot(color: MFTheme.accent.opacity(0.08),
                                  label: "Свободна")
                    }
                    .font(.caption2)
                }
                .mfCard()
            }
            .padding(24)
        }
        .background(MFTheme.heroGradient.opacity(0.2))
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}

// MARK: - Cleaner
struct CleanerView: View {
    @ObservedObject var vm: CleanerViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Очистка").font(.title2.bold())
                    HStack(spacing: 12) {
                        Label(ByteFormatter.format(vm.totalSize),
                              systemImage: "internaldrive")
                        Label("\(vm.categories.count) категорий",
                              systemImage: "folder")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("Все") { vm.selectAll(true) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(MFTheme.accent)
                    Button("Безопасные") { vm.selectSafe() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(MFTheme.success)
                    Button("Ничего") { vm.selectAll(false) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Divider().frame(height: 20)
                    Button { vm.scan() } label: {
                        Label("Сканировать",
                              systemImage: "arrow.clockwise")
                    }
                    .disabled(vm.isScanning)
                    .tint(MFTheme.accent)
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach($vm.categories) { $cat in
                        HStack(spacing: 14) {
                            Image(systemName: cat.icon)
                                .font(.title3)
                                .foregroundStyle(
                                    cat.isSelected
                                        ? MFTheme.accent
                                        : .secondary
                                )
                                .frame(width: 36, height: 36)
                                .background(
                                    cat.isSelected
                                        ? MFTheme.accent.opacity(0.08)
                                        : .clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(cat.name)
                                        .font(.body.weight(.medium))
                                    RiskBadge(level: cat.risk)
                                }
                                Text(cat.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if cat.size > 0 {
                                Text(cat.sizeFormatted)
                                    .font(.system(
                                        .body, design: .rounded,
                                        weight: .medium
                                    ))
                                    .foregroundStyle(
                                        cat.size > 1_073_741_824
                                            ? MFTheme.warning
                                            : .secondary
                                    )
                                    .monospacedDigit()
                            } else {
                                Text("—")
                                    .foregroundStyle(.tertiary)
                            }
                            Toggle("", isOn: $cat.isSelected)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .tint(MFTheme.accent)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.7))
                                .shadow(color: MFTheme.softShadow,
                                        radius: 2, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(MFTheme.accent.opacity(0.06),
                                        lineWidth: 1)
                        )
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                if vm.lastCleaned > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(MFTheme.success)
                        Text("Освобождено: \(ByteFormatter.format(vm.lastCleaned))")
                            .font(.subheadline)
                            .foregroundStyle(MFTheme.success)
                    }
                }
                Spacer()
                Text("Выбрано: \(ByteFormatter.format(vm.selectedSize))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button { vm.clean() } label: {
                    Label(
                        "Очистить выбранное (\(vm.selectedCount))",
                        systemImage: "trash.fill"
                    )
                    .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(MFTheme.accent)
                .controlSize(.large)
                .disabled(vm.isCleaning || vm.selectedCount == 0)
            }
            .padding(16)
        }
        .background(MFTheme.frost)
        .onAppear {
            if vm.categories.isEmpty { vm.scan() }
        }
        .overlay {
            if vm.isScanning || vm.isCleaning {
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.15))
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.4)
                            .tint(MFTheme.accent)
                        Text(vm.isScanning
                            ? "Сканирование..."
                            : "Очистка...")
                            .font(.headline)
                    }
                    .padding(36)
                    .background(
                        .ultraThickMaterial,
                        in: RoundedRectangle(cornerRadius: 20)
                    )
                    .shadow(radius: 20)
                }
            }
        }
        .alert("Очистка завершена",
               isPresented: $vm.showResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Освобождено \(ByteFormatter.format(vm.lastCleaned))")
        }
    }
}

// MARK: - Performance
struct PerformanceView: View {
    @ObservedObject var vm: PerformanceViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Оптимизация").font(.title2.bold())
                    Text("Галочки для пакетного применения")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("Все") { vm.selectAll(true) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(MFTheme.accent)
                    Button("Ничего") { vm.selectAll(false) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if vm.isLoading {
                        HStack {
                            Spacer()
                            ProgressView("Загрузка...")
                                .padding(40)
                                .tint(MFTheme.accent)
                            Spacer()
                        }
                    } else {
                        ForEach(vm.categories, id: \.self) { cat in
                            VStack(alignment: .leading, spacing: 10) {
                                MFSectionHeader(
                                    title: cat,
                                    icon: catIcon(cat)
                                )
                                ForEach(vm.forCategory(cat)) { t in
                                    if let idx = vm.toggles.firstIndex(
                                        where: { $0.id == t.id }
                                    ) {
                                        OptCard(
                                            toggle: $vm.toggles[idx],
                                            vm: vm
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Text("Выбрано: \(vm.selectedCount) из \(vm.toggles.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { vm.showConfirm = true } label: {
                    Label("Применить выбранные",
                          systemImage: "checkmark.circle.fill")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(MFTheme.accent)
                .controlSize(.large)
                .disabled(vm.selectedCount == 0)
            }
            .padding(16)
        }
        .background(MFTheme.frost)
        .onAppear { vm.loadStates() }
        .alert("Применить?",
               isPresented: $vm.showConfirm) {
            Button("Отмена", role: .cancel) {}
            Button("Применить (\(vm.selectedCount))") {
                vm.applySelected()
            }
        } message: {
            Text("Root-операции запросят пароль.")
        }
    }

    func catIcon(_ c: String) -> String {
        switch c {
        case "Система": return "gearshape.2.fill"
        case "Память": return "memorychip"
        case "Интерфейс": return "macwindow"
        case "Ввод": return "keyboard"
        case "Сеть": return "wifi"
        case "Энергия": return "battery.75percent"
        default: return "wrench"
        }
    }
}

// MARK: - Optimization Card
struct OptCard: View {
    @Binding var toggle: OptimizationToggle
    @ObservedObject var vm: PerformanceViewModel

    var body: some View {
        HStack(spacing: 14) {
            if !toggle.isOneShot {
                Image(systemName:
                    toggle.isSelected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.title3)
                .foregroundStyle(
                    toggle.isSelected
                        ? MFTheme.accent
                        : .secondary
                )
                .onTapGesture {
                    withAnimation(.spring(duration: 0.2)) {
                        toggle.isSelected.toggle()
                    }
                }
            }

            Image(systemName: toggle.icon)
                .font(.title3)
                .foregroundStyle(
                    toggle.isEnabled
                        ? MFTheme.success
                        : MFTheme.accent.opacity(0.5)
                )
                .frame(width: 36, height: 36)
                .background(
                    (toggle.isEnabled
                        ? MFTheme.success
                        : MFTheme.accent
                    ).opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(toggle.title)
                        .font(.body.weight(.medium))
                    if toggle.needsRoot {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(MFTheme.warning)
                    }
                    ImpactDots(count: toggle.impact)
                }
                Text(toggle.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if toggle.isOneShot {
                Button("Выполнить") {
                    vm.runOnce(toggle)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(MFTheme.accent)
            } else {
                Toggle("", isOn: $toggle.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(MFTheme.success)
                    .onChange(of: toggle.isEnabled) { _, v in
                        vm.apply(toggle, on: v)
                    }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.7))
                .shadow(color: MFTheme.softShadow, radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MFTheme.accent.opacity(0.04), lineWidth: 0.5)
        )
    }
}

// MARK: - Task Row
struct TaskRow: View {
    @Binding var task: MaintenanceTask
    let runningId: UUID?
    let runAction: (MaintenanceTask) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName:
                task.isSelected
                    ? "checkmark.circle.fill"
                    : "circle"
            )
            .font(.title3)
            .foregroundStyle(
                task.isSelected ? MFTheme.accent : .secondary
            )
            .onTapGesture {
                withAnimation { task.isSelected.toggle() }
            }

            Image(systemName: task.icon)
                .font(.title3)
                .foregroundStyle(MFTheme.accent.opacity(0.6))
                .frame(width: 36, height: 36)
                .background(
                    MFTheme.accent.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.body.weight(.medium))
                    if task.needsRoot {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(MFTheme.warning)
                    }
                }
                Text(task.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let result = task.lastResult {
                    Text(result)
                        .font(.caption2)
                        .foregroundStyle(
                            result.contains("✅")
                                ? MFTheme.success
                                : MFTheme.danger
                        )
                }
            }

            Spacer()

            if runningId == task.id {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(MFTheme.accent)
            } else {
                Button("Выполнить") {
                    runAction(task)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(MFTheme.accent)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.7))
                .shadow(color: MFTheme.softShadow, radius: 2, y: 1)
        )
    }
}

// MARK: - Maintenance
struct MaintenanceView: View {
    @ObservedObject var vm: MaintenanceViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Обслуживание").font(.title2.bold())
                    Text("Системные скрипты и базы данных")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("Все") { vm.selectAll(true) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(MFTheme.accent)
                    Button("Ничего") { vm.selectAll(false) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(20)
            Divider()
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach($vm.tasks) { $t in
                        TaskRow(
                            task: $t,
                            runningId: vm.runningId,
                            runAction: { vm.run($0) }
                        )
                    }
                }
                .padding(16)
            }
            Divider()
            HStack {
                Text("Выбрано: \(vm.tasks.filter(\.isSelected).count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { vm.runSelected() } label: {
                    Label("Выполнить", systemImage: "play.fill")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(MFTheme.accent)
                .controlSize(.large)
                .disabled(
                    vm.runningId != nil
                        || vm.tasks.filter(\.isSelected).isEmpty
                )
            }
            .padding(16)
        }
        .background(MFTheme.frost)
    }
}

// MARK: - Privacy
struct PrivacyView: View {
    @ObservedObject var vm: PrivacyViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Приватность").font(.title2.bold())
                    Text("Очистка следов активности")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("Все") { vm.selectAll(true) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(MFTheme.accent)
                    Button("Ничего") { vm.selectAll(false) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(20)
            Divider()
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach($vm.tasks) { $t in
                        TaskRow(
                            task: $t,
                            runningId: vm.runningId,
                            runAction: { vm.run($0) }
                        )
                    }
                }
                .padding(16)
            }
            Divider()
            HStack {
                Spacer()
                Button { vm.runSelected() } label: {
                    Label("Очистить",
                          systemImage: "hand.raised.fill")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(MFTheme.accent)
                .controlSize(.large)
                .disabled(
                    vm.runningId != nil
                        || vm.tasks.filter(\.isSelected).isEmpty
                )
            }
            .padding(16)
        }
        .background(MFTheme.frost)
    }
}

// MARK: - Startup
struct StartupView: View {
    @ObservedObject var vm: StartupViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Автозагрузка").font(.title2.bold())
                    Text("Найдено: \(vm.agents.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { vm.scan() } label: {
                    Label("Обновить",
                          systemImage: "arrow.clockwise")
                }
                .disabled(vm.isScanning)
                .tint(MFTheme.accent)
            }
            .padding(20)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Поиск...",
                          text: $vm.searchText)
                    .textFieldStyle(.plain)
                if !vm.searchText.isEmpty {
                    Button { vm.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(
                Color.white.opacity(0.8),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(MFTheme.accent.opacity(0.08),
                            lineWidth: 0.5)
            )
            .padding(.horizontal, 20)

            Divider().padding(.top, 12)

            if vm.filtered.isEmpty && !vm.isScanning {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(MFTheme.success)
                    Text("Нет сторонних агентов")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(vm.filtered) { agent in
                            HStack(spacing: 12) {
                                Image(systemName:
                                    agent.isDaemon
                                        ? "gearshape.2.fill"
                                        : "gearshape.fill"
                                )
                                .foregroundStyle(
                                    agent.isDaemon
                                        ? MFTheme.warning
                                        : MFTheme.accent
                                )
                                .frame(width: 32, height: 32)
                                .background(
                                    (agent.isDaemon
                                        ? MFTheme.warning
                                        : MFTheme.accent
                                    ).opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                                VStack(alignment: .leading,
                                       spacing: 2) {
                                    Text(agent.shortName)
                                        .font(.body.weight(.medium))
                                    Text(agent.label)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                if agent.isDaemon {
                                    Text("daemon")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(
                                            MFTheme.warning.opacity(0.08),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(MFTheme.warning)
                                }
                                Text(agent.isEnabled
                                    ? "Активен" : "Отключён")
                                    .font(.caption)
                                    .foregroundStyle(
                                        agent.isEnabled
                                            ? MFTheme.success
                                            : .secondary
                                    )
                                    .frame(width: 70,
                                           alignment: .trailing)
                                Toggle("", isOn: Binding(
                                    get: { agent.isEnabled },
                                    set: { _ in vm.toggle(agent) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .tint(MFTheme.accent)
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.7))
                                    .shadow(
                                        color: MFTheme.softShadow,
                                        radius: 1, y: 1
                                    )
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(MFTheme.frost)
        .onAppear {
            if vm.agents.isEmpty { vm.scan() }
        }
        .overlay {
            if vm.isScanning {
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.12))
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(MFTheme.accent)
                        Text("Сканирование...")
                            .font(.headline)
                    }
                    .padding(32)
                    .background(
                        .ultraThickMaterial,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                }
            }
        }
    }
}

// MARK: - Chart Card
struct ChartCard: View {
    let title: String
    let icon: String
    let color: Color
    let data: [DataPoint]
    let unit: String
    let current: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer()
                Text(current)
                    .font(.system(
                        .body, design: .rounded,
                        weight: .bold
                    ))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            Chart(data) { point in
                AreaMark(
                    x: .value("Время", point.time),
                    y: .value(unit, point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            color.opacity(0.12),
                            color.opacity(0.01)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Время", point.time),
                    y: .value(unit, point.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(
                    position: .leading,
                    values: .automatic(desiredCount: 3)
                ) {
                    AxisGridLine(
                        stroke: StrokeStyle(
                            lineWidth: 0.5, dash: [4]
                        )
                    )
                    .foregroundStyle(
                        MFTheme.accent.opacity(0.12)
                    )
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 100)
        }
        .mfCard()
    }
}

// MARK: - Stat Box
struct StatBox: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.system(
                    .body, design: .rounded,
                    weight: .bold
                ))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .mfCard(8, 12)
    }
}

// MARK: - Monitor
struct MonitorView: View {
    @ObservedObject var vm: MonitorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Мониторинг")
                    .font(.title2.bold())
                    .padding(.top, 20)

                HStack(spacing: 10) {
                    StatBox(label: "CPU",
                            value: String(format: "%.0f%%",
                                vm.current.cpuUsage),
                            icon: "cpu",
                            color: MFTheme.warning)
                    StatBox(label: "RAM",
                            value: String(format: "%.1f GB",
                                vm.current.ramUsedGB),
                            icon: "memorychip",
                            color: MFTheme.accent)
                    StatBox(label: "Wired",
                            value: String(format: "%.1f GB",
                                vm.current.ramWiredGB),
                            icon: "lock.fill",
                            color: MFTheme.lavender)
                    StatBox(label: "Swap",
                            value: String(format: "%.1f GB",
                                vm.current.swapUsedGB),
                            icon: "arrow.triangle.swap",
                            color: MFTheme.mint)
                    StatBox(label: "Аптайм",
                            value: vm.uptimeShort,
                            icon: "clock",
                            color: MFTheme.success)
                }

                ChartCard(
                    title: "CPU", icon: "cpu",
                    color: MFTheme.warning,
                    data: vm.cpuHistory, unit: "%",
                    current: String(format: "%.0f%%",
                        vm.current.cpuUsage)
                )

                ChartCard(
                    title: "RAM", icon: "memorychip",
                    color: MFTheme.accent,
                    data: vm.ramHistory, unit: "GB",
                    current: String(format: "%.1f GB",
                        vm.current.ramUsedGB)
                )

                HStack(spacing: 12) {
                    ChartCard(
                        title: "Загрузка",
                        icon: "arrow.down.circle",
                        color: MFTheme.success,
                        data: vm.netDownHistory,
                        unit: "MB/s",
                        current: ByteFormatter.formatSpeed(
                            vm.current.netDownload)
                    )
                    ChartCard(
                        title: "Отдача",
                        icon: "arrow.up.circle",
                        color: MFTheme.danger,
                        data: vm.netUpHistory,
                        unit: "MB/s",
                        current: ByteFormatter.formatSpeed(
                            vm.current.netUpload)
                    )
                }

                HStack(spacing: 10) {
                    StatBox(label: "Диск",
                            value: String(format: "%.0f%%",
                                vm.current.diskPercent),
                            icon: "internaldrive",
                            color: MFTheme.lavender)
                    StatBox(label: "Свободно",
                            value: String(format: "%.0f GB",
                                vm.current.diskFreeGB),
                            icon: "externaldrive",
                            color: MFTheme.accent)
                    StatBox(label: "Чтение",
                            value: ByteFormatter.formatSpeed(
                                vm.current.diskReadSpeed),
                            icon: "arrow.down.doc",
                            color: MFTheme.mint)
                    StatBox(label: "Запись",
                            value: ByteFormatter.formatSpeed(
                                vm.current.diskWriteSpeed),
                            icon: "arrow.up.doc",
                            color: MFTheme.success)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(MFTheme.frost)
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }
}

// MARK: - Processes
struct ProcessesView: View {
    @ObservedObject var vm: ProcessesViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Процессы").font(.title2.bold())
                    Text("Топ-20 по CPU")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { vm.refresh() } label: {
                    Label("Обновить",
                          systemImage: "arrow.clockwise")
                }
                .disabled(vm.isLoading)
                .tint(MFTheme.accent)
            }
            .padding(20)

            Divider()

            HStack {
                Text("Процесс")
                    .frame(maxWidth: .infinity,
                           alignment: .leading)
                Text("PID")
                    .frame(width: 60, alignment: .trailing)
                Text("CPU %")
                    .frame(width: 70, alignment: .trailing)
                Text("RAM MB")
                    .frame(width: 80, alignment: .trailing)
                Text("")
                    .frame(width: 36)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(vm.processes) { proc in
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "app.fill")
                                    .font(.caption)
                                    .foregroundStyle(
                                        MFTheme.accent.opacity(0.4)
                                    )
                                Text(proc.name)
                                    .font(.body)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity,
                                   alignment: .leading)

                            Text("\(proc.pid)")
                                .font(.system(
                                    .caption,
                                    design: .monospaced
                                ))
                                .foregroundStyle(.secondary)
                                .frame(width: 60,
                                       alignment: .trailing)

                            Text(String(format: "%.1f",
                                        proc.cpuPercent))
                                .font(.system(
                                    .body, design: .rounded
                                ))
                                .foregroundStyle(
                                    proc.cpuPercent > 50
                                        ? MFTheme.danger
                                        : proc.cpuPercent > 20
                                            ? MFTheme.warning
                                            : .primary
                                )
                                .monospacedDigit()
                                .frame(width: 70,
                                       alignment: .trailing)

                            Text(String(format: "%.0f",
                                        proc.memMB))
                                .font(.system(
                                    .body, design: .rounded
                                ))
                                .monospacedDigit()
                                .frame(width: 80,
                                       alignment: .trailing)

                            Button {
                                vm.kill(pid: proc.pid)
                            } label: {
                                Image(systemName:
                                    "xmark.circle.fill")
                                    .foregroundStyle(
                                        MFTheme.danger.opacity(0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .frame(width: 36)
                            .help("Завершить")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .background(MFTheme.frost)
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .overlay {
            if vm.isLoading && vm.processes.isEmpty {
                ProgressView("Загрузка...")
                    .padding(24)
                    .tint(MFTheme.accent)
                    .background(
                        .ultraThickMaterial,
                        in: RoundedRectangle(cornerRadius: 12)
                    )
            }
        }
    }
}

// MARK: - Tools
struct ToolsView: View {
    @ObservedObject var vm: ToolsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Инструменты")
                    .font(.title2.bold())
                    .padding(.top, 20)

                // ── Large Files ──
                VStack(alignment: .leading, spacing: 12) {
                    MFSectionHeader(
                        title: "Большие файлы",
                        icon: "doc.fill",
                        sub: "Поиск файлов по размеру"
                    )
                    HStack(spacing: 8) {
                        Picker("Мин. размер",
                               selection: $vm.minSizeMB) {
                            Text("100 MB").tag(100)
                            Text("500 MB").tag(500)
                            Text("1 GB").tag(1024)
                            Text("5 GB").tag(5120)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 300)

                        Button {
                            vm.scanLargeFiles()
                        } label: {
                            Label("Сканировать",
                                  systemImage: "magnifyingglass")
                        }
                        .disabled(vm.isScanningFiles)
                        .tint(MFTheme.accent)
                    }

                    if vm.isScanningFiles {
                        HStack {
                            Spacer()
                            ProgressView("Поиск файлов...")
                                .padding(20)
                                .tint(MFTheme.accent)
                            Spacer()
                        }
                    } else if !vm.largeFiles.isEmpty {
                        ForEach(vm.largeFiles) { file in
                            HStack(spacing: 12) {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(
                                        MFTheme.accent.opacity(0.5)
                                    )
                                VStack(alignment: .leading,
                                       spacing: 2) {
                                    Text(file.name)
                                        .font(.body.weight(.medium))
                                        .lineLimit(1)
                                    Text(file.path)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Text(file.sizeFormatted)
                                    .font(.system(
                                        .body, design: .rounded,
                                        weight: .medium
                                    ))
                                    .foregroundStyle(
                                        file.size > 5_368_709_120
                                            ? MFTheme.danger
                                            : file.size > 1_073_741_824
                                                ? MFTheme.warning
                                                : .secondary
                                    )
                                    .monospacedDigit()
                                Button {
                                    vm.reveal(file.path)
                                } label: {
                                    Image(systemName: "folder")
                                        .foregroundStyle(MFTheme.accent)
                                }
                                .buttonStyle(.plain)
                                .help("Показать в Finder")
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.7))
                                    .shadow(
                                        color: MFTheme.softShadow,
                                        radius: 1, y: 1
                                    )
                            )
                        }
                    }
                }
                .mfCard()

                // ── Disk Usage ──
                VStack(alignment: .leading, spacing: 12) {
                    MFSectionHeader(
                        title: "Использование диска",
                        icon: "internaldrive",
                        sub: "Размер основных папок"
                    )
                    HStack {
                        Spacer()
                        Button {
                            vm.scanFolders()
                        } label: {
                            Label("Сканировать",
                                  systemImage: "arrow.clockwise")
                        }
                        .disabled(vm.isScanningFolders)
                        .tint(MFTheme.accent)
                    }

                    if vm.isScanningFolders {
                        HStack {
                            Spacer()
                            ProgressView("Сканирование папок...")
                                .padding(20)
                                .tint(MFTheme.accent)
                            Spacer()
                        }
                    } else if !vm.folderUsage.isEmpty {
                        let maxSize = vm.folderUsage.first?.sizeBytes ?? 1
                        ForEach(vm.folderUsage) { folder in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(folder.name)
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text(folder.sizeFormatted)
                                        .font(.system(
                                            .caption,
                                            design: .rounded,
                                            weight: .medium
                                        ))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(MFTheme.accent.opacity(0.6))
                                        .frame(width: geo.size.width
                                            * CGFloat(folder.sizeBytes)
                                            / CGFloat(max(maxSize, 1)))
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                }
                .mfCard()

                // ── Network Tools ──
                VStack(alignment: .leading, spacing: 12) {
                    MFSectionHeader(
                        title: "Сетевые инструменты",
                        icon: "network",
                        sub: "Ping, DNS, Traceroute, Whois"
                    )
                    HStack(spacing: 8) {
                        Picker("Инструмент",
                               selection: $vm.selectedTool) {
                            Text("Ping").tag(0)
                            Text("DNS").tag(1)
                            Text("Traceroute").tag(2)
                            Text("Whois").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 300)

                        TextField("Хост (google.com)",
                                  text: $vm.networkTarget)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)

                        Button {
                            vm.runNetworkTool()
                        } label: {
                            Label("Запустить",
                                  systemImage: "play.fill")
                        }
                        .disabled(vm.isRunningNet)
                        .tint(MFTheme.accent)
                    }

                    if vm.isRunningNet {
                        HStack {
                            Spacer()
                            ProgressView("Выполнение...")
                                .padding(20)
                                .tint(MFTheme.accent)
                            Spacer()
                        }
                    }

                    ForEach(vm.networkResults) { result in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(result.tool) → \(result.target)")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(result.timestamp,
                                     style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(result.output)
                                .font(.system(
                                    .caption,
                                    design: .monospaced
                                ))
                                .lineLimit(15)
                                .textSelection(.enabled)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.7))
                                .shadow(
                                    color: MFTheme.softShadow,
                                    radius: 1, y: 1
                                )
                        )
                    }
                }
                .mfCard()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(MFTheme.frost)
    }
}
