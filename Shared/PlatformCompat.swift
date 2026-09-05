// PlatformCompat.swift —— 总部共享（~/Apps/ios 全舰队按绝对路径引用，multiplatform.py 注入 project.yml）
//
// 作用：让为 iPhone 写的 SwiftUI 代码**尽量一行不改**就能编进 macOS destination。
// 做法：只在 macOS 侧提供 iOS-only 类型 / 修饰符的同名替身（no-op 或最接近的 AppKit 语义）。
// iOS 侧这个文件是空的（整段 #if os(macOS)），所以对现有 iPhone 包零影响。
//
// 纪律：
//   · 这里只放「平台 API 缺口」的替身，不放业务；每个替身注明它在哪个 app 首次被撞出来。
//   · 一个缺口只在这儿补一次（铁律 #5）。在 app 里手写 #if os(iOS) 绕过 = 又造了一份。
//   · 只补真撞出来的，不预填「可能会用到」的 —— 与 macOS 已有同名 API 撞车会变成歧义错误。
//   · app 里仍然允许 #if os(iOS) 的只有两类：① 该功能在 Mac 上**没有对应物**（文档扫描相机、
//     UIImagePickerController）② WKWebView 这种两边 API 形状不同的一两行。
//
// 缺口清单（2026-09-02 首轮 10 app 编译收集）：
//   keyboardType / navigationBarTitleDisplayMode / textInputAutocapitalization / .topBarTrailing
//   UIImage(+jpegData/cgImage) / UIColor / UIGraphicsImageRenderer / UIViewRepresentable /
//   UIViewControllerRepresentable / UIApplication.willResignActiveNotification / UIPasteboard /
//   UINotificationFeedbackGenerator / UIImpactFeedbackGenerator / AVAudioSession

import SwiftUI

#if os(macOS)
import AppKit
import AVFoundation

// ── 键盘类型：Mac 没有软键盘，整个概念不存在 ─────────────────────────────────
// options-calc ContentView.swift:104 首撞（.keyboardType(.decimalPad)）
public enum UIKeyboardType { case `default`, decimalPad, numberPad, numbersAndPunctuation, emailAddress, URL, phonePad, asciiCapable, webSearch }

// ── 导航栏标题样式：Mac 的 toolbar 没有 large/inline 之分 ─────────────────────
// options-calc ContentView.swift:86 首撞
public enum NavigationBarItem { public enum TitleDisplayMode { case automatic, inline, large } }

// ── 自动大写：Mac 没有软键盘输入规则 ────────────────────────────────────────
// fitcoach-ios App.swift:215 / LoginView.swift:52、options-desk JournalView.swift:87 首撞
public struct TextInputAutocapitalization {
    public static let never = TextInputAutocapitalization()
    public static let words = TextInputAutocapitalization()
    public static let sentences = TextInputAutocapitalization()
    public static let characters = TextInputAutocapitalization()
}

public extension View {
    func keyboardType(_ t: UIKeyboardType) -> Self { self }
    func navigationBarTitleDisplayMode(_ m: NavigationBarItem.TitleDisplayMode) -> Self { self }
    func textInputAutocapitalization(_ t: TextInputAutocapitalization?) -> Self { self }
    /// iOS 的全屏盖板在 Mac 上就是一张 sheet（wrong-book PaperScanView 首撞）
    func fullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                        @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
    }
    /// item 版（wrong-book LearnView / WrongBookView 首撞）
    func fullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                            @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item, onDismiss: onDismiss, content: content)
    }
}

// ── ToolbarItemPlacement：.topBarLeading / .topBarTrailing 是 iOS 17 才有的名字 ──
// options-calc 首撞（.topBarTrailing）
public extension ToolbarItemPlacement {
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
}
// .pickerStyle(.navigationLink)：points-deck ParentView 首撞 —— Mac 上最接近的是下拉菜单
public extension PickerStyle where Self == MenuPickerStyle {
    static var navigationLink: MenuPickerStyle { MenuPickerStyle() }
}
// .toolbarBackground(.hidden, for: .navigationBar)：points-deck TiersView/AdminView/ParentView/ProfileEditView 首撞
public extension ToolbarPlacement {
    static var navigationBar: ToolbarPlacement { .automatic }
    static var tabBar: ToolbarPlacement { .automatic }
}

