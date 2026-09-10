import Foundation

// Network parsing uses the production Api.swift; only offline storage is stubbed.
enum LessonPaths {
    static let offlineReadOnly = false
    static let activeScope: String? = nil
}

@main
struct ApiRegression {
    static func main() throws {
        for code in [401, 403, 413, 500, 502] {
            do {
                _ = try Api.decodeResponse(Data("<html>error</html>".utf8), statusCode: code)
                fatalError("HTTP error accepted")
            } catch let error as Api.Failure {
                precondition(error.statusCode == code)
                precondition(error.message.contains(String(code)))
            }
        }
        do {
            _ = try Api.decodeResponse(Data(#"{"ok":true}"#.utf8), statusCode: 500)
            fatalError("HTTP failure hidden by JSON")
        } catch let error as Api.Failure { precondition(error.statusCode == 500) }
        let json = try Api.decodeResponse(Data(#"{"ok":true,"enabled":true}"#.utf8), statusCode: 200)
        precondition(json["enabled"] as? Bool == true)
        print("Api HTTP/JSON regression passed")
    }
}
