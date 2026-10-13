//
//  CodeCountTests.swift
//  holzBar
//

import Testing

@testable import LayoutReorderCore

@Suite("CodeCount")
struct CodeCountTests {
    @Test("Code lines skip blank lines, line comments, doc comments and block comments")
    func codeLines() {
        let text = #"""
        let a = 1
        let b = 2

        // a comment
        /// a doc comment
        /*
            a block
            comment
        */
        let c = 3 // trailing
        """#
        #expect(CodeCount.codeLines(text) == 3)
    }

    @Test("An if with an else counts the if line, its body and the closing else line, not the else body")
    func ifElseScope() {
        let text = #"""
        func f() {
            if #available(macOS 27.0, *) {
                one()
            } else {
                two()
            }
            three()
        }
        """#
        #expect(CodeCount.scopedLines(text) == 3)
    }

    @Test("An availability attribute counts through the end of its function")
    func attributeScope() {
        let text = #"""
        @available(macOS 27.0, *)
        func g() {
            one()
            two()
        }
        func other() {
            three()
        }
        """#
        #expect(CodeCount.scopedLines(text) == 5)
    }

    @Test("Braces in strings, comments and interpolations do not move the end of a scope")
    func bracesInLiterals() {
        let text = #"""
        if #available(macOS 27.0, *) {
            let open = "{"
            // }
            let name = "\(a)"
            let nested = "\(items["}"])"
        }
        let outside = 1
        """#
        #expect(CodeCount.scopedLines(text) == 5)
    }

    @Test("A nested block stays inside the scope, which ends at its own closing brace")
    func nestedBlock() {
        let text = #"""
        if #available(macOS 27.0, *) {
            if x { y() }
            for item in items {
                z()
            }
        }
        after()
        """#
        #expect(CodeCount.scopedLines(text) == 6)
    }

    @Test("A marker inside an open scope starts no second scope and a text without a marker counts 0")
    func markerInsideScope() {
        let text = #"""
        if #available(macOS 27.0, *) {
            if #available(macOS 27.0, *) {
                one()
            }
        }
        """#
        #expect(CodeCount.scopedLines(text) == 5)
        #expect(CodeCount.scopedLines("let a = 1\nlet b = 2\n") == 0)
    }

    @Test("A scope shaped like itemsKeepOrder counts the if line, the true line and the else line")
    func itemsKeepOrderShape() {
        let text = #"""
        /// Whether items keep an order within their section (before macOS 27).
        private static var itemsKeepOrder: Bool {
            if #available(macOS 27.0, *) {
                false
            } else {
                true
            }
        }
        """#
        #expect(CodeCount.codeLines(text) == 7)
        #expect(CodeCount.scopedLines(text) == 3)
    }

    @Test("The report divides the deletable lines by the new lines and compares with 1.30")
    func report() {
        let fixture = "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n"
        let scope = "if #available(macOS 27.0, *) {\n" + String(repeating: "x()\n", count: 11) + "}\n"
        let meets = CodeCount.report(appKit: [scope], carried: [fixture])
        #expect(meets.deletableMax == 13)
        #expect(meets.newMin == 10)
        #expect(meets.ratio == 1.3)
        #expect(meets.meets == true)
        #expect(meets.threshold == 1.3)
        let short = "if #available(macOS 27.0, *) {\n" + String(repeating: "x()\n", count: 10) + "}\n"
        let misses = CodeCount.report(appKit: [short], carried: [fixture])
        #expect(misses.deletableMax == 12)
        #expect(misses.meets == false)
        let none = CodeCount.report(appKit: [scope], carried: [])
        #expect(none.newMin == 0)
        #expect(none.ratio == nil)
        #expect(none.meets == nil)
    }
}
