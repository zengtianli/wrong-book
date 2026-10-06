import SwiftUI

/// Only the existing education service sends/verifies codes. Request IDs survive an
/// uncertain send so another tap cannot accidentally purchase a second message.
struct AccountVerification: View {
    @EnvironmentObject var session: Session
    let address: String
    let purpose: String
    var phone = true
    var password = ""
    var identityGrant = ""
    @Binding var grant: String
    @State private var challenge = ""
    @State private var code = ""
    @State private var requestID = UUID().uuidString
    @State private var busy = false
    @State private var canResend = true
    @State private var cooldown = UUID()
    @State private var resendSeconds = 60
    @State private var codeMinutes = 5
    @State private var sign = "恒创联众"
    @State private var message: String?
    @State private var active = true
    @State private var mayRequestNew = false
    private var inputKey: String { [address, purpose, password, identityGrant].joined(separator: "\u{1f}") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(challenge.isEmpty ? (phone ? "获取短信验证码" : "获取邮箱验证码") :
                   canResend ? "重新获取验证码" : "\(resendSeconds) 秒后可重新获取") {
                Task { await send() }
            }.frame(minHeight: 44).disabled(busy || session.busy || !canResend || address.isEmpty)
            if mayRequestNew {
                Button("等待后申请新的验证码") {
                    requestID = UUID().uuidString; mayRequestNew = false
                    Task { await send() }
                }.frame(minHeight: 44).disabled(busy || session.busy || !canResend)
                Text(T("account.phone.unknown_note", "原请求已回读；发送结果未知时不会自动重发。等待后可主动申请新验证码，旧码随之失效。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !challenge.isEmpty && grant.isEmpty {
                TextField("6 位验证码", text: $code).keyboardType(.numberPad)
                    .textContentType(.oneTimeCode).privacySensitive()
                Button("验证") { Task { await verify() } }
                    .frame(minHeight: 44).disabled(busy || session.busy || code.count != 6)
            }
            if !grant.isEmpty { Label("验证完成", systemImage: "checkmark.circle.fill").foregroundStyle(Ink.accent) }
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            if phone {
                Text(T("account.phone.footnote", "+86 家长手机号；短信签名「{sign}」，有效{minutes}分钟。收不到可等待重发或改用邮箱。",
                    ["sign": sign, "minutes": String(codeMinutes)]))
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text(T("account.email.code_note", "验证码发送到本人邮箱；请同时检查垃圾邮件。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onChange(of: inputKey) { _, _ in reset() }
        .onAppear { active = true }
        .onDisappear { active = false; reset() }
        .task(id: cooldown) {
            guard !canResend else { return }
            try? await Task.sleep(for: .seconds(resendSeconds))
            if !Task.isCancelled { canResend = true }
        }
    }
    private func send() async {
        let key = inputKey
        busy = true; defer { busy = false }
        // An uncertain failure keeps the same request ID; only a successful receipt
        // prepares the identity for the next explicit resend.
        canResend = false
        resendSeconds = phone ? AccountHints.resendSeconds() : 60
        cooldown = UUID()
        do {
            let response = try await Api.accountRequest(phone ? "api/phone_send" : "api/email_send", body: [
                phone ? "phone" : "email": address, "purpose": purpose, "password": password,
                "identity_grant": identityGrant, "request_id": requestID])
            guard active, key == inputKey else { return }
            challenge = response["challenge"] as? String ?? ""
            guard !challenge.isEmpty else { throw Api.Failure(message: "未收到验证请求编号，请稍后重试") }
            grant = ""; code = ""
            requestID = UUID().uuidString
            mayRequestNew = false
            message = response["message"] as? String
            sign = response["sign_name"] as? String ?? sign
            codeMinutes = AccountHints.codeMinutes(response["expires_in"])
            resendSeconds = phone ? AccountHints.resendSeconds(response["resend_after"]) : 60
            cooldown = UUID()
        } catch {
            guard active, key == inputKey else { return }
            session.authenticationFailure(error)
            mayRequestNew = phone && (error as? Api.Failure)?.statusCode == 503
            message = error.localizedDescription
        }
    }
    private func verify() async {
        let key = inputKey, id = challenge
        busy = true; defer { busy = false }
        do {
            let response = try await Api.accountRequest(phone ? "api/phone_verify" : "api/email_verify",
                body: ["challenge": id, "code": code])
            guard active, key == inputKey, id == challenge else { return }
            grant = response["grant"] as? String ?? ""
            guard !grant.isEmpty else { throw Api.Failure(message: "未收到验证授权，请重新验证") }
            code = ""; message = T("account.verification.done", "验证完成")
        } catch {
            guard active, key == inputKey else { return }
            session.authenticationFailure(error)
            message = error.localizedDescription
        }
    }
    private func reset() {
        challenge = ""; code = ""; grant = ""; message = nil
        requestID = UUID().uuidString; canResend = true; cooldown = UUID(); mayRequestNew = false
    }
}

struct PhoneRegisterView: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var grant = ""
    @State private var agreed = false
    @State private var showEmail = false
    var body: some View {
        NavigationStack {
            Form {
                Section("家长本人手机号") {
                    TextField("+86 手机号", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad).privacySensitive()
                    AccountVerification(address: phone, purpose: "register", grant: $grant)
                    Text(T("wrongbook.account.phone.register_note", "已有学习库账号请先登录，再在账号设置绑定手机号，保留原错题和订阅。新手机号注册会创建空白个人学习库；密码和邮箱可稍后设置。"))
                        .font(.footnote)
                }
                Section {
                    AccountPolicyLinks()
                    Toggle("我已阅读并同意用户协议与隐私政策", isOn: $agreed)
                }
                Button(session.busy ? "注册中" : "注册并登录") {
                    Task {
                        await session.phoneAuthenticate(grant: grant, registering: true, agreed: agreed)
                        if session.status != nil { dismiss() }
                    }
                }.frame(minHeight: 44).disabled(session.busy || grant.isEmpty || !agreed)
                Button("其他地区／使用邮箱注册") { showEmail = true }
                if let error = session.error { Text(error).foregroundStyle(Ink.red) }
            }.navigationTitle("手机号注册")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(session.busy) } }
                .sheet(isPresented: $showEmail) { RegisterView() }
        }.interactiveDismissDisabled(session.busy)
    }
}

struct AccountRiskVerification: View {
    @Binding var password: String
    @Binding var email: String
    @Binding var emailGrant: String
    var body: some View {
        DisclosureGroup("号码风险验证：原密码或独立邮箱") {
            SecureField("原登录密码（如已设置）", text: $password).textContentType(.password).privacySensitive()
            TextField("已绑定且验证的邮箱", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
            AccountVerification(address: email, purpose: "recover", phone: false, grant: $emailGrant)
            Text(T("account.phone.risk_note", "号码长期未用或登录环境变化时，服务端可能要求独立验证。不能完成时请联系支持。"))
                .font(.footnote)
        }
    }
}

struct AccountRecoveryView: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var phoneMode = true
    @State private var phone = ""
    @State private var email = ""
    @State private var grant = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var oldPassword = ""
    @State private var riskEmail = ""
    @State private var emailGrant = ""
    @State private var busy = false
    @State private var complete = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                if complete {
                    Text(T("wrongbook.account.recover.done_note", "密码已重置，原错题、学习记录与订阅保留。所有旧会话已失效，请重新登录。"))
                    Button("返回登录") { dismiss() }
                } else {
                    Picker("恢复方式", selection: $phoneMode) { Text("手机号").tag(true); Text("邮箱").tag(false) }
                        .onChange(of: phoneMode) { _, _ in grant = ""; emailGrant = "" }
                    TextField(phoneMode ? "已验证的 +86 手机号" : "已验证的邮箱", text: phoneMode ? $phone : $email)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    AccountVerification(address: phoneMode ? phone : email, purpose: phoneMode ? "phone_recover" : "recover",
                        phone: phoneMode, grant: $grant).id(phoneMode)
                    if phoneMode { AccountRiskVerification(password: $oldPassword, email: $riskEmail, emailGrant: $emailGrant) }
                    SecureField("新密码（15–128字符）", text: $password).textContentType(.newPassword).privacySensitive()
                    SecureField("确认新密码", text: $confirm).textContentType(.newPassword).privacySensitive()
                    Text(T("account.password.rule_note", "15–128 个字符，允许空格和中文。可使用系统生成密码或独特短语。")).font(.footnote)
                    Button(busy ? "提交中" : "重置密码") {
                        Task {
                            busy = true; defer { busy = false }
                            do {
                                _ = try await Api.accountRequest(phoneMode ? "api/phone_recover" : "api/recover",
                                    body: ["grant": grant, "new": password, "password": oldPassword, "email_grant": emailGrant])
                                complete = true; password = ""; confirm = ""; oldPassword = ""
                            } catch { message = error.localizedDescription }
                        }
                    }.frame(minHeight: 44).disabled(busy || grant.isEmpty || password.count < 15 || password.count > 128 || password != confirm)
                }
                if let message { Text(message).foregroundStyle(Ink.red) }
                Link("收不到验证码／恢复申诉：联系支持", destination: URL(string: "mailto:hi@tianli.cyou")!)
            }.navigationTitle("忘记密码")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(busy) } }
        }.interactiveDismissDisabled(busy)
    }
}

