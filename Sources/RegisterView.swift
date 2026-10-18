import SwiftUI

/// 邮箱注册先验证归属。规则、密码策略和容量由共享服务端判定。
/// 这里只做「两次密码是否一致」—— 服务端收不到第二个字段，没法替我们判。
struct RegisterView: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var nick = ""
    @State private var pw1 = ""
    @State private var pw2 = ""
    @State private var grant = ""
    @State private var agreed = false

    private var mismatch: Bool { !pw2.isEmpty && pw1 != pw2 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "邮箱"), text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField(String(localized: "昵称（可选）"), text: $nick)
                    AccountVerification(address: email, purpose: "register", phone: false, grant: $grant)
                } footer: {
                    Text(T("wrongbook.account.email.register_note", String(localized: "验证本人邮箱后注册，网页版 edu.tianli.cyou 使用同一账号。已有账号请先登录再绑定邮箱，保留原学习资料。")))
                }
                Section {
                    SecureField(String(localized: "密码（15–128字符）"), text: $pw1).textContentType(.newPassword).privacySensitive()
                    SecureField(String(localized: "再输一次"), text: $pw2).textContentType(.newPassword).privacySensitive()
                    if mismatch { Text(String(localized: "两次输入不一致")).font(.caption).foregroundStyle(Ink.red) }
                } footer: {
                    Text(String(localized: "账号保存邮箱、昵称、做题记录与你上传的试卷及识别结果。") + AccountDeletionCopy.summary)
                }
                Section {
                    AccountPolicyLinks()
                    Toggle(String(localized: "我已阅读并同意用户协议与隐私政策"), isOn: $agreed)
                    Text(T("account.password.rule_note", String(localized: "15–128 个字符，允许空格和中文。可使用系统生成密码或独特短语。"))).font(.footnote)
                }
                if let e = session.displayError ?? session.error {
                    Section { Text(e).foregroundStyle(Ink.red) }
                }
                Section {
                    Button {
                        Task {
                            await session.register(email: email.trimmingCharacters(in: .whitespaces),
                                                   password: pw1, nick: nick.trimmingCharacters(in: .whitespaces), grant: grant)
                            if session.phase == .loggedIn { dismiss() }
                        }
                    } label: {
                        HStack { Spacer()
                            if session.busy { ProgressView() } else { Text(String(localized: "注册并登录")).fontWeight(.semibold) }
                            Spacer() }
                    }
                    .disabled(session.busy || grant.isEmpty || !agreed || pw1.count < 15 || pw1.count > 128 || pw1 != pw2)
                }
            }
            .navigationTitle(String(localized: "邮箱注册"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { session.error = nil; dismiss() }
                        .disabled(session.busy)
                }
            }
        }
        .interactiveDismissDisabled(session.busy)
    }
}
