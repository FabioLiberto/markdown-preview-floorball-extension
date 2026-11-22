import JavaScriptCore
import WebKit
import XCTest
@testable import MarkdownHelpers

/// ```floorball fences: the data model and renderer (run in JavaScriptCore,
/// as read mode runs them), the read-mode figures, and the graphical editor.
final class FloorballDiagramTests: XCTestCase {
    private static let player = #"{ "id": "p1", "type": "player", "team": "attack", "number": 7, "x": 0.35, "y": 0.65 }"#
    private static let diagram = """
    {
      "version": 1,
      "rink": { "layout": "half" },
      "elements": [
        \(player)
      ],
      "paths": [
        { "id": "r1", "type": "pass", "points": [[0.35, 0.65], [0.6, 0.4]] }
      ]
    }
    """

    private static func fence(_ json: String) -> String { "```floorball\n\(json)\n```" }

    /// The bundled renderer in a fresh context, exposing `MdFloorball`.
    private func floorball() throws -> JSValue {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(try TestVendor.script("md-preview/Vendor/Floorball/floorball.min.js"))
        XCTAssertNil(context.exception)
        return try XCTUnwrap(context.objectForKeyedSubscript("MdFloorball"))
    }

    private func roundTrip(_ module: JSValue, _ source: String) -> String? {
        let parsed = module.invokeMethod("parse", withArguments: [source])
        return module.invokeMethod("serialize", withArguments: [parsed as Any])?.toString()
    }

    // MARK: Serialization

    func testSerializedDiagramRoundTripsUnchanged() throws {
        let module = try floorball()
        XCTAssertEqual(roundTrip(module, Self.diagram), Self.diagram)
    }

