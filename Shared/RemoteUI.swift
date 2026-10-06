import Foundation

// 后台下发的界面覆盖项。总部唯一可编辑的一份；产品 Shared/ 里是逐字节副本（multiplatform.py 管同步与漂移）。
//
// 用法：产品的数据载荷里带一段可选的 `ui`，模型写成 `var ui: Lenient<FeedUI>? = nil`，
// 取到新载荷和读缓存时都把它交给 `Remote.ui`。界面上会随后台变的文字写成 `T("键", "自带文案")`，
// 带变量的句子写成 `T("键", "已过期（{days} 天没上线）", ["days": "7"])`，
// 状态词表用 `Remote.label / icon / tone`，秒数和次数用 `Remote.seconds / count`。
// 只盖后台写到的键；没下发、离线或写坏时全部用 App 自带的值。改这些东西去改后台，不用发版。

/// 覆盖项的四段：说明文字、状态词表、状态排序、数字阈值。
struct FeedUI: Codable, Hashable, Sendable {
    struct Word: Codable, Hashable, Sendable {
        var label: String? = nil
        var icon: String? = nil
        var tone: String? = nil
    }
    var copy: [String: String]? = nil
    var vocab: [String: Word]? = nil
    var order: [String]? = nil
    var limits: [String: Double]? = nil
}

enum Remote {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: FeedUI?

    /// 最近一份载荷里的覆盖项；取到新载荷或读缓存时更新。
    static var ui: FeedUI? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    /// 秒数类阈值。后台给的值夹在 range 里：写错也不至于把轮询打爆或永不刷新。
    static func seconds(_ key: String, _ fallback: Double, in range: ClosedRange<Double>) -> Double {
        guard let v = ui?.limits?[key], v.isFinite else { return fallback }
        return min(max(v, range.lowerBound), range.upperBound)
    }

    /// 次数、张数这类整数。同样夹在 range 里。
    static func count(_ key: String, _ fallback: Int, in range: ClosedRange<Int>) -> Int {
        guard let v = ui?.limits?[key], v.isFinite else { return fallback }
        return min(max(Int(v.rounded()), range.lowerBound), range.upperBound)
    }

    /// 状态叫什么。空字符串当没写。
    static func label(_ state: String, _ fallback: String) -> String {
        guard let s = ui?.vocab?[state]?.label, !s.isEmpty else { return fallback }
        return s
    }

    /// 状态用哪个系统图标。
    static func icon(_ state: String, _ fallback: String) -> String {
        guard let s = ui?.vocab?[state]?.icon, !s.isEmpty else { return fallback }
        return s
    }

    /// 状态的色调名（good / warn / bad / muted 这类，由产品自己映射成颜色）；没写返回 nil。
    static func tone(_ state: String) -> String? {
        guard let s = ui?.vocab?[state]?.tone, !s.isEmpty else { return nil }
        return s
    }

    /// 状态排序；没写或写了空表用自带顺序。
    static func order(_ fallback: [String]) -> [String] {
        guard let o = ui?.order, !o.isEmpty else { return fallback }
        return o
    }
}

/// 说明文字：后台覆盖了就用后台的，否则用这里写的。键名即后台 `copy` 的键。空字符串当没写。
func T(_ key: String, _ fallback: String) -> String {
    guard let s = Remote.ui?.copy?[key], !s.isEmpty else { return fallback }
    return s
}

/// 带变量的说明文字：自带文案和后台模板用同一种 `{名}` 占位符，这里把它们换成值。
/// 后台模板漏写占位符时那个值不显示，写了不认识的占位符原样留着，都不会崩。
func T(_ key: String, _ fallback: String, _ values: [String: String]) -> String {
    Remote.fill(T(key, fallback), values)
}

extension Remote {
    /// 把模板里的 `{名}` 换成值。只扫一遍：值里带花括号也不会被再次展开。
    static func fill(_ template: String, _ values: [String: String]) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            let after = rest[rest.index(after: open)...]
            if let close = after.firstIndex(of: "}"), let value = values[String(after[..<close])] {
                out += value
                rest = after[after.index(after: close)...]
            } else {
                out += "{"
                rest = after
            }
        }
        return out + rest
    }
}

/// 解不开就当没有：后台把覆盖项写错了，不能连带把整份数据解坏。
struct Lenient<Wrapped: Codable>: Codable {
    var value: Wrapped?
    init(_ value: Wrapped? = nil) { self.value = value }
    init(from decoder: Decoder) throws { value = try? Wrapped(from: decoder) }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let value { try c.encode(value) } else { try c.encodeNil() }
    }
}

extension Lenient: Equatable where Wrapped: Equatable {}
extension Lenient: Hashable where Wrapped: Hashable {}
extension Lenient: Sendable where Wrapped: Sendable {}
