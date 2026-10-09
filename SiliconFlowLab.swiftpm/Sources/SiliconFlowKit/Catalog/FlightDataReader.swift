import Foundation

/// Next.js（React Server Components）のページに埋め込まれたデータを読み取ります。
///
/// ページの `<script>self.__next_f.push([1,"..."])</script>` に分割されて入っている
/// 文字列を連結すると、`<16進ID>:<JSON>` の行が並んだデータになります。
/// 値の中の `"$1a"` は ID 0x1a の行を参照しています。
public struct FlightDataReader {
    private let payload: [UInt8]
    /// 行 ID → payload 内の範囲
    private var rowRanges: [String: Range<Int>] = [:]

    public init(html: Data) {
        payload = Self.extractPayload(from: html)
        rowRanges = Self.indexRows(payload)
    }

    public var rowCount: Int { rowRanges.count }

    /// 行の生の文字列
    public func rawRow(_ id: String) -> String? {
        guard let range = rowRanges[id] else { return nil }
        return String(decoding: payload[range], as: UTF8.self)
    }

    /// 行を JSON として読みます。
    public func row(_ id: String) -> JSONValue? {
        guard let range = rowRanges[id], let first = payload[range].first, first == UInt8(ascii: "{") || first == UInt8(ascii: "[") || first == UInt8(ascii: "\"") else {
            return nil
        }
        return JSONValue.parse(Data(payload[range]))
    }

    /// 指定した文字列を含む行の ID（payload 内の出現順）
    public func rowIDs(containing needle: String) -> [String] {
        let pattern = Array(needle.utf8)
        return rowRanges
            .filter { Self.contains(payload, range: $0.value, pattern: pattern) }
            .sorted { $0.value.lowerBound < $1.value.lowerBound }
            .map(\.key)
    }

    /// `"$1a"` 形式の参照なら参照先の値を返します。
    public func resolve(_ value: JSONValue?) -> JSONValue? {
        guard let value else { return nil }
        guard case .string(let text) = value, text.hasPrefix("$"), text.count >= 2 else { return value }
        let id = String(text.dropFirst())
        guard id.allSatisfy({ $0.isHexDigit }) else { return value }
        return row(id) ?? value
    }

    // MARK: - 解析

    static let marker = Array("self.__next_f.push([1,\"".utf8)

    /// HTML から push された文字列リテラルを取り出し、デコードして連結します。
    static func extractPayload(from html: Data) -> [UInt8] {
        let bytes = [UInt8](html)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count / 2)
        var index = 0
        while let start = find(marker, in: bytes, from: index) {
            let literalStart = start + marker.count
            var cursor = literalStart
            var escaped = false
            while cursor < bytes.count {
                let byte = bytes[cursor]
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    break
                }
                cursor += 1
            }
            guard cursor < bytes.count else { break }
            var literal: [UInt8] = [UInt8(ascii: "\"")]
            literal.append(contentsOf: bytes[literalStart..<cursor])
            literal.append(UInt8(ascii: "\""))
            if let decoded = (try? JSONSerialization.jsonObject(with: Data(literal), options: [.fragmentsAllowed])) as? String {
                output.append(contentsOf: decoded.utf8)
            }
            index = cursor + 1
        }
        return output
    }

    /// `ID:値\n` の行を索引化します。`ID:T<長さ>,<本文>` 形式のテキスト行は長さ分読み飛ばします。
    static func indexRows(_ bytes: [UInt8]) -> [String: Range<Int>] {
        var rows: [String: Range<Int>] = [:]
        var position = 0
        let colon = UInt8(ascii: ":")
        let newline = UInt8(ascii: "\n")
        while position < bytes.count {
            var cursor = position
            while cursor < bytes.count, isHex(bytes[cursor]) { cursor += 1 }
            guard cursor > position, cursor < bytes.count, bytes[cursor] == colon else {
                // 行頭が ID でなければ次の改行まで飛ばす
                position = (bytes[position...].firstIndex(of: newline) ?? bytes.count) + 1
                continue
            }
            let id = String(decoding: bytes[position..<cursor], as: UTF8.self)
            let valueStart = cursor + 1
            if valueStart < bytes.count, bytes[valueStart] == UInt8(ascii: "T"), let textRange = textRowRange(bytes, from: valueStart + 1) {
                rows[id] = textRange
                position = textRange.upperBound
                if position < bytes.count, bytes[position] == newline { position += 1 }
                continue
            }
            let end = bytes[valueStart...].firstIndex(of: newline) ?? bytes.count
            rows[id] = valueStart..<end
            position = end + 1
        }
        return rows
    }

    /// "T<16進の長さ>,本文" の本文範囲
    private static func textRowRange(_ bytes: [UInt8], from start: Int) -> Range<Int>? {
        var cursor = start
        while cursor < bytes.count, isHex(bytes[cursor]) { cursor += 1 }
        guard cursor > start, cursor < bytes.count, bytes[cursor] == UInt8(ascii: ",") else { return nil }
        guard let length = Int(String(decoding: bytes[start..<cursor], as: UTF8.self), radix: 16) else { return nil }
        let bodyStart = cursor + 1
        let bodyEnd = min(bytes.count, bodyStart + length)
        return bodyStart..<bodyEnd
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x61 && byte <= 0x66) || (byte >= 0x41 && byte <= 0x46)
    }

    static func find(_ pattern: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard !pattern.isEmpty, bytes.count >= pattern.count else { return nil }
        let first = pattern[0]
        var index = start
        let last = bytes.count - pattern.count
        while index <= last {
            if bytes[index] == first {
                var matched = true
                for offset in 1..<pattern.count where bytes[index + offset] != pattern[offset] {
                    matched = false
                    break
                }
                if matched { return index }
            }
            index += 1
        }
        return nil
    }

    private static func contains(_ bytes: [UInt8], range: Range<Int>, pattern: [UInt8]) -> Bool {
        guard range.count >= pattern.count, let first = pattern.first else { return false }
        var index = range.lowerBound
        let last = range.upperBound - pattern.count
        while index <= last {
            if bytes[index] == first {
                var matched = true
                for offset in 1..<pattern.count where bytes[index + offset] != pattern[offset] {
                    matched = false
                    break
                }
                if matched { return true }
            }
            index += 1
        }
        return false
    }
}
