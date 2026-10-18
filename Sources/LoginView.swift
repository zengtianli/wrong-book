import SwiftUI

/// Account login, email registration, and an empty guest preview.
struct LoginView: View {
    @EnvironmentObject var session: Session
    @State private var user = ""
    @State private var password = ""
    @State private var showRegister = false
    @State private var showRecovery = false
    @State private var phoneMode = true
    @State private var phone = ""
    @State private var grant = ""
    @State private var riskPassword = ""
    @State private var riskEmail = ""
    @State private var emailGrant = ""

    var body: some View {
        ZStack {
            #if !os(visionOS)
            Ink.paper.ignoresSafeArea()
            #endif

            ScrollView { VStack(spacing: 22) {
                Spacer()
                #if os(visionOS)
                // Vision Pro：窗口是玻璃，表单是浮在上面的一张纸（亮色输入框摊在玻璃上读不清）
                VStack(spacing: 22) { form }
                    .padding(.vertical, 40).padding(.horizontal, 36)
                    .background(Ink.paper, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                #else
                form
                #endif
                Spacer()
                #if os(visionOS)
                // 这一行在纸外、直接落在玻璃上：用系统次级色，墨色在玻璃上读不清
                Text(String(localized: "从自己的错题照片开始，登录后导入和同步"))
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)
                #else
                Text(String(localized: "从自己的错题照片开始，登录后导入和同步"))
                    .font(.caption2).foregroundStyle(Ink.dim.opacity(0.8))
                    .multilineTextAlignment(.center)
                #endif
                #if os(iOS)
                ProductSettingsEntry().font(.footnote)
                #endif
            }
            .padding(.horizontal, 30).padding(.vertical, 24).frame(maxWidth: 450)
            }.frame(maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: session.error)
        .sheet(isPresented: $showRegister) { PhoneRegisterView() }
        .sheet(isPresented: $showRecovery) { AccountRecoveryView() }
        .task { try? await Api.accountHints() }
    }

    /// 标题、输入框、登录按钮和两个链接 —— 窄屏原样摊在纸色整页上，Vision Pro 收进一张纸里。
    @ViewBuilder
    private var form: some View {
        VStack(spacing: 8) {
            Text("Mistake Notebook")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Ink.text)
            Text(String(localized: "导入自己的错题照片，整理复习"))
                .font(.footnote).foregroundStyle(Ink.dim)
        }

        Picker(String(localized: "登录方式"), selection: $phoneMode) {
            Text(String(localized: "短信登录")).tag(true); Text(String(localized: "密码登录")).tag(false)
        }.pickerStyle(.segmented).disabled(session.busy)

        if phoneMode {
            VStack(alignment: .leading, spacing: 12) {
                TextField(String(localized: "+86 家长本人手机号"), text: $phone).textContentType(.telephoneNumber)
                    .keyboardType(.phonePad).privacySensitive().padding(14)
                    .background(Ink.card, in: RoundedRectangle(cornerRadius: 14))
                AccountVerification(address: phone, purpose: "login", grant: $grant)
                AccountRiskVerification(password: $riskPassword, email: $riskEmail, emailGrant: $emailGrant)
            }
            Button(session.busy ? String(localized: "登录中") : String(localized: "登录")) {
                Task { await session.phoneAuthenticate(grant: grant, password: riskPassword, emailGrant: emailGrant) }
            }.buttonStyle(.borderedProminent).frame(minHeight: 44).disabled(session.busy || grant.isEmpty)
        } else {
        VStack(spacing: 10) {
            field(String(localized: "手机号、用户名或邮箱"), text: $user, secure: false)
            field(String(localized: "密码"), text: $password, secure: true)
        }

        Button {
            Task { await session.login(user: user, password: password) }
        } label: {
            HStack {
                if session.busy { ProgressView().tint(.white) }
                Text(session.busy ? String(localized: "登录中") : String(localized: "登录")).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Ink.accent, in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(.white)
        }
        .flatButton()
        .disabled(session.busy || user.isEmpty || password.isEmpty)
        .opacity(user.isEmpty || password.isEmpty ? 0.45 : 1)
        }

        if let e = session.displayError ?? session.error {
            Text(e).font(.footnote).foregroundStyle(Ink.red)
                .multilineTextAlignment(.center).transition(.opacity)
        }

        HStack(spacing: 18) {
            Button(String(localized: "先看看")) { session.skipLogin() }
            Button(String(localized: "注册账号")) { showRegister = true }
            Button(String(localized: "忘记密码")) { showRecovery = true }
        }
        .flatButton()
        .font(.footnote).foregroundStyle(Ink.blue)
        .disabled(session.busy)
        Text(T("account.login.note", String(localized: "原账号和原密码可继续登录。短信暂不可用或其他地区可使用邮箱注册与密码登录。")))
            .font(.footnote).foregroundStyle(Ink.dim)
        AccountPolicyLinks().font(.footnote)
    }

    private var ruled: some View {
        GeometryReader { g in
            Path { p in
                var y: CGFloat = 120
                while y < g.size.height { p.move(to: .init(x: 0, y: y))
                    p.addLine(to: .init(x: g.size.width, y: y)); y += 34 }
            }
            .stroke(Ink.rule, lineWidth: 1)
        }
        .ignoresSafeArea()
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool) -> some View {
        Group {
            if secure {
                SecureField("", text: text).textContentType(.password)
            } else {
                TextField("", text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
            }
        }
        .foregroundStyle(Ink.text)
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.line, lineWidth: 1))
        .overlay(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(title).foregroundStyle(Ink.dim.opacity(0.7))
                    .padding(.leading, 16).allowsHitTesting(false)
            }
        }
    }
}
