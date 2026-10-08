import Foundation

/// リクエスト内容に関する診断（モデル名・パラメータ・サイズ）
enum RequestDiagnoses {
    static func notFound(_ context: DiagnosisContext) -> ErrorDiagnosis {
        switch context.kind {
        case .modelDeprecated:
            return ErrorDiagnosis(
                kind: .modelDeprecated,
                title: "このモデルは提供終了しました\(context.statusLabel)",
                cause: "\(context.modelLabel)は SiliconFlow での提供が終了したか、終了予定です。\(context.quotedServerMessage)",
                fixes: [
                    "モデル一覧を更新して、現在提供中のモデルを選んでください。",
                    "同じシリーズの新しいバージョンがあればそちらを使ってください。",
                ],
                actions: [.refreshModels, .chooseAnotherModel]
            )
        case .endpointNotFound:
            return ErrorDiagnosis(
                kind: .endpointNotFound,
                title: "接続先が見つかりません\(context.statusLabel)",
                cause: "API の URL が間違っているか、プロキシ・カスタム URL の設定が正しくありません。\(context.quotedServerMessage)",
                fixes: [
                    "設定でカスタム URL をオフにして、標準の接続先（\(context.region.defaultBaseURL.absoluteString)）を使ってください。",
                    "カスタム URL を使う場合は末尾が /v1 になっているか確認してください。",
                ],
                actions: [.runDiagnostics]
            )
        default:
            return ErrorDiagnosis(
                kind: .modelNotFound,
                title: "モデルが見つかりません\(context.statusLabel)",
                cause: "\(context.modelLabel)は存在しないか、このアカウント・リージョンでは使えません。モデル名は大文字・小文字も区別されます。\(context.quotedServerMessage)",
                fixes: [
                    "モデル一覧を更新して、一覧にあるモデルを選んでください。",
                    "中国版と国際版では使えるモデルが異なります。もう一方のリージョンのキーを持っている場合は切り替えてみてください。",
                    "「Pro/」付きのモデルは名前が別扱いです。付け忘れ・付けすぎが無いか確認してください。",
                ],
                actions: [.refreshModels, .chooseAnotherModel, context.openModelsPage]
            )
        }
    }

    static func badRequest(_ context: DiagnosisContext) -> ErrorDiagnosis {
        switch context.kind {
        case .contextTooLong:
            return ErrorDiagnosis(
                kind: .contextTooLong,
                title: "入力または出力が長すぎます\(context.statusLabel)",
                cause: "入力トークン数と最大出力トークン数（max_tokens）の合計がモデルの上限を超えています。\(context.quotedServerMessage)",
                fixes: [
                    "パラメータ設定で「最大トークン数」を小さくしてください（例: 1024）。",
                    "会話が長くなっている場合は「新しい会話」で履歴をリセットしてください。",
                    "長い文章を扱う場合は、コンテキスト長の大きいモデル（128K 以上など）を選んでください。",
                ],
                actions: [.reduceMaxTokens, .chooseAnotherModel]
            )
        case .unsupportedParameter:
            return ErrorDiagnosis(
                kind: .unsupportedParameter,
                title: "このモデルが対応していない設定があります\(context.statusLabel)",
                cause: "思考モード（enable_thinking）や画像入力など、\(context.modelLabel)が対応していない機能・パラメータが送信されました。\(context.quotedServerMessage)",
                fixes: [
                    "パラメータ設定で「思考モード」を「自動」に戻してください。",
                    "画像を添付している場合は、画像対応（VLM）のモデルを選ぶか画像を外してください。",
                    "パラメータをリセットして既定値で送り直してください。",
                ],
                actions: [.disableThinking, .retry, .chooseAnotherModel]
            )
        case .payloadTooLarge:
            return ErrorDiagnosis(
                kind: .payloadTooLarge,
                title: "送信データが大きすぎます\(context.statusLabel)",
                cause: "添付した画像・音声ファイルや入力テキストのサイズが上限を超えています。\(context.quotedServerMessage)",
                fixes: [
                    "画像は小さめのもの（長辺 1500px 程度）にするか、枚数を減らしてください。",
                    "音声ファイルは短く切ってから送ってください。",
                ],
                actions: [.retry]
            )
        case .contentFiltered:
            return ErrorDiagnosis(
                kind: .contentFiltered,
                title: "内容が安全フィルタに引っかかりました\(context.statusLabel)",
                cause: "入力または出力の内容が SiliconFlow のコンテンツポリシーにより遮断されました。\(context.quotedServerMessage)",
                fixes: [
                    "表現を変えて、もう一度試してください。",
                    "別のモデルでは結果が変わることがあります。",
                ],
                actions: [.chooseAnotherModel],
                severity: .warning
            )
        default:
            return invalidRequest(context)
        }
    }

    private static func invalidRequest(_ context: DiagnosisContext) -> ErrorDiagnosis {
        var fixes = [
            "サーバーのメッセージに書かれたパラメータを確認してください。",
            "パラメータ設定をリセットして既定値で送り直してください。",
        ]
        if context.isChatEndpoint {
            fixes.append("チャットモデル以外（画像生成・埋め込み等）をチャット画面で使っていないか確認してください。")
        } else {
            fixes.append("画像サイズなど、モデルが対応している値を選んでいるか確認してください。")
        }
        return ErrorDiagnosis(
            kind: .invalidRequest,
            title: "リクエストの内容が正しくありません\(context.statusLabel)",
            cause: "送信したパラメータのどれかがこのモデルで受け付けられませんでした。\(context.quotedServerMessage)",
            fixes: fixes,
            actions: [.retry, .chooseAnotherModel, context.openErrorDocs]
        )
    }
}
