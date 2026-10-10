import Foundation
import Testing
@testable import HolzBarCore

@Suite("ScriptOutput")
struct ScriptOutputTests {
    private func line(_ text: String) -> String {
        ScriptOutput.displayLine(Data(text.utf8))
    }

    @Test("The buffer keeps the first bytes up to its limit and counts the rest")
    func bufferCap() {
        var buffer = ScriptOutputBuffer(limit: ScriptLimits.maximumOutputBytes)
        buffer.append(Data(repeating: 0x61, count: 70_000))
        #expect(buffer.data.count == 65_536)
        #expect(buffer.droppedByteCount == 4_464)
        buffer.append(Data(repeating: 0x62, count: 100))
        #expect(buffer.data.count == 65_536)
        #expect(buffer.droppedByteCount == 4_564)
        #expect(buffer.data.allSatisfy { $0 == 0x61 })
    }

    @Test("Small chunks are kept in order")
    func bufferOrder() {
        var buffer = ScriptOutputBuffer(limit: 10)
        buffer.append(Data("abc".utf8))
        buffer.append(Data("def".utf8))
        #expect(buffer.data == Data("abcdef".utf8))
        #expect(buffer.droppedByteCount == 0)
        buffer.append(Data("ghijkl".utf8))
        #expect(buffer.data == Data("abcdefghij".utf8))
        #expect(buffer.droppedByteCount == 2)
    }

    @Test("The first line that has text is shown, cleaned")
    func firstLine() {
        #expect(line("\n\n  hello   world  \nsecond") == "hello world")
        #expect(line("a\tb") == "a b")
        #expect(line("line\r\nnext") == "line")
        #expect(line("  \n \t \nreal") == "real")
        #expect(line("") == "")
        #expect(line("\n\r\n   \n") == "")
    }

    @Test("Control, format and bidirectional characters are dropped, nothing else is interpreted")
    func cleaning() {
        #expect(line("x\u{202E}y") == "xy")
        #expect(line("a\u{200B}b") == "ab")
        #expect(line("\u{1B}[31mred") == "[31mred")
        #expect(line("a\u{7}b\u{0}c") == "abc")
        #expect(line("a\u{E000}b") == "ab")
        // Link-like, path-like and markup-like text stays the same text.
        #expect(line("https://example.com/x") == "https://example.com/x")
        #expect(line("**bold** [link](https://example.com) <b>x</b>") == "**bold** [link](https://example.com) <b>x</b>")
        #expect(line("/etc/passwd; rm -rf ~") == "/etc/passwd; rm -rf ~")
    }

    @Test("A long line is cut to 80 characters with an ellipsis")
    func lengthCap() {
        let long = line(String(repeating: "a", count: 200))
        #expect(long.count == 80)
        #expect(long.hasSuffix("\u{2026}"))
        let exact = line(String(repeating: "b", count: 80))
        #expect(exact.count == 80)
        #expect(!exact.contains("\u{2026}"))
        #expect(ScriptOutput.maximumDisplayLength == 80)
    }

    @Test("Bytes that are not UTF-8 become the replacement character")
    func invalidUTF8() {
        let result = ScriptOutput.displayLine(Data([0x61, 0xFF, 0xFE, 0x62]))
        #expect(result.hasPrefix("a"))
        #expect(result.hasSuffix("b"))
        #expect(result.contains("\u{FFFD}"))
    }

    @Test("A run record compares field by field")
    func record() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = ScriptRunRecord(date: date, termination: .exited(0), displayLine: "ok")
        #expect(first == ScriptRunRecord(date: date, termination: .exited(0), displayLine: "ok"))
        #expect(first != ScriptRunRecord(date: date, termination: .exited(1), displayLine: "ok"))
        #expect(first != ScriptRunRecord(date: date, termination: .exited(0), displayLine: "no"))
        #expect(first != ScriptRunRecord(date: date.addingTimeInterval(1), termination: .exited(0), displayLine: "ok"))
    }
}
