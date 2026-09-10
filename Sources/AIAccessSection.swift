import SwiftUI

struct AIAccessSection: View {
    @Binding var enabled: Bool
    @State private var code = ""
    @State private var remaining = 0
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Section {
            if enabled {
                Label("DeepSeek AI 已开通", systemImage: "checkmark.circle")
                Text("今日剩余 \(remaining) 页识别额度").font(.footnote)
            } else {
                TextField("输入免费推广邀请码", text: $code)
                    .autocorrectionDisabled()
                Button(busy ? "正在验证…" : "开通 AI 识别") {
                    Task { await refresh(activate: true) }
                }.disabled(busy || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("AI 识别")
        } footer: {
            Text("邀请码用于免费开通试卷识别，由开发者提供并承担 AI 服务费用，无需购买邀请码或填写 API 密钥。AI 可能读错，请对照原图核对结果。")
        }
        .task { await refresh(activate: false) }
    }

    private func refresh(activate: Bool) async {
        busy = true
        defer { busy = false }
        do {
            let access = try await Api.aiAccess(code: activate ? code : nil)
            enabled = access.enabled
            remaining = access.remaining
            error = nil
            if enabled { code = "" }
        } catch { self.error = error.localizedDescription }
    }
}
