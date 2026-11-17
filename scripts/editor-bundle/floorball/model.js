// Floorball tactics diagrams: the versioned data model stored in a
// ```floorball fence. Pure functions only — no DOM — so the same module runs
// in the editor page, in the read-mode renderer under JavaScriptCore, and in
// tests.
//
// Coordinates are normalized to the visible rink area: x and y run from 0 to
// 1 across the layout's width and height, so resizing never moves anything.
// The source is untrusted: parse() validates every field it understands and
// keeps fields and element types it does not, so a newer document survives a
// round trip through this editor unchanged.

export const VERSION = 1

export const LAYOUTS = {
  // Rendering units: ten per metre of a 40 m × 20 m rink.
  full: { width: 400, height: 200 },
  half: { width: 200, height: 200 },
  blank: { width: 400, height: 200 },
}

export const ELEMENT_TYPES = ["player", "ball", "cone", "goal", "marker", "text"]
export const PATH_TYPES = ["run", "pass", "shot", "dribble", "line"]
export const TEAMS = ["attack", "defense", "neutral"]
// Sizes of players and text: small, medium (the default), large.
export const SIZES = ["s", "m", "l"]

// The sizes a document may reach before the rest is kept but not drawn.
export const LIMITS = {
  elements: 500,
  paths: 500,
  points: 400,
  number: 3,
  label: 40,
  text: 400,
}

const ID_PREFIX = { player: "p", ball: "b", cone: "c", goal: "g", marker: "m", text: "t", path: "r" }
const ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/
const COLOR_PATTERN = /^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/

export class FloorballError extends Error {
  constructor(code, detail = "") {
    super(detail || code)
    this.code = code
  }
}

export function sanitizeColor(value) {
  return typeof value === "string" && COLOR_PATTERN.test(value) ? value.toLowerCase() : null
}

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value)
const finite = (value) => typeof value === "number" && Number.isFinite(value)
const clamp01 = (value) => Math.min(1, Math.max(0, value))
export const round = (value) => Math.round(value * 1000) / 1000

function coordinate(value, fallback = 0.5) {
  return finite(value) ? round(clamp01(value)) : fallback
}

function cleanText(value, limit) {
  if (typeof value === "number" && Number.isFinite(value)) value = String(value)
  if (typeof value !== "string") return ""
  // Control characters other than line breaks never reach the drawing.
  return value.replace(/[\u0000-\u0009\u000b-\u001f\u007f]/g, "").slice(0, limit)
}

function point(value) {
  if (Array.isArray(value) && value.length >= 2 && finite(value[0]) && finite(value[1])) {
    return [coordinate(value[0]), coordinate(value[1])]
  }
  if (isObject(value) && finite(value.x) && finite(value.y)) {
    return [coordinate(value.x), coordinate(value.y)]
  }
  return null
}

// A fresh id that no element or path in `diagram` uses yet.
export function nextId(diagram, kind) {
  const prefix = ID_PREFIX[kind] || "e"
  const used = new Set([...diagram.elements, ...diagram.paths].map((item) => item.id))
  let highest = 0
  for (const id of used) {
    const match = typeof id === "string" && id.startsWith(prefix) ? /^\d+$/.exec(id.slice(prefix.length)) : null
    if (match) highest = Math.max(highest, Number(match[0]))
  }
  let candidate = highest + 1
  while (used.has(prefix + candidate)) candidate++
  return prefix + candidate
}

// Validates one element. Unknown types come back untouched with `unknown`
// set, so they are written back but never drawn or edited.
function normalizeElement(raw) {
  if (!isObject(raw)) return null
  const type = raw.type
  if (!ELEMENT_TYPES.includes(type)) return { ...raw, unknown: true }
  const element = { ...raw, type, x: coordinate(raw.x), y: coordinate(raw.y) }
  const color = sanitizeColor(raw.color)
  if (color) element.color = color
  else delete element.color
  switch (type) {
    case "player": {
      element.team = TEAMS.includes(raw.team) ? raw.team : "attack"
      if (raw.role === "goalkeeper") element.role = "goalkeeper"
      else delete element.role
      if (raw.number !== undefined && raw.number !== null && raw.number !== "") {
        const number = cleanText(raw.number, LIMITS.number).replace(/\s+/g, "")
        // Plain shirt numbers stay JSON numbers; "07" or "C" stay text.
        if (number) element.number = /^(?:0|[1-9]\d{0,2})$/.test(number) ? Number(number) : number
        else delete element.number
      } else delete element.number
      setOptionalText(element, "label", raw.label, LIMITS.label)
      setSize(element, raw.size)
      break
    }
    case "goal":
      element.rotation = [0, 90, 180, 270].includes(raw.rotation) ? raw.rotation : 0
      if (element.rotation === 0) delete element.rotation
      break
    case "marker":
      setOptionalText(element, "label", raw.label, LIMITS.label)
      break
    case "text":
      element.text = cleanText(raw.text, LIMITS.text)
      setSize(element, raw.size)
      break
  }
  return element
}

// Medium is the default, so it is left out of the source.
function setSize(element, value) {
  if (SIZES.includes(value) && value !== "m") element.size = value
  else delete element.size
}

