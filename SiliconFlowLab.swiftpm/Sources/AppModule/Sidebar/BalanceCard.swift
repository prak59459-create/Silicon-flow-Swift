import SwiftUI
import SiliconFlowKit

/// 接続中のリージョンと残高（参考）
///
/// 残高照会 API（GET /user/info）は中国版で 2026-08-14 に提供終了したため、
/// 取れないときはエラーではなく、コンソールで確認する案内を出します。
struct BalanceCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ModelStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(settings.region.displayName, systemImage: "globe.asia.australia")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.isLoadingBalance {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            balance
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { router.show(.settings) }
    }

    @ViewBuilder
    private var balance: some View {
        switch store.balance {
        case .available(let info)?:
            if let total = info.effectiveTotal {
                BalanceAmountView(info: info, total: total, currency: settings.region.currency, rates: settings.showYen ? store.exchangeRates : nil)
            } else {
                ConsoleBalanceLink(message: "残高の情報がありませんでした", region: settings.region)
            }
        case .unsupported?:
            ConsoleBalanceLink(message: "残高は API で取得できなくなりました", region: settings.region)
        case .failed(let error)?:
            ConsoleBalanceLink(message: "残高を取得できませんでした（\(error.diagnosis.title)）", region: settings.region)
        case nil:
            Text(store.isLoadingBalance ? "残高を確認中…" : "残高はまだ確認していません")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// 残高を API で取れないときの案内（コンソールを開くボタン付き）
private struct ConsoleBalanceLink: View {
    let message: String
    let region: APIRegion
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Button {
                openURL(region.consoleURL)
            } label: {
                Label("残高・代金券をコンソールで見る", systemImage: "safari")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }
}

private struct BalanceAmountView: View {
    let info: UserInfo
    let total: Double
    let currency: Currency
    let rates: ExchangeRates?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("残高 \(currency.format(total))")
                .font(.headline.monospacedDigit())
            if let yen = Money(amount: total, currency: currency).converted(to: .jpy, using: rates) {
                Text("≈ \(yen.formatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let charge = info.chargeBalance {
                Text("うちチャージ \(currency.format(charge))・代金券は含まない場合があります")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if total < 0 {
                Text("残高がマイナス（未払い）です。チャージするまで使えない場合があります")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if !info.isNormalStatus {
                Text("アカウントの状態: \(info.status ?? "")")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}
