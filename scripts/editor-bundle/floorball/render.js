// Draws a floorball diagram as an SVG string. Pure string building, so it
// runs without a DOM (JavaScriptCore renders read mode from Swift).
//
// Every value that reaches the markup is either a number this module
// formats, a color that passed sanitizeColor, an id that passed the model's
// id pattern, or text run through escapeXML. Nothing from a document is ever
// emitted raw.

import { LAYOUTS, LIMITS, hasArrow, isDashed, sanitizeColor, tryParse } from "./model.js"

export const TEAM_COLORS = { attack: "#2563eb", defense: "#dc2626", neutral: "#d97706" }
const CONE_COLOR = "#f97316"
const MARKER_COLOR = "#7c3aed"
// Light-mode values of the theme variables, for an SVG shown without the
// page stylesheet (copied out, or a page that has none).
const FALLBACK = { surface: "#f5f8fc", board: "#36557f", line: "#8aa2c4", goal: "#d64545", ink: "#1d2733" }
const PADDING = 6
// Player radius per size. Large is the size players had before sizes
// existed; medium, the default, sits better against a 40 m rink.
export const PLAYER_RADIUS = { s: 4.5, m: 6, l: 9 }

export function escapeXML(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character])
}

const n = (value) => {
  const rounded = Math.round(value * 100) / 100
  return Object.is(rounded, -0) ? "0" : String(rounded)
}

export function layoutSize(diagram) {
  return LAYOUTS[diagram.rink.layout] || LAYOUTS.full
}

export function viewBox(diagram) {
  const { width, height } = layoutSize(diagram)
  return { x: -PADDING, y: -PADDING, width: width + PADDING * 2, height: height + PADDING * 2 }
}

// ---------------------------------------------------------------------------
// Rink
// ---------------------------------------------------------------------------

// One end of the rink, in full-rink units, mirrored for the right-hand end.
// Goal line 3.5 m from the end boards; goal area 4 m × 5 m and goalkeeper's
// area 1 m × 2.5 m, both starting behind the goal; goal opening 1.6 m.
function rinkEnd(mirror) {
  const x = (value) => mirror ? 400 - value : value
  const rect = (x1, y1, x2, y2, cls, fill) => {
    const left = Math.min(x(x1), x(x2))
    return `<rect class="${cls}" x="${n(left)}" y="${n(y1)}" width="${n(Math.abs(x(x2) - x(x1)))}" height="${n(y2 - y1)}"${fill}/>`
  }
  const lineAttributes = ` fill="none" stroke="${FALLBACK.line}" stroke-width="1.2"`
  return [
    rect(28.5, 75, 68.5, 125, "fb-line", lineAttributes),
    rect(28.5, 87.5, 38.5, 112.5, "fb-crease", ` fill="${FALLBACK.line}" fill-opacity="0.18" stroke="${FALLBACK.line}" stroke-width="1.2"`),
    rect(28.5, 92, 35, 108, "fb-goal", ` fill="none" stroke="${FALLBACK.goal}" stroke-width="1.6"`),
    `<line class="fb-goal-line" x1="${x(35)}" y1="92" x2="${x(35)}" y2="108" stroke="${FALLBACK.goal}" stroke-width="1"/>`,
    faceOff(x(35), 15),
    faceOff(x(35), 185),
  ].join("")
}

function faceOff(x, y) {
  return `<path class="fb-mark" d="M${n(x - 3)} ${n(y)}H${n(x + 3)}M${n(x)} ${n(y - 3)}V${n(y + 3)}" stroke="${FALLBACK.line}" stroke-width="1.2"/>`
}

