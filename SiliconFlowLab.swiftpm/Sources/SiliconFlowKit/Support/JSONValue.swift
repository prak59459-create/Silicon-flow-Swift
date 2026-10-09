import Foundation

/// 形が分からない JSON を安全に読むための小さな動的 JSON 型。
///
/// エラー応答・公式サイトの埋め込みデータなど、仕様が変わりやすい部分の
/// パースにだけ使います（大きなデータは Codable 構造体で直接デコードします）。
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// バイト列を JSON として読みます。失敗したら nil。
    public static func parse(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func parse(_ text: String) -> JSONValue? {
        parse(Data(text.utf8))
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let object) = self { return object }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let array) = self { return array }
        return nil
    }

    /// 文字列。数値・真偽値も文字列化して返します。
    public var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return NumberText.compact(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    /// 数値。"6.5" のような数値文字列も受け付けます。
    public var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value.trimmingCharacters(in: .whitespaces))
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    public var intValue: Int? {
        guard let value = doubleValue, value.isFinite else { return nil }
        guard value >= Double(Int.min), value <= Double(Int.max) else { return nil }
        return Int(value)
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        case .string(let value):
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default: return nil
        }
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}