function setOptionalText(element, key, value, limit) {
  const text = cleanText(value, limit).replace(/\s+/g, " ").trim()
  if (text) element[key] = text
  else delete element[key]
}

function normalizePath(raw) {
  if (!isObject(raw) || !PATH_TYPES.includes(raw.type)) return isObject(raw) ? { ...raw, unknown: true } : null
  const points = Array.isArray(raw.points) ? raw.points.slice(0, LIMITS.points).map(point).filter(Boolean) : []
  if (points.length < 2) return { ...raw, unknown: true }
  const path = { ...raw, points }
  const control = points.length === 2 ? point(raw.control) : null
  if (control) path.control = control
  else delete path.control
  const color = sanitizeColor(raw.color)
  if (color) path.color = color
  else delete path.color
  if (typeof raw.dashed === "boolean" && raw.dashed !== defaultDashed(raw.type)) path.dashed = raw.dashed
  else delete path.dashed
  if (typeof raw.arrow === "boolean" && raw.arrow !== defaultArrow(raw.type)) path.arrow = raw.arrow
  else delete path.arrow
  return path
}

export const defaultDashed = (type) => type === "pass"
export const defaultArrow = (type) => type !== "line"
export const isDashed = (path) => typeof path.dashed === "boolean" ? path.dashed : defaultDashed(path.type)
export const hasArrow = (path) => typeof path.arrow === "boolean" ? path.arrow : defaultArrow(path.type)

export function createDiagram(layout = "full") {
  return { version: VERSION, rink: { layout: LAYOUTS[layout] ? layout : "full" }, elements: [], paths: [] }
}

// Parses fence source into a diagram. Throws FloorballError with code
// "invalid-json", "not-object", or "unsupported-version". An empty fence is a
// new, empty diagram.
export function parse(source) {
  const text = String(source ?? "")
  if (!text.trim()) return createDiagram()
  let raw
  try {
    raw = JSON.parse(text)
  } catch (error) {
    throw new FloorballError("invalid-json", String(error && error.message || error))
  }
  if (!isObject(raw)) throw new FloorballError("not-object")
  const version = raw.version === undefined ? VERSION : raw.version
  if (!Number.isInteger(version) || version < 1 || version > VERSION) {
    throw new FloorballError("unsupported-version", String(raw.version))
  }
  const rink = isObject(raw.rink) ? { ...raw.rink } : {}
  rink.layout = LAYOUTS[rink.layout] ? rink.layout : "full"
  const diagram = { ...raw, version, rink, elements: [], paths: [] }
  const seen = new Set()
  const claim = (item, kind) => {
    if (item.unknown) return item
    if (typeof item.id !== "string" || !ID_PATTERN.test(item.id) || seen.has(item.id)) {
      item.id = nextId(diagram, kind)
    }
    seen.add(item.id)
    return item
  }
  for (const entry of Array.isArray(raw.elements) ? raw.elements : []) {
    const element = normalizeElement(entry)
    if (element) diagram.elements.push(claim(element, element.type))
  }
  for (const entry of Array.isArray(raw.paths) ? raw.paths : []) {
    const path = normalizePath(entry)
    if (path) diagram.paths.push(claim(path, "path"))
  }
  return diagram
}

// Like parse(), but reports failure as a value.
export function tryParse(source) {
  try {
    return { ok: true, diagram: parse(source) }
  } catch (error) {
    return { ok: false, code: error instanceof FloorballError ? error.code : "invalid", detail: String(error && error.message || error) }
  }
}

const ELEMENT_KEY_ORDER = ["id", "type", "team", "role", "number", "label", "text", "size", "rotation", "color", "x", "y"]
const PATH_KEY_ORDER = ["id", "type", "points", "control", "dashed", "arrow", "color"]

function ordered(item, order) {
  const result = {}
  for (const key of order) if (item[key] !== undefined) result[key] = item[key]
  for (const key of Object.keys(item)) {
    if (key !== "unknown" && result[key] === undefined && item[key] !== undefined) result[key] = item[key]
  }
  return result
}

// Readable, diff-friendly JSON: one element or path per line.
export function serialize(diagram) {
  const top = ordered({ ...diagram, version: VERSION, elements: undefined, paths: undefined }, ["version", "rink"])
  const lines = ["{"]
  const entries = Object.entries(top)
  entries.push(["elements", diagram.elements.map((item) => item.unknown ? ordered(item, []) : ordered(item, ELEMENT_KEY_ORDER))])
  entries.push(["paths", diagram.paths.map((item) => item.unknown ? ordered(item, []) : ordered(item, PATH_KEY_ORDER))])
  entries.forEach(([key, value], index) => {
    const comma = index < entries.length - 1 ? "," : ""
    if ((key === "elements" || key === "paths") && value.length) {
      lines.push(`  ${JSON.stringify(key)}: [`)
      value.forEach((item, itemIndex) => {
        lines.push(`    ${compact(item)}${itemIndex < value.length - 1 ? "," : ""}`)
      })
      lines.push(`  ]${comma}`)
    } else {
      lines.push(`  ${JSON.stringify(key)}: ${compact(value)}${comma}`)
    }
  })
  lines.push("}")
  return lines.join("\n")
}

