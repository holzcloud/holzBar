//
//  LossyJSONList.swift
//  holzBar
//

import Foundation

/// A stored JSON array that is decoded element by element.
///
/// One element that does not decode (a value written by a newer version or an import) must
/// not lose the others, and a later save must not drop it: the raw element is kept and
/// written back after the decoded ones.
nonisolated struct LossyJSONList<Element: Codable> {
    /// The elements that decoded, in their stored order.
    let elements: [Element]

    /// The elements that did not decode, as raw JSON.
    let undecodable: [Data]

    /// Decodes the array in `data`; `nil` if it is not a JSON array.
    init?(decoding data: Data) {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return nil
        }
        var elements = [Element]()
        var undecodable = [Data]()
        for item in raw {
            guard
                JSONSerialization.isValidJSONObject([item]),
                let itemData = try? JSONSerialization.data(withJSONObject: [item])
            else {
                continue
            }
            if let decoded = try? JSONDecoder().decode([Element].self, from: itemData).first {
                elements.append(decoded)
            } else {
                undecodable.append(itemData)
            }
        }
        self.elements = elements
        self.undecodable = undecodable
    }

    /// Encodes `current` followed by the elements that did not decode.
    static func encode(_ current: [Element], keeping undecodable: [Data]) -> Data? {
        guard let encoded = try? JSONEncoder().encode(current) else {
            return nil
        }
        guard !undecodable.isEmpty else {
            return encoded
        }
        guard var merged = try? JSONSerialization.jsonObject(with: encoded) as? [Any] else {
            return encoded
        }
        for data in undecodable {
            if let item = (try? JSONSerialization.jsonObject(with: data) as? [Any])?.first {
                merged.append(item)
            }
        }
        return try? JSONSerialization.data(withJSONObject: merged)
    }
}
