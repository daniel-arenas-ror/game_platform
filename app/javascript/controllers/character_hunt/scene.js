// Draws Character Hunt's scenes and people, the same on the TV and on every phone.
//
// Everything is drawn in scene units: 1 is the scene's height, x runs from 0 to the scene's ratio
// (width / height). The caller sets the canvas transform (see viewport.js). The crowd comes from
// GameServices::CharacterHunt::Crowd and the colours from config/character_hunt/characters.yml.

const OUTLINE = "#1f2937"
const SHOE    = "#292524"

// Must match Crowd::HALF_WIDTH and Crowd::HEIGHT.
const HALF_WIDTH = 0.22
const HEIGHT     = 1.1

export function drawScene(ctx, scene, catalog) {
  const draw = BACKGROUNDS[scene.id] || BACKGROUNDS.park
  draw(ctx, scene.ratio)
  scene.characters.forEach(c => drawCharacter(ctx, c.x * scene.ratio, c.y, c.h, c.flip, c.traits, catalog))
}

// The character (index) at x, y (fractions of the scene): the front one wins, like Crowd.hit.
export function hitTest(scene, x, y) {
  const px = x * scene.ratio
  for (let i = scene.characters.length - 1; i >= 0; i--) {
    const c  = scene.characters[i]
    const cx = c.x * scene.ratio
    if (px >= cx - HALF_WIDTH * c.h && px <= cx + HALF_WIDTH * c.h && y >= c.y - HEIGHT * c.h && y <= c.y) return i
  }
  return null
}

// A ring around a character: who was tapped, or where the target was.
export function drawMark(ctx, scene, index, color, width = 0.12) {
  const c = scene.characters[index]
  if (!c) return
  ctx.save()
  ctx.strokeStyle = color
  ctx.lineWidth   = c.h * width
  ctx.beginPath()
  ctx.ellipse(c.x * scene.ratio, c.y - c.h * 0.55, c.h * 0.42, c.h * 0.72, 0, 0, Math.PI * 2)
  ctx.stroke()
  ctx.restore()
}

// One character, big, on its own canvas: who to find.
export function drawPortrait(canvas, traits, catalog, background = "#e0f2fe") {
  const ratio = window.devicePixelRatio || 1
  const rect  = canvas.getBoundingClientRect()
  canvas.width  = Math.max(Math.round(rect.width * ratio), 1)
  canvas.height = Math.max(Math.round(rect.height * ratio), 1)

  const ctx = canvas.getContext("2d")
  ctx.setTransform(1, 0, 0, 1, 0, 0)
  ctx.fillStyle = background
  ctx.fillRect(0, 0, canvas.width, canvas.height)
  // Room above for a top hat or a balloon.
  const h = Math.min(canvas.height * 0.68, canvas.width * 1.1)
  drawCharacter(ctx, canvas.width / 2 - h * 0.08, canvas.height * 0.94, h, false, traits, catalog)
}

// ── People ─────────────────────────────────────────────────────────────────

// Feet at x, y; h tall to the top of the head (hats and balloons go higher).
export function drawCharacter(ctx, x, y, h, flip, t, cat) {
  const color  = i => cat.colors[i]
  const skin   = cat.skin[t.skin]
  const hair   = cat.hair_colors[t.hair_color ?? 0]
  const top    = color(t.top)
  const extra  = cat.extras[t.extra]
  const hat    = cat.hats[t.hat]

  ctx.save()
  ctx.translate(x, y)
  ctx.scale(flip ? -h : h, h)
  ctx.lineWidth   = 0.022
  ctx.lineJoin    = "round"
  ctx.lineCap     = "round"
  ctx.strokeStyle = OUTLINE

  if (extra === "cape") shape(ctx, color(t.extra_color), c => { c.moveTo(-0.17, -0.8); c.lineTo(0.17, -0.8); c.lineTo(0.29, -0.1); c.lineTo(-0.29, -0.1); c.closePath() })
  if (extra === "backpack") shape(ctx, color(t.extra_color), c => roundRect(c, -0.25, -0.77, 0.3, 0.32, 0.05))
  if (cat.hair_styles[t.hair] === "long") shape(ctx, hair, c => roundRect(c, -0.15, -0.95, 0.3, 0.26, 0.06))
  if (cat.hair_styles[t.hair] === "ponytail") shape(ctx, hair, c => c.ellipse(-0.17, -0.84, 0.05, 0.1, 0.4, 0, Math.PI * 2))

  drawLegs(ctx, cat.legs[t.legs], cat.leg_colors[t.legs_color], skin)

  // Arms (sleeves and hands), then the body over them.
  shape(ctx, top, c => { roundRect(c, -0.235, -0.77, 0.09, 0.3, 0.04); roundRect(c, 0.145, -0.77, 0.09, 0.3, 0.04) })
  if (extra === "broom") drawBroom(ctx)
  if (extra === "candy_bucket") drawCandyBucket(ctx)
  shape(ctx, skin, c => { c.arc(-0.19, -0.45, 0.042, 0, Math.PI * 2); c.moveTo(0.232, -0.45); c.arc(0.19, -0.45, 0.042, 0, Math.PI * 2) })
  shape(ctx, top, c => roundRect(c, -0.165, -0.79, 0.33, 0.4, 0.06))
  drawPattern(ctx, cat.patterns[t.pattern], color(t.pattern_color))
  if (extra === "backpack") {
    ctx.strokeStyle = color(t.extra_color)
    ctx.lineWidth   = 0.04
    line(ctx, [ [ -0.09, -0.78 ], [ -0.09, -0.52 ] ])
    line(ctx, [ [ 0.09, -0.78 ], [ 0.09, -0.52 ] ])
    ctx.strokeStyle = OUTLINE
    ctx.lineWidth   = 0.022
  }
  if (extra === "cape") {
    shape(ctx, color(t.extra_color), c => {
      c.moveTo(-0.15, -0.79); c.lineTo(-0.04, -0.79); c.lineTo(-0.17, -0.95); c.closePath()
      c.moveTo(0.15, -0.79); c.lineTo(0.04, -0.79); c.lineTo(0.17, -0.95); c.closePath()
    })
  }

  // Neck and head.
  shape(ctx, skin, c => c.rect(-0.04, -0.81, 0.08, 0.05))
  shape(ctx, skin, c => c.arc(0, -0.88, 0.12, 0, Math.PI * 2))
  drawHair(ctx, cat.hair_styles[t.hair], hair)
  drawFace(ctx, cat.beards[t.beard], hair, cat.glasses[t.glasses])
  if (extra === "scarf") drawScarf(ctx, color(t.extra_color))
  if (hat !== "none") drawHat(ctx, hat, color(t.hat_color))
  if (extra === "balloon") drawBalloon(ctx, color(t.extra_color))

  ctx.restore()
}