function rink(diagram) {
  const layout = diagram.rink.layout
  const { width, height } = layoutSize(diagram)
  const boardAttributes = `fill="${FALLBACK.surface}" stroke="${FALLBACK.board}" stroke-width="2.5"`
  if (layout === "blank") {
    return `<rect class="fb-surface" x="0" y="0" width="${width}" height="${height}" rx="12" ${boardAttributes}/>`
  }
  if (layout === "half") {
    // The attacking half: boards on three sides, the centre line on the
    // fourth, drawn as a rink marking rather than a board.
    return [
      `<path class="fb-surface" d="M0 0H170A30 30 0 0 1 200 30V170A30 30 0 0 1 170 200H0Z" ${boardAttributes} stroke-opacity="0"/>`,
      `<path class="fb-boards" d="M0 0H170A30 30 0 0 1 200 30V170A30 30 0 0 1 170 200H0" fill="none" stroke="${FALLBACK.board}" stroke-width="2.5"/>`,
      `<g transform="translate(-200 0)">${rinkEnd(true)}</g>`,
      `<line class="fb-line" x1="0" y1="0" x2="0" y2="200" stroke="${FALLBACK.line}" stroke-width="1.5"/>`,
      `<circle class="fb-spot" cx="0" cy="100" r="2.5" fill="${FALLBACK.line}"/>`,
      faceOff(0, 15),
      faceOff(0, 185),
    ].join("")
  }
  return [
    `<rect class="fb-surface" x="0" y="0" width="400" height="200" rx="30" ${boardAttributes}/>`,
    `<line class="fb-line" x1="200" y1="0" x2="200" y2="200" stroke="${FALLBACK.line}" stroke-width="1.5"/>`,
    `<circle class="fb-spot" cx="200" cy="100" r="2.5" fill="${FALLBACK.line}"/>`,
    faceOff(200, 15),
    faceOff(200, 185),
    rinkEnd(false),
    rinkEnd(true),
  ].join("")
}

// ---------------------------------------------------------------------------
// Elements
// ---------------------------------------------------------------------------

function textLines(text, perLine, maxLines) {
  const lines = []
  for (const paragraph of String(text).split(/\n/)) {
    let line = ""
    for (const word of paragraph.split(/\s+/).filter(Boolean)) {
      // A word longer than a line breaks where it must.
      for (let rest = word; rest.length; ) {
        const room = line ? perLine - line.length - 1 : perLine
        if (rest.length <= room) {
          line = line ? line + " " + rest : rest
          rest = ""
        } else if (line) {
          lines.push(line)
          line = ""
        } else {
          lines.push(rest.slice(0, perLine))
          rest = rest.slice(perLine)
        }
      }
    }
    lines.push(line)
  }
  if (lines.length > maxLines) {
    lines.length = maxLines
    lines[maxLines - 1] = lines[maxLines - 1].slice(0, perLine - 1) + "…"
  }
  return lines
}

// Text with a surface-coloured halo, so it stays readable over lines.
function haloText(x, y, size, lines, { color = null, weight = "" } = {}) {
  const lineHeight = size * 1.2
  const top = y - (lines.length - 1) * lineHeight / 2
  const spans = lines.map((line, index) =>
    `<tspan x="${n(x)}" y="${n(top + index * lineHeight)}">${escapeXML(line)}</tspan>`).join("")
  const weightAttribute = weight ? ` font-weight="${weight}"` : ""
  return `<text class="${color ? "fb-text-custom" : "fb-text"}" font-size="${n(size)}"${weightAttribute} text-anchor="middle" dominant-baseline="central" fill="${color || FALLBACK.ink}" stroke="${FALLBACK.surface}" stroke-width="${n(size / 4)}" stroke-linejoin="round" paint-order="stroke">${spans}</text>`
}

function player(element, x, y) {
  const color = element.color || TEAM_COLORS[element.team] || TEAM_COLORS.attack
  const number = element.number === undefined ? "" : String(element.number)
  const outlined = element.team === "defense"
  const fill = outlined ? FALLBACK.surface : color
  const ink = outlined ? color : "#ffffff"
  const r = PLAYER_RADIUS[element.size] || PLAYER_RADIUS.m
  // Everything inside the symbol scales with it, from the radius its
  // proportions were drawn at.
  const k = r / PLAYER_RADIUS.l
  const stroke = n(Math.max(1.4, 2 * k))
  const shape = element.role === "goalkeeper"
    ? `<rect class="${outlined ? "fb-player-outline" : ""}" x="${n(x - r)}" y="${n(y - r)}" width="${n(r * 2)}" height="${n(r * 2)}" rx="${n(4 * k)}" fill="${fill}" stroke="${color}" stroke-width="${stroke}"/>`
      + `<rect x="${n(x - r + 3 * k)}" y="${n(y - r + 3 * k)}" width="${n(r * 2 - 6 * k)}" height="${n(r * 2 - 6 * k)}" rx="${n(2 * k)}" fill="none" stroke="${ink}" stroke-width="${n(0.8 * k)}" stroke-opacity="0.7"/>`
    : `<circle class="${outlined ? "fb-player-outline" : ""}" cx="${n(x)}" cy="${n(y)}" r="${r}" fill="${fill}" stroke="${color}" stroke-width="${stroke}"/>`
  const fontSize = (number.length > 2 ? 7 : number.length > 1 ? 8.5 : 10) * k
  const label = number
    ? `<text x="${n(x)}" y="${n(y)}" font-size="${n(fontSize)}" font-weight="700" text-anchor="middle" dominant-baseline="central" fill="${ink}">${escapeXML(number)}</text>`
    : ""
  const name = element.label ? haloText(x, y + r + 7, 8, textLines(element.label, 18, 1)) : ""
  return shape + label + name
}

