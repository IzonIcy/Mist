import Testing
import Foundation
@testable import MistCore

/// Exercises the hand-written TOML parser — the charter's "parser tests".
struct TOMLParserTests {

    private func parse(_ source: String) throws -> TOMLDocument {
        var parser = TOMLParser(source: source, sourceName: "test")
        return try parser.parse()
    }

    // MARK: primitives

    @Test func parsesRootPrimitives() throws {
        let doc = try parse("""
        gap = 8
        animate = true
        ratio = 0.5
        name = "hello"
        """)
        #expect(doc.root.integer(forKey: "gap") == 8)
        #expect(doc.root.bool(forKey: "animate") == true)
        #expect(doc.root.float(forKey: "ratio") == 0.5)
        #expect(doc.root.string(forKey: "name") == "hello")
    }

    @Test func parsesStringEscapes() throws {
        let doc = try parse(#"name = "a\nb\nc""#)
        #expect(doc.root.string(forKey: "name") == "a\nb\nc")
    }

    @Test func parsesLiteralString() throws {
        let doc = try parse(#"regex = 'C:\Program Files'"#)
        #expect(doc.root.string(forKey: "regex") == #"C:\Program Files"#)
    }

    @Test func parsesArray() throws {
        let doc = try parse("nums = [1, 2, 3]")
        guard case let .array(array)? = doc.root.value(forKey: "nums") else {
            Issue.record("expected array")
            return
        }
        #expect(array.count == 3)
    }

    // MARK: comments & blank lines

    @Test func ignoresCommentsAndBlankLines() throws {
        let doc = try parse("""

        # a comment
        gap = 8 # trailing comment
        """)
        #expect(doc.root.integer(forKey: "gap") == 8)
    }

    // MARK: sections

    @Test func parsesSectionTable() throws {
        let doc = try parse("[general]\nlayout = \"bsp\"")
        guard case let .table(t)? = doc.root.value(forKey: "general") else {
            Issue.record("expected general table")
            return
        }
        #expect(t.string(forKey: "layout") == "bsp")
    }

    @Test func parsesArrayOfTables() throws {
        let doc = try parse("""
        [[rules]]
        float = true
        [[rules]]
        float = false
        """)
        guard case let .array(items)? = doc.root.value(forKey: "rules") else {
            Issue.record("expected rules array")
            return
        }
        #expect(items.count == 2)
    }

    @Test func dottedKeysSetNestedTable() throws {
        let doc = try parse("window.app = \"Safari\"")
        guard case let .table(t)? = doc.root.value(forKey: "window") else {
            Issue.record("expected window table")
            return
        }
        #expect(t.string(forKey: "app") == "Safari")
    }

    // MARK: errors

    @Test func duplicateKeyThrows() {
        #expect(throws: MistError.self) {
            _ = try parse("gap = 8\ngap = 9")
        }
    }

    @Test func unterminatedStringThrows() {
        #expect(throws: MistError.self) {
            _ = try parse(#"name = "unclosed"#)
        }
    }

    @Test func errorCarriesLineNumber() {
        do {
            _ = try parse("gap = 8\nbad = \"unclosed")
            Issue.record("expected throw")
        } catch let error as MistError {
            guard case let .configParseFailed(_, line, _) = error else {
                Issue.record("unexpected error \(error)")
                return
            }
            #expect(line == 2)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    // MARK: regressions

    @Test func deeplyNestedArraysThrowInsteadOfStackOverflow() {
        // 10_000 nested arrays previously recursed unbounded (stack overflow);
        // now it must be a positioned error well before that.
        let source = "a = " + String(repeating: "[", count: 10_000) + String(repeating: "]", count: 10_000)
        #expect(throws: MistError.self) {
            _ = try parse(source)
        }
    }

    @Test func duplicateTableHeaderThrows() {
        // TOML 1.0: redefining [table] is an error — silently discarding the
        // earlier keys used to make users lose config invisibly.
        #expect(throws: MistError.self) {
            _ = try parse("[general]\nmode = \"x\"\n[general]\nother = 1")
        }
    }

    @Test func tableThenArrayOfTablesThrows() {
        // [t] followed by [[t]] redefines the same name with a different kind.
        #expect(throws: MistError.self) {
            _ = try parse("[t]\na = 1\n[[t]]\nb = 2")
        }
    }

    @Test func arrayOfTablesThenTableThrows() {
        #expect(throws: MistError.self) {
            _ = try parse("[[t]]\nb = 2\n[t]\na = 1")
        }
    }

    @Test func parsesCRLFLineEndings() throws {
        let doc = try parse("gap = 8\r\n# comment\r\nname = \"m\"\r\n")
        #expect(doc.root.integer(forKey: "gap") == 8)
        #expect(doc.root.string(forKey: "name") == "m")
    }

    @Test func parsesBOMPrefixedSource() throws {
        let doc = try parse("\u{feff}gap = 4\n")
        #expect(doc.root.integer(forKey: "gap") == 4)
    }
}