// The graphical floorball editor: a sheet over the Markdown editor that edits
// one ```floorball fence. It never keeps a copy of its own: every finished
// gesture is written to the fence through `host.write`, so the document's
// dirty state, autosave, and undo history are CodeMirror's. Undo and redo go
// through `host.undo` / `host.redo` and the sheet re-reads the fence.
//
// host: {
//   read(): string | null      fence source, or null once the fence is gone
//   write(source): void        replaces the fence source (one history step)
//   undo(): boolean, redo(): boolean
//   remove(): void             deletes the whole fence (one history step)
//   close(): void              called once, after the sheet is removed
// }

import {
  addElement, addPath, clone, deleteItems, duplicateItems, findItem, moveItems, nextNumber,
  parse, serialize, setLayout, updateItem, hasArrow, isDashed, round,
} from "./model.js"
import { PLAYER_RADIUS, TEAM_COLORS, layoutSize, pathMarkup, renderSVG, samplePath, viewBox } from "./render.js"

const ENGLISH = {
  title: "Floorball Diagram",
  done: "Done",
  undo: "Undo",
  redo: "Redo",
  deleteDiagram: "Delete Diagram",
  layout: "Rink",
  full: "Full Rink",
  half: "Half Rink",
  blank: "Blank",
  tools: "Tools",
  select: "Select",
  attacker: "Attacker",
  defender: "Defender",
  goalkeeper: "Goalkeeper",
  ball: "Ball",
  cone: "Cone",
  goal: "Goal",
  marker: "Marker",
  text: "Text",
  run: "Run",
  pass: "Pass",
  shot: "Shot",
  dribble: "Dribble",
  freehand: "Freehand",
  line: "Line",
  team: "Team",
  attack: "Attack",
  defense: "Defense",
  neutral: "Neutral",
  player: "Player",
  number: "Number",
  label: "Label",
  color: "Color",
  automatic: "Automatic",
  size: "Size",
  small: "Small",
  medium: "Medium",
  large: "Large",
  style: "Style",
  dashed: "Dashed",
  arrowhead: "Arrowhead",
  curved: "Curved",
  rotate: "Rotate",
  duplicate: "Duplicate",
  delete: "Delete",
  selected: "%d selected",
  hintSelect: "Click an item to select it. Drag to move it.",
  hintPlace: "Click the rink to place. Esc to finish.",
  hintPath: "Drag to draw, or click the start and then the end.",
  hintFreehand: "Drag to draw a free line.",
  defaultText: "Text",
  diagram: "Floorball diagram",
}

const PALETTE = ["#2563eb", "#dc2626", "#16a34a", "#d97706", "#7c3aed", "#db2777", "#0891b2", "#334155"]
const PLACE_TOOLS = new Set(["attacker", "defender", "goalkeeper", "ball", "cone", "goal", "marker", "text"])
const PATH_TOOLS = new Set(["run", "pass", "shot", "dribble", "freehand"])
const TOOL_KEYS = {
  v: "select", a: "attacker", d: "defender", g: "goalkeeper", b: "ball", c: "cone", o: "goal",
  m: "marker", t: "text", r: "run", p: "pass", s: "shot", w: "dribble", f: "freehand",
}
const SVG_ICON = (body) => `<svg viewBox="0 0 20 20" width="20" height="20" aria-hidden="true">${body}</svg>`
const ICONS = {
  select: SVG_ICON('<path d="M5.5 3.5l9.5 6.3-4.3 1.1-2.2 4.2z" fill="currentColor" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/>'),
  attacker: SVG_ICON(`<circle cx="10" cy="10" r="6.5" fill="${TEAM_COLORS.attack}"/>`),
  defender: SVG_ICON(`<circle cx="10" cy="10" r="5.8" fill="none" stroke="${TEAM_COLORS.defense}" stroke-width="2.2"/>`),
  goalkeeper: SVG_ICON(`<rect x="3.8" y="3.8" width="12.4" height="12.4" rx="3" fill="${TEAM_COLORS.attack}"/><rect x="6.6" y="6.6" width="6.8" height="6.8" rx="1.4" fill="none" stroke="#fff" stroke-width="1.1"/>`),
  ball: SVG_ICON('<circle cx="10" cy="10" r="5.5" fill="#fff" stroke="currentColor" stroke-width="1.3"/><circle cx="8" cy="8.5" r="0.9" fill="currentColor"/><circle cx="12" cy="9" r="0.9" fill="currentColor"/><circle cx="10" cy="12.4" r="0.9" fill="currentColor"/>'),
  cone: SVG_ICON('<path d="M10 3.5l5 10.5H5z" fill="#f97316" stroke="#9a3412" stroke-width="1" stroke-linejoin="round"/><path d="M7.6 9.6h4.8" stroke="#fff" stroke-width="1.5"/><rect x="3.5" y="14" width="13" height="2.2" rx="1.1" fill="#f97316"/>'),
  goal: SVG_ICON('<rect x="7" y="3.5" width="6" height="13" fill="none" stroke="#d64545" stroke-width="1.8"/><path d="M9 3.5v13M11 3.5v13" stroke="#d64545" stroke-width="0.7"/>'),
  marker: SVG_ICON('<path d="M10 3.5l6.5 6.5-6.5 6.5-6.5-6.5z" fill="#7c3aed"/>'),
  text: SVG_ICON('<path d="M4.5 5h11M10 5v11" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>'),
  run: SVG_ICON('<path d="M3.5 16.5l9.5-9.5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><path d="M16.5 3.5l-1.7 6.1-4.4-4.4z" fill="currentColor"/>'),
  pass: SVG_ICON('<path d="M3.5 16.5l9.5-9.5" stroke="currentColor" stroke-width="1.8" stroke-dasharray="2.6 2.2"/><path d="M16.5 3.5l-1.7 6.1-4.4-4.4z" fill="currentColor"/>'),
  shot: SVG_ICON('<path d="M3.5 16.5l9-9" stroke="currentColor" stroke-width="4.4" stroke-linecap="round"/><path d="M3.5 16.5l9-9" stroke="var(--fb-sheet-bg)" stroke-width="1.5" stroke-linecap="round"/><path d="M17 3l-2 7.2-5.2-5.2z" fill="currentColor"/>'),
  dribble: SVG_ICON('<path d="M3 15.5c1.2-2.6 2.6.8 3.8-1.8s2.6.8 3.8-1.8 1.4-1.4 2.2-2.2" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/><path d="M16.8 4l-1.6 6.2-4.6-4.6z" fill="currentColor"/>'),
  freehand: SVG_ICON('<path d="M3 13.5c2.5-7 4.5 1.5 6.5-3.5s3 4 7.5-5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>'),
  undo: SVG_ICON('<path d="M7.5 5.5L4 9l3.5 3.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/><path d="M4.5 9h7a4.5 4.5 0 010 9H9" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>'),
  redo: SVG_ICON('<path d="M12.5 5.5L16 9l-3.5 3.5" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/><path d="M15.5 9h-7a4.5 4.5 0 000 9H11" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>'),
  duplicate: SVG_ICON('<rect x="7" y="7" width="9" height="9" rx="2" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M13 4.5H6A1.5 1.5 0 004.5 6v7" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>'),
  delete: SVG_ICON('<path d="M4.5 6h11M8 6V4.5h4V6M6 6l.8 10h6.4L14 6" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>'),
  rotate: SVG_ICON('<path d="M15.5 10a5.5 5.5 0 11-1.6-3.9" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/><path d="M15.5 3.5v3.5H12" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>'),
}
const TOOL_GROUPS = [
  ["select"],
  ["attacker", "defender", "goalkeeper"],
  ["ball", "cone", "goal", "marker", "text"],
  ["run", "pass", "shot", "dribble", "freehand"],
]
const ACCENT = "#0a84ff"
// Clipboard shared by every diagram in the page.
let clipboard = null
let stylesInstalled = false

