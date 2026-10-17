import Foundation

/// API キーがどちらのリージョンのものかを調べます。
///
/// 認証の確認には `GET /models`（API キー付き）を使います。
/// 以前使っていた `GET /user/info` は中国版で 2026-08-14 に停止したため使いません。
public enum RegionDetector {
    public struct Result: Sendable, Equatable {
        public var region: APIRegion
        /// 使えるモデルの数（確認に使った `GET /models` の結果）
        public var modelCount: Int?
        /// キーは受け付けられたものの、アカウントに制限がある場合の理由（実名認証が未完了・未払いなど）
        public var restriction: SiliconFlowError?

        public init(region: APIRegion, modelCount: Int? = nil, restriction: SiliconFlowError? = nil) {
            self.region = region
            self.modelCount = modelCount
            self.restriction = restriction
        }
    }

    /// 両方のリージョンで確かめ、キーが通った方を返します（優先リージョン・制限なしを先に判定）。
    public static func detect(
        apiKey: String,
        preferred: APIRegion,
        transport: HTTPTransport = SharedTransport.default
    ) async -> (Result?, [APIRegion: SiliconFlowError]) {
        let order = [preferred, preferred.other]
        let outcomes = await withTaskGroup(of: (APIRegion, Swift.Result<Result, SiliconFlowError>).self) { group in
            for region in order {
                group.addTask {
                    (region, await check(apiKey: apiKey, region: region, transport: transport))
                }
            }
            var collected: [APIRegion: Swift.Result<Result, SiliconFlowError>] = [:]
            for await (region, outcome) in group { collected[region] = outcome }
            return collected
        }
        return pick(from: outcomes, order: order)
    }

    /// 1 つのリージョンでキーを確かめます。
    public static func check(
        apiKey: String,
        region: APIRegion,
        transport: HTTPTransport = SharedTransport.default
    ) async -> Swift.Result<Result, SiliconFlowError> {
        var client = SiliconFlowClient(configuration: ClientConfiguration(region: region, apiKey: apiKey, requestTimeout: 20), transport: transport)
        client.retryPolicy = .none
        do {
            let models = try await client.listModels()
            return .success(Result(region: region, modelCount: models.count))
        } catch {
            let wrapped = SiliconFlowError.wrap(error, region: region)
            if keyWasAccepted(despite: wrapped) {
                return .success(Result(region: region, restriction: wrapped))
            }
            return .failure(wrapped)
        }
    }

    /// 認証そのものは通ったと判断できる失敗か
    ///
    /// 無効なキーは 401 になるので、SiliconFlow の JSON で返る 402 / 403（残高・実名認証・権限）は
    /// 「キーはこのリージョンのもので、アカウントに制限がある」と判断します。
    /// プロキシなどが返す HTML の 403 は判断材料にしません。
    static func keyWasAccepted(despite error: SiliconFlowError) -> Bool {
        let accountKinds: Set<FailureKind> = [.forbidden, .realNameRequired, .insufficientBalance, .modelAccessDenied]
        guard accountKinds.contains(error.kind), let status = error.httpStatus, status == 402 || status == 403 else { return false }
        return !TextSanitizer.looksLikeHTML(error.bodySnippet ?? "")
    }

    static func pick(
        from outcomes: [APIRegion: Swift.Result<Result, SiliconFlowError>],
        order: [APIRegion]
    ) -> (Result?, [APIRegion: SiliconFlowError]) {
        var errors: [APIRegion: SiliconFlowError] = [:]
        var accepted: [Result] = []
        for region in order {
            switch outcomes[region] {
            case .success(let result)?: accepted.append(result)
            case .failure(let error)?: errors[region] = error
            case nil: break
            }
        }
        let best = accepted.first { $0.restriction == nil } ?? accepted.first
        return (best, errors)
    }
}
