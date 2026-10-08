import Foundation

/// 通信・応答形式に関する診断
enum NetworkDiagnoses {
    static func network(_ context: DiagnosisContext) -> ErrorDiagnosis {
        let host = context.region.host
        switch context.kind {
        case .offline:
            return ErrorDiagnosis(
                kind: .offline,
                title: "インターネットに接続されていません",
                cause: "iPad がネットワークにつながっていないため、SiliconFlow に接続できませんでした。",
                fixes: [
                    "Wi-Fi またはモバイル通信がオンになっているか確認してください。",
                    "機内モードがオフになっているか確認してください。",
                    "Swift Playgrounds にモバイル通信の使用が許可されているか（設定 → モバイル通信）確認してください。",
                ],
                actions: [.retry],
                isRetryable: true
            )
        case .timedOut:
            return ErrorDiagnosis(
                kind: .timedOut,
                title: "通信がタイムアウトしました",
                cause: "決められた時間内に応答がありませんでした。回線が遅い・サーバーが混雑している・長い生成に時間がかかっている、のいずれかです。",
                fixes: [
                    "ストリーミングをオンにしてください（長い生成でも途切れにくくなります）。",
                    "設定でタイムアウト時間を長くしてください。",
                    "電波の良い場所で再試行してください。",
                ],
                actions: [.enableStreaming, .retry],
                isRetryable: true,
                severity: .warning
            )
        case .dnsFailure:
            return ErrorDiagnosis(
                kind: .dnsFailure,
                title: "接続先のサーバーが見つかりません",
                cause: "\(host) の名前解決（DNS）に失敗しました。ネットワークがこのサイトをブロックしているか、カスタム URL が間違っています。",
                fixes: [
                    "別の Wi-Fi やモバイル通信に切り替えて試してください（学校・会社のネットワークは制限があることがあります）。",
                    "カスタム URL を設定している場合はオフにしてください。",
                    "VPN を使っている場合は、オン・オフを切り替えて試してください。",
                ],
                actions: [.retry, .runDiagnostics],
                isRetryable: true
            )
        case .tlsFailure:
            return ErrorDiagnosis(
                kind: .tlsFailure,
                title: "安全な接続（HTTPS）を確立できませんでした",
                cause: "サーバー証明書の確認に失敗しました。端末の日付がずれている・公衆 Wi-Fi のログイン画面に捕まっている・通信を監視するプロキシがある、のいずれかが原因です。",
                fixes: [
                    "設定 → 一般 → 日付と時刻 で「自動設定」がオンか確認してください。",
                    "公衆 Wi-Fi の場合は Safari を開いてログインを済ませてください。",
                    "VPN・プロキシ・フィルタリングアプリをオフにして試してください。",
                ],
                actions: [.retry, .runDiagnostics]
            )
        case .cancelled:
            return ErrorDiagnosis(
                kind: .cancelled,
                title: "キャンセルしました",
                cause: "リクエストは途中で中止されました。",
                fixes: ["必要ならもう一度送信してください。"],
                actions: [.retry],
                isRetryable: true,
                severity: .info
            )
        default:
            return ErrorDiagnosis(
                kind: .connectionFailed,
                title: "サーバーに接続できませんでした",
                cause: "\(host) への接続が確立できなかったか、途中で切断されました。",
                fixes: [
                    "ネットワークの状態を確認して再試行してください。",
                    "VPN やプロキシを使っている場合はオフにして試してください。",
                    "「接続診断」でどこまで通信できているか確認できます。",
                ],
                actions: [.retry, .runDiagnostics],
                isRetryable: true
            )
        }
    }

    static func response(_ context: DiagnosisContext) -> ErrorDiagnosis {
        let snippet = context.error.bodySnippet.map { "\n受信した内容の先頭: \(TextSanitizer.snippet($0, limit: 160))" } ?? ""
        switch context.kind {
        case .unexpectedResponse:
            return ErrorDiagnosis(
                kind: .unexpectedResponse,
                title: "API ではないページが返ってきました\(context.statusLabel)",
                cause: "JSON ではなく Web ページ（HTML）などが返ってきました。公衆 Wi-Fi のログイン画面・プロキシ・誤ったカスタム URL が原因のことが多いです。\(snippet)",
                fixes: [
                    "Safari で何かのサイトを開き、Wi-Fi のログイン画面が出ないか確認してください。",
                    "カスタム URL を設定している場合はオフにしてください。",
                    "別のネットワークで試してください。",
                ],
                actions: [.retry, .runDiagnostics]
            )
        case .decodingFailed:
            return ErrorDiagnosis(
                kind: .decodingFailed,
                title: "応答を読み取れませんでした",
                cause: "サーバーの応答の形式が想定と違いました。API の仕様変更、または特殊なモデルの応答形式が原因の可能性があります。\(context.error.underlying.map { "\n詳細: \($0)" } ?? "")",
                fixes: [
                    "もう一度試してください。",
                    "別のモデルで同じ操作ができるか確認してください。",
                    "続く場合は「技術情報」をコピーして GitHub の Issue で報告してください。",
                ],
                actions: [.retry, .chooseAnotherModel]
            )
        case .streamInterrupted:
            return ErrorDiagnosis(
                kind: .streamInterrupted,
                title: "応答の受信が途中で途切れました",
                cause: "ストリーミング中に接続が切れました。ここまでに受信した内容は残してあります。",
                fixes: [
                    "通信が安定している場所で再試行してください。",
                    "長い出力の場合は最大トークン数を減らしてください。",
                ],
                actions: [.retry, .reduceMaxTokens],
                isRetryable: true,
                severity: .warning
            )
        case .emptyResponse:
            return ErrorDiagnosis(
                kind: .emptyResponse,
                title: "応答が空でした",
                cause: "サーバーは成功を返しましたが、内容がありませんでした。最大トークン数が小さすぎる・思考だけで出力上限に達した、などが考えられます。",
                fixes: [
                    "最大トークン数を増やして再試行してください。",
                    "思考（推論）モデルの場合は思考の予算（thinking_budget）を小さくするか、最大トークン数を大きくしてください。",
                ],
                actions: [.retry],
                isRetryable: true,
                severity: .warning
            )
        default:
            return ErrorDiagnosis(
                kind: .unknown,
                title: "予期しないエラーが起きました\(context.statusLabel)",
                cause: "原因を特定できませんでした。\(context.quotedServerMessage)\(context.error.underlying.map { "\n詳細: \($0)" } ?? "")",
                fixes: [
                    "もう一度試してください。",
                    "「接続診断」を実行して、どこで失敗しているか確認してください。",
                    "続く場合は「技術情報」をコピーして GitHub の Issue で報告してください。",
                ],
                actions: [.retry, .runDiagnostics]
            )
        }
    }
}