function element(tag, attributes = {}, children = []) {
  const node = document.createElement(tag)
  for (const [key, value] of Object.entries(attributes)) {
    if (value === undefined || value === null || value === false) continue
    if (key === "text") node.textContent = value
    else if (key === "html") node.innerHTML = value
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value)
    else node.setAttribute(key, value === true ? "" : value)
  }
  for (const child of [].concat(children)) if (child) node.append(child)
  return node
}

const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1])

// Ramer–Douglas–Peucker, in rendering units.
function simplify(points, epsilon) {
  if (points.length < 3) return points
  const [first, last] = [points[0], points[points.length - 1]]
  let farthest = 0
  let index = 0
  const dx = last[0] - first[0]
  const dy = last[1] - first[1]
  const span = Math.hypot(dx, dy) || 1
  for (let i = 1; i < points.length - 1; i++) {
    const offset = Math.abs(dy * points[i][0] - dx * points[i][1] + last[0] * first[1] - last[1] * first[0]) / span
    if (offset > farthest) { farthest = offset; index = i }
  }
  if (farthest <= epsilon) return [first, last]
  return [...simplify(points.slice(0, index + 1), epsilon).slice(0, -1), ...simplify(points.slice(index), epsilon)]
}

export class FloorballEditor {
  constructor(host, options = {}) {
    this.host = host
    this.messages = { ...ENGLISH, ...(options.messages || {}) }
    this.diagram = parse(host.read() ?? "")
    this.working = this.diagram
    this.source = host.read() ?? ""
    this.selection = []
    this.tool = "select"
    // New players take the size last chosen for a player.
    this.playerSize = "m"
    this.gesture = null
    this.pending = null
    // Steps this sheet wrote and can still take back, and steps it took back.
    this.undoDepth = 0
    this.redoDepth = 0
    this.closed = false
    this.frame = 0
    installStyles()
    this.build()
    if (options.initialTool) this.setTool(options.initialTool)
    this.render()
    this.updateInspector()
  }

  // ---------------------------------------------------------------------
  // Document
  // ---------------------------------------------------------------------

  // `keepInspector` leaves the property fields alone, for a commit made by
  // leaving a text field: rebuilding them would swallow the click that left it.
  commit(next, selection = this.selection, { keepInspector = false } = {}) {
    this.gesture = null
    const source = serialize(next)
    this.selection = selection.filter((id) => findItem(next, id))
    if (source === serialize(this.diagram)) {
      this.working = this.diagram
      this.render()
      this.updateInspector()
      return false
    }
    this.diagram = next
    this.working = next
    this.writing = true
    try {
      this.host.write(source)
    } finally {
      this.writing = false
    }
    this.source = this.host.read() ?? source
    this.undoDepth++
    this.redoDepth = 0
    this.render()
    if (!keepInspector) this.updateInspector()
    this.updateHistoryButtons()
    return true
  }

  undo() {
    this.finishPendingInput()
    if (!this.undoDepth || !this.host.undo()) return false
    this.undoDepth--
    this.redoDepth++
    this.reload()
    return true
  }

  redo() {
    if (!this.redoDepth || !this.host.redo()) return false
    this.redoDepth--
    this.undoDepth++
    this.reload()
    return true
  }

  // The fence changed under the sheet (undo, redo, or another edit).
  reload() {
    if (this.closed) return
    const source = this.host.read()
    if (source === null) return this.close()
    if (source === this.source) return
    let diagram
    try {
      diagram = parse(source)
    } catch (_) {
      return this.close()
    }
    this.source = source
    this.diagram = diagram
    this.working = diagram
    this.gesture = null
    this.pending = null
    this.selection = this.selection.filter((id) => findItem(diagram, id))
    this.render()
    this.updateInspector()
    this.updateHistoryButtons()
  }

  // Called by the host for every document update while the sheet is open.
  documentChanged() {
    if (!this.writing) this.reload()
  }

