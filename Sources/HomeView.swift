import SwiftUI

/// 三个主入口与 Web 一致：错题本 / 导入 / 复习；设置在右上角。
///
/// ⚠ **用系统标准 TabView，不用 `.page` 分页样式。**
/// 练习页自己带左右滑翻题（`practice.js` 的 `bindNav()`，平板上就是这么翻的）。
/// 外壳再套一个横向分页手势，两边会抢 —— 表现是「翻题翻着翻着跳到别的 tab」。
/// 京宝积分那个 app 用分页样式是因为它每个 tab 都是纯原生列表，没有这个冲突。
struct HomeView: View {
    @EnvironmentObject var session: Session
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sync = LessonSync.shared
    // 验证通道：`-tab 1` 直接落到某一屏，方便 headless 截图核对
    @State private var tab = UserDefaults.standard.integer(forKey: "tab")
    @State private var settings = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("w·").font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(.white).frame(width: 32, height: 32)
                    .background(Ink.accent, in: RoundedRectangle(cornerRadius: 8))
                Text("wrongbook").font(.system(size: 20, weight: .bold))
                Spacer()
                Button { Task { await sync.sync(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(sync.running).accessibilityLabel("同步错题").keyboardShortcut("r", modifiers: .command)
                Button { settings = true } label: { Image(systemName: "person.crop.circle") }
                    .accessibilityLabel("账号与设置").keyboardShortcut(",", modifiers: .command)
            }.buttonStyle(.plain).foregroundStyle(Ink.text)
                .padding(.horizontal, 20).padding(.vertical, 12).background(Ink.card)
            Divider()
            TabView(selection: $tab) {
                FocusLibraryView().tabItem { Label("错题本", systemImage: "book.closed") }.tag(0)
                NavigationStack { PaperScanView() }.tabItem { Label("导入", systemImage: "square.and.arrow.down") }.tag(1)
                FocusLibraryView(reviewOnly: true).tabItem { Label("复习", systemImage: "arrow.clockwise") }.tag(2)
            }
        }
        .tint(Ink.accent).background(Ink.paper)
        .environmentObject(sync)
        .sheet(isPresented: $settings) {
            VStack(spacing: 0) {
                HStack { Text("账号与设置").font(.headline); Spacer(); Button("完成") { settings = false } }.padding(16)
                MeView()
            }.frame(minWidth: 320, minHeight: 480).environmentObject(sync)
        }
        .onReceive(NotificationCenter.default.publisher(for: .wrongbookImport)) { _ in tab = 1 }
        // 增量更新：启动拉一次，回前台再拉一次（内部 10 分钟节流）。
        // 拉不到就安静地什么都不做 —— 离线是这个 app 的常态，不是故障。
        .task { await sync.sync() }
        .onChange(of: scenePhase) { _, p in
            guard p == .active else { return }
            Task {
                await sync.sync()
                await session.refresh()
                await Reminder.reschedule()      // 今天做够了就把提醒撤掉
            }
        }
    }
}

extension Notification.Name {
    static let wrongbookImport = Notification.Name("wrongbook.import")
}
