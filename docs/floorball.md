# Floorball diagrams

A fenced code block with the info string `floorball` holds one tactics diagram
as JSON. Markdown Preview draws it as a rink in Read Mode, Edit Mode, Quick
Look, printing, and export, and edits it with the diagram editor (click the
diagram in Edit Mode). The JSON stays in the file; there is no separate image.

````markdown
```floorball
{
  "version": 1,
  "rink": { "layout": "half" },
  "elements": [
    { "id": "p1", "type": "player", "team": "attack", "number": 7, "x": 0.35, "y": 0.65 },
    { "id": "b1", "type": "ball", "x": 0.37, "y": 0.68 }
  ],
  "paths": [
    { "id": "r1", "type": "pass", "points": [[0.35, 0.65], [0.6, 0.4]] }
  ]
}
```
````

An empty fence is an empty full rink. The editor writes one element or path
per line, so changes diff cleanly.

## Coordinates

`x` and `y` run from 0 to 1 across the visible rink: (0, 0) is the top left,
(1, 1) the bottom right. The full and blank layouts are twice as wide as they
are tall (a 40 m × 20 m rink); the half layout is square and shows the
right-hand, attacking half. Switching layout in the editor converts positions
so everything stays where it was on the rink. Values outside 0–1 are clamped.

## Top level

| Key        | Value                                                         |
| ---------- | ------------------------------------------------------------- |
| `version`  | `1`. Missing means 1; a higher version is shown as an error.  |
| `rink`     | `{ "layout": "full" \| "half" \| "blank" }`, default `full`.  |
| `elements` | Array of elements, below.                                     |
| `paths`    | Array of paths, below.                                        |

## Elements

Every element has `id` (letters, digits, `-`, `_`; generated when missing or
duplicated), `type`, `x`, and `y`. `color` (`#rgb` or `#rrggbb`) is optional
on all of them; other values are ignored.

| `type`   | Other keys                                                                      |
| -------- | ------------------------------------------------------------------------------- |
| `player` | `team`: `attack` (filled, blue), `defense` (ring, red), `neutral` (amber); `role`: `goalkeeper` (square); `number` (up to 3 characters, drawn inside); `label` (drawn below); `size`: `s`, `m` (default), `l` |
| `ball`   | —                                                                               |
| `cone`   | —                                                                               |
| `goal`   | `rotation`: 0, 90, 180, or 270 (the direction the opening faces)                |
| `marker` | `label`                                                                         |
| `text`   | `text`; `size`: `s`, `m` (default), `l`. Long text wraps and is cut after 6 lines. |

## Paths

Every path has `id`, `type`, and `points`: two or more `[x, y]` pairs. Two
points with a `control` point make a curve; more points make a smooth freehand
line.

| `type`    | Drawn as                     |
| --------- | ---------------------------- |
| `run`     | solid arrow                  |
| `pass`    | dashed arrow                 |
| `shot`    | double-line arrow            |
| `dribble` | wavy arrow                   |
| `line`    | solid line, no arrowhead     |

`dashed` and `arrow` (booleans) override the type's default; `color` as above.

## Compatibility

Keys and element or path types the app does not know are kept, unchanged and
undrawn, when the editor saves a version 1 diagram. A diagram with a higher
`version` is never rewritten: it shows an error and keeps its source. Labels
are drawn as text, never as markup. A diagram that is not valid JSON shows an
error above its unchanged source; fix it in the Markdown source.
