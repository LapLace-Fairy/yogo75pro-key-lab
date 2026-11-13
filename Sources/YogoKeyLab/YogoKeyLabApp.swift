import SwiftUI
import YogoCore

@main
struct YogoKeyLabApp: App {
    @StateObject private var hotkeys = GlobalHotkeys()

    var body: some Scene {
        WindowGroup("YogoLab") { ContentView(hotkeys: hotkeys) }
            .windowResizability(.contentMinSize)
            #if DEBUG
            .defaultSize(width: 900, height: 950)
            #else
            .defaultSize(width: 900, height: 820)
            #endif
    }
}

private enum Palette {
    static let background = Color(red: 0.88, green: 0.92, blue: 0.97)
    static let ink = Color(red: 0.19, green: 0.27, blue: 0.40)
    static let muted = Color(red: 0.34, green: 0.43, blue: 0.56)
    static let blue = Color(red: 0.35, green: 0.50, blue: 0.68)
    static let tile = Color(red: 0.88, green: 0.93, blue: 0.99)
}

private struct ContentView: View {
    @ObservedObject var hotkeys: GlobalHotkeys
    @StateObject private var keyboard = KeyboardMonitor()
    @StateObject private var agents = AgentMonitor()
    @StateObject private var display = DisplayCoordinator()
    #if DEBUG
    @StateObject private var performance = PerformanceMonitor()
    @State private var testCodex = false
    @State private var testZcode = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                        .resizable().interpolation(.high).frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("YogoLab").font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("键盘点阵小助手").font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Link(destination: URL(string: "https://hub.atk.pro/")!) {
                        Label("打开 ATK HUB", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    #if DEBUG
                    Text("DEBUG").font(.caption.bold()).foregroundStyle(Palette.muted)
                    #endif
                }

                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 14) {
                        deviceCard
                        agentCard
                        batteryCard
                    }
                    .frame(maxWidth: .infinity)
                    displayCard.frame(width: 260)
                }
                #if DEBUG
                debugCard
                #endif
            }
            .foregroundStyle(Palette.ink)
            .padding(28)
        }
        .background(Palette.background)
        .frame(minWidth: 760, minHeight: 760)
        .onAppear {
            hotkeys.start()
            agents.start()
            display.waitingChanged(codex: agents.codex == .waiting, zcode: agents.zcode == .waiting)
            keyboard.start()
            keyboard.setFrame(.alert(display.alert))
        }
        .onDisappear {
            #if DEBUG
            performance.stop()
            #endif
            display.stop(); agents.stop(); keyboard.stop()
        }
        .onChange(of: keyboard.battery) { _, value in display.batteryChanged(value) }
        .onChange(of: display.alert) { _, alert in keyboard.setFrame(.alert(alert)) }
        .onChange(of: agents.codex) { _, _ in updateWaiting() }
        .onChange(of: agents.zcode) { _, _ in updateWaiting() }
    }

    private func updateWaiting() {
        #if DEBUG
        display.waitingChanged(codex: agents.codex == .waiting || testCodex,
                               zcode: agents.zcode == .waiting || testZcode)
        #else
        display.waitingChanged(codex: agents.codex == .waiting, zcode: agents.zcode == .waiting)
        #endif
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("设备连接").font(.headline)
            HStack(spacing: 14) {
                tile("keyboard")
                VStack(alignment: .leading, spacing: 5) {
                    Text("ATK YOGO 75 PRO").font(.system(.headline, design: .rounded))
                    Text(keyboard.connection == "键盘已响应" ? "已连接" : keyboard.connection)
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(keyboard.battery.map { "\($0)%" } ?? "—")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("键盘电量").font(.caption).foregroundStyle(Palette.muted)
                }
            }
            HStack {
                Spacer()
                Button("重新检测") { keyboard.refresh() }
                    .controlSize(.small)
            }
        }.card()
    }

    private var agentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Agent 提醒").font(.headline)
            agentRow("Codex", symbol: "chevron.left.forwardslash.chevron.right", status: agents.codex)
            Divider()
            agentRow("ZCode", symbol: "sparkle", status: agents.zcode)
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Text("全局快捷键  ⇧⌃⌥⌘ X：ChatGPT   ⇧⌃⌥⌘ Z：ZCode")
                    .font(.caption.weight(.semibold))
                Text(hotkeys.message).font(.caption).foregroundStyle(Palette.muted)
            }
        }.card()
    }

    private func agentRow(_ name: String, symbol: String, status: AgentStatus) -> some View {
        HStack(spacing: 14) {
            tile(symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(.headline, design: .rounded))
                Text(statusDescription(status)).font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer()
            Text(status == .waiting ? "待确认" : statusBadge(status))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(status == .waiting ? Color.orange.opacity(0.18) : Palette.tile,
                            in: Capsule())
        }
    }

    private func statusDescription(_ status: AgentStatus) -> String {
        switch status {
        case .waiting: return "需要回复或确认"
        case .running: return "任务进行中，暂无待确认"
        case .completed: return "本轮任务已完成"
        case .unknown: return "暂无可用会话状态"
        }
    }
    private func statusBadge(_ status: AgentStatus) -> String {
        switch status {
        case .waiting: return "待确认"
        case .running: return "进行中"
        case .completed: return "已完成"
        case .unknown: return "未知"
        }
    }

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("低电量提醒", systemImage: "battery.25percent").font(.headline)
            Text("低于以下电量时，感叹号闪烁 10 次")
                .font(.caption).foregroundStyle(Palette.muted)
            HStack(spacing: 18) {
                threshold("50%", color: .yellow)
                threshold("20%", color: .orange)
                threshold("10%", color: .red)
            }
        }.card()
    }
    private func threshold(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) { Circle().fill(color).frame(width: 10, height: 10); Text("< " + title).font(.caption.weight(.semibold)) }
    }

    private var displayCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("点阵预览").font(.headline)
            MatrixPreview(frame: .alert(display.alert))
                .padding(20).frame(maxWidth: .infinity)
                .background(Palette.tile, in: RoundedRectangle(cornerRadius: 20))
            Text(display.alert == .off ? "当前熄屏" : "正在显示提醒")
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
            Text("待确认优先；电量提醒等待处理后显示。")
                .font(.caption).foregroundStyle(Palette.muted)
            Text(keyboard.displayStatus).font(.caption).foregroundStyle(Palette.muted)
            Spacer(minLength: 0)
        }.card()
    }

    private func tile(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Palette.blue).frame(width: 48, height: 48)
            .background(Palette.tile, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }

    #if DEBUG
    private var debugCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("调试工具").font(.headline)
            Text("待确认提醒优先，电量测试会排队。")
                .font(.caption).foregroundStyle(Palette.muted)
            HStack {
                Button("测试黄色") { display.testWarning(.yellow) }
                Button("测试橙色") { display.testWarning(.orange) }
                Button("测试红色") { display.testWarning(.red) }
                Button("测量空闲 CPU") { performance.start() }.disabled(performance.measuring)
            }
            HStack {
                Toggle("模拟 Codex 待确认", isOn: $testCodex)
                Toggle("模拟 ZCode 待确认", isOn: $testZcode)
            }.onChange(of: testCodex) { _, _ in updateWaiting() }
             .onChange(of: testZcode) { _, _ in updateWaiting() }
            Text(performance.message).font(.caption).foregroundStyle(Palette.muted)
        }.card()
    }
    #endif
}

private extension View {
    func card() -> some View {
        self.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct MatrixPreview: View {
    let frame: MatrixFrame
    private let columns = Array(repeating: GridItem(.fixed(20), spacing: 8), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<36, id: \.self) { index in
                let pixel = frame.pixels[index]
                Circle().fill(pixel == .black ? Palette.ink.opacity(0.18) :
                    Color(red: Double(pixel.red) / 255, green: Double(pixel.green) / 255,
                          blue: Double(pixel.blue) / 255))
                    .frame(width: 20, height: 20)
            }
        }.accessibilityLabel("6 行 6 列点阵显示预览")
    }
}
