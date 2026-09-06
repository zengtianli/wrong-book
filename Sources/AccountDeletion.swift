import Foundation

enum AccountDeletionCopy {
    static let summary = "可在「我的 → 注销账号」发起删除。无扫描历史的普通账号可即时删除；涉及试卷、识别归档或旧数据的申请需核验处理，通常 30 天内完成。申请受理后暂停新增数据，受理不代表已删除，可在 App 内查看进度。"
}

struct DeletionReceipt: Codable {
    let id: String
    let status: String
    let expectedBy: String
    var owner: String = ""

    init(json: [String: Any], id: String = "") throws {
        self.id = json["receipt_id"] as? String ?? id
        self.status = json["status"] as? String ?? ""
        self.expectedBy = json["expected_by"] as? String ?? ""
        guard !self.id.isEmpty, ["pending", "completed"].contains(status) else {
            throw Api.Failure(message: "未收到有效的注销处理回执，请刷新后重试。")
        }
    }
}