  // ---------------------------------------------------------------------
  // DOM
  // ---------------------------------------------------------------------

  build() {
    const m = this.messages
    this.toolButtons = new Map()
    const toolbar = element("div", { class: "fb-toolbar", role: "toolbar", "aria-label": m.tools, "aria-orientation": "vertical" })
    TOOL_GROUPS.forEach((group, index) => {
      if (index) toolbar.append(element("div", { class: "fb-tool-separator", role: "separator" }))
      for (const tool of group) {
        const key = Object.keys(TOOL_KEYS).find((letter) => TOOL_KEYS[letter] === tool)
        const button = element("button", {
          type: "button",
          class: "fb-tool",
          title: `${m[tool]} (${key.toUpperCase()})`,
          "aria-label": m[tool],
          "aria-pressed": "false",
          "data-tool": tool,
          html: ICONS[tool],
          onclick: () => this.setTool(tool),
        })
        this.toolButtons.set(tool, button)
        toolbar.append(button)
      }
    })

    this.layoutButtons = new Map()
    const layouts = element("div", { class: "fb-segmented", role: "radiogroup", "aria-label": m.layout })
    for (const layout of ["full", "half", "blank"]) {
      const button = element("button", {
        type: "button", role: "radio", "data-layout": layout, text: m[layout],
        onclick: () => this.commit(setLayout(this.diagram, layout)),
      })
      this.layoutButtons.set(layout, button)
      layouts.append(button)
    }

    const deleteDiagram = element("button", {
      type: "button", class: "fb-icon-button fb-destructive", title: m.deleteDiagram, "aria-label": m.deleteDiagram,
      html: ICONS.delete, onclick: () => this.deleteDiagram(),
    })
    this.undoButton = element("button", { type: "button", class: "fb-icon-button", title: `${m.undo} (⌘Z)`, "aria-label": m.undo, html: ICONS.undo, onclick: () => this.undo() })
    this.redoButton = element("button", { type: "button", class: "fb-icon-button", title: `${m.redo} (⇧⌘Z)`, "aria-label": m.redo, html: ICONS.redo, onclick: () => this.redo() })
    const done = element("button", { type: "button", class: "fb-done", text: m.done, onclick: () => this.close() })

    this.canvas = element("div", { class: "fb-canvas" })
    this.inspector = element("div", { class: "fb-inspector", "aria-live": "polite" })
    this.panel = element("div", { class: "fb-sheet", role: "dialog", "aria-modal": "true", "aria-label": m.title, tabindex: "-1" }, [
      element("div", { class: "fb-header" }, [
        element("div", { class: "fb-title", text: m.title }),
        layouts,
        element("div", { class: "fb-spacer" }),
        deleteDiagram,
        element("div", { class: "fb-header-separator", role: "separator" }),
        this.undoButton,
        this.redoButton,
        done,
      ]),
      element("div", { class: "fb-body" }, [toolbar, this.canvas]),
      this.inspector,
    ])
    this.root = element("div", { class: "fb-backdrop" }, [this.panel])

    this.onKeyDown = (event) => this.keyDown(event)
    this.onPointerDown = (event) => this.pointerDown(event)
    this.onPointerMove = (event) => this.pointerMove(event)
    this.onPointerUp = (event) => this.pointerUp(event)
    this.onBackdrop = (event) => { if (event.target === this.root) this.close() }
    this.onWheel = (event) => { if (!event.target.closest?.(".fb-inspector")) event.preventDefault() }
    window.addEventListener("keydown", this.onKeyDown, true)
    this.canvas.addEventListener("pointerdown", this.onPointerDown)
    this.canvas.addEventListener("pointermove", this.onPointerMove)
    this.canvas.addEventListener("pointerup", this.onPointerUp)
    this.canvas.addEventListener("pointercancel", this.onPointerUp)
    this.canvas.addEventListener("dblclick", (event) => this.doubleClick(event))
    this.root.addEventListener("mousedown", this.onBackdrop)
    this.root.addEventListener("wheel", this.onWheel, { passive: false })
    document.body.append(this.root)
    this.panel.focus({ preventScroll: true })
    this.updateHistoryButtons()
  }

  close() {
    if (this.closed) return
    this.finishPendingInput()
    this.closed = true
    cancelAnimationFrame(this.frame)
    window.removeEventListener("keydown", this.onKeyDown, true)
    this.root.remove()
    this.host.close()
  }

  // Removes the diagram from the document. No confirmation: it is one
  // document edit, which ⌘Z in the document brings back.
  deleteDiagram() {
    if (this.closed) return
    this.writing = true
    try {
      this.host.remove()
    } finally {
      this.writing = false
    }
    this.close()
  }

  setTool(tool) {
    this.tool = tool
    this.pending = null
    this.gesture = null
    for (const [name, button] of this.toolButtons) {
      button.setAttribute("aria-pressed", String(name === tool))
    }
    this.canvas.dataset.tool = tool
    this.render()
    this.updateInspector()
  }

  updateHistoryButtons() {
    this.undoButton.disabled = !this.undoDepth
    this.redoButton.disabled = !this.redoDepth
    for (const [layout, button] of this.layoutButtons) {
      button.setAttribute("aria-checked", String(this.diagram.rink.layout === layout))
    }
  }

  // ---------------------------------------------------------------------
  // Drawing
  // ---------------------------------------------------------------------

  scheduleRender() {
    if (this.frame) return
    this.frame = requestAnimationFrame(() => {
      this.frame = 0
      this.render()
    })
  }

  render() {
    if (this.closed) return
    cancelAnimationFrame(this.frame)
    this.frame = 0
    const diagram = this.working
    const box = viewBox(diagram)
    this.canvas.style.setProperty("--fb-aspect", `${box.width} / ${box.height}`)
    this.canvas.innerHTML = renderSVG(diagram, {
      interactive: true,
      label: this.messages.diagram,
      overlay: this.overlay(diagram),
    })
    this.svg = this.canvas.firstElementChild
    this.updateHistoryButtons()
  }

