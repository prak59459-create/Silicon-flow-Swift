import Foundation
import SiliconFlowKit

/// 1 回の API 呼び出しの実行状態（実行中・結果・エラー・所要時間）
@MainActor
final class RequestRunner<Output>: ObservableObject {
    @Published private(set) var output: Output?
    @Published private(set) var isRunning = false
    @Published private(set) var error: SiliconFlowError?
    @Published private(set) var elapsed: TimeInterval?

    private var task: Task<Void, Never>?

    func run(region: APIRegion, modelID: String, _ operation: @escaping () async throws -> Output) {
        task?.cancel()
        isRunning = true
        error = nil
        let start = ProcessInfo.processInfo.systemUptime
        task = Task { [weak self] in
            do {
                let value = try await operation()
                guard let self, !Task.isCancelled else { return }
                self.output = value
                self.elapsed = ProcessInfo.processInfo.systemUptime - start
            } catch {
                let wrapped = SiliconFlowError.wrap(error, region: region, modelID: modelID)
                if !wrapped.isCancellation { self?.error = wrapped }
            }
            self?.isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
        isRunning = false
    }

    func dismissError() {
        error = nil
    }
}