function ball(x, y) {
  return `<circle class="fb-ball" cx="${n(x)}" cy="${n(y)}" r="3.4" fill="#ffffff" stroke="#3a3a3a" stroke-width="0.9"/>`
    + [[-1.2, -1], [1.3, -0.6], [0, 1.4]].map(([dx, dy]) =>
      `<circle cx="${n(x + dx)}" cy="${n(y + dy)}" r="0.55" fill="#3a3a3a"/>`).join("")
}

function cone(element, x, y) {
  const color = element.color || CONE_COLOR
  return `<path d="M${n(x)} ${n(y - 6)}L${n(x + 5)} ${n(y + 4)}H${n(x - 5)}Z" fill="${color}" stroke="#7c2d12" stroke-width="0.8" stroke-linejoin="round"/>`
    + `<path d="M${n(x - 2.6)} ${n(y - 0.8)}H${n(x + 2.6)}" stroke="#ffffff" stroke-width="1.4"/>`
    + `<rect x="${n(x - 6.5)}" y="${n(y + 3.6)}" width="13" height="1.8" rx="0.9" fill="${color}" stroke="#7c2d12" stroke-width="0.6"/>`
}

function goal(element, x, y) {
  // Opening faces the rotation: 0 = right, 90 = down, 180 = left, 270 = up.
  const rotation = element.rotation || 0
  return `<g transform="translate(${n(x)} ${n(y)}) rotate(${rotation})">`
    + `<rect x="-3.25" y="-8" width="6.5" height="16" fill="${FALLBACK.surface}" fill-opacity="0.7" stroke="${element.color || FALLBACK.goal}" stroke-width="1.6" class="${element.color ? "" : "fb-goal"}"/>`
    + `<path d="M-3.25 -8V8M-1 -8V8M1.25 -8V8" stroke="${element.color || FALLBACK.goal}" stroke-width="0.4" stroke-opacity="0.6"/>`
    + `</g>`
}

function marker(element, x, y) {
  const color = element.color || MARKER_COLOR
  const label = element.label ? haloText(x, y + 13, 8, textLines(element.label, 18, 1)) : ""
  return `<path d="M${n(x)} ${n(y - 6)}L${n(x + 6)} ${n(y)}L${n(x)} ${n(y + 6)}L${n(x - 6)} ${n(y)}Z" fill="${color}" stroke="#ffffff" stroke-width="1.2" stroke-linejoin="round"/>` + label
}

const TEXT_SIZE = { s: 8, m: 11, l: 15 }

function textElement(element, x, y) {
  const size = TEXT_SIZE[element.size] || TEXT_SIZE.m
  const lines = textLines(element.text || "", Math.max(8, Math.round(260 / size)), 6)
  return haloText(x, y, size, lines, { color: element.color, weight: "600" })
}

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