// JSON.stringify with a space after separators, on one line.
function compact(value) {
  if (Array.isArray(value)) return "[" + value.map(compact).join(", ") + "]"
  if (isObject(value)) {
    return "{ " + Object.entries(value).filter(([, item]) => item !== undefined)
      .map(([key, item]) => JSON.stringify(key) + ": " + compact(item)).join(", ") + " }"
  }
  return JSON.stringify(value) ?? "null"
}

export function clone(diagram) {
  return JSON.parse(JSON.stringify(diagram))
}

// ---------------------------------------------------------------------------
// Editing operations. Each returns a new diagram and leaves its input alone.
// ---------------------------------------------------------------------------

export function findItem(diagram, id) {
  return diagram.elements.find((item) => item.id === id) || diagram.paths.find((item) => item.id === id) || null
}

export function addElement(diagram, element) {
  const next = clone(diagram)
  const normalized = normalizeElement(element)
  normalized.id = nextId(next, normalized.type)
  next.elements.push(normalized)
  return { diagram: next, id: normalized.id }
}

export function addPath(diagram, path) {
  const next = clone(diagram)
  const normalized = normalizePath(path)
  if (!normalized || normalized.unknown) return { diagram, id: null }
  normalized.id = nextId(next, "path")
  next.paths.push(normalized)
  return { diagram: next, id: normalized.id }
}

// Applies `changes` to one item, revalidating it so a property panel can
// never write a value the parser would reject.
export function updateItem(diagram, id, changes) {
  const next = clone(diagram)
  const merge = (item) => {
    const merged = { ...item, ...changes, id }
    for (const [key, value] of Object.entries(changes)) if (value === undefined) delete merged[key]
    return merged
  }
  const index = next.elements.findIndex((item) => item.id === id)
  if (index >= 0) {
    next.elements[index] = normalizeElement(merge(next.elements[index]))
    return next
  }
  const pathIndex = next.paths.findIndex((item) => item.id === id)
  if (pathIndex >= 0) {
    const updated = normalizePath(merge(next.paths[pathIndex]))
    if (updated && !updated.unknown) next.paths[pathIndex] = updated
    return next
  }
  return diagram
}

export function moveItems(diagram, ids, dx, dy) {
  const next = clone(diagram)
  const wanted = new Set(ids)
  for (const element of next.elements) {
    if (!wanted.has(element.id) || element.unknown) continue
    element.x = coordinate(element.x + dx)
    element.y = coordinate(element.y + dy)
  }
  for (const path of next.paths) {
    if (!wanted.has(path.id) || path.unknown) continue
    path.points = path.points.map(([x, y]) => [coordinate(x + dx), coordinate(y + dy)])
    if (path.control) path.control = [coordinate(path.control[0] + dx), coordinate(path.control[1] + dy)]
  }
  return next
}

export function deleteItems(diagram, ids) {
  const wanted = new Set(ids)
  const next = clone(diagram)
  next.elements = next.elements.filter((item) => !wanted.has(item.id))
  next.paths = next.paths.filter((item) => !wanted.has(item.id))
  return next
}

// Copies `ids`, offset so the copies sit beside the originals.
export function duplicateItems(diagram, ids, offset = 0.03) {
  let next = clone(diagram)
  const created = []
  for (const id of ids) {
    const item = findItem(next, id)
    if (!item || item.unknown) continue
    const copy = clone(item)
    if (next.paths.includes(item)) {
      copy.id = nextId(next, "path")
      next.paths.push(copy)
    } else {
      copy.id = nextId(next, copy.type)
      next.elements.push(copy)
    }
    created.push(copy.id)
  }
  next = moveItems(next, created, offset, offset)
  return { diagram: next, ids: created }
}

// Switches the rink layout, keeping everything where it was on the rink: the
// half rink is the right-hand (attacking) half of the full rink.
export function setLayout(diagram, layout) {
  const from = diagram.rink.layout
  if (!LAYOUTS[layout] || from === layout) return diagram
  const next = clone(diagram)
  next.rink.layout = layout
  const toHalf = from !== "half" && layout === "half"
  const fromHalf = from === "half" && layout !== "half"
  if (!toHalf && !fromHalf) return next
  const mapX = (x) => coordinate(toHalf ? (x - 0.5) * 2 : 0.5 + x / 2)
  for (const element of next.elements) {
    if (!element.unknown) element.x = mapX(element.x)
  }
  for (const path of next.paths) {
    if (path.unknown) continue
    path.points = path.points.map(([x, y]) => [mapX(x), y])
    if (path.control) path.control = [mapX(path.control[0]), path.control[1]]
  }
  return next
}

// The next free shirt number for a team, so placing players numbers them.
export function nextNumber(diagram, team) {
  const used = new Set(diagram.elements
    .filter((item) => item.type === "player" && item.team === team && item.role !== "goalkeeper")
    .map((item) => String(item.number)))
  let number = 1
  while (used.has(String(number))) number++
  return number
}