  // Selection rings, path handles, and the path being drawn.
  overlay(diagram) {
    const size = layoutSize(diagram)
    const parts = []
    for (const id of this.selection) {
      const item = findItem(diagram, id)
      if (!item || item.unknown) continue
      if (item.points) {
        const sampled = samplePath(item, size)
        parts.push(`<path d="${sampled.map(([x, y], i) => (i ? "L" : "M") + x.toFixed(2) + " " + y.toFixed(2)).join("")}" fill="none" stroke="${ACCENT}" stroke-opacity="0.3" stroke-width="7" stroke-linecap="round" stroke-linejoin="round" pointer-events="none"/>`)
        if (this.selection.length === 1) parts.push(...this.pathHandles(item, size))
      } else {
        const x = item.x * size.width
        const y = item.y * size.height
        if (item.type === "text") {
          const lines = String(item.text || " ").split("\n")
          const fontSize = { s: 8, m: 11, l: 15 }[item.size || "m"]
          const width = Math.min(260, Math.max(...lines.map((line) => line.length), 2) * fontSize * 0.6) + 8
          const height = Math.min(6, lines.length) * fontSize * 1.2 + 6
          parts.push(`<rect x="${(x - width / 2).toFixed(2)}" y="${(y - height / 2).toFixed(2)}" width="${width.toFixed(2)}" height="${height.toFixed(2)}" rx="4" fill="none" stroke="${ACCENT}" stroke-width="1.2" stroke-dasharray="3 2" pointer-events="none"/>`)
        } else {
          const radius = item.type === "player" ? (PLAYER_RADIUS[item.size] || PLAYER_RADIUS.m) + 4
            : { ball: 7, cone: 10, goal: 12, marker: 10 }[item.type] || 10
          parts.push(`<circle cx="${x.toFixed(2)}" cy="${y.toFixed(2)}" r="${radius}" fill="none" stroke="${ACCENT}" stroke-width="1.4" stroke-dasharray="3 2" pointer-events="none"/>`)
        }
      }
    }
    const draft = this.draftPath()
    if (draft) {
      parts.push(`<g opacity="0.75" pointer-events="none">${pathMarkup(draft, size)}</g>`)
    }
    return `<g class="fb-overlay">${parts.join("")}</g>`
  }

  pathHandles(path, size) {
    const handle = (name, [x, y], shape = "circle") => shape === "circle"
      ? `<circle class="fb-handle" data-fb-handle="${name}" cx="${(x * size.width).toFixed(2)}" cy="${(y * size.height).toFixed(2)}" r="4.2" fill="#fff" stroke="${ACCENT}" stroke-width="1.6"/>`
      : `<rect class="fb-handle" data-fb-handle="${name}" x="${(x * size.width - 3.6).toFixed(2)}" y="${(y * size.height - 3.6).toFixed(2)}" width="7.2" height="7.2" rx="1.5" transform="rotate(45 ${(x * size.width).toFixed(2)} ${(y * size.height).toFixed(2)})" fill="${path.control ? ACCENT : "#fff"}" stroke="${ACCENT}" stroke-width="1.4"/>`
    const points = path.points
    const handles = [handle("start", points[0]), handle("end", points[points.length - 1])]
    if (points.length === 2) {
      const bend = path.control || [(points[0][0] + points[1][0]) / 2, (points[0][1] + points[1][1]) / 2]
      handles.push(handle("control", bend, "diamond"))
    }
    return handles
  }

  draftPath() {
    const state = this.gesture?.kind === "draw" ? this.gesture : this.pending
    if (state) {
      if (distance(state.start, state.current) < 0.002) return null
      return { id: "draft", type: state.type, points: [state.start, state.current] }
    }
    if (this.gesture?.kind === "freehand" && this.gesture.points.length > 1) {
      return { id: "draft", type: "run", points: this.gesture.points }
    }
    return null
  }

  // ---------------------------------------------------------------------
  // Pointer
  // ---------------------------------------------------------------------

  // Pointer position as normalized rink coordinates, clamped to the rink.
  normalized(event) {
    const svg = this.svg
    const matrix = svg?.getScreenCTM?.()
    const size = layoutSize(this.working)
    let x
    let y
    if (matrix) {
      const point = svg.createSVGPoint()
      point.x = event.clientX
      point.y = event.clientY
      const local = point.matrixTransform(matrix.inverse())
      x = local.x
      y = local.y
    } else {
      // No layout (tests): map the canvas box onto the view box.
      const rect = this.canvas.getBoundingClientRect()
      const box = viewBox(this.working)
      x = box.x + (event.clientX - rect.left) / (rect.width || 1) * box.width
      y = box.y + (event.clientY - rect.top) / (rect.height || 1) * box.height
    }
    return [round(Math.min(1, Math.max(0, x / size.width))), round(Math.min(1, Math.max(0, y / size.height)))]
  }

