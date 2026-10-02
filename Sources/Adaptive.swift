import SwiftUI

/// 宽屏与窄屏的**唯一判定入口**，由 RootView 往下传。
///
/// 宽屏 = iPad 全屏 / 宽分屏、Mac、Vision Pro：侧栏 + 错题列表 + 题目（RegularHomeView）。
/// 窄屏 = iPhone（含 Pro Max 横屏，那时尺寸类也会变成 regular）和 iPad 窄分屏：
/// 原来的三个标签页，一个像素都不动 —— App Store 的截图和预览视频就是这套布局录的。
struct WideLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var wideLayout: Bool {
        get { self[WideLayoutKey.self] }
        set { self[WideLayoutKey.self] = newValue }
    }
}

extension View {
    /// 整个 App 是亮色（跟着它包着的练习页走，见 Theme.swift）。Vision Pro 没有亮色外观：
    /// 窗口本身是玻璃，那边不强制配色，纸面只铺在内容区（`paperPanel`）。
    @ViewBuilder
    func lightAppearance() -> some View {
        #if os(visionOS)
        self
        #else
        self.preferredColorScheme(.light)
        #endif
    }

    /// 宽屏内容区的「纸」：iPhone / iPad / Mac 原样铺 Ink.paper；Vision Pro 上是浮在玻璃窗里的一张圆角纸，
    /// 四周露出玻璃 —— 练习页和错题列表都是亮色的，直接摊在玻璃上读不清。
    @ViewBuilder
    func paperPanel() -> some View {
        #if os(visionOS)
        // 纸上按亮色排：没写死颜色的字（表单、系统控件）默认是玻璃上的白字，摊在纸上看不见
        self.environment(\.colorScheme, .light)
            .foregroundStyle(Ink.text)
            .background(Ink.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(18)
        #else
        self.background(Ink.paper)
        #endif
    }

    /// 自己画了底的按钮 / 只有一个图标的按钮：Vision Pro 的默认按钮样式会再垫一块玻璃底（深色圆片压住图标、
    /// 文字链接变成实心胶囊），那边改 plain 并补上注视高亮。iPhone / iPad / Mac 原样不动。
    @ViewBuilder
    func flatButton() -> some View {
        #if os(visionOS)
        self.buttonStyle(.plain).hoverEffect()
        #else
        self
        #endif
    }

    /// 宽屏里不许折行的短控件（「全部科目」菜单）：宽屏列表栏比 iPhone 窄一点、Vision 的菜单底更胖，
    /// 会被挤成两行。窄屏原样返回 —— iPhone 的排版一个像素都不动。
    func wideFixedSize() -> some View { modifier(WideFixedSize()) }

    /// 宽屏时把内容收在 `width` 以内并居中；窄屏传 nil，原样返回（不留一层空 frame）。
    @ViewBuilder
    func contentWidth(_ width: CGFloat?) -> some View {
        if let width {
            self.frame(maxWidth: width).frame(maxWidth: .infinity)
        } else {
            self
        }
    }
}

private struct WideFixedSize: ViewModifier {
    @Environment(\.wideLayout) private var wide

    @ViewBuilder
    func body(content: Content) -> some View {
        if wide { content.fixedSize() } else { content }
    }
}
