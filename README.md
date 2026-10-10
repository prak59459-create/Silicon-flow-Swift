# SiliconFlow Lab

**SiliconFlow の API キーを入れるだけで、使えるモデルの一覧・料金・パラメータ数（B 数）を確認して、その場で試せる iPad アプリ**です。
iPad の **Swift Playgrounds の「App」プロジェクト（`.swiftpm`）** として作られているので、Mac が無くても iPad だけで開いて実行・改造できます。

[![CI](https://github.com/prak59459-create/Silicon-flow-Swift/actions/workflows/ci.yml/badge.svg)](https://github.com/prak59459-create/Silicon-flow-Swift/actions/workflows/ci.yml)
[![モデルカタログの自動更新](https://github.com/prak59459-create/Silicon-flow-Swift/actions/workflows/catalog.yml/badge.svg)](https://github.com/prak59459-create/Silicon-flow-Swift/actions/workflows/catalog.yml)

---

## できること

| 機能 | 内容 |
| --- | --- |
| モデル一覧 | API キーで `GET /v1/models` を呼び、**あなたのアカウントで使えるモデルだけ**を表示。種類（チャット・画像理解・埋め込み・リランク・画像生成・音声合成・音声認識・動画生成）ごとに自動分類 |
| 料金 | 入力 / 出力の 100 万トークンあたりの価格（画像は 1 枚、動画は 1 本あたり）。中国版は人民元（元）、国際版は米ドル。**円換算**も表示 |
| パラメータ数（B 数） | 総パラメータ数と、MoE モデルはアクティブパラメータ数（例: `235B（アクティブ 22B）`） |
| その他の仕様 | コンテキスト長・最大出力・画像入力 / ツール呼び出し / 思考（推論）などの対応機能・公開日・提供終了予定日 |
| 検索・並べ替え | 名前・組織・タグで検索。安い順・パラメータ数順・コンテキスト長順・新しい順。「無料のみ」 |
| チャットで試す | ストリーミング表示、思考過程（reasoning_content）の表示、Markdown・コードブロック、画像の添付（VLM）、**最初の応答までの時間・トークン/秒・使用トークン・料金**をメッセージごとに表示 |
| その他のモデルを試す | 埋め込み（類似度計算）・リランク・画像生成 / 編集・音声合成（再生）・音声認識（ファイルから）・動画生成（受付→自動で完成を確認→再生） |
| 残高（参考） | 残高照会 API（`GET /v1/user/info`）は中国版で **2026-08-14 に提供終了**（HTTP 410 / コード 20092）したため、取れたときだけ参考表示し、取れないときはコンソールを開くボタンを表示。キーの確認やモデル一覧には一切使いません |
| **失敗したときの診断** | 「なぜ失敗したか」と「どうすれば直るか」を日本語で表示し、直すための操作（リージョン切り替え・キー再入力・最大トークン数を減らす 等）をボタン 1 つで実行 |
| 接続診断 | キーの形式 → サーバーへの接続 → 認証とモデル一覧（`GET /v1/models`）→ 残高（参考・失敗しても問題として数えない）→ 無料モデルでのテスト送信、の順にどこで失敗しているかを特定 |

---

## iPad に入れる方法

### いちばん簡単な方法（Releases からダウンロード）

1. iPad の Safari で [**Releases の「latest」**](https://github.com/prak59459-create/Silicon-flow-Swift/releases/tag/latest) を開き、`SiliconFlowLab.swiftpm.zip` をタップしてダウンロードします。
2. **ファイル** App の「ダウンロード」を開き、zip をタップして展開します。
3. できた **`SiliconFlowLab.swiftpm`** をタップすると Swift Playgrounds で開きます。
4. 右上の ▶︎（実行）を押すとアプリが起動します。

> zip は main ブランチが更新されるたびに GitHub Actions が自動で作り直します（CI のすべてのテスト・ビルドに合格したものだけ）。

### ほかの方法

- GitHub のこのページで「Code → Download ZIP」→ 展開した中の `SiliconFlowLab.swiftpm` を開く
- Mac で `git clone` して `SiliconFlowLab.swiftpm` を iCloud Drive に置き、iPad の Swift Playgrounds で開く（Mac の Xcode でもそのまま開けます）

### 動作環境

- iPadOS 17 以降
- Swift Playgrounds 4.4 以降（最新版を推奨）。Mac の Swift Playgrounds / Xcode でも動きます
- iPhone でも動きます（画面は 1 列表示になります）

---

## 使い方

1. 初回起動時に API キーを貼り付けて「接続」を押します。
   - キーは [中国版のコンソール](https://cloud.siliconflow.cn/account/ak) または [国際版のコンソール](https://cloud.siliconflow.com/account/ak) で作れます。
   - **中国版と国際版のどちらのキーかは自動で判定**します（両方で `GET /v1/models` を API キー付きで呼び、通った方を使います）。
   - 通信できない・サーバーが不調などで確認できなかったときも、キーが無効と分かった場合以外は「確認せずに保存」で始められます。
   - キーは端末の**キーチェーン**に保存され、SiliconFlow 以外には送信されません。
2. 左のサイドバーで種類を選び、一覧からモデルを選びます。
3. 右側の「試す」タブで実際に使い、「詳細」タブで料金・パラメータ数・情報の出どころを確認します。

---

## 料金・パラメータ数はどこから取っているか

すべて **Web から取得**し、取れないときは自動で次の情報源に切り替えます。

| 優先 | 情報源 | 内容 |
| --- | --- | --- |
| 1 | **SiliconFlow 公式サイト**（[siliconflow.cn/pricing](https://siliconflow.cn/pricing)） | 中国版の人民元価格・パラメータ数・コンテキスト長・機能をページから直接読み取り |
| 2 | **GitHub カタログ**（[`catalog/siliconflow-catalog.json`](catalog/siliconflow-catalog.json)） | GitHub Actions が**毎日**公式サイト・models.dev・Hugging Face から集めて更新。CDN（jsDelivr）経由の予備 URL あり |
| 3 | **[models.dev](https://models.dev)** | GitHub が使えないときの予備。国際版の米ドル価格など。5MB の JSON から必要な部分だけを切り出して読むのでメモリを使いません |
| 4 | **[Hugging Face](https://huggingface.co)** | モデルの詳細を開いたときに、実際のパラメータ数・ライセンス・ダウンロード数を取得 |
| 5 | モデル名からの推定 | `Qwen3-235B-A22B` → 235B / アクティブ 22B のように名前から読み取り |
| 6 | **同梱データ** | 完全にオフラインでも表示できるよう、アプリに入れてある最終手段のデータ（毎日自動で更新） |

画面の「価格情報の取得元」（一覧右上の ⓘ）で、どの情報源から取得できたか・失敗したかを確認できます。
円換算は [ExchangeRate-API](https://www.exchangerate-api.com)（予備に欧州中央銀行の [Frankfurter](https://frankfurter.dev)）のレートを使った目安です。

---

## API 呼び出しに失敗したとき

失敗はすべて分類され、次の 3 点が表示されます。

1. **何が起きたか**（例: 「API キーが無効です（HTTP 401 / コード 30014）」）
2. **なぜ失敗したか**（サーバーのメッセージも引用）
3. **どうすれば直るか**（番号付きの手順 ＋ ワンタップで実行できるボタン）

| 分類の例 | 主な原因 | 表示される直し方の例 |
| --- | --- | --- |
| API キーが無効（401 / 30014） | 打ち間違い・削除済み・**中国版と国際版の取り違え** | もう一方のリージョンに切り替えるボタン、キーのページを開く |
| モデルが見つからない（20012） | モデル名の違い・提供終了・リージョン違い | モデル一覧を更新、別のモデルを選ぶ |
| 実名認証が必要 / 残高不足（402 / 403 / 30001） | 実名認証未完了・残高がマイナス（未払い）・代金券では払えないモデル | コンソールを開く、無料モデルを選ぶ |
| API が提供終了（410 / 20092） | SiliconFlow 側で API が廃止された（例: 残高照会 API） | キーの問題ではないことを明示し、お知らせ・コンソールを開く |
| 入力が長すぎる（400） | コンテキスト長・max_tokens の超過 | 最大トークン数を半分にして再試行するボタン |
| 対応していないパラメータ（400） | 思考モードなど非対応の機能 | 思考モードをオフにして再試行するボタン |
| レート制限（429） | RPM / TPM / RPD などの上限 | どの上限か・待つべき秒数（Retry-After） |
| 混雑・タイムアウト（503 / 504） | サーバーの一時的な混雑 | ストリーミングをオンにして再試行 |
| オフライン・DNS・TLS | 通信できない・名前解決できない・証明書エラー | Wi-Fi・機内モード・日時設定・VPN の確認 |
| HTML が返ってきた | 公衆 Wi-Fi のログイン画面・プロキシ | Safari でログイン、カスタム URL をオフ |

技術情報（エンドポイント・HTTP ステータス・エラーコード・トレース ID）はコピーして問い合わせに使えます。

---

## ビルドを速く・軽くするための工夫

iPad 上でコンパイルすることを前提に、ビルド時間とメモリ使用量を抑える設計にしています。

- **モジュールを 2 つに分割**: UI 以外のすべて（`SiliconFlowKit`）と SwiftUI の画面（`AppModule`）。画面だけを直したときは UI 側だけが再コンパイルされ、1 回のコンパイルに必要なメモリも小さくなります。
- **ファイルを小さく分割**（約 100 ファイル、1 ファイル 400 行以下を CI で強制）。増分ビルドで変更したファイルだけが再コンパイルされます。
- **マクロを使わない**（`@Observable` `#Preview` `SwiftData` 不使用）。マクロ展開のための追加処理が発生しません。
- **外部パッケージに依存しない**。依存関係の取得・コンパイルが不要です。
- **型チェックの重い書き方を避ける**: 大きな `body` は小さな View に分割し、クロージャに型を明示。CI で **型チェックに 150ms 以上かかる関数・式を自動検出**して報告します。
- 実行時も、ストリーミング中の画面更新を間引く（60ms ごと）・Markdown の整形は生成完了後だけ・画像は縮小してから送信・巨大な JSON は必要部分だけ読む、などでメモリと CPU を節約しています。

---

## 品質保証（GitHub Actions）

| ジョブ | 内容 |
| --- | --- |
| Playgrounds 互換チェック | `.swiftpm` の形式、Swift 以外のファイルが無いこと、マクロ・Swift 6 専用構文を使っていないこと、ファイルの大きさ など |
| Linux テスト（Swift 5.10 / 6.0 / 6.3） | `SiliconFlowKit` の 150 件以上の単体テスト。Swift 5.10 は Swift Playgrounds 4.5 と同じコンパイラ |
| 厳格な並行性チェック | Swift 6 言語モードでコンパイル（データ競合が無いことをコンパイラで保証） |
| macOS テスト | Apple 版 Foundation での同じテスト |
| iPad アプリのビルド（Xcode 16 / 26） | **UI を含むアプリ全体**を iOS 向けにビルドし、型チェックの遅い箇所を報告 |
| 配布用 zip | すべて合格したら `SiliconFlowLab.swiftpm.zip` を作成し、main では Releases に公開 |
| モデルカタログの自動更新（毎日） | Web から価格・パラメータ数を取り直し、公式サイトの形式が変わっていないかも本物のサイトで検証 |

テストでは、モック通信で「401・402・403・404・410（API の提供終了）・429・503・HTML 応答・空応答・壊れた JSON・ストリーム途中の切断・ストリーム中のエラー JSON・オフライン」などあらゆる失敗パターンを再現し、正しく分類・診断されることを確認しています。

**本物の API での結合テスト**も用意しています。リポジトリの Settings → Secrets and variables → Actions に
`SILICONFLOW_API_KEY`（Secret）と、必要なら `SILICONFLOW_REGION`（Variable、`cn` または `global`）を登録すると、CI で実際に API を呼ぶテスト（キーの確認・モデル一覧・無料モデルでのストリーミング・残高 API が提供終了していても他に影響しないこと）も実行されます。

---

## 開発者向け

```text
.
├── SiliconFlowLab.swiftpm/          ← Swift Playgrounds で開くアプリ本体
│   ├── Package.swift                  （AppleProductTypes の iOSApplication）
│   └── Sources/
│       ├── SiliconFlowKit/            ← UI 以外（Linux でもテスト可能）
│       │   ├── Networking/  API クライアント・SSE・再試行
│       │   ├── API/         リクエスト / レスポンスの型
│       │   ├── Errors/      失敗の分類と日本語の診断
│       │   ├── Catalog/     料金・パラメータ数の取得と統合
│       │   ├── Models/      モデルの分類・パラメータ数の推定・並べ替え
│       │   ├── Chat/        ストリーミングの集計・料金計算・Markdown
│       │   ├── Settings/    キーの検証・キーチェーン
│       │   └── Diagnostics/ 接続診断・リージョン自動判定
│       └── AppModule/                 ← SwiftUI の画面
├── Package.swift                    ← CI 用（同じ SiliconFlowKit を swift test する）
├── Tests/SiliconFlowKitTests/       ← 単体テスト
├── Tools/CatalogBuilder/            ← Web からカタログを作る CLI
├── catalog/siliconflow-catalog.json ← アプリが起動時に取得するカタログ
└── scripts/                         ← CI 用スクリプト
```

```sh
swift test                                   # 単体テスト（Linux / macOS）
LIVE_WEB_TESTS=1 swift test --filter Live    # 本物の Web サイトで解析できるか確認
SILICONFLOW_API_KEY=sk-... swift test --filter LiveAPITests   # 本物の API で確認
swift run catalog-builder --out catalog/siliconflow-catalog.json \
  --swift-out SiliconFlowLab.swiftpm/Sources/SiliconFlowKit/Catalog/BundledCatalogSnapshot.swift
python3 scripts/check_playgrounds_compat.py  # Playgrounds 互換チェック
```

---

## 注意

- このアプリは SiliconFlow の非公式クライアントです。表示される料金は公開情報をもとにした目安で、実際の請求額は SiliconFlow のコンソールで確認してください。
- モデルを試すと SiliconFlow の料金がかかります（無料モデルを除く）。特に画像・動画生成は 1 回ごとに課金されます。