function drawLegs(ctx, style, legColor, skin) {
  const legs = c => { c.rect(-0.13, -0.42, 0.11, 0.39); c.rect(0.02, -0.42, 0.11, 0.39) }
  shape(ctx, style === "pants" ? legColor : skin, legs)
  if (style === "shorts") shape(ctx, legColor, c => { c.rect(-0.14, -0.43, 0.13, 0.17); c.rect(0.01, -0.43, 0.13, 0.17) })
  if (style === "skirt") {
    shape(ctx, legColor, c => { c.moveTo(-0.15, -0.44); c.lineTo(0.15, -0.44); c.lineTo(0.21, -0.22); c.lineTo(-0.21, -0.22); c.closePath() })
  }
  shape(ctx, SHOE, c => { c.ellipse(-0.085, -0.025, 0.075, 0.035, 0, 0, Math.PI * 2); c.moveTo(0.16, -0.025); c.ellipse(0.085, -0.025, 0.075, 0.035, 0, 0, Math.PI * 2) })
}

function drawPattern(ctx, pattern, color) {
  if (pattern === "plain") return

  ctx.save()
  ctx.beginPath()
  roundRect(ctx, -0.165, -0.79, 0.33, 0.4, 0.06)
  ctx.clip()
  ctx.fillStyle = color
  if (pattern === "stripes") {
    for (let y = -0.75; y < -0.39; y += 0.09) ctx.fillRect(-0.2, y, 0.4, 0.045)
  } else if (pattern === "dots") {
    [ [ -0.08, -0.7 ], [ 0.07, -0.66 ], [ -0.05, -0.53 ], [ 0.09, -0.48 ], [ 0.0, -0.6 ] ].forEach(([ dx, dy ]) => {
      ctx.beginPath()
      ctx.arc(dx, dy, 0.032, 0, Math.PI * 2)
      ctx.fill()
    })
  } else if (pattern === "split") {
    ctx.fillRect(0, -0.8, 0.2, 0.42)
  } else if (pattern === "bones") {
    ctx.fillRect(-0.015, -0.77, 0.03, 0.36)
    ;[ -0.72, -0.64, -0.56 ].forEach(y => ctx.fillRect(-0.12, y, 0.24, 0.03))
    ctx.beginPath()
    ctx.ellipse(0, -0.46, 0.08, 0.035, 0, 0, Math.PI * 2)
    ctx.fill()
  } else if (pattern === "bandages") {
    ctx.save()
    ctx.rotate(-0.25)
    for (let y = -0.85; y < -0.2; y += 0.075) ctx.fillRect(-0.4, y, 0.8, 0.05)
    ctx.restore()
  }
  ctx.restore()
  ctx.beginPath()
  roundRect(ctx, -0.165, -0.79, 0.33, 0.4, 0.06)
  ctx.stroke()
}

