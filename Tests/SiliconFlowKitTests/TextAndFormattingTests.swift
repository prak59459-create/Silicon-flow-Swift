import XCTest
@testable import SiliconFlowKit

final class NumberTextTests: XCTestCase {
    func testCompactRemovesTrailingZeros() {
        XCTAssertEqual(NumberText.compact(2.50), "2.5")
        XCTAssertEqual(NumberText.compact(3.0), "3")
        XCTAssertEqual(NumberText.compact(0.000_001), "0.000001")
        XCTAssertEqual(NumberText.compact(-0.0), "0")
        XCTAssertEqual(NumberText.compact(.infinity), "-")
    }

    func testFixed() {
        XCTAssertEqual(NumberText.fixed(2.5, fractionDigits: 2), "2.50")
        XCTAssertEqual(NumberText.fixed(-0.001, fractionDigits: 2), "0.00")
    }

    func testMoneyKeepsSignificantDigits() {
        XCTAssertEqual(NumberText.money(2), "2.00")
        XCTAssertEqual(NumberText.money(0.042), "0.042")
        XCTAssertEqual(NumberText.money(0.000_123_4), "0.000123")
        XCTAssertEqual(NumberText.money(150), "150")
        XCTAssertEqual(NumberText.money(0), "0")
    }

    func testGrouped() {
        XCTAssertEqual(NumberText.grouped(1_234_567), "1,234,567")
        XCTAssertEqual(NumberText.grouped(999), "999")
        XCTAssertEqual(NumberText.grouped(-1000), "-1,000")
    }
}

final class TextSanitizerTests: XCTestCase {
    func testTrimmedRemovesInvisiblesAndFullWidthSpace() {
        XCTAssertEqual(TextSanitizer.trimmed("\u{200B} sk-abc\u{3000}\n"), "sk-abc")
    }

    func testHalfWidth() {
        XCTAssertEqual(TextSanitizer.halfWidth("ｓｋ－ＡＢＣ１２３"), "sk-ABC123")
        XCTAssertEqual(TextSanitizer.halfWidth("sk‐abc"), "sk-abc")
    }

    func testHTMLDetection() {
        XCTAssertTrue(TextSanitizer.looksLikeHTML("<!DOCTYPE html><html>"))
        XCTAssertTrue(TextSanitizer.looksLikeHTML("  <HTML><body>"))
        XCTAssertFalse(TextSanitizer.looksLikeHTML("{\"a\":1}"))
    }

    func testMasked() {
        XCTAssertEqual(TextSanitizer.masked("sk-abcdefghijklmnopqrstuvwxyz"), "sk-ab••••wxyz")
        XCTAssertEqual(TextSanitizer.masked("short"), "•••••")
    }

    func testSnippetCollapsesNewlinesAndTruncates() {
        let text = String(repeating: "あ", count: 400)
        XCTAssertEqual(TextSanitizer.snippet(text, limit: 10), String(repeating: "あ", count: 10) + "…")
        XCTAssertEqual(TextSanitizer.snippet("a\nb\r\nc"), "a b  c")
    }
}

final class APIKeyValidatorTests: XCTestCase {
    func testSanitizeRemovesBearerQuotesAndWhitespace() {
        XCTAssertEqual(APIKeyValidator.sanitize("  Bearer sk-abc123  "), "sk-abc123")
        XCTAssertEqual(APIKeyValidator.sanitize("\"sk-abc123\""), "sk-abc123")
        XCTAssertEqual(APIKeyValidator.sanitize("Authorization: Bearer sk-abc"), "sk-abc")
        XCTAssertEqual(APIKeyValidator.sanitize("「sk-abc」"), "sk-abc")
        XCTAssertEqual(APIKeyValidator.sanitize("ｓｋ－ａｂｃ"), "sk-abc")
    }

    func testValidKey() {
        let result = APIKeyValidator.validate("sk-abcdefghijklmnopqrstuvwxyz0123456789")
        XCTAssertTrue(result.isUsable)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testEmptyKeyIsBlocking() {
        let result = APIKeyValidator.validate("   ")
        XCTAssertFalse(result.isUsable)
        XCTAssertEqual(result.issues, [.empty])
    }

    func testInnerWhitespaceIsBlocking() {
        let result = APIKeyValidator.validate("sk-abcdefghij klmnopqrstuvwxyz")
        XCTAssertFalse(result.isUsable)
        XCTAssertTrue(result.issues.contains(.containsWhitespace))
    }

    func testNonASCIIIsBlocking() {
        let result = APIKeyValidator.validate("sk-abcdefghijklmnopqrstuvwxyzあ")
        XCTAssertFalse(result.isUsable)
        XCTAssertTrue(result.issues.contains(.containsNonASCII))
    }

    func testWarningsDoNotBlock() {
        let result = APIKeyValidator.validate("abc123")
        XCTAssertTrue(result.isUsable)
        XCTAssertEqual(Set(result.warnings), [.unexpectedPrefix, .tooShort])
        for issue in APIKeyValidator.Issue.allCases { XCTAssertFalse(issue.message.isEmpty) }
    }
}

final class BaseURLNormalizerTests: XCTestCase {
    func testAddsSchemeAndVersionPath() throws {
        XCTAssertEqual(try BaseURLNormalizer.normalize("api.example.com").get().absoluteString, "https://api.example.com/v1")
    }