  pointerDown(event) {
    if (event.button !== 0) return
    this.finishPendingInput()
    this.panel.focus({ preventScroll: true })
    event.preventDefault()
    try { this.canvas.setPointerCapture(event.pointerId) } catch (_) { /* synthetic events */ }
    const point = this.normalized(event)
    const handle = event.target.closest?.("[data-fb-handle]")
    const hit = event.target.closest?.("[data-fb-id]")
    const hitId = hit?.getAttribute("data-fb-id")

    if (this.pending) {
      const pending = this.pending
      this.pending = null
      this.finishPath(pending.type, pending.start, point)
      return
    }
    if (handle && this.selection.length === 1) {
      this.gesture = { kind: "handle", id: this.selection[0], handle: handle.getAttribute("data-fb-handle"), origin: this.diagram }
      return
    }
    if (PATH_TOOLS.has(this.tool)) {
      this.gesture = this.tool === "freehand"
        ? { kind: "freehand", points: [point] }
        : { kind: "draw", type: this.tool, start: point, current: point, clientX: event.clientX, clientY: event.clientY }
      return
    }
    if (hitId) {
      if (event.shiftKey || event.metaKey) {
        this.selection = this.selection.includes(hitId)
          ? this.selection.filter((id) => id !== hitId)
          : [...this.selection, hitId]
      } else if (!this.selection.includes(hitId)) {
        this.selection = [hitId]
      }
      this.gesture = { kind: "move", ids: this.selection.slice(), start: point, origin: this.diagram, moved: false, clientX: event.clientX, clientY: event.clientY }
      this.render()
      this.updateInspector()
      return
    }
    if (PLACE_TOOLS.has(this.tool)) {
      this.place(this.tool, point)
      return
    }
    if (this.selection.length) {
      this.selection = []
      this.render()
      this.updateInspector()
    }
  }

  pointerMove(event) {
    const gesture = this.gesture
    if (!gesture && !this.pending) return
    const point = this.normalized(event)
    if (this.pending) {
      this.pending.current = point
    } else if (gesture.kind === "draw") {
      gesture.current = point
    } else if (gesture.kind === "freehand") {
      const size = layoutSize(this.working)
      const last = gesture.points[gesture.points.length - 1]
      if (Math.hypot((point[0] - last[0]) * size.width, (point[1] - last[1]) * size.height) >= 2) gesture.points.push(point)
    } else if (gesture.kind === "move") {
      // A few pixels of slack, so a click never nudges what it selects.
      if (!gesture.moved && Math.hypot(event.clientX - gesture.clientX, event.clientY - gesture.clientY) < 3) return
      gesture.moved = true
      this.working = moveItems(gesture.origin, gesture.ids, point[0] - gesture.start[0], point[1] - gesture.start[1])
    } else if (gesture.kind === "handle") {
      const path = findItem(gesture.origin, gesture.id)
      if (!path?.points) return
      const changes = {}
      if (gesture.handle === "control") changes.control = point
      else {
        const points = path.points.slice()
        points[gesture.handle === "start" ? 0 : points.length - 1] = point
        changes.points = points
      }
      this.working = updateItem(gesture.origin, gesture.id, changes)
    }
    this.scheduleRender()
  }

  pointerUp(event) {
    if (!this.gesture) return
    if (event.type === "pointercancel") {
      this.gesture = null
      this.working = this.diagram
      this.render()
      return
    }
    // The release point counts: it can differ from the last move.
    this.pointerMove(event)
    const gesture = this.gesture
    this.gesture = null
    if (gesture.kind === "move") {
      if (gesture.moved) this.commit(this.working, gesture.ids)
      else this.render()
    } else if (gesture.kind === "handle") {
      this.commit(this.working)
    } else if (gesture.kind === "draw") {
      const size = layoutSize(this.working)
      const span = Math.hypot((gesture.current[0] - gesture.start[0]) * size.width, (gesture.current[1] - gesture.start[1]) * size.height)
      if (span < 6) {
        // A click: the path ends at the next click.
        this.pending = { type: gesture.type, start: gesture.start, current: gesture.start }
        this.updateInspector()
      } else {
        this.finishPath(gesture.type, gesture.start, gesture.current)
      }
    } else if (gesture.kind === "freehand") {
      const size = layoutSize(this.working)
      const units = gesture.points.map(([x, y]) => [x * size.width, y * size.height])
      const simplified = simplify(units, 1.5)
      const points = simplified.map(([x, y]) => [round(x / size.width), round(y / size.height)])
      // Anything shorter than a few units was a click, not a line.
      if (simplified.length >= 2 && Math.max(...simplified.map((point) => distance(point, simplified[0]))) >= 4) {
        const { diagram, id } = addPath(this.diagram, { type: "run", points })
        if (id) this.commit(diagram, [id])
        else this.render()
      } else this.render()
    }
  }

  doubleClick(event) {
    const id = event.target.closest?.("[data-fb-id]")?.getAttribute("data-fb-id")
    if (!id) return
    this.selection = [id]
    this.render()
    this.updateInspector()
    this.inspector.querySelector("[data-fb-primary]")?.focus()
    this.inspector.querySelector("[data-fb-primary]")?.select?.()
  }

  place(tool, [x, y]) {
    let element
    switch (tool) {
      case "attacker": element = { type: "player", team: "attack", number: nextNumber(this.diagram, "attack"), size: this.playerSize, x, y }; break
      case "defender": element = { type: "player", team: "defense", number: nextNumber(this.diagram, "defense"), size: this.playerSize, x, y }; break
      case "goalkeeper": element = { type: "player", team: "attack", role: "goalkeeper", size: this.playerSize, x, y }; break
      case "text": element = { type: "text", text: this.messages.defaultText, x, y }; break
      default: element = { type: tool, x, y }
    }
    const { diagram, id } = addElement(this.diagram, element)
    this.commit(diagram, [id])
    if (tool === "text") {
      const input = this.inspector.querySelector("[data-fb-primary]")
      input?.focus()
      input?.select()
    }
  }

  finishPath(type, start, end) {
    const { diagram, id } = addPath(this.diagram, { type, points: [start, end] })
    if (id) this.commit(diagram, [id])
    else this.render()
  }

  // ---------------------------------------------------------------------
  // Keyboard
  // ---------------------------------------------------------------------

