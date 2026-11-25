import Foundation
import Testing
@testable import HolzBarCore

@Suite("LossyJSONList")
struct LossyJSONListTests {
    private struct Entry: Codable, Equatable {
        var id: UUID
        var name: String
    }

    @Test("A bad element does not lose the others, and a save keeps it")
    func keepsUndecodableElements() throws {
        let good = Entry(id: UUID(), name: "A")
        let goodJSON = String(decoding: try JSONEncoder().encode(good), as: UTF8.self)
        let data = Data("[\(goodJSON),{\"id\":\"not-a-uuid\",\"name\":\"B\"}]".utf8)

        let list = try #require(LossyJSONList<Entry>(decoding: data))
        #expect(list.elements == [good])
        #expect(list.undecodable.count == 1)

        let saved = try #require(LossyJSONList<Entry>.encode(list.elements, keeping: list.undecodable))
        let reread = try #require(LossyJSONList<Entry>(decoding: saved))
        #expect(reread.elements == [good])
        #expect(reread.undecodable.count == 1)
    }

    @Test("Data that is not an array does not decode")
    func rejectsNonArray() {
        #expect(LossyJSONList<Entry>(decoding: Data("{}".utf8)) == nil)
        #expect(LossyJSONList<Entry>(decoding: Data("nope".utf8)) == nil)
    }

    @Test("Without leftovers the encoding is the plain one")
    func plainEncoding() throws {
        let entries = [Entry(id: UUID(), name: "A")]
        let data = try #require(LossyJSONList<Entry>.encode(entries, keeping: []))
        #expect(try JSONDecoder().decode([Entry].self, from: data) == entries)
    }
}