/// One existing internal account; both addresses can be changed without creating a
/// second learning library. All identity and two-address requirements are server-side.
struct AccountBindingView: View {
    let phone: Bool
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var currentPhone = ""
    @State private var hasPassword = true
    @State private var loaded = false
    @State private var address = ""
    @State private var password = ""
    @State private var identity = ""
    @State private var newGrant = ""
    @State private var oldGrant = ""
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section(phone ? "当前手机号" : "当前邮箱") { Text(current.isEmpty ? "未绑定验证" : current).privacySensitive() }
                if loaded {
                    Section("重新确认身份") {
                        if hasPassword { SecureField("当前登录密码", text: $password).textContentType(.password).privacySensitive() }
                        else { AccountVerification(address: currentPhone, purpose: "phone_identity", grant: $identity) }
                    }
                    Section(current.isEmpty ? "绑定验证地址" : "验证新地址") {
                        TextField(phone ? "+86 家长手机号" : "本人邮箱", text: $address)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        AccountVerification(address: address,
                            purpose: phone ? (current.isEmpty ? "phone_new" : "phone_change_new") : "email_new",
                            phone: phone, password: password, identityGrant: identity, grant: $newGrant)
                    }
                    if !current.isEmpty {
                        Section("确认原地址") {
                            AccountVerification(address: current, purpose: phone ? "phone_old" : "email_old",
                                phone: phone, password: password, identityGrant: identity, grant: $oldGrant)
                        }
                    }
                    Button(session.busy ? "保存中" : "确认保存") {
                        Task {
                            do {
                                let result = try await session.updateAccount(phone ? "api/phone_bind" : "api/email_bind", body: [
                                    phone ? "phone" : "email": address, "password": password, "identity_grant": identity,
                                    "grant": newGrant, "old_grant": oldGrant])
                                message = result["message"] as? String ?? T("account.binding.done", "绑定验证已保存")
                                password = ""; identity = ""; newGrant = ""; oldGrant = ""; address = ""
                                await load()
                            } catch { message = error.localizedDescription }
                        }
                    }.frame(minHeight: 44).disabled(session.busy || newGrant.isEmpty || (!current.isEmpty && oldGrant.isEmpty))
                } else { Button("重新读取账号") { Task { await load() } } }
                if let message { Text(message).font(.footnote) }
                Text(T("wrongbook.account.binding.note", "绑定和换绑保留原内部账号、错题、学习记录和订阅。手机号换绑会使其他旧会话失效；地址被占用时不会自动合并账号。")).font(.footnote)
                Link("原地址无法使用／恢复申诉", destination: URL(string: "mailto:hi@tianli.cyou")!)
            }.navigationTitle(phone ? "手机绑定与换绑" : "邮箱验证与换绑")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(session.busy) } }
                .task { await load() }
        }.interactiveDismissDisabled(session.busy)
    }
    private func load() async {
        do {
            let me = try await Api.accountRequest("api/me")
            currentPhone = me["phone"] as? String ?? ""
            current = phone ? (me["phone_verified"] as? Bool == true ? currentPhone : "") :
                (me["email_verified"] as? Bool == true ? me["email"] as? String ?? "" : "")
            hasPassword = me["has_password"] as? Bool ?? true
            loaded = true
        } catch { session.authenticationFailure(error); message = error.localizedDescription }
    }
}