// The path as a polyline in rendering units: straight, a quadratic curve
// through its control point, or a smooth curve through every point.
export function samplePath(path, size) {
  const points = path.points.map(([x, y]) => [x * size.width, y * size.height])
  if (points.length === 2 && path.control) {
    const [a, b] = points
    const c = [path.control[0] * size.width, path.control[1] * size.height]
    const result = []
    for (let i = 0; i <= 24; i++) {
      const t = i / 24
      const u = 1 - t
      result.push([u * u * a[0] + 2 * u * t * c[0] + t * t * b[0], u * u * a[1] + 2 * u * t * c[1] + t * t * b[1]])
    }
    return result
  }
  if (points.length <= 2) return points
  // Catmull–Rom through the points.
  const result = [points[0]]
  for (let i = 0; i < points.length - 1; i++) {
    const p0 = points[Math.max(0, i - 1)]
    const p1 = points[i]
    const p2 = points[i + 1]
    const p3 = points[Math.min(points.length - 1, i + 2)]
    for (let step = 1; step <= 6; step++) {
      const t = step / 6
      const t2 = t * t
      const t3 = t2 * t
      result.push([0, 1].map((axis) => 0.5 * ((2 * p1[axis]) + (-p0[axis] + p2[axis]) * t
        + (2 * p0[axis] - 5 * p1[axis] + 4 * p2[axis] - p3[axis]) * t2
        + (-p0[axis] + 3 * p1[axis] - 3 * p2[axis] + p3[axis]) * t3)))
    }
  }
  return result
}

function length(points) {
  let total = 0
  for (let i = 1; i < points.length; i++) total += Math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1])
  return total
}

// Cuts `amount` off the end so the line stops at the base of the arrowhead.
function trimEnd(points, amount) {
  const result = points.slice()
  let remaining = amount
  while (result.length > 1) {
    const end = result[result.length - 1]
    const previous = result[result.length - 2]
    const segment = Math.hypot(end[0] - previous[0], end[1] - previous[1])
    if (segment > remaining) {
      const t = (segment - remaining) / segment
      result[result.length - 1] = [previous[0] + (end[0] - previous[0]) * t, previous[1] + (end[1] - previous[1]) * t]
      return result
    }
    remaining -= segment
    result.pop()
  }
  return result
}

// A zigzag along the polyline for a dribble, settling straight at the end.
function wave(points, amplitude, wavelength) {
  const total = length(points)
  const result = [points[0]]
  let travelled = 0
  for (let i = 1; i < points.length; i++) {
    const [ax, ay] = points[i - 1]
    const [bx, by] = points[i]
    const segment = Math.hypot(bx - ax, by - ay)
    if (!segment) continue
    const steps = Math.max(1, Math.ceil(segment / (wavelength / 6)))
    for (let step = 1; step <= steps; step++) {
      const t = step / steps
      const distance = travelled + segment * t
      const fade = Math.min(1, Math.max(0, (total - distance) / wavelength), distance / (wavelength / 2))
      const offset = Math.sin(distance / wavelength * Math.PI * 2) * amplitude * fade
      result.push([ax + (bx - ax) * t - (by - ay) / segment * offset, ay + (by - ay) * t + (bx - ax) / segment * offset])
    }
    travelled += segment
  }
  return result
}

function polyline(points) {
  return points.map(([x, y], index) => (index ? "L" : "M") + n(x) + " " + n(y)).join("")
}

function arrowhead(points, size, color, cls) {
  if (points.length < 2) return ""
  const tip = points[points.length - 1]
  // Direction from a point a little way back, so a curve's last tiny
  // segment cannot twist the head.
  let base = points[points.length - 2]
  for (let i = points.length - 2; i >= 0; i--) {
    base = points[i]
    if (Math.hypot(tip[0] - base[0], tip[1] - base[1]) >= size) break
  }
  const angle = Math.atan2(tip[1] - base[1], tip[0] - base[0])
  const corner = (side) => [tip[0] - size * Math.cos(angle) + side * size * 0.55 * Math.sin(angle),
    tip[1] - size * Math.sin(angle) - side * size * 0.55 * Math.cos(angle)]
  const [left, right] = [corner(1), corner(-1)]
  return `<path class="${cls}" d="M${n(tip[0])} ${n(tip[1])}L${n(left[0])} ${n(left[1])}L${n(right[0])} ${n(right[1])}Z" fill="${color}"/>`
}

const PATH_STYLE = {
  run: { width: 1.8, head: 7 },
  pass: { width: 1.6, head: 7 },
  shot: { width: 4.6, head: 10 },
  dribble: { width: 1.6, head: 7 },
  line: { width: 1.8, head: 7 },
}

