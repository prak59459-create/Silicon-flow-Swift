import Foundation

/// API キー・権限・残高に関する診断
enum AccountDiagnoses {
    static func credentials(_ context: DiagnosisContext) -> ErrorDiagnosis {
        let region = context.region
        switch context.kind {
        case .missingAPIKey:
            return ErrorDiagnosis(
                kind: .missingAPIKey,
                title: "API キーが入力されていません",
                cause: "SiliconFlow の API を呼ぶには API キー（sk- で始まる文字列）が必要です。",
                fixes: [
                    "\(region.displayName) のコンソールにログインし、「API キー」ページで新しいキーを作成します。",
                    "作成したキーをコピーして、このアプリの設定画面に貼り付けます。",
                ],
                actions: [.editAPIKey, context.openKeysPage]
            )
        case .malformedAPIKey:
            return ErrorDiagnosis(
                kind: .malformedAPIKey,
                title: "API キーの形式が正しくないようです",
                cause: "入力されたキーに空白・改行・全角文字などが含まれているか、キーの一部しか貼り付けられていない可能性があります。",
                fixes: [
                    "コンソールの「API キー」ページでキーの右にあるコピーボタンを使ってコピーし直してください。",
                    "「Bearer 」や引用符（\"）は付けずに、sk- から始まるキーだけを貼り付けてください。",
                ],
                actions: [.editAPIKey, context.openKeysPage]
            )
        case .invalidBaseURL:
            return ErrorDiagnosis(
                kind: .invalidBaseURL,
                title: "接続先 URL が正しくありません",
                cause: "設定されたカスタム URL を解釈できませんでした。",
                fixes: [
                    "設定でカスタム URL をオフにして、標準の接続先（\(region.defaultBaseURL.absoluteString)）を使ってください。",
                    "独自のプロキシを使う場合は https:// から始まる URL（例: https://example.com/v1）を入力してください。",
                ],
                actions: [.runDiagnostics]
            )
        default:
            return invalidKey(context)
        }
    }

    private static func invalidKey(_ context: DiagnosisContext) -> ErrorDiagnosis {
        let region = context.region
        return ErrorDiagnosis(
            kind: .invalidAPIKey,
            title: "API キーが無効です\(context.statusLabel)",
            cause: "SiliconFlow がこの API キーを受け付けませんでした。キーの打ち間違い・削除済みのキー・別リージョンのキーを使っている、のいずれかが原因です。\(context.quotedServerMessage)",
            fixes: [
                "中国版（siliconflow.cn）と国際版（siliconflow.com）はキーが別です。今は「\(region.displayName)」に接続しています。キーを作ったサイトと一致しているか確認してください。",
                "コンソールの「API キー」ページでキーが存在し、無効化されていないか確認してください。",
                "キーをコピーし直して貼り付けてください（前後の空白は自動で取り除かれます）。",
                "それでもダメなら新しいキーを作成してください。",
            ],
            actions: [.switchRegion(region.other), .editAPIKey, context.openKeysPage, .runDiagnostics]
        )
    }

    static func permission(_ context: DiagnosisContext) -> ErrorDiagnosis {
        switch context.kind {
        case .realNameRequired:
            return ErrorDiagnosis(
                kind: .realNameRequired,
                title: "実名認証が必要です\(context.statusLabel)",
                cause: "\(context.modelLabel)は実名認証（本人確認）を済ませたアカウントだけが使えます。\(context.quotedServerMessage)",
                fixes: [
                    "コンソールの「アカウント」→「実名認証」で本人確認を完了してください。",
                    "認証が終わるまでは、認証不要の別のモデルを選んでください。",
                ],
                actions: [context.openConsole, .chooseAnotherModel]
            )
        case .insufficientBalance:
            return ErrorDiagnosis(
                kind: .insufficientBalance,
                title: "残高が足りません\(context.statusLabel)",
                cause: "アカウントの残高が足りないか、未払い（残高がマイナス）になっているため、呼び出せませんでした。「Pro/」付きなど一部のモデルは代金券（旧・贈与残高）では支払えず、チャージした残高（充值余额）が必要です。\(context.quotedServerMessage)",
                fixes: [
                    "コンソールで残高と代金券（有効期限を含む）を確認し、必要ならチャージしてください。",
                    "残高がマイナスの場合は、チャージして未払い分を精算するまで無料モデルも含めて使えないことがあります。",
                    "モデル一覧で「無料」と表示されているモデルを試してください（フィルタで「無料のみ」を選べます）。",
                    "「Pro/」で始まるモデルはチャージ残高が必要な場合があります。「Pro/」の付かない版を試してください。",
                ],
                actions: [context.openConsole, .chooseAnotherModel]
            )
        case .modelAccessDenied:
            return ErrorDiagnosis(
                kind: .modelAccessDenied,
                title: "このモデルを使う権限がありません\(context.statusLabel)",
                cause: "\(context.modelLabel)はアカウントの種類・利用レベル・地域によって利用が制限されています。\(context.quotedServerMessage)",
                fixes: [
                    "モデル一覧を更新して、今のアカウントで使えるモデルか確認してください。",
                    "コンソールのモデルページで利用条件（実名認証・チャージ残高など）を確認してください。",
                    "別のモデルを選んでください。",
                ],
                actions: [.refreshModels, context.openModelsPage, .chooseAnotherModel]
            )
        default:
            return ErrorDiagnosis(
                kind: .forbidden,
                title: "アクセスが拒否されました\(context.statusLabel)",
                cause: "権限が不足しています。最も多い原因は実名認証が済んでいないことです（中国版では 2026 年 5 月 15 日から、実名認証が済んでいないアカウントはプラットフォームの機能を使えません）。ほかに残高不足やアカウントの制限も考えられます。\(context.quotedServerMessage)",
                fixes: [
                    "コンソールで実名認証が完了しているか確認してください。",
                    "残高と代金券が残っているか、残高がマイナスになっていないか確認してください。",
                    "別のモデルで試して、このモデルだけの問題か確認してください。",
                ],
                actions: [context.openConsole, .chooseAnotherModel, .runDiagnostics]
            )
        }
    }
}
