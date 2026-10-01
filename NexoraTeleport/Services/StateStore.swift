import Foundation

actor StateStore {
    static let shared = StateStore()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var baseURL: URL {
        let fm = FileManager.default
        let root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("NexoraTeleport", isDirectory: true)
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try fm.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: root.path
            )
        } catch {
            // Individual writes still request Data Protection below.
        }
        return root
    }

    func save<T: Encodable>(_ value: T, name: String) throws {
        let fm = FileManager.default
        let finalURL = baseURL.appendingPathComponent(name)
        let tempURL = baseURL.appendingPathComponent(".\(name).\(UUID().uuidString).tmp")
        let data = try encoder.encode(value)

        try data.write(
            to: tempURL,
            options: [.completeFileProtectionUntilFirstUserAuthentication]
        )

        if fm.fileExists(atPath: finalURL.path) {
            _ = try fm.replaceItemAt(finalURL, withItemAt: tempURL)
        } else {
            try fm.moveItem(at: tempURL, to: finalURL)
        }
    }

    func load<T: Decodable>(_ type: T.Type, name: String, fallback: T) -> T {
        let url = baseURL.appendingPathComponent(name)
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? decoder.decode(type, from: data)
        else {
            return fallback
        }
        return decoded
    }
}
