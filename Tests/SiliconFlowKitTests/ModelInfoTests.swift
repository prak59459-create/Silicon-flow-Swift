import XCTest
@testable import SiliconFlowKit

final class ParameterCountParserTests: XCTestCase {
    private func parse(_ id: String) -> ParameterCount? { ParameterCountParser.parse(modelID: id) }

    func testDenseModels() {
        XCTAssertEqual(parse("Qwen/Qwen2.5-7B-Instruct"), ParameterCount(totalB: 7))
        XCTAssertEqual(parse("Qwen/Qwen3-0.6B"), ParameterCount(totalB: 0.6))
        XCTAssertEqual(parse("THUDM/glm-4-9b-chat"), ParameterCount(totalB: 9))
        XCTAssertEqual(parse("deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B"), ParameterCount(totalB: 1.5))
        XCTAssertEqual(parse("openai/gpt-oss-120b"), ParameterCount(totalB: 120))
        XCTAssertEqual(parse("Pro/Qwen/Qwen2.5-VL-7B-Instruct"), ParameterCount(totalB: 7))
        XCTAssertEqual(parse("FunAudioLLM/CosyVoice2-0.5B"), ParameterCount(totalB: 0.5))
    }

    func testMoEModels() {
        XCTAssertEqual(parse("Qwen/Qwen3-235B-A22B"), ParameterCount(totalB: 235, activeB: 22))
        XCTAssertEqual(parse("Qwen/Qwen3-30B-A3B-Instruct-2507"), ParameterCount(totalB: 30, activeB: 3))
        XCTAssertEqual(parse("baidu/ERNIE-4.5-300B-A47B"), ParameterCount(totalB: 300, activeB: 47))
        XCTAssertEqual(parse("tencent/Hunyuan-A13B-Instruct"), ParameterCount(activeB: 13))
        XCTAssertEqual(parse("mistralai/Mixtral-8x7B-Instruct"), ParameterCount(totalB: 56))
        XCTAssertEqual(parse("google/gemma-4-26B-A4B-it"), ParameterCount(totalB: 26, activeB: 4))
    }

    func testNoFalsePositives() {
        for id in ["deepseek-ai/DeepSeek-V3", "moonshotai/Kimi-K2-Instruct", "BAAI/bge-m3", "inclusionAI/Ling-mini-2.0", "MiniMaxAI/MiniMax-M2.5", "Qwen/Qwen2.5-Instruct-128K", "deepseek-ai/DeepSeek-R1", "stepfun-ai/Step-3.5-Flash", "zai-org/GLM-4.5-Air"] {
            XCTAssertNil(parse(id), id)
        }
        XCTAssertEqual(parse("Qwen/Qwen2.5-72B-Instruct-128K"), ParameterCount(totalB: 72))
    }

    func testDescriptions() {
        XCTAssertEqual(ParameterCountParser.parse(description: "Open agentic MoE model (397B total, 17B active) for coding"), ParameterCount(totalB: 397, activeB: 17))
        XCTAssertEqual(ParameterCountParser.parse(description: "模型采用 MoE 架构，总参数量 1T，激活参数 32B，支持 256K"), ParameterCount(totalB: 1000, activeB: 32))
        XCTAssertEqual(ParameterCountParser.parse(description: "A 7B parameters model"), ParameterCount(totalB: 7))
        XCTAssertNil(ParameterCountParser.parse(description: "supports 128K context"))
        XCTAssertNil(ParameterCountParser.parse(description: nil))
    }

    func testKnownFacts() {
        XCTAssertEqual(KnownModelFacts.parameters(for: "Pro/deepseek-ai/DeepSeek-V3.2"), ParameterCount(totalB: 671, activeB: 37))
        XCTAssertEqual(KnownModelFacts.parameters(for: "moonshotai/Kimi-K2-Instruct-0905"), ParameterCount(totalB: 1000, activeB: 32))
        XCTAssertEqual(KnownModelFacts.parameters(for: "zai-org/GLM-4.5-Air"), ParameterCount(totalB: 106, activeB: 12))
        XCTAssertNil(KnownModelFacts.parameters(for: "deepseek-ai/DeepSeek-R1-Distill-Qwen-7B"), "蒸留版は本体と別物")
        XCTAssertNil(KnownModelFacts.parameters(for: "unknown/model"))
    }

    func testFilling() {
        let partial = ParameterCount(activeB: 13)
        XCTAssertEqual(partial.filling(from: ParameterCount(totalB: 80, activeB: 99)), ParameterCount(totalB: 80, activeB: 13))
        XCTAssertTrue(ParameterCount().isEmpty)
    }
}

