import CryptoKit
import Foundation

/// 个人课页在本机的落点（按账号实例分目录）与当前生效的分区。
///
/// 从 LessonSync.swift 拆出来的 WebKit 无关部分：Apple Watch 没有 WebKit，但要和 iPhone 共用
/// Lesson / WrongBook / Api 这几份文件，它们都引用这里。网页存储分区（webDataStore）仍在 LessonSync.swift。
enum LessonPaths {
    static var activeScope: String?
    static var offlineReadOnly = false
    static func remoteURL(file: String) -> URL {
        var url = URLComponents(url: Api.base.appendingPathComponent("api/lesson"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "file", value: file)]
        return url.url!
    }
    static func valid(_ file: String) -> Bool {
        !file.isEmpty && !file.hasPrefix("/") && !file.contains("\\") &&
        !file.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) &&
        file.hasSuffix(".html")
    }
    static func directory(scope: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wrong-book/private-v2/" + Data(scope.utf8).sha256Hex, isDirectory: true)
    }
    static var downloads: URL? { activeScope.map(directory(scope:)) }
    static func removeFiles(scope: String) throws {
        let directory = directory(scope: scope)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
}

extension Data {
    var sha256Hex: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}
