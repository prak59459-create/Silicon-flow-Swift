import Foundation

/// サーバー側（混雑・障害・レート制限）に関する診断
enum ServerDiagnoses {
    static func server(_ context: DiagnosisContext) -> ErrorDiagnosis {
        switch context.kind {
        case .rateLimited:
            return rateLimited(context)
        case .overloaded:
            return ErrorDiagnosis(
                kind: .overloaded,
                title: "モデルが混み合っています\(context.statusLabel)",
                cause: "\(context.modelLabel)へのアクセスが集中しているため、一時的に受け付けられませんでした。あなたの設定の問題ではありません。\(context.quotedServerMessage)",
                fixes: [
                    "数十秒〜数分待ってから再試行してください。",
                    "ストリーミングをオンにすると成功しやすくなることがあります。",
                    "急ぎの場合は、同じ系列の小さいモデルや「Pro/」版など別のモデルを試してください。",
                ],
                actions: [.retry, .enableStreaming, .chooseAnotherModel],
                isRetryable: true,
                severity: .warning
            )
        case .gatewayTimeout:
            return ErrorDiagnosis(
                kind: .gatewayTimeout,
                title: "サーバーの応答が時間切れになりました\(context.statusLabel)",
                cause: "生成に時間がかかりすぎたか、サーバーが混み合っています。長い出力や思考（推論）モデルで起こりやすいです。\(context.quotedServerMessage)",
                fixes: [
                    "ストリーミングをオンにしてください（少しずつ受け取るので時間切れになりにくくなります）。",
                    "最大トークン数を減らすか、質問を短くしてください。",
                    "少し待ってから再試行してください。",
                ],
                actions: [.enableStreaming, .reduceMaxTokens, .retry],
                isRetryable: true,
                severity: .warning
            )
        case .badGateway:
            return ErrorDiagnosis(
                kind: .badGateway,
                title: "中継サーバーでエラーが起きました\(context.statusLabel)",
                cause: "SiliconFlow の手前のサーバー（ゲートウェイ）で一時的な障害が起きています。\(context.quotedServerMessage)",
                fixes: [
                    "少し待ってから再試行してください。",
                    "VPN やプロキシを使っている場合は、オフにして試してください。",
                ],
                actions: [.retry, .runDiagnostics],
                isRetryable: true,
                severity: .warning
            )
        default:
            return ErrorDiagnosis(
                kind: .serverError,
                title: "サーバー内部でエラーが起きました\(context.statusLabel)",
                cause: "SiliconFlow のサーバー側で予期しない問題が起きました。\(context.quotedServerMessage)",
                fixes: [
                    "少し待ってから再試行してください。",
                    "別のモデルで試して、このモデルだけの問題か確認してください。",
                    "続く場合は、下の「技術情報」をコピーして help@siliconflow.com に問い合わせてください。",
                ],
                actions: [.retry, .chooseAnotherModel],
                isRetryable: true
            )
        }
    }

    private static func rateLimited(_ context: DiagnosisContext) -> ErrorDiagnosis {
        let dimension = FailureClassifier.rateLimitDimension(in: context.error.serverMessage)
        let limitText: String
        switch dimension {
        case "TPM": limitText = "1 分あたりのトークン数（TPM）"
        case "RPM": limitText = "1 分あたりのリクエスト数（RPM）"
        case "TPD": limitText = "1 日あたりのトークン数（TPD）"
        case "RPD": limitText = "1 日あたりのリクエスト数（RPD）"
        case "IPM": limitText = "1 分あたりの画像数（IPM）"
        case "IPD": limitText = "1 日あたりの画像数（IPD）"
        default: limitText = "利用回数・トークン数"
        }
        var fixes: [String] = []
        if let wait = context.error.retryAfter {
            fixes.append("\(NumberText.compact(wait, maxFractionDigits: 0)) 秒ほど待ってから再試行してください。")
        } else if dimension == "TPD" || dimension == "RPD" || dimension == "IPD" {
            fixes.append("1 日の上限に達しています。日付が変わるのを待つか、別のモデルを使ってください。")
        } else {
            fixes.append("1 分ほど待ってから再試行してください。")
        }
        fixes.append("短時間に連続して送信しないようにしてください。")
        fixes.append("上限はアカウントの利用レベルで決まります。チャージ額が増えると上限も上がります。")
        return ErrorDiagnosis(
            kind: .rateLimited,
            title: "利用上限（レート制限）に達しました\(context.statusLabel)",
            cause: "\(limitText)の上限を超えたため、一時的にリクエストが拒否されました。\(context.quotedServerMessage)",
            fixes: fixes,
            actions: [.retry, .chooseAnotherModel],
            isRetryable: true,
            severity: .warning
        )
    }
}