  keyDown(event) {
    if (this.closed) return
    const inField = event.target instanceof Element && event.target.closest("input, textarea, select")
    const command = event.metaKey || event.ctrlKey
    const key = event.key.toLowerCase()
    let handled = true
    if (command && key === "z") {
      if (inField && !event.shiftKey && this.hasPendingInput()) handled = false
      else if (event.shiftKey) this.redo()
      else this.undo()
    } else if (command && key === "y") {
      this.redo()
    } else if (event.key === "Escape") {
      this.escape(inField)
    } else if (inField) {
      if (event.key === "Enter" && event.target.tagName === "INPUT") event.target.blur()
      handled = event.key === "Enter"
    } else if (command && key === "d") {
      this.duplicate()
    } else if (command && key === "a") {
      this.selection = [...this.diagram.elements, ...this.diagram.paths].filter((item) => !item.unknown).map((item) => item.id)
      this.render()
      this.updateInspector()
    } else if (command && key === "c") {
      this.copy()
    } else if (command && key === "x") {
      if (this.copy()) this.deleteSelection()
    } else if (command && key === "v") {
      this.paste()
    } else if (command) {
      // ⌘S, ⌘W and the rest stay with the app.
      handled = false
    } else if (event.key === "Delete" || event.key === "Backspace") {
      this.deleteSelection()
    } else if (event.key.startsWith("Arrow") && this.selection.length) {
      const step = event.shiftKey ? 0.025 : 0.005
      const dx = event.key === "ArrowLeft" ? -step : event.key === "ArrowRight" ? step : 0
      const dy = event.key === "ArrowUp" ? -step : event.key === "ArrowDown" ? step : 0
      this.commit(moveItems(this.diagram, this.selection, dx, dy))
    } else if (TOOL_KEYS[key] && !event.altKey) {
      this.setTool(TOOL_KEYS[key])
    } else if (event.key === "Tab") {
      handled = false
    } else {
      handled = !event.target.closest?.("button")
    }
    if (handled) {
      event.preventDefault()
      event.stopPropagation()
    }
  }

  escape(inField) {
    if (inField) {
      this.finishPendingInput()
      this.panel.focus({ preventScroll: true })
    } else if (this.gesture || this.pending) {
      this.gesture = null
      this.pending = null
      this.working = this.diagram
      this.render()
      this.updateInspector()
    } else if (this.selection.length) {
      this.selection = []
      this.render()
      this.updateInspector()
    } else if (this.tool !== "select") {
      this.setTool("select")
    } else {
      this.close()
    }
  }

  deleteSelection() {
    if (!this.selection.length) return
    this.commit(deleteItems(this.diagram, this.selection), [])
  }

  duplicate() {
    if (!this.selection.length) return
    const { diagram, ids } = duplicateItems(this.diagram, this.selection)
    this.commit(diagram, ids)
  }

  copy() {
    const items = this.selection.map((id) => findItem(this.diagram, id)).filter(Boolean)
    if (!items.length) return false
    clipboard = {
      elements: items.filter((item) => !item.points).map(clone),
      paths: items.filter((item) => item.points).map(clone),
      layout: this.diagram.rink.layout,
    }
    return true
  }

  paste() {
    if (!clipboard) return
    let diagram = this.diagram
    const ids = []
    for (const element of clipboard.elements) {
      const added = addElement(diagram, element)
      diagram = added.diagram
      ids.push(added.id)
    }
    for (const path of clipboard.paths) {
      const added = addPath(diagram, path)
      if (!added.id) continue
      diagram = added.diagram
      ids.push(added.id)
    }
    this.commit(moveItems(diagram, ids, 0.03, 0.03), ids)
  }

  // ---------------------------------------------------------------------
  // Inspector
  // ---------------------------------------------------------------------

  hasPendingInput() {
    return !!this.inspector.querySelector("[data-fb-dirty]")
  }

  // Text typed into a field is shown live but written to the document once,
  // when the field is left.
  finishPendingInput() {
    const field = this.inspector?.querySelector("[data-fb-dirty]")
    if (field) field.dispatchEvent(new Event("change"))
  }

  updateInspector() {
    if (this.closed) return
    const m = this.messages
    const items = this.selection.map((id) => findItem(this.diagram, id)).filter((item) => item && !item.unknown)
    const content = []
    if (!items.length) {
      const hint = this.pending || PATH_TOOLS.has(this.tool)
        ? (this.tool === "freehand" ? m.hintFreehand : m.hintPath)
        : PLACE_TOOLS.has(this.tool) ? m.hintPlace : m.hintSelect
      content.push(element("div", { class: "fb-hint", text: hint }))
    } else if (items.length > 1) {
      content.push(element("div", { class: "fb-field-label", text: m.selected.replace("%d", String(items.length)) }))
      const players = items.filter((item) => item.type === "player")
      if (players.length) content.push(this.playerSizeField(players))
    } else {
      content.push(...this.fieldsFor(items[0]))
    }
    if (items.length) {
      content.push(element("div", { class: "fb-spacer" }))
      content.push(this.iconButton("duplicate", m.duplicate + " (⌘D)", () => this.duplicate()))
      content.push(this.iconButton("delete", m.delete + " (⌫)", () => this.deleteSelection(), "fb-destructive"))
    }
    this.inspector.replaceChildren(...content)
  }

  iconButton(icon, label, action, extraClass = "") {
    return element("button", { type: "button", class: `fb-icon-button ${extraClass}`.trim(), title: label, "aria-label": label, html: ICONS[icon], onclick: action })
  }