function drawHair(ctx, style, color) {
  const cap = c => c.arc(0, -0.88, 0.128, Math.PI * 1.05, Math.PI * 1.95)
  switch (style) {
    case "short":
    case "long":
    case "ponytail":
      shape(ctx, color, cap)
      break
    case "curly":
      shape(ctx, color, c => {
        [ [ -0.1, -0.93 ], [ -0.05, -0.99 ], [ 0.02, -1.0 ], [ 0.08, -0.97 ], [ 0.12, -0.9 ], [ -0.13, -0.86 ] ].forEach(([ cx, cy ]) => {
          c.moveTo(cx + 0.05, cy)
          c.arc(cx, cy, 0.05, 0, Math.PI * 2)
        })
      })
      break
    case "spiky":
      shape(ctx, color, c => {
        c.moveTo(-0.13, -0.89)
        ;[ [ -0.12, -1.04 ], [ -0.06, -0.97 ], [ -0.02, -1.08 ], [ 0.03, -0.98 ], [ 0.09, -1.06 ], [ 0.1, -0.96 ], [ 0.14, -0.88 ] ]
          .forEach(([ px, py ]) => c.lineTo(px, py))
        c.closePath()
      })
      break
    case "bun":
      shape(ctx, color, cap)
      shape(ctx, color, c => c.arc(0, -1.02, 0.055, 0, Math.PI * 2))
      break
  }
}

function drawFace(ctx, beard, hair, glasses) {
  if (beard === "beard") shape(ctx, hair, c => c.arc(0, -0.85, 0.11, Math.PI * 0.05, Math.PI * 0.95))
  if (beard === "mustache") shape(ctx, hair, c => c.ellipse(0, -0.835, 0.055, 0.018, 0, 0, Math.PI * 2))
  if (beard === "fangs") {
    ctx.lineWidth = 0.01
    shape(ctx, "#ffffff", c => {
      c.moveTo(-0.04, -0.835); c.lineTo(-0.015, -0.835); c.lineTo(-0.0275, -0.8); c.closePath()
      c.moveTo(0.015, -0.835); c.lineTo(0.04, -0.835); c.lineTo(0.0275, -0.8); c.closePath()
    })
    ctx.lineWidth = 0.022
  }

  ctx.fillStyle = OUTLINE
  ;[ -0.045, 0.045 ].forEach(ex => { ctx.beginPath(); ctx.arc(ex, -0.89, 0.016, 0, Math.PI * 2); ctx.fill() })

  if (glasses === "round") {
    ctx.lineWidth = 0.016
    ;[ -0.045, 0.045 ].forEach(ex => { ctx.beginPath(); ctx.arc(ex, -0.89, 0.036, 0, Math.PI * 2); ctx.stroke() })
    line(ctx, [ [ -0.01, -0.89 ], [ 0.01, -0.89 ] ])
    ctx.lineWidth = 0.022
  } else if (glasses === "sunglasses") {
    shape(ctx, "#111827", c => { roundRect(c, -0.095, -0.915, 0.085, 0.05, 0.015); roundRect(c, 0.01, -0.915, 0.085, 0.05, 0.015) })
  }
}

function drawScarf(ctx, color) {
  shape(ctx, color, c => roundRect(c, -0.13, -0.8, 0.26, 0.06, 0.03))
  shape(ctx, color, c => roundRect(c, 0.05, -0.77, 0.06, 0.17, 0.02))
}

