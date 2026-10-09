import Foundation

/// `GET /models` が返すモデル 1 件
public struct RemoteModel: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var object: String?
    public var created: Int?
    public var ownedBy: String?

    public init(id: String, object: String? = "model", created: Int? = nil, ownedBy: String? = nil) {
        self.id = id
        self.object = object
        self.created = created
        self.ownedBy = ownedBy
    }

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case ownedBy = "owned_by"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        object = try? container.decodeIfPresent(String.self, forKey: .object)
        created = try? container.decodeIfPresent(Int.self, forKey: .created)
        ownedBy = try? container.decodeIfPresent(String.self, forKey: .ownedBy)
    }
}

/// `GET /models` のレスポンス
public struct ModelListResponse: Decodable, Sendable {
    public var object: String?
    public var data: [RemoteModel]

    enum CodingKeys: String, CodingKey {
        case object
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try? container.decodeIfPresent(String.self, forKey: .object)
        // 1 件だけ壊れていても全体を失敗させない
        let items = try container.decode([FailableDecodable<RemoteModel>].self, forKey: .data)
        data = items.compactMap(\.value)
    }
}

/// `GET /models` のフィルタ
public enum ModelListFilter: Hashable, Sendable {
    case all
    case type(String)
    case subType(String)

    /// カテゴリ判定に使うフィルタ一覧（公式 API が受け付ける値）
    public static let classificationFilters: [ModelListFilter] = [
        .subType("chat"),
        .subType("embedding"),
        .subType("reranker"),
        .subType("text-to-image"),
        .subType("image-to-image"),
        .subType("speech-to-text"),
        .subType("text-to-video"),
        .type("audio"),
        .type("video"),
    ]

    var queryItems: [URLQueryItem] {
        switch self {
        case .all: return []
        case .type(let value): return [URLQueryItem(name: "type", value: value)]
        case .subType(let value): return [URLQueryItem(name: "sub_type", value: value)]
        }
    }
}

/// 配列の一部の要素が壊れていても残りを読めるようにするラッパー
public struct FailableDecodable<Value: Decodable>: Decodable {
    public let value: Value?

    public init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension FailableDecodable: Sendable where Value: Sendable {}
