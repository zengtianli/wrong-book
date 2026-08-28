import SwiftUI

@main
struct WrongBookApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(session)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var session: Session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let r = UserDefaults.standard.string(forKey: "review"),
               r.contains(":") {
                // 验证通道：`-review <slug>:<gid>` 直接进某一类的复习。
                // 没有它，「复习出的是同类新题、不是原题」这条只能靠手点 ——
                // 而手点验不了的东西，等于没有验过。
                let parts = r.split(separator: ":", maxSplits: 1).map(String.init)
                LessonPreview(slug: parts[0], drillGid: parts[1])
            } else if let slug = UserDefaults.standard.string(forKey: "lesson") {
                // 验证通道：`-lesson <slug>` 直接开某一课，不必先登录。
                // 练习引擎本身不依赖登录（页面自包含，登录只决定分记不记得上），
                // 有了它「离线能不能做题」这条才验得了：不登录、不联网，照样该能做完一套。
                LessonPreview(slug: slug)
            } else {
                switch session.phase {
                case .checking:  SplashView()
                case .loggedOut: LoginView()
                case .loggedIn:  HomeView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: session.phase)
        .task { await session.restore() }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            ProgressView().tint(Ink.red).scaleEffect(1.3)
        }
    }
}
