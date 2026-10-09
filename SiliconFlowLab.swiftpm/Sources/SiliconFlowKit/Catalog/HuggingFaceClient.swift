import Foundation

/// Hugging Face の公開 API からモデルの実際のパラメータ数などを取得します（キー不要）。
public struct HuggingFaceClient: Sendable {
    public static let sourceName = "Hugging Face"

    public struct ModelInfo: Sendable, Equatable, Codable {
        public var repoID: String
        public var totalParameters: Int64?
        public var pipelineTag: String?
        public var license: String?
        public var downloads: Int?
        public var likes: Int?

        public var parameters: ParameterCount? {
            totalParameters.flatMap(ParameterCount.fromRawCount)
        }

        public var pageURL: URL? { URL(string: "https://huggingface.co/\(repoID)") }
    }

    let fetcher: WebFetcher

    public init(fetcher: WebFetcher = WebFetcher(retryPolicy: .none, timeout: 15)) {
        self.fetcher = fetcher
    }

    /// SiliconFlow のモデル ID から Hugging Face のリポジトリ名の候補を作ります。
    /// 例: "Pro/deepseek-ai/DeepSeek-V3" → ["deepseek-ai/DeepSeek-V3"]
    public static func candidateRepoIDs(for modelID: String) -> [String] {
        let stripped = ModelClassifier.strippedPrefixes(modelID)
        let parts = stripped.split(separator: "/")
        guard parts.count == 2 else { return [] }
        var candidates = [stripped]
        // "-128K" のような SiliconFlow 独自の接尾辞を外した版も試す
        for suffix in ["-128K", "-Turbo"] where stripped.hasSuffix(suffix) {
            candidates.append(String(stripped.dropLast(suffix.count)))
        }
        return candidates
    }

    public static func apiURL(for repoID: String) -> URL? {
        let encoded = repoID.split(separator: "/").map { component in
            String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
        }.joined(separator: "/")
        let fields = ["safetensors", "pipeline_tag", "cardData", "downloads", "likes"]
            .map { "expand%5B%5D=\($0)" }
            .joined(separator: "&")
        return URL(string: "https://huggingface.co/api/models/\(encoded)?\(fields)")
    }

    /// 見つからなければ nil（エラーにはしません）
    public func fetch(modelID: String) async -> ModelInfo? {
        for repoID in Self.candidateRepoIDs(for: modelID) {
            guard let url = Self.apiURL(for: repoID) else { continue }
            do {
                let data = try await fetcher.get(url, accept: "application/json")
                if let info = Self.parse(data) { return info }
            } catch {
                if (error as? SiliconFlowError)?.kind == .cancelled { return nil }
                continue
            }
        }
        return nil
    }

    public static func parse(_ data: Data) -> ModelInfo? {
        guard let json = JSONValue.parse(data), let repoID = json["id"]?.stringValue else { return nil }
        var total: Int64?
        if let value = json["safetensors"]?["total"]?.doubleValue, value > 0 {
            total = Int64(value)
        } else if let parameters = json["safetensors"]?["parameters"]?.objectValue {
            let sum = parameters.values.compactMap(\.doubleValue).reduce(0, +)
            if sum > 0 { total = Int64(sum) }
        }
        return ModelInfo(
            repoID: repoID,
            totalParameters: total,
            pipelineTag: json["pipeline_tag"]?.stringValue,
            license: json["cardData"]?["license"]?.stringValue,
            downloads: json["downloads"]?.intValue,
            likes: json["likes"]?.intValue
        )
    }
}