    func testParseNormalizesMissingOptionalPropertiesAndKeepsUnknownOnes() throws {
        let module = try floorball()
        let source = #"{ "elements": [{ "type": "player", "x": 2, "future": true }, { "type": "zamboni" }], "extra": [1] }"#
        let parsed = try XCTUnwrap(module.invokeMethod("parse", withArguments: [source]))
        XCTAssertEqual(parsed.objectForKeyedSubscript("version").toInt32(), 1)
        XCTAssertEqual(parsed.objectForKeyedSubscript("rink").objectForKeyedSubscript("layout").toString(), "full")
        let player = parsed.objectForKeyedSubscript("elements").atIndex(0)!
        XCTAssertEqual(player.objectForKeyedSubscript("id").toString(), "p1", "a missing id is generated")
        XCTAssertEqual(player.objectForKeyedSubscript("team").toString(), "attack")
        XCTAssertEqual(player.objectForKeyedSubscript("x").toDouble(), 1, "coordinates are clamped to the rink")
        XCTAssertTrue(player.objectForKeyedSubscript("future").toBool(), "unknown fields survive")
        let serialized = try XCTUnwrap(module.invokeMethod("serialize", withArguments: [parsed]).toString())
        XCTAssertTrue(serialized.contains(#""type": "zamboni""#), "unknown element types survive")
        XCTAssertTrue(serialized.contains(#""extra": [1]"#))
    }

    func testInvalidJSONAndNewerVersionsFailSafely() throws {
        let module = try floorball()
        let invalid = module.invokeMethod("tryParse", withArguments: ["{ nope"])
        XCTAssertFalse(invalid?.objectForKeyedSubscript("ok").toBool() ?? true)
        XCTAssertEqual(invalid?.objectForKeyedSubscript("code").toString(), "invalid-json")
        let newer = module.invokeMethod("tryParse", withArguments: [#"{ "version": 2 }"#])
        XCTAssertEqual(newer?.objectForKeyedSubscript("code").toString(), "unsupported-version")
        let array = module.invokeMethod("tryParse", withArguments: ["[]"])
        XCTAssertEqual(array?.objectForKeyedSubscript("code").toString(), "not-object")
    }

    // MARK: Rendering

    func testRendersPlayersAndPathsAsSVG() {
        guard case let .svg(svg, layout) = MarkdownHTML.drawFloorball(Self.diagram) else {
            return XCTFail("diagram did not draw")
        }
        XCTAssertEqual(layout, "half")
        XCTAssertTrue(svg.hasPrefix("<svg class=\"fb-diagram\""))
        XCTAssertTrue(svg.contains(">7</text>"), "the shirt number is drawn")
        XCTAssertTrue(svg.contains("stroke-dasharray"), "a pass is dashed")
        XCTAssertNotNil(svg.range(of: #"viewBox="-6 -6 212 212""#), "a half rink is square")
    }

    func testPlayerSizesScaleTheSymbol() throws {
        func radius(_ size: String?) -> String? {
            let sizeKey = size.map { #", "size": "\#($0)""# } ?? ""
            // A blank rink has no markings, so the player is the only circle.
            let source = #"{ "rink": { "layout": "blank" }, "elements": [{ "type": "player", "x": 0.5, "y": 0.5"# + sizeKey + " }] }"
            guard case let .svg(svg, _) = MarkdownHTML.drawFloorball(source) else { return nil }
            return svg.range(of: #"<circle[^>]* r="([0-9.]+)""#, options: .regularExpression)
                .map { String(svg[$0]) }?.components(separatedBy: "r=\"").last?.dropLast().description
        }
        XCTAssertEqual(radius(nil), "6", "medium is the default")
        XCTAssertEqual(radius("m"), "6")
        XCTAssertEqual(radius("s"), "4.5")
        XCTAssertEqual(radius("l"), "9")
        XCTAssertEqual(radius("huge"), "6", "an unknown size falls back to medium")

        let module = try floorball()
        let small = #"{ "elements": [{ "id": "p1", "type": "player", "size": "s", "x": 0.5, "y": 0.5 }] }"#
        XCTAssertTrue(roundTrip(module, small)?.contains(#""size": "s""#) ?? false)
        let medium = #"{ "elements": [{ "id": "p1", "type": "player", "size": "m", "x": 0.5, "y": 0.5 }] }"#
        XCTAssertFalse(roundTrip(module, medium)?.contains("size") ?? true, "the default is left out")
    }

    func testEmptyFenceDrawsAnEmptyFullRink() {
        guard case let .svg(svg, layout) = MarkdownHTML.drawFloorball("") else {
            return XCTFail("empty diagram did not draw")
        }
        XCTAssertEqual(layout, "full")
        XCTAssertFalse(svg.contains("fb-item"))
    }

    func testEscapesUserProvidedLabels() {
        let hostile = #"{ "elements": [{ "type": "text", "text": "<script>alert(1)</script>", "x": 0.5, "y": 0.5 }, { "type": "player", "label": "\" onload=\"x", "color": "red;fill:url(x)", "x": 0.2, "y": 0.2 }] }"#
        guard case let .svg(svg, _) = MarkdownHTML.drawFloorball(hostile) else {
            return XCTFail("diagram did not draw")
        }
        XCTAssertFalse(svg.contains("<script"))
        XCTAssertTrue(svg.contains("&lt;script&gt;"))
        XCTAssertFalse(svg.contains("\" onload="))
        XCTAssertFalse(svg.contains("url(x)"), "colors that are not hex values are dropped")
    }

    // MARK: Document integration

    func testRecognizesFencesAndKeepsSurroundingMarkdown() {
        let markdown = "# Drill\n\nBefore.\n\n" + Self.fence(Self.diagram) + "\n\nBetween.\n\n"
            + Self.fence(#"{ "version": 1, "rink": { "layout": "full" } }"#) + "\n\nAfter.\n"
        let html = MarkdownHTML.render(markdown: markdown).articleHTML
        XCTAssertEqual(html.components(separatedBy: "class=\"floorball-figure\"").count - 1, 2)
        XCTAssertTrue(html.contains("data-fb-layout=\"half\""))
        XCTAssertTrue(html.contains("data-fb-layout=\"full\""))
        XCTAssertFalse(html.contains("language-floorball"), "the JSON is not shown as code")
        for text in ["Drill", "Before.", "Between.", "After."] { XCTAssertTrue(html.contains(text)) }
        XCTAssertTrue(html.contains("data-source-line=\"5\""), "the figure keeps its fence line for Edit")
    }

    func testInvalidFencesShowAnErrorAndTheirSource() {
        let markdown = Self.fence("{ \"version\": 1, oops") + "\n\n" + Self.fence(#"{ "version": 9 }"#)
        let html = MarkdownHTML.render(markdown: markdown).articleHTML
        XCTAssertTrue(html.contains("This floorball diagram is not valid JSON."))
        XCTAssertTrue(html.contains("newer version of Markdown Preview"))
        XCTAssertTrue(html.contains("oops"), "the source stays readable for fixing")
    }

    func testDocumentsWithoutDiagramsAreUnchanged() {
        let html = MarkdownHTML.render(markdown: "Plain.\n\n```json\n{}\n```\n").articleHTML
        XCTAssertFalse(html.contains("floorball"))
    }

    // MARK: Editing

    /// The editor page with the graphical editor open on the fence that
    /// starts on .
    @MainActor
    private func openEditor(_ markdown: String, line: Int) async throws -> WebViewLayoutHarness {
        let script = try TestVendor.script("md-preview/Vendor/CodeMirror/mdedit.min.js")
        let editor = WebViewLayoutHarness(
            html: EditorHTML.render(markdown: markdown, editorJavaScript: script),
            width: 1000, isEditor: true, height: 800)
        _ = try await editor.layout(texts: [], imageCount: 0)
        let opened = try await editor.webView.evaluateJavaScript("window.__mdEditor.openFloorball(\(line))")
        XCTAssertEqual(opened as? Bool, true)
        return editor
    }

    /// Pointer events at a diagram item's centre (or an empty spot when
    /// there is no such item), then moved by (dx, dy).
    private static func dragScript(id: String, dx: Double, dy: Double, tool: String? = nil) -> String {
        """
        (() => {
            \(tool.map { "document.querySelector('[data-tool=\"\($0)\"]').click();" } ?? "")
            const canvas = document.querySelector('.fb-canvas');
            const item = canvas.querySelector('[data-fb-id="\(id)"] circle') || canvas.querySelector('svg');
            const box = item.getBoundingClientRect();
            // No item: an empty spot near the top right of the rink.
            const [fx, fy] = item.tagName === 'svg' ? [0.8, 0.15] : [0.5, 0.5];
            let x = box.left + box.width * fx, y = box.top + box.height * fy;
            const fire = (target, type) => target.dispatchEvent(new PointerEvent(type,
                { bubbles: true, cancelable: true, clientX: x, clientY: y, button: 0, pointerId: 1 }));
            fire(item, 'pointerdown');
            for (let i = 0; i < 5; i++) { x += \(dx) / 5; y += \(dy) / 5; fire(canvas, 'pointermove'); }
            fire(canvas, 'pointerup');
            return window.__mdEditor.getMarkdown();
        })()
        """
    }

    @MainActor
    func testEditorAddsMovesDeletesAndUndoes() async throws {
        let markdown = "Intro.\n\n" + Self.fence(Self.diagram) + "\n\nOutro.\n"
        let editor = try await openEditor(markdown, line: 3)
        defer { editor.close() }
        let web = editor.webView

        let moved = try await web.evaluateJavaScript(Self.dragScript(id: "p1", dx: 60, dy: -40)) as? String
        XCTAssertFalse(moved?.contains(Self.player) ?? true, "the drag moved the player")
        XCTAssertTrue(moved?.hasPrefix("Intro.\n\n```floorball\n") ?? false)
        XCTAssertTrue(moved?.hasSuffix("\n```\n\nOutro.\n") ?? false)

        let added = try await web.evaluateJavaScript(Self.dragScript(id: "none", dx: 0, dy: 0, tool: "cone")) as? String
        XCTAssertTrue(added?.contains(#""type": "cone""#) ?? false)

        _ = try await web.evaluateJavaScript("""
            document.querySelector('[data-tool="select"]').click();
            document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'Backspace', bubbles: true, cancelable: true }));
            """)
        let deleted = try await web.evaluateJavaScript("window.__mdEditor.getMarkdown()") as? String
        XCTAssertFalse(deleted?.contains(#""type": "cone""#) ?? true, "Backspace deletes the selection")

        let undo = "document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'z', metaKey: true, bubbles: true, cancelable: true }))"
        _ = try await web.evaluateJavaScript(undo)
        let restored = try await web.evaluateJavaScript("window.__mdEditor.getMarkdown()") as? String
        XCTAssertTrue(restored?.contains(#""type": "cone""#) ?? false, "⌘Z restores the deleted cone")
        _ = try await web.evaluateJavaScript("""
            document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'z', metaKey: true, shiftKey: true, bubbles: true, cancelable: true }))
            """)
        let redone = try await web.evaluateJavaScript("window.__mdEditor.getMarkdown()") as? String
        XCTAssertFalse(redone?.contains(#""type": "cone""#) ?? true, "⇧⌘Z deletes it again")

        for _ in 0..<6 { _ = try await web.evaluateJavaScript(undo) }
        let original = try await web.evaluateJavaScript("window.__mdEditor.getMarkdown()") as? String
        XCTAssertEqual(original, markdown, "undo returns to the document as it was opened, and no further")

        _ = try await web.evaluateJavaScript("document.querySelector('.fb-done').click()")
        let closed = try await web.evaluateJavaScript("window.__mdEditor.isFloorballOpen()") as? Bool
        XCTAssertEqual(closed, false)
    }

    @MainActor
    func testDeleteDiagramRemovesTheFenceAndClosesTheEditor() async throws {
        let markdown = "Intro.\n\n" + Self.fence(Self.diagram) + "\n\nOutro.\n"
        let editor = try await openEditor(markdown, line: 3)
        defer { editor.close() }
        let web = editor.webView
        _ = try await web.evaluateJavaScript("document.querySelector('[aria-label=\"Delete Diagram\"]').click()")
        let deleted = try await web.evaluateJavaScript("window.__mdEditor.getMarkdown()") as? String
        XCTAssertEqual(deleted, "Intro.\n\nOutro.\n")
        let open = try await web.evaluateJavaScript("window.__mdEditor.isFloorballOpen()") as? Bool
        XCTAssertEqual(open, false)
    }
}
