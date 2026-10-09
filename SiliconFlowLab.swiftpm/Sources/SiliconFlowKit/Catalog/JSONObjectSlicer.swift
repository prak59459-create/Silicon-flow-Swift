import Foundation

/// 巨大な JSON から、最上位の 1 つのキーの値だけを切り出します。
///
/// models.dev の api.json は 5MB 以上あり、全体をデコードするとメモリを大きく使います。
/// バイト列を 1 回なめるだけで目的の部分（数十 KB）を取り出し、そこだけをデコードします。
public enum JSONObjectSlicer {
    /// 最上位オブジェクトの `key` の値のバイト範囲を返します。
    public static func slice(topLevelKey key: String, in data: Data) -> Data? {
        let bytes = [UInt8](data)
        let target = Array(key.utf8)
        var index = 0
        var depth = 0
        var inString = false
        var escaped = false
        var stringStart = 0

        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C { // \
                    escaped = true
                } else if byte == 0x22 { // "
                    inString = false
                    if depth == 1, bytes[stringStart..<index].elementsEqual(target),
                       let valueStart = valueStart(after: index + 1, in: bytes),
                       let valueEnd = valueEnd(from: valueStart, in: bytes) {
                        return Data(bytes[valueStart..<valueEnd])
                    }
                }
            } else {
                switch byte {
                case 0x22:
                    inString = true
                    stringStart = index + 1
                case 0x7B, 0x5B: // { [
                    depth += 1
                case 0x7D, 0x5D: // } ]
                    depth -= 1
                default:
                    break
                }
            }
            index += 1
        }
        return nil
    }

    /// キー文字列の直後の ':' を探し、値の開始位置を返します（キーでなく値の文字列だった場合は nil）。
    private static func valueStart(after position: Int, in bytes: [UInt8]) -> Int? {
        var index = position
        while index < bytes.count, isWhitespace(bytes[index]) { index += 1 }
        guard index < bytes.count, bytes[index] == 0x3A else { return nil } // :
        index += 1
        while index < bytes.count, isWhitespace(bytes[index]) { index += 1 }
        return index < bytes.count ? index : nil
    }

    /// 値の終了位置（排他的）
    private static func valueEnd(from start: Int, in bytes: [UInt8]) -> Int? {
        let first = bytes[start]
        guard first == 0x7B || first == 0x5B else {
            // スカラー値: 文字列なら閉じ引用符まで、それ以外は , } 空白 まで
            let isString = first == 0x22
            var escaped = false
            var index = start + 1
            while index < bytes.count {
                let byte = bytes[index]
                if isString {
                    if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { return index + 1 }
                } else if byte == 0x2C || byte == 0x7D || isWhitespace(byte) {
                    return index
                }
                index += 1
            }
            return bytes.count
        }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped { escaped = false } else if byte == 0x5C { escaped = true } else if byte == 0x22 { inString = false }
            } else {
                switch byte {
                case 0x22: inString = true
                case 0x7B, 0x5B: depth += 1
                case 0x7D, 0x5D:
                    depth -= 1
                    if depth == 0 { return index + 1 }
                default: break
                }
            }
            index += 1
        }
        return nil
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
    }
}
