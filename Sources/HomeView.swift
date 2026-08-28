import SwiftUI

/// 三个 tab：学 / 补 / 我。
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

    var body: some View {
        TabView(selection: $tab) {
            LearnView().tabItem { Label("学习", systemImage: "book") }.tag(0)
            WrongBookView().tabItem { Label("错题本", systemImage: "checkmark.circle") }.tag(1)
            MeView().tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(2)
        }
        .tint(Ink.red)
        .environmentObject(sync)
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
