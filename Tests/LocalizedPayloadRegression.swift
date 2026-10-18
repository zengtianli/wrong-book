import Foundation

// Production response parsing is exercised without network or personal storage.
enum LessonPaths {
    static let offlineReadOnly = false
    static let activeScope: String? = nil
}

@main
struct LocalizedPayloadRegression {
    private static var assertions = 0
    private static var failures: [String] = []

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { failures.append(message) }
    }

    private static func snapshot(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func main() throws {
        let english = ["en-US"]
        let chinese = ["zh-Hans-CN"]
        let split: [String: Any] = [
            "message": "旧中文", "message_en": "English message", "message_zh-Hans": "简体中文"
        ]
        expect(Api.displayText(split, key: "message", languages: english) == "English message", "English suffix should be preferred")
        expect(Api.displayText(split, key: "message", languages: chinese) == "简体中文", "Chinese suffix should be preferred")
        expect(Api.displayText(split, key: "message", languages: ["fr-FR"]) == "English message", "Other system languages should use English")
        expect(Api.displayText(split, key: "message", languages: ["fr-FR", "zh-Hans"]) == "简体中文", "The first supported preferred language should be selected")
        expect(Api.displayText(["message": "原有中文", "message_en": "English only"], key: "message", languages: chinese) == "原有中文", "Chinese legacy text should win over an English-only suffix")

        let dictionary: [String: Any] = ["message": ["en": "English dictionary", "zh-Hans": "字典中文"]]
        expect(Api.displayText(dictionary, key: "message", languages: english) == "English dictionary", "English dictionary value should be preferred")
        expect(Api.displayText(dictionary, key: "message", languages: chinese) == "字典中文", "Chinese dictionary value should be preferred")
        expect(Api.displayText(["message": ["zh-Hans": "仅中文"]], key: "message", languages: english) == "仅中文", "Missing English should fall back to Chinese")
        expect(Api.displayText(["message": ["en": "English only"]], key: "message", languages: chinese) == "English only", "Missing Chinese should fall back to English")
        expect(Api.displayText(["message": ["en": "English fallback", "zh-Hans": ""]], key: "message", languages: chinese) == "English fallback", "Empty Chinese dictionary value should fall back to English")
        expect(Api.displayText(["message": ["en": "", "zh-Hans": "空值回落"]], key: "message", languages: english) == "空值回落", "Empty English dictionary value should fall back to Chinese")
        expect(Api.displayText(["message_en": "", "message": "旧文案"], key: "message", languages: english) == "旧文案", "Empty English suffix should fall back to legacy text")
        expect(Api.displayText(["message_en": 42, "message": "旧文案"], key: "message", languages: english) == "旧文案", "Malformed English suffix should fall back to legacy text")
        expect(Api.displayText(["message": ["en": 42, "zh-Hans": "有效中文"]], key: "message", languages: english) == "有效中文", "Malformed English dictionary value must not discard valid Chinese")
        expect(Api.displayText(["message": ["en": "Valid English", "zh-Hans": NSNull()]], key: "message", languages: english) == "Valid English", "Malformed Chinese dictionary value must not discard valid English")
        expect(Api.displayText(["message": NSNull()], key: "message", fallback: "Built-in", languages: english) == "Built-in", "Malformed value should use the built-in fallback")
        expect(Api.displayText([:], key: "message", fallback: "Built-in", languages: english) == "Built-in", "Missing value should use the built-in fallback")
        expect(Api.displayText(["message": "", "message_en": ""], key: "message", fallback: "Built-in", languages: english) == "Built-in", "All empty values should use the built-in fallback")

        let raw: [String: Any] = [
            "copy": [
                "legacy": "旧文案", "dictionary": ["en": "Dictionary text", "zh-Hans": "字典文案"],
                "overlay": "原文案", "chineseOnly": "旧回落", "empty": "空值原文案"
            ],
            "copy_en": ["overlay": "English overlay", "empty": ""],
            "copy_zh-Hans": ["overlay": "简体覆盖", "chineseOnly": "只有中文"],
            "vocab": [
                "ready": ["label": "旧状态", "label_en": "Ready", "label_zh-Hans": "就绪", "tone": "good", "icon": "checkmark.circle"],
                "pending": ["label": ["en": "Pending", "zh-Hans": "等待"], "tone": "warn", "icon": "clock"],
                "legacy": ["label": "旧标签", "tone": "muted", "icon": "questionmark.circle"]
            ],
            "limits": ["retry": 12.0], "order": ["ready", "pending", "legacy"],
            "opaque": ["user_label": "用户自己的中文"]
        ]
        let before = try snapshot(raw)
        let en = Api.localizedUI(raw, languages: english)
        let zh = Api.localizedUI(raw, languages: chinese)
        let enCopy = en["copy"] as? [String: String] ?? [:]
        let zhCopy = zh["copy"] as? [String: String] ?? [:]
        expect(enCopy["overlay"] == "English overlay", "English copy overlay should win")
        expect(zhCopy["overlay"] == "简体覆盖", "Chinese copy overlay should win")
        expect(enCopy["dictionary"] == "Dictionary text", "English copy value dictionary should be selected")
        expect(zhCopy["dictionary"] == "字典文案", "Chinese copy value dictionary should be selected")
        expect(enCopy["chineseOnly"] == "只有中文", "A missing English copy overlay should fall back to Chinese")
        expect(enCopy["empty"] == "空值原文案", "Empty overlay should preserve the legacy copy")
        expect(enCopy["legacy"] == "旧文案", "Legacy copy should remain usable")
        let zhLegacyOverlay = Api.localizedUI(["copy": ["note": "中文原文"], "copy_en": ["note": "English only"]], languages: chinese)
        expect((zhLegacyOverlay["copy"] as? [String: String])?["note"] == "中文原文", "English-only copy overlays must not replace Chinese legacy copy")
        let zhLegacyVocab = Api.localizedUI(["vocab": ["ready": ["label": "中文原状态", "label_en": "Ready"]]], languages: chinese)
        expect((zhLegacyVocab["vocab"] as? [String: [String: Any]])?["ready"]?["label"] as? String == "中文原状态", "English-only vocabulary must not replace a Chinese legacy label")
        let enVocab = en["vocab"] as? [String: [String: Any]] ?? [:]
        let zhVocab = zh["vocab"] as? [String: [String: Any]] ?? [:]
        expect(enVocab["ready"]?["label"] as? String == "Ready", "English vocabulary suffix should be selected")
        expect(zhVocab["ready"]?["label"] as? String == "就绪", "Chinese vocabulary suffix should be selected")
        expect(enVocab["pending"]?["label"] as? String == "Pending", "Vocabulary label dictionaries should be selected")
        expect(enVocab["legacy"]?["label"] as? String == "旧标签", "Legacy vocabulary labels should remain usable")
        expect(enVocab["ready"]?["tone"] as? String == "good", "Localization must preserve status tone")
        expect(enVocab["ready"]?["icon"] as? String == "checkmark.circle", "Localization must preserve status icons")
        expect((en["limits"] as? [String: Double])?["retry"] == 12.0, "Localization must preserve numeric limits")
        expect(en["order"] as? [String] == ["ready", "pending", "legacy"], "Localization must preserve status order")
        expect((en["opaque"] as? [String: String])?["user_label"] == "用户自己的中文", "Localization must preserve unrelated user data")
        let after = try snapshot(raw)
        expect(after == before, "Localization must not mutate its input payload")

        let malformed: [String: Any] = [
            "copy": ["valid": "原文案", "fallback": "原回落"],
            "copy_en": ["valid": "Valid English", "fallback": NSNull()],
            "copy_zh-Hans": ["fallback": "中文回落"],
            "vocab": ["ready": ["label": ["en": 42, "zh-Hans": "中文状态"], "tone": "good", "icon": "checkmark"]]
        ]
        let malformedResult = Api.localizedUI(malformed, languages: english)
        let safeCopy = malformedResult["copy"] as? [String: String] ?? [:]
        expect(safeCopy["valid"] == "Valid English", "A malformed sibling overlay must not discard valid English")
        expect(safeCopy["fallback"] == "中文回落", "A malformed English overlay should fall back to valid Chinese")
        expect((malformedResult["vocab"] as? [String: [String: Any]])?["ready"]?["label"] as? String == "中文状态", "Malformed vocabulary English should fall back to valid Chinese")
        expect((Api.localizedUI(["copy": 42], languages: english)["copy"] as? [String: String])?.isEmpty == true, "Malformed copy container should become an empty override")

        let legacy: [String: Any] = ["copy": ["note": "原有中文"], "vocab": ["ok": ["label": "正常", "tone": "good"]]]
        let normalizedLegacy = Api.localizedUI(legacy, languages: english)
        let legacyData = try snapshot(normalizedLegacy)
        let feed = try JSONDecoder().decode(FeedUI.self, from: legacyData)
        expect(feed.copy?["note"] == "原有中文", "Legacy payload should decode through the unchanged shared schema")
        expect(feed.vocab?["ok"]?.label == "正常", "Legacy vocabulary should decode through the unchanged shared schema")

        let error = Api.Failure(message: "原始错误", statusCode: 403, displayMessage: "English error")
        expect(error.message == "原始错误" && error.localizedDescription == "原始错误", "UI translation must not alter raw error text")
        expect(Api.displayError(error) == "English error", "UI error should use its separate display text")
        do {
            _ = try Api.decodeResponse(Data(#"{"ok":false,"err":"原始服务端错误","err_en":"English server error","code":"stable_code"}"#.utf8), statusCode: 409)
            failures.append("Expected an HTTP failure")
        } catch let failure as Api.Failure {
            expect(failure.message == "原始服务端错误", "Response errors must retain their original message")
            expect(failure.statusCode == 409, "Response errors must retain their HTTP status")
        }
        let successData = Data(#"{"ok":true,"message":"原消息","message_en":"English message","user_label":"用户中文","remaining":7}"#.utf8)
        let decoded = try Api.decodeResponse(successData, statusCode: 200)
        let expected = try JSONSerialization.jsonObject(with: successData) as! [String: Any]
        let actualSuccess = try snapshot(decoded)
        let expectedSuccess = try snapshot(expected)
        expect(actualSuccess == expectedSuccess, "Response parsing must preserve successful JSON fields and values")

        if !failures.isEmpty {
            for failure in failures { print("FAIL: \(failure)") }
            print("Localized payload regression: \(failures.count) failures / \(assertions) assertions")
            exit(1)
        }
        print("Localized payload regression passed (\(assertions) assertions)")
    }
}
