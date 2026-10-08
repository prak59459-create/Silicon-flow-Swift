import Foundation

/// `POST /embeddings` のリクエスト
public struct EmbeddingRequest: Encodable, Sendable, Hashable {
    public var model: String
    public var input: [String]
    public var encodingFormat: String?

    public init(model: String, input: [String], encodingFormat: String? = "float") {
        self.model = model
        self.input = input
        self.encodingFormat = encodingFormat
    }

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case encodingFormat = "encoding_format"
    }
}

/// `POST /embeddings` のレスポンス
public struct EmbeddingResponse: Decodable, Sendable, Hashable {
    public struct Item: Decodable, Sendable, Hashable {
        public var index: Int?
        public var embedding: [Double]
    }

    public var model: String?
    public var data: [Item]
    public var usage: Usage?

    /// index 順に並べたベクトル
    public var vectors: [[Double]] {
        data.enumerated()
            .sorted { ($0.element.index ?? $0.offset) < ($1.element.index ?? $1.offset) }
            .map(\.element.embedding)
    }
}

/// ベクトル計算
public enum VectorMath {
    public static func norm(_ vector: [Double]) -> Double {
        vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
    }

    /// コサイン類似度（-1〜1）。次元が違う・ゼロベクトルなら nil。
    public static func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        var dot = 0.0
        for index in lhs.indices { dot += lhs[index] * rhs[index] }
        let denominator = norm(lhs) * norm(rhs)
        guard denominator > 0 else { return nil }
        return max(-1, min(1, dot / denominator))
    }
}

/// `POST /rerank` のリクエスト
public struct RerankRequest: Encodable, Sendable, Hashable {
    public var model: String
    public var query: String
    public var documents: [String]
    public var topN: Int?
    public var returnDocuments: Bool

    public init(model: String, query: String, documents: [String], topN: Int? = nil, returnDocuments: Bool = true) {
        self.model = model
        self.query = query
        self.documents = documents
        self.topN = topN
        self.returnDocuments = returnDocuments
    }

    enum CodingKeys: String, CodingKey {
        case model
        case query
        case documents
        case topN = "top_n"
        case returnDocuments = "return_documents"
    }
}

/// `POST /rerank` のレスポンス
public struct RerankResponse: Decodable, Sendable, Hashable {
    public struct Result: Decodable, Sendable, Hashable {
        public struct Document: Decodable, Sendable, Hashable {
            public var text: String?
        }

        public var index: Int
        public var relevanceScore: Double
        public var document: Document?

        enum CodingKeys: String, CodingKey {
            case index
            case relevanceScore = "relevance_score"
            case document
        }
    }

    public struct Tokens: Decodable, Sendable, Hashable {
        public var inputTokens: Int?
        public var outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    public var id: String?
    public var results: [Result]
    public var tokens: Tokens?

    /// スコアの高い順
    public var ranked: [Result] { results.sorted { $0.relevanceScore > $1.relevanceScore } }
}