function drawHat(ctx, hat, color) {
  switch (hat) {
    case "cap":
      shape(ctx, color, c => c.arc(0, -0.93, 0.125, Math.PI, Math.PI * 2))
      shape(ctx, color, c => roundRect(c, 0.0, -0.95, 0.23, 0.04, 0.02))
      break
    case "beanie":
      shape(ctx, color, c => c.arc(0, -0.93, 0.13, Math.PI, Math.PI * 2))
      shape(ctx, color, c => roundRect(c, -0.14, -0.96, 0.28, 0.06, 0.02))
      shape(ctx, color, c => c.arc(0, -1.08, 0.035, 0, Math.PI * 2))
      break
    case "top_hat":
      shape(ctx, color, c => c.rect(-0.1, -1.16, 0.2, 0.2))
      shape(ctx, color, c => roundRect(c, -0.17, -0.98, 0.34, 0.04, 0.02))
      break
    case "cowboy":
      shape(ctx, color, c => roundRect(c, -0.1, -1.1, 0.2, 0.15, 0.05))
      shape(ctx, color, c => c.ellipse(0, -0.96, 0.24, 0.035, 0, 0, Math.PI * 2))
      break
    case "party":
      shape(ctx, color, c => { c.moveTo(-0.09, -0.97); c.lineTo(0.0, -1.2); c.lineTo(0.09, -0.97); c.closePath() })
      shape(ctx, "#facc15", c => c.arc(0, -1.2, 0.03, 0, Math.PI * 2))
      break
    case "witch":
      shape(ctx, color, c => c.ellipse(0, -0.96, 0.23, 0.04, 0, 0, Math.PI * 2))
      shape(ctx, color, c => { c.moveTo(-0.11, -0.97); c.lineTo(0.03, -1.2); c.lineTo(0.15, -1.26); c.lineTo(0.08, -1.18); c.lineTo(0.11, -0.97); c.closePath() })
      shape(ctx, "#facc15", c => c.rect(-0.03, -1.02, 0.06, 0.04))
      break
    case "horns":
      shape(ctx, color, c => {
        c.moveTo(-0.1, -0.96); c.quadraticCurveTo(-0.15, -1.05, -0.12, -1.11); c.quadraticCurveTo(-0.07, -1.03, -0.04, -0.99); c.closePath()
        c.moveTo(0.1, -0.96); c.quadraticCurveTo(0.15, -1.05, 0.12, -1.11); c.quadraticCurveTo(0.07, -1.03, 0.04, -0.99); c.closePath()
      })
      break
    case "cat_ears":
      shape(ctx, color, c => {
        c.moveTo(-0.12, -0.94); c.lineTo(-0.1, -1.08); c.lineTo(-0.02, -0.99); c.closePath()
        c.moveTo(0.12, -0.94); c.lineTo(0.1, -1.08); c.lineTo(0.02, -0.99); c.closePath()
      })
      fill(ctx, "#f9a8d4", c => {
        c.moveTo(-0.1, -0.96); c.lineTo(-0.095, -1.04); c.lineTo(-0.05, -0.99); c.closePath()
        c.moveTo(0.1, -0.96); c.lineTo(0.095, -1.04); c.lineTo(0.05, -0.99); c.closePath()
      })
      break
    case "pumpkin":
      // Covers the whole head (the crowd builder drops the hair and face underneath).
      shape(ctx, "#16a34a", c => c.rect(-0.015, -1.06, 0.03, 0.05))
      shape(ctx, "#f97316", c => c.ellipse(0, -0.89, 0.16, 0.14, 0, 0, Math.PI * 2))
      ctx.lineWidth = 0.012
      ctx.beginPath(); ctx.ellipse(0, -0.89, 0.07, 0.14, 0, 0, Math.PI * 2); ctx.stroke()
      ctx.lineWidth = 0.022
      fill(ctx, "#1c1917", c => {
        c.moveTo(-0.08, -0.9); c.lineTo(-0.04, -0.9); c.lineTo(-0.06, -0.95); c.closePath()
        c.moveTo(0.08, -0.9); c.lineTo(0.04, -0.9); c.lineTo(0.06, -0.95); c.closePath()
        c.moveTo(-0.08, -0.84); c.lineTo(0.08, -0.84); c.lineTo(0.05, -0.8); c.lineTo(0.02, -0.83)
        c.lineTo(-0.01, -0.8); c.lineTo(-0.04, -0.83); c.lineTo(-0.06, -0.8); c.closePath()
      })
      break
  }
}

function drawBroom(ctx) {
  ctx.strokeStyle = "#78350f"
  ctx.lineWidth   = 0.03
  line(ctx, [ [ 0.24, -0.98 ], [ 0.17, -0.18 ] ])
  ctx.strokeStyle = OUTLINE
  ctx.lineWidth   = 0.022
  shape(ctx, "#eab308", c => { c.moveTo(0.13, -0.2); c.lineTo(0.21, -0.2); c.lineTo(0.27, 0); c.lineTo(0.06, 0); c.closePath() })
}

// A pumpkin pail hanging from the hand.
function drawCandyBucket(ctx) {
  ctx.lineWidth = 0.012
  ctx.beginPath()
  ctx.arc(0.235, -0.38, 0.07, Math.PI * 1.05, Math.PI * 1.95)
  ctx.stroke()
  ctx.lineWidth = 0.022
  shape(ctx, "#f97316", c => roundRect(c, 0.16, -0.39, 0.15, 0.13, 0.04))
  fill(ctx, "#1c1917", c => {
    c.moveTo(0.19, -0.35); c.lineTo(0.215, -0.35); c.lineTo(0.2025, -0.375); c.closePath()
    c.moveTo(0.255, -0.35); c.lineTo(0.28, -0.35); c.lineTo(0.2675, -0.375); c.closePath()
    c.rect(0.2, -0.32, 0.07, 0.02)
  })
}

function drawBalloon(ctx, color) {
  ctx.lineWidth = 0.012
  line(ctx, [ [ 0.2, -0.46 ], [ 0.27, -0.8 ], [ 0.3, -1.08 ] ])
  ctx.lineWidth = 0.022
  shape(ctx, color, c => c.ellipse(0.3, -1.19, 0.085, 0.11, 0, 0, Math.PI * 2))
}

// ── Places ─────────────────────────────────────────────────────────────────

