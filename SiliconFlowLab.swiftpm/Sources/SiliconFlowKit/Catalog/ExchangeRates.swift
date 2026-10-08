import Foundation

/// 為替レート（円換算の表示用）
public struct ExchangeRates: Codable, Sendable, Equatable {
    public var base: Currency
    /// 1 base あたりの各通貨の額（キーは "JPY" など）
    public var rates: [String: Double]
    public var fetchedAt: Date
    public var source: String

    public init(base: Currency, rates: [String: Double], fetchedAt: Date = Date(), source: String) {
        self.base = base
        self.rates = rates
        self.fetchedAt = fetchedAt
        self.source = source
    }

    /// from → to のレート。base を経由した換算にも対応します。
    public func rate(from: Currency, to: Currency) -> Double? {
        if from == to { return 1 }
        let fromRate = from == base ? 1 : rates[from.rawValue]
        let toRate = to == base ? 1 : rates[to.rawValue]
        guard let fromRate, let toRate, fromRate > 0 else { return nil }
        return toRate / fromRate
    }

    public func isFresh(now: Date = Date(), maxAge: TimeInterval = 12 * 3600) -> Bool {
        now.timeIntervalSince(fetchedAt) < maxAge
    }

    /// open.er-api.com 形式 `{"result":"success","base_code":"CNY","rates":{...}}`
    /// と frankfurter 形式 `{"base":"CNY","rates":{...}}` の両方を読みます。
    public static func parse(_ data: Data, expectedBase: Currency, source: String, now: Date = Date()) -> ExchangeRates? {
        guard let json = JSONValue.parse(data), let object = json.objectValue else { return nil }
        if let result = object["result"]?.stringValue, result != "success" { return nil }
        let baseCode = object["base_code"]?.stringValue ?? object["base"]?.stringValue ?? expectedBase.rawValue
        guard baseCode.uppercased() == expectedBase.rawValue, let rateObject = object["rates"]?.objectValue else { return nil }
        var rates: [String: Double] = [:]
        for (code, value) in rateObject {
            if let rate = value.doubleValue, rate > 0 { rates[code.uppercased()] = rate }
        }
        guard !rates.isEmpty else { return nil }
        return ExchangeRates(base: expectedBase, rates: rates, fetchedAt: now, source: source)
    }
}

/// 為替レートの取得（無料・キー不要の公開 API を 2 つ試します）
public struct ExchangeRateClient: Sendable {
    let fetcher: WebFetcher

    public init(fetcher: WebFetcher = WebFetcher()) {
        self.fetcher = fetcher
    }

    public func fetch(base: Currency) async throws -> ExchangeRates {
        let candidates: [(String, String)] = [
            ("https://open.er-api.com/v6/latest/\(base.rawValue)", "ExchangeRate-API"),
            ("https://api.frankfurter.dev/v1/latest?base=\(base.rawValue)&symbols=JPY,USD,CNY", "Frankfurter (ECB)"),
        ]
        var lastError: Error = SiliconFlowError(kind: .unknown, endpoint: "為替レート")
        for (urlText, source) in candidates {
            guard let url = URL(string: urlText) else { continue }
            do {
                let data = try await fetcher.get(url)
                if let rates = ExchangeRates.parse(data, expectedBase: base, source: source) { return rates }
                lastError = SiliconFlowError(kind: .decodingFailed, endpoint: "GET \(url.host ?? urlText)")
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}