final class ModelClassifierTests: XCTestCase {
    func testHeuristicCategories() {
        let cases: [(String, ModelCategory)] = [
            ("Qwen/Qwen3-8B", .chat),
            ("deepseek-ai/DeepSeek-V3.2", .chat),
            ("Qwen/Qwen2.5-VL-72B-Instruct", .vision),
            ("zai-org/GLM-4.5V", .vision),
            ("deepseek-ai/DeepSeek-OCR", .vision),
            ("Qwen/Qwen3-Omni-30B-A3B-Instruct", .vision),
            ("BAAI/bge-m3", .embedding),
            ("Qwen/Qwen3-Embedding-8B", .embedding),
            ("Qwen/Qwen3-VL-Embedding-8B", .embedding),
            ("BAAI/bge-reranker-v2-m3", .reranker),
            ("Qwen/Qwen3-VL-Reranker-8B", .reranker),
            ("black-forest-labs/FLUX.1-schnell", .textToImage),
            ("Kwai-Kolors/Kolors", .textToImage),
            ("Qwen/Qwen-Image", .textToImage),
            ("Qwen/Qwen-Image-Edit-2509", .imageToImage),
            ("FunAudioLLM/CosyVoice2-0.5B", .textToSpeech),
            ("fishaudio/fish-speech-1.5", .textToSpeech),
            ("FunAudioLLM/SenseVoiceSmall", .speechToText),
            ("Qwen/Qwen3-ASR-1.7B", .speechToText),
            ("Wan-AI/Wan2.2-T2V-A14B", .textToVideo),
            ("Wan-AI/Wan2.2-I2V-A14B", .imageToVideo),
        ]
        for (id, expected) in cases {
            XCTAssertEqual(ModelClassifier.heuristicCategory(for: id), expected, id)
        }
    }

    func testNameHelpers() {
        XCTAssertEqual(ModelClassifier.organization(of: "Pro/deepseek-ai/DeepSeek-V3"), "deepseek-ai")
        XCTAssertEqual(ModelClassifier.organization(of: "Qwen/Qwen3-8B"), "Qwen")
        XCTAssertNil(ModelClassifier.organization(of: "solo"))
        XCTAssertEqual(ModelClassifier.shortName(of: "Pro/deepseek-ai/DeepSeek-V3"), "DeepSeek-V3")
        XCTAssertEqual(ModelClassifier.strippedPrefixes("Pro/deepseek-ai/DeepSeek-V3"), "deepseek-ai/DeepSeek-V3")
        XCTAssertTrue(ModelClassifier.isProVariant("Pro/Qwen/Qwen2.5-7B-Instruct"))
        XCTAssertFalse(ModelClassifier.isProVariant("Qwen/Qwen2.5-7B-Instruct"))
    }

    func testCategoryMetadata() {
        for category in ModelCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty)
            XCTAssertFalse(category.systemImage.isEmpty)
            if let subType = category.apiSubType, category != .vision {
                XCTAssertEqual(ModelCategory(apiSubType: subType), category)
            }
        }
        XCTAssertNil(ModelCategory(apiSubType: "unknown"))
        XCTAssertTrue(ModelCategory.chat < ModelCategory.embedding)
        XCTAssertTrue(ModelCategory.vision.isChatLike)
        XCTAssertFalse(ModelCategory.reranker.isChatLike)
        for capability in ModelCapability.allCases {
            XCTAssertFalse(capability.displayName.isEmpty)
        }
    }
}

final class ModelDescriptorTests: XCTestCase {
    private func entry(_ id: String, input: Double? = nil, output: Double? = nil, category: ModelCategory? = nil, params: Double? = nil, context: Int? = nil, release: String? = nil) -> CatalogEntry {
        var entry = CatalogEntry(id: id)
        entry.inputPrice = input
        entry.outputPrice = output
        entry.currency = .cny
        entry.unit = .perMillionTokens
        entry.category = category
        entry.totalParamsB = params
        entry.paramsSource = params == nil ? nil : "公式"
        entry.contextLength = context
        entry.releaseDate = release
        return entry
    }

    func testBuildUsesAPICategoryAndCatalog() {
        let catalog = CatalogIndex(entries: [
            entry("Qwen/Qwen3-8B", input: 0, output: 0, category: .chat, params: 8, context: 131_072),
            {
                var vision = entry("zai-org/GLM-4.5V", input: 1, output: 6, category: .vision)
                vision.capabilities = [.vision]
                return vision
            }(),
        ])
        let remote = [RemoteModel(id: "Qwen/Qwen3-8B"), RemoteModel(id: "zai-org/GLM-4.5V"), RemoteModel(id: "BAAI/bge-m3"), RemoteModel(id: "Qwen/Qwen3-8B")]
        let models = ModelDescriptorBuilder.build(
            remote: remote,
            apiCategories: ["Qwen/Qwen3-8B": .chat, "zai-org/GLM-4.5V": .chat],
            catalog: catalog,
            hfParameters: ["BAAI/bge-m3": ParameterCount(totalB: 0.57)]
        )
        XCTAssertEqual(models.map(\.id), ["Qwen/Qwen3-8B", "zai-org/GLM-4.5V", "BAAI/bge-m3"], "重複は除く")
        XCTAssertEqual(models[0].category, .chat)
        XCTAssertTrue(models[0].isFree)
        XCTAssertEqual(models[0].priceText, "無料")
        XCTAssertEqual(models[0].contextText, "128K")
        XCTAssertEqual(models[0].parametersSource, "公式")
        XCTAssertEqual(models[1].category, .vision, "API が chat でもカタログが VLM なら画像理解")
        XCTAssertEqual(models[2].category, .embedding)
        XCTAssertEqual(models[2].categorySource, .heuristic)
        XCTAssertEqual(models[2].parameters?.totalB, 0.57)
        XCTAssertEqual(models[2].parametersSource, HuggingFaceClient.sourceName)
        XCTAssertEqual(models[2].priceText, "価格不明")
    }