const BACKGROUNDS = {
  park(ctx, w) {
    const rand = seeded(11)
    fill(ctx, "#bae6fd", c => c.rect(0, 0, w, 0.2))
    fill(ctx, "#86c96a", c => c.rect(0, 0.19, w, 0.81))
    // A row of trees along the back.
    for (let x = 0.03; x < w; x += 0.09 + rand() * 0.05) {
      fill(ctx, "#78350f", c => c.rect(x - 0.008, 0.18, 0.016, 0.08))
      fill(ctx, rand() < 0.5 ? "#15803d" : "#166534", c => c.arc(x, 0.17, 0.045 + rand() * 0.025, 0, Math.PI * 2))
    }
    // A winding path.
    ctx.strokeStyle = "#e7d3a8"
    ctx.lineWidth   = 0.08
    ctx.lineCap     = "round"
    ctx.beginPath()
    ctx.moveTo(-0.05, 0.92)
    ctx.bezierCurveTo(0.5, 0.75, 0.55, 0.42, 1.0, 0.36)
    ctx.bezierCurveTo(1.3, 0.32, 1.45, 0.4, w + 0.05, 0.33)
    ctx.stroke()
    // The pond (Crowd's hole, so nobody stands in it).
    fill(ctx, "#0ea5e9", c => c.ellipse(1.136, 0.53, 0.215, 0.105, 0, 0, Math.PI * 2))
    fill(ctx, "#38bdf8", c => c.ellipse(1.136, 0.53, 0.19, 0.088, 0, 0, Math.PI * 2))
    ctx.strokeStyle = "#e0f2fe"
    ctx.lineWidth   = 0.006
    ;[ [ 1.07, 0.5 ], [ 1.2, 0.56 ], [ 1.12, 0.59 ] ].forEach(([ x, y ]) => line(ctx, [ [ x - 0.03, y ], [ x + 0.03, y ] ]))
    // Grass tufts and flowers.
    const flowers = [ "#f472b6", "#facc15", "#ffffff", "#a78bfa", "#fb7185" ]
    for (let i = 0; i < 260; i++) {
      const x = rand() * w, y = 0.24 + rand() * 0.76
      if (i % 3 === 0) {
        fill(ctx, flowers[i % flowers.length], c => c.arc(x, y, 0.006, 0, Math.PI * 2))
      } else {
        ctx.strokeStyle = "#5fa548"
        ctx.lineWidth   = 0.004
        line(ctx, [ [ x - 0.008, y - 0.012 ], [ x, y ], [ x + 0.008, y - 0.012 ] ])
      }
    }
  },

  beach(ctx, w) {
    const rand = seeded(23)
    fill(ctx, "#bae6fd", c => c.rect(0, 0, w, 0.13))
    fill(ctx, "#facc15", c => c.arc(w * 0.85, 0.06, 0.035, 0, Math.PI * 2))
    fill(ctx, "#0284c7", c => c.rect(0, 0.12, w, 0.08))
    fill(ctx, "#38bdf8", c => c.rect(0, 0.2, w, 0.12))
    ctx.strokeStyle = "#e0f2fe"
    ctx.lineWidth   = 0.005
    for (let i = 0; i < 40; i++) {
      const x = rand() * w, y = 0.14 + rand() * 0.16
      line(ctx, [ [ x, y ], [ x + 0.02, y - 0.006 ], [ x + 0.04, y ] ])
    }
    fill(ctx, "#e9cf9a", c => c.rect(0, 0.32, w, 0.68))
    fill(ctx, "#f6e3b4", c => {
      c.moveTo(0, 0.36)
      for (let x = 0; x <= w + 0.1; x += 0.1) c.quadraticCurveTo(x + 0.05, 0.34, x + 0.1, 0.36)
      c.lineTo(w, 1)
      c.lineTo(0, 1)
      c.closePath()
    })
    // Towels, shells and a few umbrellas.
    const towels = [ "#ef4444", "#3b82f6", "#22c55e", "#f97316", "#a855f7", "#ec4899" ]
    for (let i = 0; i < 14; i++) {
      const x = 0.05 + rand() * (w - 0.15), y = 0.42 + rand() * 0.5
      fill(ctx, towels[i % towels.length], c => c.rect(x, y, 0.09, 0.045))
      fill(ctx, "#ffffff", c => c.rect(x + 0.03, y, 0.015, 0.045))
    }
    for (let i = 0; i < 60; i++) fill(ctx, "#fde68a", c => c.arc(rand() * w, 0.4 + rand() * 0.6, 0.005, 0, Math.PI * 2))
    for (let i = 0; i < 6; i++) {
      const x = 0.1 + rand() * (w - 0.2), y = 0.45 + rand() * 0.45
      ctx.strokeStyle = "#78716c"
      ctx.lineWidth   = 0.008
      line(ctx, [ [ x, y ], [ x, y - 0.13 ] ])
      fill(ctx, towels[(i + 2) % towels.length], c => c.arc(x, y - 0.12, 0.07, Math.PI, Math.PI * 2))
    }
  },

  plaza(ctx, w) {
    const rand = seeded(37)
    fill(ctx, "#bae6fd", c => c.rect(0, 0, w, 0.1))
    // Buildings along the back.
    const walls = [ "#fca5a5", "#fde68a", "#bfdbfe", "#d9f99d", "#fbcfe8", "#fed7aa", "#e9d5ff" ]
    let x = 0
    for (let i = 0; x < w; i++) {
      const bw = 0.16 + rand() * 0.1, top = 0.04 + rand() * 0.06
      fill(ctx, walls[i % walls.length], c => c.rect(x, top, bw, 0.32 - top))
      fill(ctx, "#78716c", c => c.rect(x, top - 0.015, bw, 0.015))
      for (let wy = top + 0.03; wy < 0.26; wy += 0.06) {
        for (let wx = x + 0.025; wx < x + bw - 0.03; wx += 0.05) fill(ctx, "#475569", c => c.rect(wx, wy, 0.022, 0.032))
      }
      fill(ctx, "#57534e", c => c.rect(x + bw / 2 - 0.02, 0.26, 0.04, 0.06))
      x += bw
    }
    // Paving.
    fill(ctx, "#e5e7eb", c => c.rect(0, 0.32, w, 0.68))
    ctx.strokeStyle = "#d1d5db"
    ctx.lineWidth   = 0.004
    for (let gy = 0.36; gy < 1; gy += 0.06) line(ctx, [ [ 0, gy ], [ w, gy ] ])
    for (let gx = 0.04; gx < w; gx += 0.1) line(ctx, [ [ gx, 0.32 ], [ gx, 1 ] ])
    // The fountain (Crowd's hole).
    fill(ctx, "#9ca3af", c => c.ellipse(0.8, 0.67, 0.18, 0.1, 0, 0, Math.PI * 2))
    fill(ctx, "#7dd3fc", c => c.ellipse(0.8, 0.665, 0.15, 0.08, 0, 0, Math.PI * 2))
    fill(ctx, "#9ca3af", c => c.rect(0.785, 0.55, 0.03, 0.11))
    fill(ctx, "#bae6fd", c => c.ellipse(0.8, 0.55, 0.05, 0.025, 0, 0, Math.PI * 2))
    // Lamp posts.
    ;[ 0.15, 0.55, 1.05, 1.45 ].forEach(lx => {
      ctx.strokeStyle = "#374151"
      ctx.lineWidth   = 0.008
      line(ctx, [ [ lx, 0.4 ], [ lx, 0.3 ] ])
      fill(ctx, "#fde68a", c => c.arc(lx, 0.295, 0.012, 0, Math.PI * 2))
    })
  }
}

