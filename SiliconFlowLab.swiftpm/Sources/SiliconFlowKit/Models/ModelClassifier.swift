import Foundation

/// モデル ID の文字列からカテゴリを推定します（API・カタログに情報が無いときの最後の手段）。
public enum ModelClassifier {
    public static func heuristicCategory(for modelID: String) -> ModelCategory {
        let id = modelID.lowercased()
        let name = id.split(separator: "/").last.map(String.init) ?? id

        if name.contains("rerank") { return .reranker }
        if name.contains("embedding") || name.hasPrefix("bge-") || name.contains("-embed") || name.hasPrefix("bce-embedding") {
            return .embedding
        }
        if containsAny(name, ["cosyvoice", "fish-speech", "fishaudio", "tts", "indextts", "moss-ttsd", "speech-0", "speech-1", "-voice-"]) && !name.contains("asr") {
            return .textToSpeech
        }
        if containsAny(name, ["sensevoice", "asr", "whisper", "speech-to-text", "gsr", "paraformer"]) {
            return .speechToText
        }
        if containsAny(name, ["i2v", "image-to-video"]) { return .imageToVideo }
        if containsAny(name, ["t2v", "hunyuanvideo", "ltx-video", "text-to-video", "mochi", "cogvideo"]) { return .textToVideo }
        if containsAny(name, ["image-edit", "kontext", "-edit", "img2img", "inpaint"]) { return .imageToImage }
        if containsAny(name, ["flux", "kolors", "stable-diffusion", "sdxl", "sd3", "qwen-image", "z-image", "hidream", "seedream", "playground-v", "dall"]) {
            return .textToImage
        }
        if isVisionName(name) { return .vision }
        return .chat
    }

    static func isVisionName(_ name: String) -> Bool {
        if containsAny(name, ["-vl", "vl-", "vision", "omni", "-ocr", "ocr-", "qvq", "janus", "llava", "internvl", "minicpm-v", "deepseek-vl"]) {
            return true
        }
        // GLM-4.5V / GLM-4.6V / GLM-5V のような「数字 + v」
        let tokens = name.split(whereSeparator: { $0 == "-" || $0 == "_" })
        for token in tokens where token.count >= 2 && token.hasSuffix("v") {
            let body = token.dropLast()
            if body.allSatisfy({ $0.isNumber || $0 == "." }) { return true }
            if body.hasPrefix("glm"), body.dropFirst(3).allSatisfy({ $0.isNumber || $0 == "." }) { return true }
        }
        return false
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    /// モデル ID の組織名部分（例: "Qwen/Qwen3-8B" → "Qwen"、"Pro/deepseek-ai/DeepSeek-V3" → "deepseek-ai"）
    public static func organization(of modelID: String) -> String? {
        let parts = strippedPrefixes(modelID).split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return String(parts[parts.count - 2])
    }

    /// モデル ID の名前部分（例: "Qwen/Qwen3-8B" → "Qwen3-8B"）
    public static func shortName(of modelID: String) -> String {
        modelID.split(separator: "/").last.map(String.init) ?? modelID
    }

    /// "Pro/" や "LoRA/" などの接頭辞を取り除いた ID
    public static func strippedPrefixes(_ modelID: String) -> String {
        var id = modelID
        for prefix in ["Pro/", "pro/", "LoRA/", "lora/", "Vendor-A/", "Vendor-B/"] where id.hasPrefix(prefix) {
            id.removeFirst(prefix.count)
        }
        return id
    }

    /// "Pro/" 付きのモデルか（高速・安定版。チャージ残高が必要な場合が多い）
    public static func isProVariant(_ modelID: String) -> Bool {
        modelID.hasPrefix("Pro/") || modelID.hasPrefix("pro/")
    }
}
