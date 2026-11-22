// Global entry for read mode: esbuild wraps this as `var MdFloorball`, which
// Swift evaluates in JavaScriptCore to draw diagrams into the page HTML.
export { VERSION, parse, tryParse, serialize, createDiagram } from "./model.js"
export { renderSource, renderSVG, escapeXML } from "./render.js"
