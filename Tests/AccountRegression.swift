import Foundation

enum LessonPaths { static var offlineReadOnly = false; static var activeScope: String? }

@main struct AccountRegression {
    static func main() {
        AccountHints.adopt(["resend_seconds": 90, "code_ttl_seconds": 600,
                            "ui": ["copy": ["account.fixture": "有效{minutes}分钟"]]])
        precondition(AccountHints.resendSeconds() == 90 && AccountHints.codeMinutes() == 10)
        precondition(T("account.fixture", "fallback", ["minutes": "10"]) == "有效10分钟")
        precondition(AccountHints.resendSeconds(0) == 10 && AccountHints.resendSeconds(10000) == 600)
        precondition(AccountHints.codeMinutes(1) == 1 && AccountHints.codeMinutes(10000) == 60)
        AccountHints.adopt(["resend_seconds": true, "code_ttl_seconds": "broken", "ui": ["copy": "broken"]])
        precondition(AccountHints.resendSeconds() == 60 && AccountHints.codeMinutes() == 5)
        precondition(T("account.fixture", "fallback") == "fallback")
        AccountHints.adopt([:])
        precondition(AccountHints.resendSeconds(Double.infinity) == 60)
        print("PASS account hints: server values, receipt bounds, invalid types and remote copy fallback")
    }
}
