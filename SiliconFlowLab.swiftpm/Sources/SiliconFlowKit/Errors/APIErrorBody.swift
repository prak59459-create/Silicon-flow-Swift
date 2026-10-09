import Foundation

/// エラー応答の本文から取り出した情報。
///
/// SiliconFlow は状況によって次のような異なる形式で返すため、すべて受け付けます。
/// - `{"code":30014,"message":"Token is invalid.","data":null}`
/// - `"Invalid token"`（JSON 文字列）
/// - `404 page not found`（プレーンテキスト）
/// - `{"error":{"message":"...","type":"...","code":"..."}}`（OpenAI 形式）
/// - HTML（プロキシ・キャプティブポータル・誤った URL）
public struct APIErrorBody: Equatable, Sendable {
    public var code: Int?
    public var codeText: String?
    public var message: String?
    public var type: String?
    public var isHTML: Bool
    public var rawSnippet: String?

    public init(code: Int? = nil, codeText: String? = nil, message: String? = nil, type: String? = nil, isHTML: Bool = false, rawSnippet: String? = nil) {
        self.code = code
        self.codeText = codeText
        self.message = message
        self.type = type
        self.isHTML = isHTML
        self.rawSnippet = rawSnippet
    }

    public static func parse(_ data: Data) -> APIErrorBody {
        let text = String(decoding: data.prefix(64 * 1024), as: UTF8.self)
        return parse(text: text)
    }

    public static func parse(text rawText: String) -> APIErrorBody {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return APIErrorBody() }
        let snippet = TextSanitizer.snippet(text)

        if TextSanitizer.looksLikeHTML(text) {
            return APIErrorBody(message: htmlTitle(in: text), isHTML: true, rawSnippet: snippet)
        }

        if let json = JSONValue.parse(text) {
            if let message = json.stringValue, json.objectValue == nil {
                return APIErrorBody(message: message, rawSnippet: snippet)
            }
            if let body = fromObject(json) {
                var result = body
                result.rawSnippet = snippet
                return result
            }
        }
        return APIErrorBody(message: snippet, rawSnippet: snippet)
    }

    /// JSON オブジェクトがエラー形式なら取り出します（成功応答なら nil）。
    public static func fromObject(_ json: JSONValue) -> APIErrorBody? {
        guard let object = json.objectValue else { return nil }
        if let error = object["error"] {
            if let nested = error.objectValue {
                let codeValue = nested["code"]
                return APIErrorBody(
                    code: codeValue?.intValue,
                    codeText: codeValue?.stringValue,
                    message: nested["message"]?.stringValue,
                    type: nested["type"]?.stringValue
                )
            }
            if let message = error.stringValue {
                return APIErrorBody(message: message)
            }
        }
        let message = object["message"]?.stringValue ?? object["msg"]?.stringValue ?? object["detail"]?.stringValue
        let codeValue = object["code"]
        if message == nil, codeValue == nil { return nil }
        // {"code":20000,"message":"OK"} は成功
        if let code = codeValue?.intValue, code == 20000 || code == 0 { return nil }
        return APIErrorBody(code: codeValue?.intValue, codeText: codeValue?.stringValue, message: message)
    }

    private static func htmlTitle(in html: String) -> String? {
        guard let start = html.range(of: "<title>", options: .caseInsensitive),
              let end = html.range(of: "</title>", options: .caseInsensitive, range: start.upperBound..<html.endIndex)
        else { return nil }
        let title = html[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : TextSanitizer.snippet(title, limit: 120)
    }
}
