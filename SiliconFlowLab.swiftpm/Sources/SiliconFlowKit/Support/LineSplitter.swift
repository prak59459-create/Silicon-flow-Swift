import Foundation

/// バイト列を行に分割します（LF / CRLF 両対応、空行も保持）。
///
/// 行が完成してから UTF-8 として解釈するので、
/// マルチバイト文字がチャンクの境目で分かれても文字化けしません。
public struct LineSplitter: Sendable {
    private var buffer: [UInt8] = []

    public init() {
        buffer.reserveCapacity(1024)
    }

    /// 1 バイト追加します。行が完成したらその行を返します。
    public mutating func append(_ byte: UInt8) -> String? {
        if byte == 0x0A {
            return takeLine()
        }
        buffer.append(byte)
        return nil
    }

    /// 複数バイトを追加し、完成した行をすべて返します。
    public mutating func append<S: Sequence>(contentsOf bytes: S) -> [String] where S.Element == UInt8 {
        var lines: [String] = []
        for byte in bytes {
            if let line = append(byte) { lines.append(line) }
        }
        return lines
    }

    /// 末尾に改行が無い最後の行を取り出します。
    public mutating func finish() -> String? {
        guard !buffer.isEmpty else { return nil }
        return takeLine()
    }

    private mutating func takeLine() -> String {
        if buffer.last == 0x0D { buffer.removeLast() }
        let line = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: true)
        return line
    }

    /// データ全体を行に分割します。
    public static func lines(in data: Data) -> [String] {
        var splitter = LineSplitter()
        var lines = splitter.append(contentsOf: data)
        if let last = splitter.finish() { lines.append(last) }
        return lines
    }
}