// ── 图片 / 颜色：UIImage → NSImage，UIColor → NSColor ────────────────────────
// hydro-deck Backend.swift / ChatModel.swift、wrong-book PaperScan.swift、points-deck Skin.swift 首撞
public typealias UIImage = NSImage
public typealias UIColor = NSColor

public extension NSImage {
    /// UIImage.cgImage 的对应物（NSImage 的 cgImage 要传 rect/context/hints，形状不同）
    var cgImage: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
    /// UIImage.jpegData(compressionQuality:)
    func jpegData(compressionQuality q: CGFloat) -> Data? {
        guard let cg = cgImage else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: q])
    }
    /// UIImage.pngData()
    func pngData() -> Data? {
        guard let cg = cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}

public extension Image {
    /// SwiftUI 的 Image(uiImage:) 在 Mac 上叫 Image(nsImage:)
    init(uiImage: NSImage) { self.init(nsImage: uiImage) }
}

// ── UIColor 语义色：case-deck ContentView/Lock（.systemBackground）、hydro-deck ChatView（.secondarySystemBackground）首撞
// NSColor 自己有 labelColor / separatorColor / systemGray，名字带 Color 后缀；UIKit 的不带。只补 UIKit 名。
public extension NSColor {
    static var systemBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemBackground: NSColor { .controlBackgroundColor }
    static var tertiarySystemBackground: NSColor { .underPageBackgroundColor }
    static var systemGroupedBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemGroupedBackground: NSColor { .controlBackgroundColor }
    static var tertiarySystemGroupedBackground: NSColor { .underPageBackgroundColor }
    static var label: NSColor { .labelColor }
    static var secondaryLabel: NSColor { .secondaryLabelColor }
    static var tertiaryLabel: NSColor { .tertiaryLabelColor }
    static var quaternaryLabel: NSColor { .quaternaryLabelColor }
    static var separator: NSColor { .separatorColor }
    static var placeholderText: NSColor { .placeholderTextColor }
    static var systemGray2: NSColor { .systemGray.withAlphaComponent(0.85) }
    static var systemGray3: NSColor { .systemGray.withAlphaComponent(0.65) }
    static var systemGray4: NSColor { .systemGray.withAlphaComponent(0.45) }
    static var systemGray5: NSColor { .systemGray.withAlphaComponent(0.30) }
    static var systemGray6: NSColor { .systemGray.withAlphaComponent(0.18) }
}

public extension Color {
    init(uiColor: NSColor) { self.init(nsColor: uiColor) }
}

// ── UIGraphicsImageRenderer：hydro-deck 缩图 / wrong-book 压 JPEG / 测试夹具画图 首撞 ──
public final class UIGraphicsImageRendererFormat {
    public var scale: CGFloat = 1
    public var opaque = false
    public init() {}
    public static func `default`() -> UIGraphicsImageRendererFormat { UIGraphicsImageRendererFormat() }
}

public final class UIGraphicsImageRendererContext {
    public let cgContext: CGContext
    init(_ c: CGContext) { cgContext = c }
    public func fill(_ rect: CGRect) { cgContext.fill(rect) }
}

public final class UIGraphicsImageRenderer {
    let size: CGSize
    let format: UIGraphicsImageRendererFormat
    public init(size: CGSize, format: UIGraphicsImageRendererFormat = .init()) { self.size = size; self.format = format }
    /// 立即渲染进位图（不能用 NSImage(size:flipped:drawingHandler:)：它把闭包存起来**每次画时才调**，
    /// 而 UIKit 的 actions 是非逃逸闭包 —— 编译器直接拒；就算 withoutActuallyEscaping 也会在之后画时炸）。
    public func image(actions: (UIGraphicsImageRendererContext) -> Void) -> NSImage {
        let scale = format.scale > 0 ? format.scale : 1
        let pw = max(1, Int(size.width * scale)), ph = max(1, Int(size.height * scale))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let bmp = NSGraphicsContext(bitmapImageRep: rep)
        else { return NSImage(size: size) }
        rep.size = size
        let cg = bmp.cgContext
        // UIKit 坐标原点在左上；AppKit 在左下 → 翻转一次，并把 flipped 告诉 AppKit，NSImage.draw(in:) 才不会倒
        cg.translateBy(x: 0, y: CGFloat(ph)); cg.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        actions(UIGraphicsImageRendererContext(cg))
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: size)
        img.addRepresentation(rep)
        return img
    }
}