export function pathMarkup(path, size, interactive = false) {
  const style = PATH_STYLE[path.type] || PATH_STYLE.run
  const custom = path.color
  const color = custom || FALLBACK.ink
  const strokeClass = custom ? "" : "fb-ink-stroke"
  const fillClass = custom ? "" : "fb-ink-fill"
  let points = samplePath(path, size)
  if (length(points) < 0.5) return ""
  const arrow = hasArrow(path)
  const head = arrow ? arrowhead(points, style.head, color, fillClass) : ""
  if (arrow) points = trimEnd(points, style.head * 0.8)
  if (path.type === "dribble") points = wave(points, 2.6, 9)
  const dash = isDashed(path) ? ` stroke-dasharray="${path.type === "shot" ? "9 5" : "6 4"}"` : ""
  const d = polyline(points)
  let body = `<path class="${strokeClass}" d="${d}" fill="none" stroke="${color}" stroke-width="${style.width}" stroke-linecap="round" stroke-linejoin="round"${dash}/>`
  if (path.type === "shot") {
    // A shot is a double line: the surface colour cuts the thick stroke.
    body += `<path class="fb-surface-stroke" d="${d}" fill="none" stroke="${FALLBACK.surface}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"${dash}/>`
  }
  const hit = interactive
    ? `<path class="fb-hit" d="${polyline(samplePath(path, size))}" fill="none" stroke="transparent" stroke-width="12" stroke-linecap="round"/>`
    : ""
  return body + head + hit
}

// ---------------------------------------------------------------------------
// Diagram
// ---------------------------------------------------------------------------

export function elementMarkup(element, size) {
  const x = element.x * size.width
  const y = element.y * size.height
  switch (element.type) {
    case "player": return player(element, x, y)
    case "ball": return ball(x, y)
    case "cone": return cone(element, x, y)
    case "goal": return goal(element, x, y)
    case "marker": return marker(element, x, y)
    case "text": return textElement(element, x, y)
    default: return ""
  }
}

// Draw order: paths under the players they start from, the ball on top.
const ELEMENT_ORDER = { goal: 0, cone: 1, marker: 2, text: 3, player: 4, ball: 5 }

// `options.label` is the accessible name; `options.interactive` adds the
// `data-fb-id` hooks and wide hit areas the editor uses.
export function renderSVG(diagram, options = {}) {
  const size = layoutSize(diagram)
  const box = viewBox(diagram)
  const interactive = !!options.interactive
  const idAttribute = (item) => interactive ? ` data-fb-id="${escapeXML(item.id)}"` : ""
  const paths = diagram.paths.filter((path) => !path.unknown).slice(0, LIMITS.paths)
  const elements = diagram.elements.filter((element) => !element.unknown).slice(0, LIMITS.elements)
    .map((element, index) => ({ element, index }))
    .sort((a, b) => (ELEMENT_ORDER[a.element.type] - ELEMENT_ORDER[b.element.type]) || a.index - b.index)
    .map(({ element }) => element)
  const label = escapeXML(options.label || "Floorball diagram")
  const parts = [
    `<svg class="fb-diagram" xmlns="http://www.w3.org/2000/svg" viewBox="${box.x} ${box.y} ${box.width} ${box.height}" role="img" aria-label="${label}" font-family="-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif">`,
    `<title>${label}</title>`,
    `<g class="fb-rink">${rink(diagram)}</g>`,
    `<g class="fb-paths">`,
    ...paths.map((path) => `<g class="fb-item fb-path"${idAttribute(path)}>${pathMarkup(path, size, interactive)}</g>`),
    `</g><g class="fb-elements">`,
    ...elements.map((element) => `<g class="fb-item fb-${element.type}"${idAttribute(element)}>${elementMarkup(element, size)}</g>`),
    `</g>`,
    options.overlay || "",
    `</svg>`,
  ]
  return parts.join("")
}

// Read mode: fence source in, SVG or a failure code out.
export function renderSource(source, options = {}) {
  const parsed = tryParse(source)
  if (!parsed.ok) return { ok: false, code: parsed.code, detail: parsed.detail }
  const diagram = parsed.diagram
  return {
    ok: true,
    svg: renderSVG(diagram, options),
    layout: diagram.rink.layout,
    width: viewBox(diagram).width,
    height: viewBox(diagram).height,
  }
}

export { sanitizeColor }
