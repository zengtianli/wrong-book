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

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: kEnabled) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: kEnabled) }
    }

    static var hour: Int {
        get { UserDefaults.standard.object(forKey: kHour) as? Int ?? 19 }
        set { UserDefaults.standard.set(newValue, forKey: kHour) }
    }

    /// 重排。返回一句给界面显示的权限状态 —— **不静默失败**：
    /// 用户点了开关却没通知，八成是权限被拒，而那一句话就是唯一能看见的线索。
    @discardableResult
    static func reschedule() async -> String {
        let c = UNUserNotificationCenter.current()
        let existing = await c.pendingNotificationRequests()
            .map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        c.removePendingNotificationRequests(withIdentifiers: existing)

        guard enabled else { return await permissionText() }

        let granted = (try? await c.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return await permissionText() }

        // 今天的进度：读引擎写的那一份
        var remaining: Int?
        var goal = 12
        if let snap = try? await EduArchive.shared.snapshot(),
           let p = GrowthProfile.parse(archive: snap) {
            remaining = p.remaining
            goal = p.goal
        }

        let cal = Calendar.current
        let now = Date()
        for day in 0..<horizonDays {
            guard let base = cal.date(byAdding: .day, value: day, to: now),
                  let fire = cal.date(bySettingHour: hour, minute: 0, second: 0, of: base),
                  fire > now else { continue }
            // 今天已经做够了就不排今天这一条 —— 说错一次，往后就没人信它了
            if day == 0, let r = remaining, r == 0 { continue }

            let body: String
            if day == 0, let r = remaining {
                body = "今天还差 \(r) 题就完成任务了，补完 +50 经验"
            } else {
                body = "今天的 \(goal) 题做了吗？错过的那几类正等着换新题考你"
            }
            let content = UNMutableNotificationContent()
            content.title = "错题本"
            content.body = body
            content.sound = .default

            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let req = UNNotificationRequest(
                identifier: idPrefix + "\(day)",
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

    /// 只给验证用：把排了什么原样吐出来。
    static func pendingDump() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(idPrefix) }
            .sorted { $0.identifier < $1.identifier }
            .map { r in
                let t = (r.trigger as? UNCalendarNotificationTrigger)?.dateComponents
                return "\(r.identifier) @\(t?.month ?? 0)-\(t?.day ?? 0) \(t?.hour ?? 0):00 「\(r.content.body)」"
            }
    }
}
