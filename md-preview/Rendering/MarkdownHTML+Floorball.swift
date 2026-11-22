//
//  MarkdownHTML+Floorball.swift
//  md-preview
//
//  Floorball tactics diagrams: ```floorball fences drawn as SVG.
//

import Foundation
import JavaScriptCore
import Synchronization

// `nonisolated` matters: the targets default to MainActor isolation, and
// rendering runs off the main actor.
nonisolated extension MarkdownHTML {
    // MARK: - Floorball

    struct FloorballRenderResult {
        let html: String
        let containsFloorball: Bool
    }

    /// The outcome of drawing one fence: an SVG, or the reason there is none.
    enum FloorballDrawing: Equatable {
        case svg(String, layout: String)
        case failure(code: String)
        case rendererUnavailable
    }

    private static let floorballRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"<pre\b([^>]*)>\s*<code\b[^>]*class="[^"]*\blanguage-floorball\b[^"]*"[^>]*>([\s\S]*?)</code>\s*</pre>"#
        )
    }()

    /// Replaces each floorball fence with a figure holding its drawing. The
    /// SVG is drawn here, from the same renderer the editor bundles (run in
    /// JavaScriptCore), so read mode, printing, export, and Quick Look all
    /// get a finished, static drawing with no script of its own. The figure
    /// keeps the fence's source-line attributes: read mode's Edit button
    /// reports the line, and edit mode opens the fence on it.
    static func renderFloorballBlocks(in html: String) -> FloorballRenderResult {
        guard html.contains("language-floorball") else {
            return FloorballRenderResult(html: html, containsFloorball: false)
        }
        let nsHTML = html as NSString
        let matches = floorballRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        guard !matches.isEmpty else {
            return FloorballRenderResult(html: html, containsFloorball: false)
        }
        let diagramLabel = NSLocalizedString("Floorball diagram", comment: "Accessibility label for a floorball tactics diagram")
        #if QUICK_LOOK_EXTENSION
        // Quick Look cannot edit, so it gets no Edit button.
        let editButton = ""
        #else
        let edit = htmlEscape(NSLocalizedString("Edit Diagram", comment: "Button on a floorball diagram that opens it in the diagram editor"))
        let editButton = "<button type=\"button\" class=\"floorball-edit\" data-fb-edit=\"1\" tabindex=\"-1\">\(edit)</button>"
        #endif

        var rendered = ""
        rendered.reserveCapacity(html.count)
        var cursor = 0
        for match in matches {
            rendered += nsHTML.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let attributes = nsHTML.substring(with: match.range(at: 1))
            let escapedSource = nsHTML.substring(with: match.range(at: 2))
            let source = htmlUnescape(escapedSource)
            switch drawFloorball(source, label: diagramLabel) {
            case let .svg(svg, layout):
                rendered += """
                <figure\(attributes) class="floorball-figure" data-fb-layout="\(htmlEscape(layout))" role="group" aria-label="\(htmlEscape(diagramLabel))">\
                <div class="floorball-stage">\(svg)</div>\(editButton)</figure>
                """
            case let .failure(code):
                rendered += floorballErrorFigure(attributes: attributes,
                                                 message: floorballErrorMessage(code: code),
                                                 escapedSource: escapedSource)
            case .rendererUnavailable:
                rendered += floorballErrorFigure(
                    attributes: attributes,
                    message: NSLocalizedString("Floorball renderer is unavailable.", comment: "Shown in place of a floorball diagram when the renderer is missing"),
                    escapedSource: escapedSource
                )
            }
            cursor = match.range.location + match.range.length
        }
        rendered += nsHTML.substring(from: cursor)
        return FloorballRenderResult(html: rendered, containsFloorball: true)
    }

    /// A diagram that cannot be drawn says why, above its untouched source.
    private static func floorballErrorFigure(attributes: String, message: String, escapedSource: String) -> String {
        """
        <figure\(attributes) class="floorball-figure floorball-error" role="group">\
        <div class="floorball-message">\(htmlEscape(message))</div>\
        <div class="floorball-source">\(escapedSource)</div></figure>
        """
    }

    static func floorballErrorMessage(code: String) -> String {
        switch code {
        case "invalid-json":
            return NSLocalizedString("This floorball diagram is not valid JSON.", comment: "Floorball diagram error")
        case "unsupported-version":
            return NSLocalizedString("This floorball diagram was made with a newer version of Markdown Preview.", comment: "Floorball diagram error")
        default:
            return NSLocalizedString("This floorball diagram is not valid.", comment: "Floorball diagram error")
        }
    }

    /// Undoes the formatter's text escaping, so the renderer sees the fence
    /// exactly as written.
    static func htmlUnescape(_ string: String) -> String {
        guard string.contains("&") else { return string }
        return string
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Renderer

    /// Draws one fence's source. Thread-safe: renders take turns on one
    /// JavaScriptCore context, loaded on first use.
    static func drawFloorball(_ source: String, label: String = "Floorball diagram") -> FloorballDrawing {
        floorballEngine.withLock { state in
            if case .unloaded = state {
                state = FloorballEngine().map(FloorballEngineState.ready) ?? .unavailable
            }
            guard case let .ready(engine) = state else { return .rendererUnavailable }
            return engine.draw(source, label: label)
        }
    }

    private enum FloorballEngineState {
        case unloaded
        case unavailable
        case ready(FloorballEngine)
    }

    private static let floorballEngine = Mutex<FloorballEngineState>(.unloaded)

    private final class FloorballEngine {
        private let context: JSContext
        private let renderSource: JSValue

        init?() {
            guard let script = MarkdownHTML.bundledVendorResource("floorball.min", ext: "js", subdir: "Vendor/Floorball"),
                  let context = JSContext() else { return nil }
            context.evaluateScript(script)
            guard let module = context.objectForKeyedSubscript("MdFloorball"),
                  let renderSource = module.objectForKeyedSubscript("renderSource"),
                  renderSource.isObject else { return nil }
            self.context = context
            self.renderSource = renderSource
        }

        func draw(_ source: String, label: String) -> FloorballDrawing {
            context.exception = nil
            let options = JSValue(newObjectIn: context)
            options?.setObject(label, forKeyedSubscript: "label" as NSString)
            guard let result = renderSource.call(withArguments: [source, options as Any]),
                  context.exception == nil, result.isObject else {
                context.exception = nil
                return .failure(code: "invalid")
            }
            guard result.objectForKeyedSubscript("ok").toBool() else {
                return .failure(code: result.objectForKeyedSubscript("code").toString() ?? "invalid")
            }
            let svg = result.objectForKeyedSubscript("svg").toString() ?? ""
            let layout = result.objectForKeyedSubscript("layout").toString() ?? "full"
            return svg.hasPrefix("<svg") ? .svg(svg, layout: layout) : .failure(code: "invalid")
        }
    }

    // MARK: Styles and strings

    /// Diagram colors and figure layout, shared by the preview and the editor
    /// so a diagram looks the same in both modes. The SVG carries light
    /// fallback colors as attributes; these rules give it the theme's.
    static let floorballStylesheet = """
    .floorball-figure, .cm-md-floorball-preview, .fb-canvas {
        --fb-surface: light-dark(#f5f8fc, #1c232c);
        --fb-board: light-dark(#36557f, #a3b8d6);
        --fb-line: light-dark(#8aa2c4, #5f7799);
        --fb-goal: light-dark(#d64545, #ef7070);
        --fb-ink: light-dark(#1d2733, #e6ebf2);
    }
    svg.fb-diagram .fb-surface { fill: var(--fb-surface); stroke: var(--fb-board); }
    svg.fb-diagram .fb-boards { stroke: var(--fb-board); }
    svg.fb-diagram .fb-line, svg.fb-diagram .fb-mark { stroke: var(--fb-line); }
    svg.fb-diagram .fb-spot { fill: var(--fb-line); }
    svg.fb-diagram .fb-crease { fill: color-mix(in srgb, var(--fb-line) 18%, transparent); stroke: var(--fb-line); }
    svg.fb-diagram .fb-goal, svg.fb-diagram .fb-goal-line { stroke: var(--fb-goal); }
    svg.fb-diagram .fb-ink-stroke { stroke: var(--fb-ink); }
    svg.fb-diagram .fb-ink-fill { fill: var(--fb-ink); }
    svg.fb-diagram .fb-surface-stroke { stroke: var(--fb-surface); }
    svg.fb-diagram .fb-player-outline { fill: var(--fb-surface); }
    svg.fb-diagram .fb-text { fill: var(--fb-ink); stroke: var(--fb-surface); }
    svg.fb-diagram .fb-text-custom { stroke: var(--fb-surface); }
    svg.fb-diagram text { font-family: var(--mdp-doc-font, \(bodyFontFamily)); }
    .floorball-figure {
        position: relative;
        margin: \(largeBlockSpacing)px 0 0;
        padding: 0;
        break-inside: avoid;
    }
    .floorball-stage svg {
        display: block;
        width: 100%;
        height: auto;
    }
    .floorball-figure[data-fb-layout="half"] .floorball-stage {
        max-width: 520px;
        margin: 0 auto;
    }
    .floorball-edit {
        position: absolute;
        top: 10px;
        right: 10px;
        padding: 3px 10px;
        border: 0.5px solid color-mix(in srgb, var(--text) 18%, transparent);
        border-radius: 999px;
        background: color-mix(in srgb, Canvas 85%, transparent);
        -webkit-backdrop-filter: blur(8px);
        backdrop-filter: blur(8px);
        color: var(--text);
        font: 500 12px/1.4 -apple-system, BlinkMacSystemFont, sans-serif;
        opacity: 0;
        transition: opacity 0.15s;
    }
    .floorball-figure:hover .floorball-edit, .floorball-edit:focus-visible { opacity: 1; }
    .floorball-error {
        padding: 12px 14px;
        border-radius: 10px;
        background: var(--code-bg);
        border: 1px solid color-mix(in srgb, #d70015 35%, transparent);
    }
    .floorball-message { color: light-dark(#b3261e, #ff6961); font-weight: 500; }
    .floorball-source {
        margin-top: 8px;
        white-space: pre-wrap;
        overflow-wrap: anywhere;
        font-family: \(codeFontFamily);
        font-size: 0.85em;
        color: var(--secondary);
    }
    html:not([data-mdp-host]) .floorball-edit,
    html.\(previewPrintClass) .floorball-edit { display: none; }
    @media print {
        .floorball-edit { display: none !important; }
    }
    """

    /// The editor's words for the diagram widget and the graphical editor,
    /// as `window.__mdFloorballMessages`. Keys match the bundle's English.
    static var floorballMessagesJS: String {
        let entries: [(String, String, String)] = [
            ("diagram", "Floorball diagram", "Accessibility label for a floorball tactics diagram"),
            ("edit", "Edit Diagram", "Button on a floorball diagram that opens it in the diagram editor"),
            ("editHint", "Click to edit the diagram.", "Tooltip of a floorball diagram in the editor"),
            ("editSource", "Click to edit the source.", "Tooltip of a floorball diagram that cannot be drawn"),
            ("invalidJSON", "This floorball diagram is not valid JSON.", "Floorball diagram error"),
            ("invalid", "This floorball diagram is not valid.", "Floorball diagram error"),
            ("unsupportedVersion", "This floorball diagram was made with a newer version of Markdown Preview.", "Floorball diagram error"),
            ("title", "Floorball Diagram", "Title of the floorball diagram editor"),
            ("done", "Done", "Closes the floorball diagram editor"),
            ("undo", "Undo", "Floorball diagram editor button"),
            ("redo", "Redo", "Floorball diagram editor button"),
            ("deleteDiagram", "Delete Diagram", "Floorball diagram editor button that removes the whole diagram from the document"),
            ("layout", "Rink", "Floorball diagram editor: rink layout picker"),
            ("full", "Full Rink", "Floorball rink layout"),
            ("half", "Half Rink", "Floorball rink layout"),
            ("blank", "Blank", "Floorball rink layout without markings"),
            ("tools", "Tools", "Floorball diagram editor toolbar"),
            ("select", "Select", "Floorball diagram editor tool"),
            ("attacker", "Attacker", "Floorball diagram editor tool"),
            ("defender", "Defender", "Floorball diagram editor tool"),
            ("goalkeeper", "Goalkeeper", "Floorball diagram editor tool"),
            ("ball", "Ball", "Floorball diagram editor tool"),
            ("cone", "Cone", "Floorball diagram editor tool"),
            ("goal", "Goal", "Floorball diagram editor tool"),
            ("marker", "Marker", "Floorball diagram editor tool"),
            ("text", "Text", "Floorball diagram editor tool"),
            ("run", "Run", "Floorball diagram editor tool: a player's movement arrow"),
            ("pass", "Pass", "Floorball diagram editor tool: a passing arrow"),
            ("shot", "Shot", "Floorball diagram editor tool: a shooting arrow"),
            ("dribble", "Dribble", "Floorball diagram editor tool: carrying the ball"),
            ("freehand", "Freehand", "Floorball diagram editor tool: a free line"),
            ("line", "Line", "Floorball diagram path style without an arrowhead"),
            ("team", "Team", "Floorball diagram editor property"),
            ("attack", "Attack", "Floorball team"),
            ("defense", "Defense", "Floorball team"),
            ("neutral", "Neutral", "Floorball team"),
            ("player", "Player", "Floorball diagram editor: a field player, as opposed to a goalkeeper"),
            ("number", "Number", "Floorball diagram editor property: shirt number"),
            ("label", "Label", "Floorball diagram editor property"),
            ("color", "Color", "Floorball diagram editor property"),
            ("automatic", "Automatic", "Floorball diagram editor: the default color"),
            ("size", "Size", "Floorball diagram editor property"),
            ("small", "Small", "Floorball diagram text size"),
            ("medium", "Medium", "Floorball diagram text size"),
            ("large", "Large", "Floorball diagram text size"),
            ("style", "Style", "Floorball diagram editor property: the kind of arrow"),
            ("dashed", "Dashed", "Floorball diagram editor property"),
            ("arrowhead", "Arrowhead", "Floorball diagram editor property"),
            ("curved", "Curved", "Floorball diagram editor property"),
            ("rotate", "Rotate", "Floorball diagram editor button"),
            ("duplicate", "Duplicate", "Floorball diagram editor button"),
            ("delete", "Delete", "Floorball diagram editor button"),
            ("selected", "%d selected", "Floorball diagram editor: number of selected items"),
            ("hintSelect", "Click an item to select it. Drag to move it.", "Floorball diagram editor hint"),
            ("hintPlace", "Click the rink to place. Esc to finish.", "Floorball diagram editor hint"),
            ("hintPath", "Drag to draw, or click the start and then the end.", "Floorball diagram editor hint"),
            ("hintFreehand", "Drag to draw a free line.", "Floorball diagram editor hint"),
            ("defaultText", "Text", "Default text of a new label in a floorball diagram"),
        ]
        let body = entries.map { key, english, comment in
            "\(key): \(javaScriptStringLiteral(NSLocalizedString(english, comment: comment)))"
        }.joined(separator: ",\n")
        return "{\n\(body)\n}"
    }
}
