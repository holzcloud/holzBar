//
//  SyncModelNormalizers.swift
//  holzBar
//

import Foundation
import ImageIO

/// The normalizers of the sync unit table that name the app's models (analysis section
/// 4.6.2, D-03).
///
/// A JSON unit is decoded with the model's own decoder, which fills what is missing and
/// keeps numbers in their range, and encoded again with the model's own encoder in a
/// canonical form (sorted keys). A load-time re-encode by another build therefore compares
/// equal. A value with a field this build does not know is not applicable here (`nil`), so
/// it is relayed and never applied; the model would drop that field on its next save.
///
/// The closures read no preferences and log nothing: no value of a setting reaches a log.
///
/// The models and their `Codable` conformances belong to the main actor, and the table is
/// used by the sync engine, which runs on the main actor (its state changes there only), so
/// the closures assume that isolation.
@MainActor
enum SyncModelNormalizers {
    /// The normalizers of the app's unit table.
    static func make() -> SyncNormalizers {
        SyncNormalizers(
            appearance: { value in
                MainActor.assumeIsolated { normalizedJSON(MenuBarAppearanceConfigurationV2.self, value) }
            },
            itemGroups: { value in
                MainActor.assumeIsolated { normalizedJSON([MenuBarItemGroup].self, value) }
            },
            holzBarIcon: { value in
                MainActor.assumeIsolated { normalizedIcon(value) }
            }
        )
    }

    // MARK: JSON units

    /// `value` decoded as `model` and encoded again canonically, or `nil` when it is not
    /// JSON data the model decodes, or holds a field the model does not know.
    private static func normalizedJSON<Model: Codable>(_ model: Model.Type, _ value: SyncValue) -> SyncValue? {
        guard case .data(let data) = value, let canonical = canonicalJSON(model, from: data) else {
            return nil
        }
        return .data(canonical)
    }

    private static func canonicalJSON<Model: Codable>(_ model: Model.Type, from data: Data) -> Data? {
        guard
            let raw = try? JSONSerialization.jsonObject(with: data, options: []),
            raw is [String: Any] || raw is [Any],
            let decoded = try? JSONDecoder().decode(model, from: data),
            let encoded = canonicalData(of: decoded),
            let reencoded = try? JSONSerialization.jsonObject(with: encoded, options: []),
            covers(reencoded, raw)
        else {
            return nil
        }
        return encoded
    }

    private static func canonicalData(of model: some Encodable) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(model)
    }

    /// Whether `encoded` has every key `raw` has, at any depth, so that nothing a newer
    /// build wrote is lost by decoding. A `null` in `raw` is an absent optional.
    private static func covers(_ encoded: Any, _ raw: Any) -> Bool {
        switch raw {
        case is NSNull:
            return true
        case let rawObject as [String: Any]:
            guard let encodedObject = encoded as? [String: Any] else {
                return false
            }
            return rawObject.allSatisfy { key, value in
                if value is NSNull {
                    return true
                }
                guard let counterpart = encodedObject[key] else {
                    return false
                }
                return covers(counterpart, value)
            }
        case let rawArray as [Any]:
            guard let encodedArray = encoded as? [Any], encodedArray.count == rawArray.count else {
                return false
            }
            return zip(encodedArray, rawArray).allSatisfy { covers($0, $1) }
        default:
            return true
        }
    }

    // MARK: Icon

    /// The unit value of the holzBar icon: the stored image set (JSON data) and the
    /// template flag, at least one of them. The image set is normalized like the JSON
    /// units; custom image data is accepted only when it is a bitmap `CustomIconData`
    /// decodes, which is checked from the image headers, without decoding pixel data.
    private static func normalizedIcon(_ value: SyncValue) -> SyncValue? {
        guard let fields = value.dictionaryValue, !fields.isEmpty else {
            return nil
        }
        var canonical: [String: SyncValue] = [:]
        for (name, field) in fields {
            switch (name, field) {
            case (SyncNormalizers.iconField, .data(let data)):
                guard let set = canonicalImageSet(from: data) else {
                    return nil
                }
                canonical[name] = .data(set)
            case (SyncNormalizers.templateField, .bool):
                canonical[name] = field
            default:
                return nil
            }
        }
        return .dictionary(canonical)
    }

    private static func canonicalImageSet(from data: Data) -> Data? {
        guard
            let canonical = canonicalJSON(ControlItemImageSet.self, from: data),
            let set = try? JSONDecoder().decode(ControlItemImageSet.self, from: canonical),
            // A name this build does not know decodes as the default set; that is a value of
            // a newer build, not the default.
            let raw = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            raw["name"] as? String == set.name.rawValue,
            acceptsImages(of: set)
        else {
            return nil
        }
        return canonical
    }

    private static func acceptsImages(of set: ControlItemImageSet) -> Bool {
        [set.hidden, set.visible].allSatisfy { image in
            if case .data(let data) = image {
                return isDecodableBitmap(data)
            }
            return true
        }
    }

    /// Whether `data` is a bitmap that holzBar decodes (`CustomIconData`): an allowed type,
    /// within the byte and pixel limits. Only the header is read.
    private nonisolated static func isDecodableBitmap(_ data: Data) -> Bool {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard
            let source = CGImageSourceCreateWithData(data as CFData, options),
            CustomIconData.accepts(typeIdentifier: CGImageSourceGetType(source) as String?, byteCount: data.count),
            CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return false
        }
        return CustomIconData.accepts(pixelWidth: width, pixelHeight: height)
    }
}
