import Foundation
import SiliconFlowKit

/// 接続診断の実行状態
@MainActor
final class DiagnosticsStore: ObservableObject {
    @Published private(set) var outcomes: [DiagnosticStep: DiagnosticOutcome] = [:]
    @Published private(set) var runningStep: DiagnosticStep?
    @Published private(set) var isRunning = false
    /// キーが別リージョンのものだった場合の検出結果
    @Published private(set) var otherRegionMatch: RegionDetector.Result?
    @Published private(set) var finishedAt: Date?

    private var task: Task<Void, Never>?

    var failedCount: Int { outcomes.values.filter(\.isFailure).count }

    func run(settings: AppSettings, models: [ModelDescriptor]) {
        task?.cancel()
        outcomes = [:]
        otherRegionMatch = nil
        finishedAt = nil
        isRunning = true
        let client = settings.makeClient()
        let testModel = ConnectionDiagnostics.preferredTestModel(from: models)
        let otherRegion = settings.region.other
        let currentKey = settings.currentAPIKey ?? ""
        task = Task { [weak self] in
            await self?.execute(client: client, testModel: testModel, currentKey: currentKey, otherRegion: otherRegion)
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func execute(client: SiliconFlowClient, testModel: String?, currentKey: String, otherRegion: APIRegion) async {
        let diagnostics = ConnectionDiagnostics(client: client)
        var blocked = false
        for step in DiagnosticStep.allCases {
            if Task.isCancelled { break }
            if blocked {
                outcomes[step] = .skipped("前の項目が失敗したため実行しませんでした")
                continue
            }
            runningStep = step
            let outcome = await diagnostics.run(step, testModel: testModel)
            outcomes[step] = outcome
            if case .failed(let error) = outcome {
                // キー・接続に問題があると以降は確実に失敗するので止める
                blocked = step != .testChat && step != .modelList
                if error.kind == .invalidAPIKey {
                    await detectOtherRegion(key: currentKey, region: otherRegion)
                }
            }
        }
        runningStep = nil
        isRunning = false
        finishedAt = Date()
    }

    /// 401 のとき、同じキーがもう一方のリージョンで使えるか確かめます。
    private func detectOtherRegion(key: String, region: APIRegion) async {
        guard !key.isEmpty else { return }
        var client = SiliconFlowClient(configuration: ClientConfiguration(region: region, apiKey: key, requestTimeout: 20))
        client.retryPolicy = .none
        if let info = try? await client.userInfo() {
            otherRegionMatch = RegionDetector.Result(region: region, userInfo: info)
        }
    }
}
