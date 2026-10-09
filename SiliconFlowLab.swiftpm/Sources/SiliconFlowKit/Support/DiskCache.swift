import Foundation

/// 小さな JSON ファイルのキャッシュ（端末の Caches フォルダ）。
/// 失敗しても例外を出さず nil / false を返します（キャッシュは無くても動くため）。
public struct DiskCache: Sendable {
    public let directory: URL?

    public init(directory: URL?) {
        self.directory = directory
    }

    /// アプリ用の既定のキャッシュフォルダ
    public static func `default`(subdirectory: String = "SiliconFlowLab") -> DiskCache {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return DiskCache(directory: base?.appendingPathComponent(subdirectory, isDirectory: true))
    }

    public func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let url = fileURL(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    @discardableResult
    public func save<T: Encodable>(_ value: T, name: String) -> Bool {
        guard let directory, let url = fileURL(name) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func remove(name: String) -> Bool {
        guard let url = fileURL(name) else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    /// キャッシュフォルダを丸ごと削除します。
    @discardableResult
    public func clear() -> Bool {
        guard let directory else { return false }
        return (try? FileManager.default.removeItem(at: directory)) != nil
    }

    private func fileURL(_ name: String) -> URL? {
        let safe = name.replacingOccurrences(of: "/", with: "_")
        return directory?.appendingPathComponent(safe + ".json")
    }
}
