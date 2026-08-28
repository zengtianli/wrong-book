import SwiftUI

/// 配色 —— **亮色**，跟着它包着的那些练习页走。
///
/// 练习页是「亮色 + 零 CDN + 自包含单文件」（~/Edu 的既定设计目标：双击就能用、
/// 能发家长、能塞平板离线）。原生壳做成深色，就会出现「深壳套亮页」的夹心，
/// 每次从列表点进一课都闪一下白。这个 app 的壳只是页面的相框，别抢戏。
///
/// 京宝积分那个 app 是另一套视觉（时代插画 + 深色压底），两个 app 在桌面上、
/// 在屏幕上都应该一眼分得开 —— 它们本来就是两件事。
enum Ink {
    static let paper      = Color(hex: 0xFBF7F0)   // 页底：暖白纸
    static let card       = Color.white
    static let line       = Color(hex: 0xE7DFD2)
    static let text       = Color(hex: 0x2B2620)
    static let dim        = Color(hex: 0x7A7169)
    static let red        = Color(hex: 0xD62D2A)   // 老师的红笔 = 错题
    static let redSoft    = Color(hex: 0xFBEAE8)
    static let green      = Color(hex: 0x2E7D5B)   // 订正好了
    static let blue       = Color(hex: 0x3B6EA5)   // 学科/链接
    static let rule       = Color(hex: 0xDCE6F0)   // 横格线
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
