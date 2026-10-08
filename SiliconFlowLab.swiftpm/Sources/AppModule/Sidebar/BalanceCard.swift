import SwiftUI
import SiliconFlowKit

/// 接続中のリージョンと残高
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
        if let info = store.userInfo, let total = info.effectiveTotal {
            BalanceAmountView(info: info, total: total, currency: settings.region.currency, rates: settings.showYen ? store.exchangeRates : nil)
        } else if let error = store.balanceError {
            Label(error.diagnosis.title, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(3)
        } else {
            Text("残高を確認中…")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            if let charge = info.chargeBalance, let gift = info.balance {
                Text("チャージ \(currency.format(charge)) ・ 無料枠 \(currency.format(gift))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !info.isNormalStatus {
                Text("アカウントの状態: \(info.status ?? "")")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}