// ── Halloween places ───────────────────────────────────────────────────────

Object.assign(BACKGROUNDS, {
  graveyard(ctx, w) {
    const rand = seeded(53)
    nightSky(ctx, w, 0.3, rand)
    fill(ctx, "#312e81", c => { c.moveTo(0, 0.3); c.quadraticCurveTo(w * 0.25, 0.2, w * 0.5, 0.28); c.quadraticCurveTo(w * 0.8, 0.19, w, 0.27); c.lineTo(w, 0.32); c.lineTo(0, 0.32); c.closePath() })
    fill(ctx, "#6b8f4e", c => c.rect(0, 0.31, w, 0.69))
    // Bare trees in the corners.
    ctx.strokeStyle = "#292524"
    ;[ [ 0.12, 0.33 ], [ w - 0.12, 0.33 ] ].forEach(([ x, y ]) => {
      ctx.lineWidth = 0.022
      line(ctx, [ [ x, y ], [ x + 0.01, y - 0.2 ] ])
      ctx.lineWidth = 0.01
      line(ctx, [ [ x + 0.005, y - 0.1 ], [ x - 0.07, y - 0.19 ], [ x - 0.1, y - 0.2 ] ])
      line(ctx, [ [ x + 0.008, y - 0.14 ], [ x + 0.08, y - 0.22 ] ])
      line(ctx, [ [ x + 0.01, y - 0.2 ], [ x - 0.02, y - 0.26 ] ])
    })
    // The iron fence, then the crypt in front of it.
    ctx.strokeStyle = "#111827"
    ctx.lineWidth   = 0.006
    line(ctx, [ [ 0, 0.25 ], [ w, 0.25 ] ])
    line(ctx, [ [ 0, 0.3 ], [ w, 0.3 ] ])
    for (let x = 0.01; x < w; x += 0.03) line(ctx, [ [ x, 0.32 ], [ x, 0.23 ] ])
    fill(ctx, "#6b7280", c => c.rect(0.7, 0.17, 0.2, 0.2))
    fill(ctx, "#4b5563", c => { c.moveTo(0.68, 0.17); c.lineTo(0.8, 0.09); c.lineTo(0.92, 0.17); c.closePath() })
    fill(ctx, "#1f2937", c => { c.moveTo(0.77, 0.37); c.lineTo(0.77, 0.27); c.arc(0.8, 0.27, 0.03, Math.PI, 0); c.lineTo(0.83, 0.37); c.closePath() })
    ;[ 0.37, 0.4, 0.43 ].forEach((y, i) => fill(ctx, i % 2 ? "#9ca3af" : "#a8a29e", c => c.rect(0.69 - i * 0.02, y, 0.22 + i * 0.04, 0.03)))
    // Gravestones.
    for (let i = 0; i < 22; i++) {
      const x = 0.05 + rand() * (w - 0.1), y = 0.36 + rand() * 0.62
      const s = 0.6 + (y - 0.36) * 0.9
      if (x > 0.62 && x < 0.98 && y < 0.5) continue // the crypt's steps
      ctx.strokeStyle = "#57534e"
      ctx.lineWidth   = 0.004
      if (i % 4 === 0) {
        fill(ctx, "#a8a29e", c => { c.rect(x - 0.006 * s, y - 0.07 * s, 0.012 * s, 0.07 * s); c.rect(x - 0.022 * s, y - 0.055 * s, 0.044 * s, 0.012 * s) })
      } else {
        shape(ctx, "#a8a29e", c => { c.moveTo(x - 0.022 * s, y); c.lineTo(x - 0.022 * s, y - 0.04 * s); c.arc(x, y - 0.04 * s, 0.022 * s, Math.PI, 0); c.lineTo(x + 0.022 * s, y); c.closePath() })
        fill(ctx, "#78716c", c => c.rect(x - 0.01 * s, y - 0.045 * s, 0.02 * s, 0.004 * s))
      }
    }
    // Low mist.
    ;[ [ 0.3, 0.55 ], [ 1.1, 0.7 ], [ 0.6, 0.88 ] ].forEach(([ x, y ]) => fill(ctx, "rgba(226, 232, 240, 0.18)", c => c.ellipse(x, y, 0.3, 0.025, 0, 0, Math.PI * 2)))
  },

  pumpkin_patch(ctx, w) {
    const rand = seeded(71)
    fill(ctx, "#a78bfa", c => c.rect(0, 0, w, 0.1))
    fill(ctx, "#fdba74", c => c.rect(0, 0.1, w, 0.24))
    fill(ctx, "#f97316", c => c.arc(w * 0.7, 0.27, 0.07, Math.PI, Math.PI * 2))
    // The barn and the corn.
    fill(ctx, "#b91c1c", c => c.rect(0.12, 0.13, 0.24, 0.2))
    fill(ctx, "#7f1d1d", c => { c.moveTo(0.1, 0.13); c.lineTo(0.24, 0.05); c.lineTo(0.38, 0.13); c.closePath() })
    fill(ctx, "#f8fafc", c => c.rect(0.2, 0.22, 0.08, 0.11))
    ctx.strokeStyle = "#b91c1c"
    ctx.lineWidth   = 0.008
    line(ctx, [ [ 0.2, 0.22 ], [ 0.28, 0.33 ] ])
    line(ctx, [ [ 0.28, 0.22 ], [ 0.2, 0.33 ] ])
    for (let x = 0.45; x < w; x += 0.025) {
      ctx.strokeStyle = "#a16207"
      ctx.lineWidth   = 0.006
      line(ctx, [ [ x, 0.34 ], [ x + 0.004, 0.22 + rand() * 0.03 ] ])
      fill(ctx, "#eab308", c => c.ellipse(x + 0.004, 0.25, 0.006, 0.015, 0, 0, Math.PI * 2))
    }
    fill(ctx, "#b07a45", c => c.rect(0, 0.33, w, 0.67))
    ctx.strokeStyle = "#9a6a3c"
    ctx.lineWidth   = 0.006
    for (let y = 0.38; y < 1; y += 0.07) line(ctx, [ [ 0, y ], [ w, y + 0.02 ] ])
    // The hay bales (Crowd's hole).
    ;[ [ 0.11, 0.66 ], [ 0.2, 0.66 ], [ 0.15, 0.6 ] ].forEach(([ x, y ]) => {
      ctx.strokeStyle = "#a16207"
      ctx.lineWidth   = 0.005
      shape(ctx, "#eab308", c => c.rect(x, y, 0.1, 0.07))
      line(ctx, [ [ x, y + 0.035 ], [ x + 0.1, y + 0.035 ] ])
    })
    // Pumpkins with their vines, small at the back.
    for (let i = 0; i < 45; i++) {
      const x = 0.03 + rand() * (w - 0.06), y = 0.36 + rand() * 0.63
      if (x > 0.08 && x < 0.34 && y > 0.56 && y < 0.82) continue
      const s = 0.5 + (y - 0.36) * 1.1
      ctx.strokeStyle = "#4d7c0f"
      ctx.lineWidth   = 0.005
      line(ctx, [ [ x - 0.05 * s, y + 0.01 ], [ x, y - 0.005 ], [ x + 0.05 * s, y + 0.012 ] ])
      ctx.strokeStyle = "#9a3412"
      ctx.lineWidth   = 0.004
      shape(ctx, "#f97316", c => c.ellipse(x, y - 0.018 * s, 0.03 * s, 0.022 * s, 0, 0, Math.PI * 2))
      fill(ctx, "#4d7c0f", c => c.rect(x - 0.003 * s, y - 0.046 * s, 0.006 * s, 0.01 * s))
    }
  },

  haunted_street(ctx, w) {
    const rand = seeded(97)
    nightSky(ctx, w, 0.36, rand)
    // Crooked houses, with the haunted one in the middle.
    const walls = [ "#4c1d95", "#374151", "#14532d", "#581c87", "#1e3a8a", "#3f3f46" ]
    let x = 0
    for (let i = 0; x < w; i++) {
      const big = Math.abs(x + 0.15 - w / 2) < 0.15
      const bw  = big ? 0.3 : 0.18 + rand() * 0.06
      const top = big ? 0.07 : 0.13 + rand() * 0.06
      fill(ctx, walls[i % walls.length], c => c.rect(x, top, bw, 0.36 - top))
      fill(ctx, "#1f2937", c => { c.moveTo(x - 0.01, top); c.lineTo(x + bw * (0.4 + rand() * 0.2), top - 0.07); c.lineTo(x + bw + 0.01, top); c.closePath() })
      for (let wy = top + 0.03; wy < 0.28; wy += 0.06) {
        for (let wx = x + 0.025; wx < x + bw - 0.03; wx += 0.055) {
          fill(ctx, rand() < 0.6 ? "#fde047" : "#111827", c => c.rect(wx, wy, 0.022, 0.03))
        }
      }
      fill(ctx, "#111827", c => c.rect(x + bw / 2 - 0.02, 0.29, 0.04, 0.07))
      x += bw
    }
    fill(ctx, "#6b7280", c => c.rect(0, 0.35, w, 0.03))
    fill(ctx, "#a1a1aa", c => c.rect(0, 0.38, w, 0.62))
    ctx.strokeStyle = "#8e8e96"
    ctx.lineWidth   = 0.004
    for (let y = 0.42, row = 0; y < 1; y += 0.045, row++) {
      line(ctx, [ [ 0, y ], [ w, y ] ])
      for (let bx = (row % 2) * 0.04; bx < w; bx += 0.08) line(ctx, [ [ bx, y ], [ bx, y + 0.045 ] ])
    }
    // Street lamps and jack-o'-lanterns on the pavement.
    ;[ 0.2, 0.6, 1.0, 1.4 ].forEach(lx => {
      fill(ctx, "rgba(253, 224, 71, 0.25)", c => c.arc(lx, 0.3, 0.04, 0, Math.PI * 2))
      ctx.strokeStyle = "#111827"
      ctx.lineWidth   = 0.008
      line(ctx, [ [ lx, 0.38 ], [ lx, 0.3 ] ])
      fill(ctx, "#fde047", c => c.arc(lx, 0.3, 0.013, 0, Math.PI * 2))
    })
    for (let i = 0; i < 9; i++) {
      const jx = 0.08 + i * 0.18 + rand() * 0.05
      fill(ctx, "#f97316", c => c.ellipse(jx, 0.365, 0.016, 0.013, 0, 0, Math.PI * 2))
      fill(ctx, "#fde047", c => { c.rect(jx - 0.008, 0.362, 0.005, 0.004); c.rect(jx + 0.003, 0.362, 0.005, 0.004) })
    }
  }
})

