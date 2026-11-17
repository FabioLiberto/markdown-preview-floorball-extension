# Floorball Training — Transition Week

Two floorball diagrams, stored as `floorball` code fences. In the app they draw
as rinks; in Edit Mode click a diagram (or **Edit Diagram** in Read Mode) to
change it with the graphical editor. **Format › Insert Floorball Diagram** adds
a new one. Show the Markdown source to see the JSON behind each drawing.

## Tactical play: 3 vs 2 counterattack

The ball is won at the center line. Number 10 carries it while 7
and 14 fill the lanes wide.

```floorball
{
  "version": 1,
  "rink": { "layout": "half" },
  "elements": [
    { "id": "p1", "type": "player", "team": "attack", "number": 7, "x": 0.12, "y": 0.22 },
    { "id": "p2", "type": "player", "team": "attack", "number": 10, "label": "Carrier", "x": 0.08, "y": 0.5 },
    { "id": "p3", "type": "player", "team": "attack", "number": 14, "x": 0.12, "y": 0.78 },
    { "id": "p4", "type": "player", "team": "defense", "number": 4, "x": 0.55, "y": 0.38 },
    { "id": "p5", "type": "player", "team": "defense", "number": 5, "x": 0.55, "y": 0.62 },
    { "id": "p6", "type": "player", "team": "defense", "role": "goalkeeper", "number": 1, "x": 0.76, "y": 0.5 },
    { "id": "b1", "type": "ball", "x": 0.115, "y": 0.47 },
    { "id": "t1", "type": "text", "text": "2 on 1 on the weak side", "size": "s", "x": 0.4, "y": 0.95 }
  ],
  "paths": [
    { "id": "r1", "type": "dribble", "points": [[0.12, 0.5], [0.38, 0.5]] },
    { "id": "r2", "type": "run", "points": [[0.15, 0.2], [0.62, 0.14]], "control": [0.4, 0.08] },
    { "id": "r3", "type": "run", "points": [[0.15, 0.8], [0.6, 0.84]] },
    { "id": "r4", "type": "pass", "points": [[0.4, 0.53], [0.59, 0.8]] },
    { "id": "r5", "type": "shot", "points": [[0.63, 0.8], [0.79, 0.6]] }
  ]
}
```

### Coaching notes

- 10 drives the middle until a defender commits, then passes.
- 14 shoots first time; 7 crashes the far post for the rebound.

## Training exercise: pass and follow

Three groups at the cones. Pass, then run to the cone you passed to. The last
pass ends with a shot.

```floorball
{
  "version": 1,
  "rink": { "layout": "full" },
  "elements": [
    { "id": "c1", "type": "cone", "x": 0.3, "y": 0.3 },
    { "id": "c2", "type": "cone", "x": 0.45, "y": 0.75 },
    { "id": "c3", "type": "cone", "x": 0.6, "y": 0.3 },
    { "id": "p1", "type": "player", "team": "attack", "number": 1, "x": 0.27, "y": 0.22 },
    { "id": "p2", "type": "player", "team": "attack", "number": 2, "x": 0.45, "y": 0.86 },
    { "id": "p3", "type": "player", "team": "attack", "number": 3, "x": 0.63, "y": 0.22 },
    { "id": "p4", "type": "player", "team": "defense", "role": "goalkeeper", "x": 0.895, "y": 0.5 },
    { "id": "b1", "type": "ball", "x": 0.29, "y": 0.27 },
    { "id": "m1", "type": "marker", "label": "Start", "x": 0.2, "y": 0.22 },
    { "id": "t1", "type": "text", "text": "Pass and follow", "x": 0.45, "y": 0.08 }
  ],
  "paths": [
    { "id": "r1", "type": "pass", "points": [[0.31, 0.33], [0.43, 0.7]] },
    { "id": "r2", "type": "run", "points": [[0.25, 0.27], [0.41, 0.82]], "control": [0.24, 0.62] },
    { "id": "r3", "type": "pass", "points": [[0.48, 0.71], [0.58, 0.36]] },
    { "id": "r4", "type": "shot", "points": [[0.64, 0.3], [0.89, 0.46]] }
  ]
}
```