struct AccountPasswordView: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var hasPassword = true
    @State private var loaded = false
    @State private var old = ""
    @State private var grant = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                if loaded {
                    if hasPassword { SecureField("当前密码", text: $old).textContentType(.password).privacySensitive() }
                    else {
                        Text(T("account.phone.password_set_note", "确认当前绑定手机后设置独立登录密码。已有密码请使用修改或找回流程。")).font(.footnote)
                        AccountVerification(address: phone, purpose: "phone_identity", grant: $grant)
                    }
                    SecureField("新密码（15–128字符）", text: $password).textContentType(.newPassword).privacySensitive()
                    SecureField("确认密码", text: $confirm).textContentType(.newPassword).privacySensitive()
                    Text(T("account.password.rule_note", "15–128 个字符，允许空格和中文。可使用系统生成密码或独特短语。")).font(.footnote)
                    Button(session.busy ? "保存中" : hasPassword ? "修改登录密码" : "设置登录密码") {
                        Task {
                            do {
                                _ = try await session.updateAccount(hasPassword ? "api/passwd" : "api/password_set",
                                    body: hasPassword ? ["old": old, "new": password] : ["identity_grant": grant, "new": password])
                                old = ""; password = ""; confirm = ""; grant = ""
                                message = T("account.password.saved", "密码已保存，其他旧会话已失效。")
                                await load()
                            } catch { message = error.localizedDescription }
                        }
                    }.frame(minHeight: 44).disabled(session.busy || (hasPassword ? old.isEmpty : grant.isEmpty) ||
                        password.count < 15 || password.count > 128 || password != confirm)
                } else { Button("重新读取账号") { Task { await load() } } }
                if let message { Text(message).font(.footnote) }
            }.navigationTitle("登录密码")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.disabled(session.busy) } }
                .task { await load() }
        }.interactiveDismissDisabled(session.busy)
    }
    private func load() async {
        do {
            let me = try await Api.accountRequest("api/me")
            phone = me["phone"] as? String ?? ""; hasPassword = me["has_password"] as? Bool ?? true; loaded = true
        } catch { session.authenticationFailure(error); message = error.localizedDescription }
    }
}