    func testRemovesTrailingSlashAndEndpointSuffix() throws {
        XCTAssertEqual(try BaseURLNormalizer.normalize("https://api.example.com/v1/").get().absoluteString, "https://api.example.com/v1")
        XCTAssertEqual(try BaseURLNormalizer.normalize("https://api.example.com/v1/chat/completions").get().absoluteString, "https://api.example.com/v1")
        XCTAssertEqual(try BaseURLNormalizer.normalize("https://proxy.example.com/siliconflow/v1?x=1").get().absoluteString, "https://proxy.example.com/siliconflow/v1")
    }

    func testRejectsInvalidAndInsecure() {
        XCTAssertEqual(BaseURLNormalizer.normalize(""), .failure(.empty))
        XCTAssertEqual(BaseURLNormalizer.normalize("http://api.example.com"), .failure(.insecure))
        XCTAssertNoThrow(try BaseURLNormalizer.normalize("http://localhost:8080").get())
        XCTAssertEqual(BaseURLNormalizer.normalize("https://"), .failure(.invalid))
    }

    func testRegionGuess() {
        XCTAssertEqual(APIRegion.guess(fromHost: "api.siliconflow.cn"), .china)
        XCTAssertEqual(APIRegion.guess(fromHost: "API.SILICONFLOW.COM"), .international)
        XCTAssertNil(APIRegion.guess(fromHost: "example.com"))
    }

    func testRegionURLs() {
        XCTAssertEqual(APIRegion.china.defaultBaseURL.absoluteString, "https://api.siliconflow.cn/v1")
        XCTAssertEqual(APIRegion.international.defaultBaseURL.absoluteString, "https://api.siliconflow.com/v1")
        XCTAssertEqual(APIRegion.china.apiKeysURL.absoluteString, "https://cloud.siliconflow.cn/account/ak")
        XCTAssertEqual(APIRegion.china.other, .international)
        XCTAssertEqual(APIRegion.international.currency, .usd)
    }
}

final class PriceFormattingTests: XCTestCase {
    func testCurrencyFormatting() {
        XCTAssertEqual(Currency.cny.format(2), "2.00元")
        XCTAssertEqual(Currency.usd.format(0.27), "$0.27")
        XCTAssertEqual(Currency.jpy.format(1234.4), "1,234円")
        XCTAssertEqual(Currency.jpy.format(41.26), "41.3円")
        XCTAssertEqual(Currency.jpy.format(0.0123), "0.0123円")
        XCTAssertEqual(Currency.from(symbol: "¥"), .cny)
        XCTAssertEqual(Currency.from(symbol: "$"), .usd)
        XCTAssertNil(Currency.from(symbol: "€"))
    }

    func testCompactPrice() {
        var entry = CatalogEntry(id: "a/b")
        XCTAssertEqual(PriceFormatter.compact(entry), "価格不明")
        entry.inputPrice = 2
        entry.outputPrice = 8
        entry.currency = .cny
        entry.unit = .perMillionTokens
        XCTAssertEqual(PriceFormatter.compact(entry), "2.00元 / 8.00元/M")
        entry.inputPrice = 0
        entry.outputPrice = 0
        XCTAssertEqual(PriceFormatter.compact(entry), "無料")
        var image = CatalogEntry(id: "x/img")
        image.outputPrice = 0.3
        image.currency = .cny
        image.unit = .perImage
        XCTAssertEqual(PriceFormatter.compact(image), "0.30元/枚")
    }

    func testDetailRowsWithYenConversion() {
        var entry = CatalogEntry(id: "a/b")
        entry.inputPrice = 1
        entry.outputPrice = 4
        entry.currency = .cny
        entry.unit = .perMillionTokens
        let rates = ExchangeRates(base: .cny, rates: ["JPY": 20], source: "test")
        let rows = PriceFormatter.detailRows(entry, rates: rates, showYen: true)
        XCTAssertEqual(rows.map(\.0), ["入力", "出力"])
        XCTAssertEqual(rows[1].1, "4.00元（100万トークンあたり） ≈ 80円")
    }

    func testPriceUnitParsing() {
        XCTAssertEqual(PriceUnit.parse("/ M Tokens"), .perMillionTokens)
        XCTAssertEqual(PriceUnit.parse("/ Image"), .perImage)
        XCTAssertEqual(PriceUnit.parse("/ Video"), .perVideo)
        XCTAssertEqual(PriceUnit.parse("/ M UTF-8 bytes"), .perMillionBytes)
        XCTAssertEqual(PriceUnit.parse(nil), .unknown)
    }

    func testContextLength() {
        XCTAssertEqual(ContextLengthFormatter.format(131_072), "128K")
        XCTAssertEqual(ContextLengthFormatter.format(200_000), "200K")
        XCTAssertEqual(ContextLengthFormatter.format(1_048_576), "1M")
        XCTAssertEqual(ContextLengthFormatter.format(512), "512")
        XCTAssertEqual(ContextLengthFormatter.format(nil), "?")
    }

    func testParameterFormatting() {
        XCTAssertEqual(ParameterCount.format(1000), "1T")
        XCTAssertEqual(ParameterCount.format(1026.88), "1.03T")
        XCTAssertEqual(ParameterCount.format(235), "235B")
        XCTAssertEqual(ParameterCount.format(8.19), "8.2B")
        XCTAssertEqual(ParameterCount.format(0.6), "0.6B")
        XCTAssertEqual(ParameterCount(totalB: 235, activeB: 22).displayText, "235B（アクティブ 22B）")
        XCTAssertEqual(ParameterCount(totalB: 235, activeB: 22).compactText, "235B/A22B")
        XCTAssertEqual(ParameterCount.fromRawCount(8_190_735_360)?.totalB, 8.19)
    }
}
