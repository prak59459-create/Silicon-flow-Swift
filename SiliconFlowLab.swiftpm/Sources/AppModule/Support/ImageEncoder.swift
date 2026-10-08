import UIKit

/// 画像を API に送れる形（縮小した JPEG の data URL）にします。
///
/// そのまま送ると数 MB になり、メモリも通信量も増えるため、長辺を制限して圧縮します。
enum ImageEncoder {
    static let maxDimension: CGFloat = 1280
    static let quality: CGFloat = 0.8

    static func dataURL(from data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        return dataURL(from: image)
    }

    static func dataURL(from image: UIImage) -> String? {
        let resized = downscaled(image)
        guard let jpeg = resized.jpegData(compressionQuality: quality) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    static func downscaled(_ image: UIImage) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// data URL を表示用の画像に戻します（毎回デコードしないようキャッシュします）。
    static func image(fromDataURL dataURL: String) -> UIImage? {
        let key = "\(dataURL.count)-\(dataURL.suffix(48))"
        if let cached = ThumbnailCache.shared.image(for: key) { return cached }
        guard let comma = dataURL.firstIndex(of: ",") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: comma)...])
        guard let data = Data(base64Encoded: base64), let image = UIImage(data: data) else { return nil }
        ThumbnailCache.shared.store(image, for: key)
        return image
    }
}

/// デコード済み画像のキャッシュ（NSCache はスレッドセーフで、メモリが足りなくなると自動で捨てます）
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 40
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}