// ── Representable：UIView/UIViewController 版协议在 Mac 上映射到 NSView 版 ─────────
// case-deck WebView.swift、wrong-book LessonWebView.swift、hydro-deck CameraPicker.swift 首撞
// 做法：声明同名协议继承 NSViewRepresentable，用默认实现把 makeUIView 转发成 makeNSView。
// app 里的 struct 一个字不改（Context 由 typealias 对齐）。
public protocol UIViewRepresentable: NSViewRepresentable where NSViewType == UIViewType {
    associatedtype UIViewType: NSView
    func makeUIView(context: Context) -> UIViewType
    func updateUIView(_ uiView: UIViewType, context: Context)
}
public extension UIViewRepresentable {
    func makeNSView(context: Context) -> UIViewType { makeUIView(context: context) }
    func updateNSView(_ nsView: UIViewType, context: Context) { updateUIView(nsView, context: context) }
}

public protocol UIViewControllerRepresentable: NSViewControllerRepresentable where NSViewControllerType == UIViewControllerType {
    associatedtype UIViewControllerType: NSViewController
    func makeUIViewController(context: Context) -> UIViewControllerType
    func updateUIViewController(_ vc: UIViewControllerType, context: Context)
}
public extension UIViewControllerRepresentable {
    func makeNSViewController(context: Context) -> UIViewControllerType { makeUIViewController(context: context) }
    func updateNSViewController(_ vc: UIViewControllerType, context: Context) { updateUIViewController(vc, context: context) }
}

// ── UIApplication 通知：wrong-book LessonWebView 监听进后台 首撞 ─────────────────
public enum UIApplication {
    public static let willResignActiveNotification = NSApplication.willResignActiveNotification
    public static let didBecomeActiveNotification = NSApplication.didBecomeActiveNotification
    public static let didEnterBackgroundNotification = NSApplication.didHideNotification
    public static let willEnterForegroundNotification = NSApplication.willUnhideNotification
}

// ── 剪贴板：fitcoach-ios StudentDetailView 复制学员链接 首撞 ──────────────────
public final class UIPasteboard {
    public static let general = UIPasteboard()
    public var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            NSPasteboard.general.clearContents()
            if let s = newValue { NSPasteboard.general.setString(s, forType: .string) }
        }
    }
}

// ── 触感反馈：Mac 没有 Taptic（触控板的 NSHapticFeedbackManager 语义不同，不硬映射）─────
// points-deck Celebration / ParentView / ShopView 首撞
public final class UINotificationFeedbackGenerator {
    public enum FeedbackType { case success, warning, error }
    public init() {}
    public func notificationOccurred(_ t: FeedbackType) {}
    public func prepare() {}
}
public final class UIImpactFeedbackGenerator {
    public enum FeedbackStyle { case light, medium, heavy, soft, rigid }
    public init(style: FeedbackStyle = .medium) {}
    public func impactOccurred() {}
    public func impactOccurred(intensity: CGFloat) {}
    public func prepare() {}
}

// ── AVAudioSession：iOS 独有的音频路由概念，Mac 上录音/朗读不需要它 ─────────────
// hydro-deck Speaker.swift / VoiceInput.swift 首撞。全部 no-op，不抛。
public final class AVAudioSession {
    public struct Category { public static let playback = Category(); public static let record = Category(); public static let playAndRecord = Category(); public static let ambient = Category() }
    public struct Mode { public static let `default` = Mode(); public static let spokenAudio = Mode(); public static let measurement = Mode() }
    public struct CategoryOptions: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let duckOthers = CategoryOptions(rawValue: 1)
        public static let mixWithOthers = CategoryOptions(rawValue: 2)
        public static let defaultToSpeaker = CategoryOptions(rawValue: 4)
    }
    public struct SetActiveOptions: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let notifyOthersOnDeactivation = SetActiveOptions(rawValue: 1)
    }
    private static let shared = AVAudioSession()
    public static func sharedInstance() -> AVAudioSession { shared }
    public func setCategory(_ c: Category, mode: Mode = .default, options: CategoryOptions = []) throws {}
    public func setActive(_ on: Bool, options: SetActiveOptions = []) throws {}
}

#endif
