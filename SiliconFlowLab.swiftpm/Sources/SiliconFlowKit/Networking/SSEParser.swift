import Foundation

/// Server-Sent Events の 1 イベント
public struct SSEEvent: Equatable, Sendable {
    public var event: String?
    public var data: String

    public init(event: String? = nil, data: String) {
        self.event = event
        self.data = data
    }

    /// OpenAI 互換 API のストリーム終端
    public var isDone: Bool { data.trimmingCharacters(in: .whitespaces) == "[DONE]" }
}

/// SSE の行パーサー。
///
/// OpenAI 互換 API は 1 つの `data:` 行に 1 つの JSON を入れて送ってくるため、
/// 空行を待たずに `data:` 行ごとにイベントとして返します（空行が省かれる
/// プロキシ経由でも壊れないようにするため）。
/// `data:` で始まらない行（エラー JSON をそのまま返すサーバー等）は `rawLines` に溜めます。
public struct SSEParser: Sendable {
    private var pendingEventName: String?
    public private(set) var rawLines: [String] = []
    public private(set) var eventCount = 0

    public init() {}

    public mutating func consume(line: String) -> SSEEvent? {
        if line.isEmpty {
            pendingEventName = nil
            return nil
        }
        if line.hasPrefix(":") { return nil } // コメント / keep-alive
        guard let colon = line.firstIndex(of: ":") else {
            appendRaw(line)
            return nil
        }
        let field = String(line[..<colon])
        var value = String(line[line.index(after: colon)...])
        if value.hasPrefix(" ") { value.removeFirst() }

        switch field {
        case "data":
            eventCount += 1
            let event = SSEEvent(event: pendingEventName, data: value)
            pendingEventName = nil
            return event
        case "event":
            pendingEventName = value
            return nil
        case "id", "retry":
            return nil
        default:
            // "{"code":...}" のような JSON 行は ':' を含むので field 判定に来る
            appendRaw(line)
            return nil
        }
    }

    /// `data:` 以外の行の連結（ストリームではなく通常の JSON が返ってきた場合に使います）
    public var rawBody: String { rawLines.joined(separator: "\n") }

    private mutating func appendRaw(_ line: String) {
        // 巨大な HTML などでメモリを使いすぎないよう上限を設けます
        if rawLines.count < 400 { rawLines.append(line) }
    }
}
