import Foundation

/// iPhone → Apple Watch 的登录态转交：总部共享 `WatchCookieLink`（Shared/）的一个实例 ——
/// cookie 名 `edu_sess`（server.py 发的那枚 HttpOnly 会话），服务地址跟着 `Api.base` 走。
///
/// 手表上没有输入框可登录，由 iPhone 在登录 / 恢复 / 注册成功后递过去，退出 / 注销时递一份不带 cookie 的，
/// 手表随即删掉。转的是同一个会话：改密码、注销照样让手表一起下线。
/// iPhone 侧的触发点在 RootView（看 Session 的登录态变化，不改 Session 本身）；手表侧在 Watch/。
/// iPad、Mac、Vision Pro 上这里全是空操作。
enum WatchLink {
    @MainActor static let shared = WatchCookieLink(cookieName: "edu_sess") { Api.base }
}
