import SwiftUI

/// 邮箱注册。规则（邮箱格式 / 密码至少 6 位 / 邮箱是否已注册 / 名额）全在服务端，
/// 这里只做「两次密码是否一致」—— 服务端收不到第二个字段，没法替我们判。
struct RegisterView: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var nick = ""
    @State private var pw1 = ""
    @State private var pw2 = ""

    private var mismatch: Bool { !pw2.isEmpty && pw1 != pw2 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("邮箱", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("昵称（可选）", text: $nick)
                } footer: {
                    Text("邮箱就是登录名，网页版 edu.tianli.cyou 用同一个账号。")
                }
                Section {
                    SecureField("密码（至少 6 位）", text: $pw1).textContentType(.newPassword)
                    SecureField("再输一次", text: $pw2).textContentType(.newPassword)
                    if mismatch { Text("两次输入不一致").font(.caption).foregroundStyle(Ink.red) }
                } footer: {
                    Text("账号保存邮箱、昵称、做题记录与你上传的试卷及识别结果。" + AccountDeletionCopy.summary)
                    Link("阅读隐私政策", destination: URL(string: "https://app-ios-wrong-book.tianli.cyou/privacy.html")!)
                }
                if let e = session.error {
                    Section { Text(e).foregroundStyle(Ink.red) }
                }
                Section {
                    Button {
                        Task {
                            await session.register(email: email.trimmingCharacters(in: .whitespaces),
                                                   password: pw1, nick: nick.trimmingCharacters(in: .whitespaces))
                            if session.phase == .loggedIn { dismiss() }
                        }
                    } label: {
                        HStack { Spacer()
                            if session.busy { ProgressView() } else { Text("注册并登录").fontWeight(.semibold) }
                            Spacer() }
                    }
                    .disabled(session.busy || email.isEmpty || pw1.isEmpty || pw1 != pw2)
                }
            }
            .navigationTitle("邮箱注册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { session.error = nil; dismiss() } } }
        }
    }
}
