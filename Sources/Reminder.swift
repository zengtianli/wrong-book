import Foundation
import UserNotifications

/// 每日任务提醒 —— 「今天还差 N 题」。
///
/// ## 为什么不是一条「每天重复」的通知
///
/// 重复触发器的文案在排期那一刻就定死了，之后改不了、也**没法只撤掉今天这一次**。
/// 于是会出现最伤的一种情况：孩子今天已经做完了，晚上还被提醒「你还差 12 题」——
/// 提醒一旦说错过一次，往后就没人信它了。
///
/// 这里的做法：每次 app 活跃时**重排未来 7 天**的独立通知。
/// - 今天那条：拿存档里的真实进度算，已经做够就**不排**；
/// - 往后几天：说不出具体数字（那时的进度还没发生），就不说数字。
/// 7 天是「app 一周没打开也还有提醒」和「不排一堆过期通知」之间的取舍。
///
/// ## 进度从哪来
///
/// `edu:@profile` —— 练习引擎写的那一份（见 `EduArchive`）。原生不另记一份，
/// 否则「app 说还差 3 题、页面说做完了」这种事迟早发生，而且没人能说清谁对。
enum Reminder {
    private static let idPrefix = "daily-goal-"
    private static let kEnabled = "remind_enabled"
    private static let kHour = "remind_hour"
    private static let horizonDays = 7

    /// 默认关。用 `bool(forKey:)` 而不是 `object(...) as? Bool`：
    /// 前者认得 launch 参数域里的 `-remind_enabled YES`（那是字符串，转不成 Bool），
    /// 于是这个开关在 headless 验证里也拨得动。
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: kEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: kEnabled) }
    }

    /// 同上用 `integer(forKey:)`：launch 参数域里的 `-remind_hour 23` 是字符串，
    /// `object(...) as? Int` 转不成，于是 headless 验证永远只能验 19:00 那一档。
    /// 没设过时 integer 返回 0，落回默认 19。
    static var hour: Int {
        get { let h = UserDefaults.standard.integer(forKey: kHour); return (1...23).contains(h) ? h : 19 }
        set { UserDefaults.standard.set(newValue, forKey: kHour) }
    }

    /// 排哪几条 —— **纯函数**，不碰系统、不弹框。
    ///
    /// 抽出来是为了让它验得了：真正的排期要么弹权限框（headless 点不掉），
    /// 要么落在系统里看不见。而这一段才是会出错的地方（今天该不该排、说什么）。
    /// 界面上也直接摊开它 —— 用户能自己看出「今晚 19:00 会说什么」。
    static func plan(now: Date, hour: Int, remaining: Int?, goal: Int,
                     days: Int = horizonDays) -> [(day: Int, fire: Date, body: String)] {
        let cal = Calendar.current
        var out: [(Int, Date, String)] = []
        for day in 0..<days {
            guard let base = cal.date(byAdding: .day, value: day, to: now),
                  let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: base),
                  fire > now else { continue }
            // 今天已经做够了就不排今天这一条 —— 提醒说错一次，往后就没人信它了
            if day == 0, let r = remaining, r == 0 { continue }
            let body: String
            if day == 0, let r = remaining {
                body = "今天还差 \(r) 题就完成任务了，补完 +50 经验"
            } else {
                // 往后几天的进度还没发生，说不出数字就别说数字
                body = "今天的 \(goal) 题做了吗？错过的那几类正等着换新题考你"
            }
            out.append((day, fire, body))
        }
        return out
    }

    /// 当前该排的那几条（读引擎写的存档现算）。界面直接显示它。
    static func currentPlan() async -> [(day: Int, fire: Date, body: String)] {
        var remaining: Int?
        var goal = 12
        if let snap = try? await EduArchive.shared.snapshot(),
           let p = GrowthProfile.parse(archive: snap) {
            remaining = p.remaining
            goal = p.goal
        }
        return plan(now: Date(), hour: hour, remaining: remaining, goal: goal)
    }

    /// 重排。返回一句给界面显示的权限状态 —— **不静默失败**：
    /// 用户点了开关却没通知，八成是权限被拒，而那一句话就是唯一能看见的线索。
    ///
    /// `ask` 只在**用户自己拨开关**那一下为真。每次回前台都问一遍权限，
    /// 会在孩子做题做到一半时弹系统框 —— 那是最讨厌的一种打扰，而且问不出新答案。
    @discardableResult
    static func reschedule(ask: Bool = false) async -> String {
        let c = UNUserNotificationCenter.current()
        let existing = await c.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        c.removePendingNotificationRequests(withIdentifiers: existing)

        guard enabled else { return await permissionText() }

        var status = await c.notificationSettings().authorizationStatus
        if status == .notDetermined, ask {
            _ = try? await c.requestAuthorization(options: [.alert, .sound])
            status = await c.notificationSettings().authorizationStatus
        }
        #if os(iOS)
        let granted = status == .authorized || status == .provisional || status == .ephemeral   // .ephemeral = App Clip 专属，Mac 没有
        #else
        let granted = status == .authorized || status == .provisional
        #endif
        guard granted else {
            return await permissionText()
        }

        for p in await currentPlan() {
            let content = UNMutableNotificationContent()
            content.title = "错题本"
            content.body = p.body
            content.sound = .default
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: p.fire)
            let req = UNNotificationRequest(
                identifier: idPrefix + "\(p.day)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            try? await c.add(req)
        }
        return await permissionText()
    }

    static func permissionText() async -> String {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            let n = await UNUserNotificationCenter.current().pendingNotificationRequests()
                .filter { $0.identifier.hasPrefix(idPrefix) }.count
            return enabled ? "已开（排了 \(n) 天）" : "已允许，开关没开"
        case .denied:
            return "被拒了 —— 去 设置 → 错题本 → 通知 打开"
        case .notDetermined:
            return "还没问过"
        @unknown default:
            return "未知"
        }
    }
}