// Night sky down to `horizon`: stars, a moon and a few bats.
function nightSky(ctx, w, horizon, rand) {
  fill(ctx, "#1e1b4b", c => c.rect(0, 0, w, horizon))
  for (let i = 0; i < 70; i++) fill(ctx, "#e0e7ff", c => c.arc(rand() * w, rand() * horizon * 0.8, 0.002 + rand() * 0.002, 0, Math.PI * 2))
  fill(ctx, "#fef9c3", c => c.arc(w * 0.82, 0.08, 0.05, 0, Math.PI * 2))
  fill(ctx, "#1e1b4b", c => c.arc(w * 0.82 + 0.02, 0.07, 0.045, 0, Math.PI * 2))
  ctx.strokeStyle = "#0f172a"
  ctx.lineWidth   = 0.005
  ;[ [ 0.3, 0.06 ], [ 0.38, 0.1 ], [ 1.05, 0.05 ] ].forEach(([ bx, by ]) => {
    line(ctx, [ [ bx - 0.02, by - 0.006 ], [ bx - 0.01, by ], [ bx, by - 0.004 ], [ bx + 0.01, by ], [ bx + 0.02, by - 0.006 ] ])
  })
}

// ── Helpers ────────────────────────────────────────────────────────────────

function shape(ctx, color, path) {
  ctx.beginPath()
  path(ctx)
  ctx.fillStyle = color
  ctx.fill()
  ctx.stroke()
}

function fill(ctx, color, path) {
  ctx.beginPath()
  path(ctx)
  ctx.fillStyle = color
  ctx.fill()
}

function line(ctx, points) {
  ctx.beginPath()
  points.forEach(([ x, y ], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)))
  ctx.stroke()
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.moveTo(x + r, y)
  ctx.arcTo(x + w, y, x + w, y + h, r)
  ctx.arcTo(x + w, y + h, x, y + h, r)
  ctx.arcTo(x, y + h, x, y, r)
  ctx.arcTo(x, y, x + w, y, r)
  ctx.closePath()
}

// The same "random" decorations on every screen.
function seeded(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
