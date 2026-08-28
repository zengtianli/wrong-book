import SwiftUI

/// 登录页。
///
/// **有一条「先不登录，直接做题」** —— 这不是偷懒的兜底，是这个 app 的真实语义：
/// 练习页是自包含的，没网没账号照样能做完一套。登录只决定两件事：
/// 刷题积分记不记得上、学习进度跨不跨设备。把它做成硬门就会在没网时把 app 变砖，
/// 而没网恰恰是最需要它的时候。
struct LoginView: View {
    @EnvironmentObject var session: Session
    @State private var user = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            ruled                                   // 横格纸底纹：这是一个本子

            VStack(spacing: 22) {
                Spacer()
                VStack(spacing: 8) {
                    Text("错题本")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .foregroundStyle(Ink.text)
                    Text("错过的那一类题，换道新的再考你一次")
                        .font(.footnote).foregroundStyle(Ink.dim)
                }

                VStack(spacing: 10) {
                    field("用户名", text: $user, secure: false)
                    field("密码", text: $password, secure: true)
                }

                if let e = session.error {
                    Text(e).font(.footnote).foregroundStyle(Ink.red)
                        .multilineTextAlignment(.center).transition(.opacity)
                }

                Button {
                    Task { await session.login(user: user, password: password) }
                } label: {
                    HStack {
                        if session.busy { ProgressView().tint(.white) }
                        Text(session.busy ? "登录中" : "登录").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Ink.red, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .disabled(session.busy || user.isEmpty || password.isEmpty)
                .opacity(user.isEmpty || password.isEmpty ? 0.45 : 1)

                Button("先不登录，直接做题") { session.skipLogin() }
                    .font(.footnote).foregroundStyle(Ink.blue)

                Spacer()
                Text("题和进度都在 edu.tianli.cyou，这里是它的离线随身版")
                    .font(.caption2).foregroundStyle(Ink.dim.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)
        }
        .animation(.easeInOut(duration: 0.2), value: session.error)
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
