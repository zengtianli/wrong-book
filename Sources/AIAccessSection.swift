import StoreKit
import SwiftUI

struct AIAccessSection: View {
    @Binding var enabled: Bool
    var refreshID = 0
    @EnvironmentObject private var session: Session
    @ObservedObject private var store = AISubscription.shared

    var body: some View {
        Section {
            if let access = store.access {
                if access.subscribed {
                    Label("AI 识别订阅有效", systemImage: "checkmark.circle")
                    if let expires = access.expires {
                        Text("当前有效期至 \(expires.formatted(date: .numeric, time: .omitted))").font(.footnote)
                    }
                } else {
                    Text("免费识别剩余 \(access.remaining) / 10 张")
                    Text("前 10 张免费，之后订阅继续识别。已导入的题目可继续复习。")
                        .font(.footnote)
                }
            } else {
                Text(store.refreshingAccess ? "正在查询识别额度…" : "识别额度尚未同步，请登录后刷新。")
            }
            if store.access?.subscribed != true {
                ForEach(store.products) { product in
                    Button {
                        Task { await store.purchase(product) }
                    } label: {
                        Text(product.id.hasSuffix(".monthly")
                             ? "月订阅 · \(product.displayPrice) / 月"
                             : "年订阅 · \(product.displayPrice) / 年")
                    }.disabled(store.busy || store.loadingProducts || store.access?.token == nil)
                }
                if store.loadingProducts { ProgressView("正在加载订阅方案…") }
                if let message = store.productMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                    Button("重新加载订阅方案") { Task { await store.loadProducts() } }
                        .disabled(store.loadingProducts || store.processingPurchase)
                }
            }
            Button("恢复购买") { Task { await store.restore() } }.disabled(store.busy)
            Button("刷新额度与订阅") { Task { await store.refresh() } }.disabled(store.busy || store.loadingProducts)
            Link("管理或取消订阅", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            if let message = store.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            Link("隐私政策", destination: URL(string: "https://app-ios-wrong-book.tianli.cyou/privacy.html")!)
            Link("使用条款", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
        } header: {
            Text("AI 识别与订阅")
        } footer: {
            Text("月订阅和年订阅均可在有效期内继续识别。订阅由 Apple 收费并自动续期，可在系统订阅设置中取消。免费 10 张为账号一次性额度，识别失败不扣次数。AI 可能读错，请对照原图核对结果。")
        }
        .task(id: "\(session.status?.user ?? "")-\(refreshID)") { await store.refresh() }
        .onChange(of: store.access?.enabled) { _, value in enabled = value == true }
        .onChange(of: store.busy) { _, busy in
            if !busy, store.access == nil { enabled = false }
        }
    }
}