    func testParameterFallbackChain() {
        let catalog = CatalogIndex(entries: [])
        let fromName = ModelDescriptorBuilder.describe("Qwen/Qwen3-235B-A22B", isListed: true, apiCategory: .chat, catalog: catalog, hf: nil)
        XCTAssertEqual(fromName.parameters, ParameterCount(totalB: 235, activeB: 22))
        XCTAssertEqual(fromName.parametersSource, "モデル名から推定")
        let fromFacts = ModelDescriptorBuilder.describe("deepseek-ai/DeepSeek-V3", isListed: true, apiCategory: .chat, catalog: catalog, hf: nil)
        XCTAssertEqual(fromFacts.parameters, ParameterCount(totalB: 671, activeB: 37))
        let hfThenName = ModelDescriptorBuilder.describe("tencent/Hunyuan-A13B-Instruct", isListed: true, apiCategory: nil, catalog: catalog, hf: ParameterCount(totalB: 80.39))
        XCTAssertEqual(hfThenName.parameters, ParameterCount(totalB: 80.39, activeB: 13))
        XCTAssertEqual(hfThenName.parametersSource, HuggingFaceClient.sourceName)
    }

    func testQueryFilterAndSort() {
        let catalog = CatalogIndex(entries: [
            entry("a/cheap-7B", input: 0.1, output: 0.2, category: .chat, params: 7, context: 8192, release: "2025-01-01"),
            entry("b/free-1B", input: 0, output: 0, category: .chat, params: 1, context: 32768, release: "2026-01-01"),
            entry("c/big-400B", input: 4, output: 16, category: .chat, params: 400, context: 131_072, release: "2024-01-01"),
            entry("d/embed", input: 0.5, category: .embedding),
        ])
        let remote = ["a/cheap-7B", "b/free-1B", "c/big-400B", "d/embed", "e/unknown"].map { RemoteModel(id: $0) }
        let models = ModelDescriptorBuilder.build(remote: remote, apiCategories: [:], catalog: catalog)

        XCTAssertEqual(ModelQuery(sort: .priceLowToHigh).apply(models).map(\.id), ["b/free-1B", "a/cheap-7B", "d/embed", "c/big-400B", "e/unknown"])
        XCTAssertEqual(ModelQuery(sort: .priceHighToLow).apply(models).first?.id, "c/big-400B")
        XCTAssertEqual(ModelQuery(sort: .parametersLargeFirst).apply(models).prefix(3).map(\.id), ["c/big-400B", "a/cheap-7B", "b/free-1B"])
        XCTAssertEqual(ModelQuery(sort: .parametersSmallFirst).apply(models).first?.id, "b/free-1B")
        XCTAssertEqual(ModelQuery(sort: .contextLargeFirst).apply(models).first?.id, "c/big-400B")
        XCTAssertEqual(ModelQuery(sort: .newest).apply(models).first?.id, "b/free-1B")
        XCTAssertEqual(ModelQuery(freeOnly: true).apply(models).map(\.id), ["b/free-1B"])
        XCTAssertEqual(ModelQuery(category: .embedding).apply(models).map(\.id), ["d/embed"])
        XCTAssertEqual(ModelQuery(searchText: "BIG 400").apply(models).map(\.id), ["c/big-400B"])
        XCTAssertEqual(ModelQuery(searchText: "埋め込み").apply(models).map(\.id), ["d/embed"])
        XCTAssertEqual(ModelQuery.counts(models)[.chat], 4)
        let recommended = ModelQuery().apply(models).map(\.id)
        XCTAssertEqual(recommended.last, "d/embed", "カテゴリ順")
        XCTAssertEqual(recommended.firstIndex(of: "e/unknown"), 3, "価格が分かるものを先に")
    }

    func testBuildFromCatalogSkipsDeprecated() {
        var old = entry("x/old", category: .chat)
        old.deprecated = true
        let models = ModelDescriptorBuilder.buildFromCatalog(CatalogIndex(entries: [old, entry("x/new", category: .chat)]))
        XCTAssertEqual(models.map(\.id), ["x/new"])
        XCTAssertFalse(models[0].isListedByAPI)
    }
}
