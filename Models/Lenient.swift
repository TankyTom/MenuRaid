import Foundation

/// Helpers for decoding leniently: a missing, null or oddly typed field becomes nil instead of
/// failing the whole section. GraphQL big numbers often arrive as strings, so numbers accept both.
nonisolated extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type = T.self, _ key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return Double(text.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        return lenientDouble(key).map { Int($0.rounded()) }
    }

    /// Decodes an array, silently dropping elements that fail to decode.
    func lenientArray<T: Decodable>(_ key: Key) -> [T] {
        let lossy = try? decodeIfPresent([Lossy<T>].self, forKey: key)
        return lossy?.compactMap(\.value) ?? []
    }
}

nonisolated struct Lossy<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