  fieldsFor(item) {
    const m = this.messages
    const fields = []
    const update = (changes) => this.commit(updateItem(this.diagram, item.id, changes))
    const updateText = (changes) => this.commit(updateItem(this.diagram, item.id, changes), this.selection, { keepInspector: true })
    if (item.points) {
      fields.push(this.segmented(m.style, ["run", "pass", "shot", "dribble", "line"].map((type) => [type, m[type]]), item.type, (type) => {
        // Dashes and arrowheads follow the new style's own defaults.
        update({ type, dashed: undefined, arrow: undefined })
      }))
      fields.push(this.toggle(m.dashed, isDashed(item), (on) => update({ dashed: on })))
      fields.push(this.toggle(m.arrowhead, hasArrow(item), (on) => update({ arrow: on })))
      if (item.points.length === 2) {
        fields.push(this.toggle(m.curved, !!item.control, (on) => {
          if (!on) return update({ control: undefined })
          const [[ax, ay], [bx, by]] = item.points
          // Bend to the left of the direction of travel.
          update({ control: [(ax + bx) / 2 + (ay - by) * 0.35, (ay + by) / 2 - (ax - bx) * 0.35] })
        }))
      }
      fields.push(this.colors(item.color, (color) => update({ color })))
      return fields
    }
    switch (item.type) {
      case "player":
        fields.push(this.segmented(m.team, [["attack", m.attack], ["defense", m.defense], ["neutral", m.neutral]], item.team, (team) => update({ team })))
        fields.push(this.segmented(m.player, [["player", m.player], ["goalkeeper", m.goalkeeper]], item.role === "goalkeeper" ? "goalkeeper" : "player",
          (role) => update({ role: role === "goalkeeper" ? "goalkeeper" : undefined })))
        fields.push(this.textField(m.number, item.number ?? "", 3, "fb-narrow", (number) => updateText({ number: number || undefined }), true))
        fields.push(this.textField(m.label, item.label ?? "", 40, "", (label) => updateText({ label: label || undefined })))
        fields.push(this.playerSizeField([item]))
        fields.push(this.colors(item.color, (color) => update({ color })))
        break
      case "text":
        fields.push(this.textField(m.text, item.text ?? "", 400, "fb-wide", (text) => updateText({ text }), true))
        fields.push(this.segmented(m.size, [["s", m.small], ["m", m.medium], ["l", m.large]], item.size || "m", (size) => update({ size })))
        fields.push(this.colors(item.color, (color) => update({ color })))
        break
      case "marker":
        fields.push(this.textField(m.label, item.label ?? "", 40, "", (label) => updateText({ label: label || undefined }), true))
        fields.push(this.colors(item.color, (color) => update({ color })))
        break
      case "cone":
        fields.push(this.colors(item.color, (color) => update({ color })))
        break
      case "goal":
        fields.push(this.iconButton("rotate", m.rotate, () => update({ rotation: ((item.rotation || 0) + 90) % 360 })))
        fields.push(this.colors(item.color, (color) => update({ color })))
        break
    }
    return fields
  }

  // One size for every player in `players`, written as one step. It also
  // becomes the size of the next player placed.
  playerSizeField(players) {
    const m = this.messages
    const sizes = new Set(players.map((item) => item.size || "m"))
    const current = sizes.size === 1 ? [...sizes][0] : null
    return this.segmented(m.size, [["s", m.small], ["m", m.medium], ["l", m.large]], current, (size) => {
      this.playerSize = size
      let next = this.diagram
      for (const item of players) next = updateItem(next, item.id, { size })
      this.commit(next)
    })
  }

  segmented(label, options, selected, choose) {
    const group = element("div", { class: "fb-segmented fb-small", role: "radiogroup", "aria-label": label })
    for (const [value, title] of options) {
      group.append(element("button", {
        type: "button", role: "radio", "aria-checked": String(value === selected), text: title,
        onclick: () => { if (value !== selected) choose(value) },
      }))
    }
    return group
  }

  toggle(label, on, change) {
    const input = element("input", { type: "checkbox", checked: on, onchange: () => change(input.checked) })
    return element("label", { class: "fb-toggle" }, [input, element("span", { text: label })])
  }

  textField(label, value, maxLength, extraClass, change, primary = false) {
    const input = element("input", {
      type: "text", value: String(value), maxlength: String(maxLength), "aria-label": label,
      placeholder: label, class: extraClass, spellcheck: "false", "data-fb-primary": primary,
    })
    input.addEventListener("input", () => {
      input.setAttribute("data-fb-dirty", "")
    })
    input.addEventListener("change", () => {
      if (!input.hasAttribute("data-fb-dirty")) return
      input.removeAttribute("data-fb-dirty")
      change(input.value.trim())
    })
    return element("label", { class: "fb-field" }, [element("span", { class: "fb-field-label", text: label }), input])
  }

  colors(current, choose) {
    const m = this.messages
    const group = element("div", { class: "fb-colors", role: "radiogroup", "aria-label": m.color })
    group.append(element("button", {
      type: "button", role: "radio", class: "fb-swatch fb-swatch-auto", title: m.automatic, "aria-label": m.automatic,
      "aria-checked": String(!current), onclick: () => current && choose(undefined),
    }))
    for (const color of PALETTE) {
      const swatch = element("button", {
        type: "button", role: "radio", class: "fb-swatch", title: color, "aria-label": color,
        "aria-checked": String(current === color), onclick: () => current !== color && choose(color),
      })
      swatch.style.setProperty("--swatch", color)
      group.append(swatch)
    }
    return group
  }
}

function installStyles() {
  if (stylesInstalled) return
  stylesInstalled = true
  const style = document.createElement("style")
  style.id = "fb-editor-styles"
  style.textContent = SHEET_CSS
  document.head.append(style)
}