/// Legal text and decisions ship with the app; remote UI only overrides account hints.
struct AccountPolicyLinks: View {
    @State private var privacy = false
    @State private var terms = false
    var body: some View {
        Group {
            Button("阅读用户协议") { terms = true }
            Button("阅读隐私政策") { privacy = true }
        }
        .sheet(isPresented: $privacy) { AccountPolicyView(privacy: true) }
        .sheet(isPresented: $terms) { AccountPolicyView(privacy: false) }
    }
}

struct AccountPolicyView: View {
    let privacy: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(privacy ? "错题本隐私政策" : "错题本用户协议").font(.title2.bold())
                    Text("错题本用于整理家长和学习者自己的错题照片、学习资料及复习记录；只上传你有权使用的内容。")
                    Text("账号保存家长本人手机号或邮箱、已设置密码的安全哈希、可选昵称、错题照片、识别结果与学习记录。手机验证码用于注册、登录、绑定和恢复；不收集孩子手机号，不用于营销。")
                    Text("手机认证由阿里云处理手机号和验证请求，当前只支持中国大陆 +86；海外用户可以使用邮箱。请勿向他人提供密码和验证码。")
                    Text("图片只有在明确同意后才上传至现有学习服务并交由 DeepSeek 识别。免费识别额度和 Apple 订阅权益由服务端核验。")
                    Text(AccountDeletionCopy.summary + "注销不会自动取消 Apple 订阅，请先在系统订阅设置中取消续期。")
                    Link("完整隐私说明", destination: URL(string: "https://app-ios-wrong-book.tianli.cyou/privacy.html")!)
                    Link("帮助与账号恢复申诉", destination: URL(string: "mailto:hi@tianli.cyou")!)
                }.padding(24).frame(maxWidth: 740)
            }.navigationTitle(privacy ? "隐私政策" : "用户协议")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}