const SHEET_CSS = `
.fb-backdrop {
  position: fixed; inset: 0; z-index: 1000;
  display: flex; align-items: center; justify-content: center;
  padding: calc(var(--mdp-top-inset, 0px) / var(--mdp-chrome-zoom, 1) + 12px) 16px 16px;
  box-sizing: border-box;
  background: color-mix(in srgb, Canvas 55%, transparent);
  -webkit-backdrop-filter: blur(6px); backdrop-filter: blur(6px);
  overscroll-behavior: contain;
  font: 13px/1.35 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
  color: CanvasText;
  -webkit-user-select: none; user-select: none;
}
html[data-page-scrolling="true"] .fb-backdrop { padding-top: calc(var(--mdp-top-inset, 0px) / var(--mdp-chrome-zoom, 1) + 52px); }
.fb-sheet {
  --fb-sheet-bg: light-dark(#ffffff, #232325);
  --fb-sheet-line: light-dark(rgba(0,0,0,0.1), rgba(255,255,255,0.12));
  --fb-control: light-dark(rgba(0,0,0,0.05), rgba(255,255,255,0.08));
  --fb-control-hover: light-dark(rgba(0,0,0,0.09), rgba(255,255,255,0.14));
  --fb-secondary: light-dark(#6e6e73, #98989d);
  display: flex; flex-direction: column;
  width: min(1180px, 100%); max-height: 100%;
  background: var(--fb-sheet-bg);
  border: 0.5px solid var(--fb-sheet-line);
  border-radius: 14px;
  box-shadow: 0 18px 50px rgba(0,0,0,0.22), 0 2px 8px rgba(0,0,0,0.08);
  overflow: hidden; outline: none;
}
.fb-header, .fb-inspector {
  display: flex; align-items: center; gap: 8px;
  padding: 8px 10px 8px 14px; min-height: 30px;
}
.fb-header { border-bottom: 0.5px solid var(--fb-sheet-line); }
.fb-inspector { border-top: 0.5px solid var(--fb-sheet-line); flex-wrap: wrap; min-height: 32px; }
.fb-title { font-weight: 600; margin-right: 6px; white-space: nowrap; }
.fb-spacer { flex: 1; }
.fb-hint { color: var(--fb-secondary); }
.fb-body { display: flex; min-height: 0; flex: 1; }
.fb-toolbar {
  display: flex; flex-direction: column; gap: 2px; padding: 8px 6px;
  border-right: 0.5px solid var(--fb-sheet-line); overflow-y: auto;
}
.fb-header-separator { width: 0.5px; height: 18px; background: var(--fb-sheet-line); margin: 0 2px; }
.fb-tool-separator { height: 0.5px; background: var(--fb-sheet-line); margin: 5px 4px; flex: none; }
.fb-sheet button {
  font: inherit; color: inherit; border: none; background: transparent; cursor: default;
}
.fb-tool, .fb-icon-button {
  display: grid; place-items: center; width: 32px; height: 30px; border-radius: 7px; flex: none;
}
.fb-tool:hover, .fb-icon-button:hover:not(:disabled) { background: var(--fb-control-hover); }
.fb-tool[aria-pressed="true"] { background: color-mix(in srgb, ${ACCENT} 18%, transparent); color: ${ACCENT}; box-shadow: inset 0 0 0 1px color-mix(in srgb, ${ACCENT} 45%, transparent); }
.fb-icon-button:disabled { opacity: 0.35; }
.fb-destructive { color: light-dark(#d70015, #ff6961); }
.fb-done {
  padding: 4px 14px; border-radius: 7px; font-weight: 600;
  background: ${ACCENT} !important; color: #fff !important;
}
.fb-done:active { filter: brightness(0.9); }
.fb-segmented { display: inline-flex; padding: 2px; border-radius: 8px; background: var(--fb-control); gap: 1px; }
.fb-segmented button { padding: 3px 10px; border-radius: 6px; white-space: nowrap; }
.fb-segmented.fb-small button { padding: 2px 8px; font-size: 12px; }
.fb-segmented button[aria-checked="true"] { background: var(--fb-sheet-bg); box-shadow: 0 0.5px 2px rgba(0,0,0,0.18); font-weight: 500; }
.fb-segmented button:hover:not([aria-checked="true"]) { background: var(--fb-control-hover); }
.fb-canvas {
  flex: 1; min-width: 0; display: flex; align-items: center; justify-content: center;
  padding: 14px; background: light-dark(#eef1f5, #18181a); touch-action: none;
  cursor: crosshair;
}
.fb-canvas[data-tool="select"] { cursor: default; }
.fb-canvas[data-tool="text"] { cursor: text; }
.fb-canvas svg {
  display: block; width: 100%; height: auto; max-height: calc(100vh - 230px);
  aspect-ratio: var(--fb-aspect);
}
.fb-canvas .fb-item { cursor: grab; }
.fb-canvas[data-tool="run"] .fb-item, .fb-canvas[data-tool="pass"] .fb-item, .fb-canvas[data-tool="shot"] .fb-item,
.fb-canvas[data-tool="dribble"] .fb-item, .fb-canvas[data-tool="freehand"] .fb-item { cursor: crosshair; }
.fb-canvas .fb-handle { cursor: move; }
.fb-field { display: inline-flex; align-items: center; gap: 6px; }
.fb-field-label { color: var(--fb-secondary); font-size: 12px; }
.fb-field input {
  font: inherit; color: inherit; width: 140px; padding: 3px 7px; border-radius: 6px;
  border: 0.5px solid var(--fb-sheet-line); background: var(--fb-control); outline: none;
  -webkit-user-select: text; user-select: text;
}
.fb-field input:focus { box-shadow: 0 0 0 3px color-mix(in srgb, ${ACCENT} 35%, transparent); border-color: ${ACCENT}; }
.fb-field input.fb-narrow { width: 44px; text-align: center; }
.fb-field input.fb-wide { width: 220px; }
.fb-toggle { display: inline-flex; align-items: center; gap: 5px; font-size: 12px; }
.fb-colors { display: inline-flex; gap: 4px; align-items: center; }
.fb-swatch {
  width: 18px; height: 18px; border-radius: 50%; padding: 0;
  background: var(--swatch) !important; box-shadow: inset 0 0 0 0.5px rgba(0,0,0,0.25);
}
.fb-swatch-auto {
  background: conic-gradient(${TEAM_COLORS.attack} 0 33%, ${TEAM_COLORS.defense} 0 66%, ${TEAM_COLORS.neutral} 0) !important;
}
.fb-swatch[aria-checked="true"] { box-shadow: 0 0 0 2px var(--fb-sheet-bg), 0 0 0 3.5px ${ACCENT}; }
.fb-sheet button:focus-visible { outline: 2px solid ${ACCENT}; outline-offset: 1px; }
`
