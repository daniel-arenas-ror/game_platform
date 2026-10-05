---
name: Grouparty
description: Free party games for one shared screen and everyone's phone.
colors:
  studio-black: "oklch(12.9% .042 264.695)"
  stage-floor: "oklch(20.8% .042 265.755)"
  set-panel: "oklch(27.9% .041 260.031)"
  set-panel-raised: "oklch(37.2% .044 257.287)"
  rig-line: "oklch(37.2% .044 257.287)"
  rig-line-strong: "oklch(44.6% .043 257.281)"
  ink-bright: "#ffffff"
  ink-soft: "oklch(86.9% .022 252.894)"
  ink-muted: "oklch(70.4% .04 256.788)"
  ink-faint: "oklch(55.4% .046 257.417)"
  house-purple: "oklch(55.8% .288 302.321)"
  house-purple-lit: "oklch(62.7% .265 303.9)"
  house-purple-glow: "oklch(71.4% .203 305.504)"
  house-pink: "oklch(59.2% .249 .584)"
  spotlight-gold: "oklch(85.2% .199 91.936)"
  spotlight-gold-deep: "oklch(79.5% .184 86.047)"
  go-green: "oklch(72.3% .219 149.579)"
  correct-green: "oklch(79.2% .209 151.711)"
  miss-red: "oklch(70.4% .191 22.216)"
  set-violet: "oklch(60.6% .25 292.717)"
  set-cyan: "oklch(78.9% .154 211.53)"
  set-emerald: "oklch(76.5% .177 163.223)"
  set-blue: "oklch(37.9% .146 265.522)"
typography:
  display:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "3rem"
    fontWeight: 900
    lineHeight: 1
  headline:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "2.25rem"
    fontWeight: 900
    lineHeight: 1.11
  title:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.5rem"
    fontWeight: 700
    lineHeight: 1.33
  body:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.5
  body-lead:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "1.125rem"
    fontWeight: 400
    lineHeight: 1.56
  label:
    fontFamily: "ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.75rem"
    fontWeight: 900
    lineHeight: 1.33
    letterSpacing: "0.1em"
  room-code:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace"
    fontSize: "1.25rem"
    fontWeight: 900
    letterSpacing: "0.4em"
  score:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace"
    fontSize: "1.5rem"
    fontWeight: 900
    lineHeight: 1
rounded:
  sm: "0.25rem"
  lg: "0.5rem"
  xl: "0.75rem"
  2xl: "1rem"
  3xl: "1.5rem"
  full: "9999px"
spacing:
  1: "4px"
  2: "8px"
  3: "12px"
  4: "16px"
  5: "20px"
  6: "24px"
  8: "32px"
  12: "48px"
  16: "64px"
  24: "96px"
components:
  button-primary:
    backgroundColor: "{colors.house-purple}"
    textColor: "{colors.ink-bright}"
    typography: "{typography.label}"
    rounded: "{rounded.xl}"
    padding: "16px 24px"
  button-primary-hover:
    backgroundColor: "{colors.house-purple-lit}"
  button-solid:
    backgroundColor: "{colors.house-purple}"
    textColor: "{colors.ink-bright}"
    rounded: "{rounded.xl}"
    padding: "12px 16px"
  button-solid-hover:
    backgroundColor: "{colors.house-purple-lit}"
  button-go:
    backgroundColor: "{colors.go-green}"
    textColor: "{colors.stage-floor}"
    typography: "{typography.label}"
    rounded: "{rounded.xl}"
    padding: "16px 0"
  input-field:
    backgroundColor: "{colors.stage-floor}"
    textColor: "{colors.ink-bright}"
    rounded: "{rounded.xl}"
    padding: "12px 16px"
  input-room-code:
    backgroundColor: "{colors.stage-floor}"
    textColor: "{colors.ink-bright}"
    typography: "{typography.room-code}"
    rounded: "{rounded.xl}"
    padding: "12px 16px"
  card-game:
    backgroundColor: "{colors.set-panel}"
    textColor: "{colors.ink-bright}"
    rounded: "{rounded.2xl}"
    padding: "24px"
  panel-lobby:
    backgroundColor: "{colors.set-panel}"
    textColor: "{colors.ink-bright}"
    rounded: "{rounded.3xl}"
    padding: "32px"
  picker-option:
    backgroundColor: "{colors.set-panel}"
    textColor: "{colors.ink-bright}"
    rounded: "{rounded.xl}"
    padding: "16px 0"
  pill-status:
    backgroundColor: "{colors.house-purple}"
    textColor: "{colors.ink-bright}"
    rounded: "{rounded.full}"
    padding: "4px 12px"
  player-row:
    backgroundColor: "{colors.set-panel-raised}"
    textColor: "{colors.ink-bright}"
    rounded: "{rounded.xl}"
    padding: "16px"
---

# Design System: Grouparty

## Overview

**Creative North Star: "The Game-Show Studio"**

Grouparty is a studio with the lights down. The host screen is the set, seen by the whole room from the sofa, the back of a classroom or the end of a meeting table. Every phone is a contestant's buzzer. The building is permanently dark: a deep slate floor, panels one step lighter, and thin rigging lines between them. The house lights are purple, with a purple-to-pink sweep on the main call to action. The Grouparty wordmark is solid white type. When something matters, like a score, a winner or a correct answer, the gold spotlight hits it.

Each game is its own set on the same stage. Mind Match is lit violet, Submarine Combat cyan, Soup of Numbers emerald, and the billionaire quiz deep studio blue. The studio itself stays constant, so moving between games feels like a scene change rather than leaving the show. The chrome is clean and calm: quiet panels, plain system type and restrained borders. The game moments are what's allowed to shout.

The studio is family-show TV, not a casino and not a kids' channel. It should look right in front of a class, a team or a family. That rules out flashing slot-machine glare, wall-to-wall neon and cartoon mascots.

**Key Characteristics:**
- Permanently dark, built from tonal slate layers (950 → 900 → 800 → 700).
- One house accent (purple) for site chrome, and one set accent per game.
- Gold is reserved for scores, highlights and winners.
- Heavy black-weight system sans, with monospace for codes and numbers.
- Softly rounded panels (16–24px) with 1px rig lines and no hard edges.
- Large, readable-at-a-distance type on the host screen, and thumb-sized controls on the phone.

## Colors

The palette is a dark studio floor with one house light, a gold spotlight, and a different colored set light for each game. All values come straight from Tailwind v4's OKLCH palette. Use the Tailwind utilities rather than custom values.

### Primary
- **House Purple** (`purple-600`): The brand's voice. Status pills, the hover fill of the catalog's "Play Now" / "Switch to this game" buttons, and player avatar discs (in its lighter step, `purple-500`). It also starts the purple→pink CTA sweep.
- **House Purple Lit** (`purple-500`): Hover state for purple buttons, focus borders on inputs (`focus:border-purple-500`), and the active game-card border.
- **House Purple Glow** (`purple-400`): Accent text on dark backgrounds, such as room codes, "← Back to games" links, step numbers and inline links.
- **House Pink** (`pink-600`): Only appears as the end of the purple→pink gradient on the primary CTAs (Start a game, Join, Join game, Enter Lobby). It never appears on its own.

### Secondary
- **Spotlight Gold** (`yellow-400`): The most-used accent inside games. It marks scores, point gains, the current round, winners, highlighted cells and leaderboard leaders. `yellow-500` is its deeper fill.

### Tertiary
These are the set accents, one per game. A game's accent owns its selected-picker state, its key borders and its emphasis text, and appears only inside that game's views.
- **Set Violet** (`violet-500` / `violet-400`): Mind Match.
- **Set Cyan** (`cyan-400`): Submarine Combat.
- **Set Emerald** (`emerald-400`): Soup of Numbers.
- **Set Blue** (`blue-900` / `blue-950` gradients, `blue-400` text): How Want Be Billionaire.
- **Go Green** (`green-500`): The host's Start Game button. `green-400` marks correct answers.
- **Miss Red** (`red-400`): Errors, wrong answers, hits taken and eliminations.

### Neutral
- **Studio Black** (`slate-950`): The deepest surface. It's the footer, full-bleed game backdrops and the darkest wells.
- **Stage Floor** (`slate-900`): The default page background (`body`), plus the wells inside inputs.
- **Set Panel** (`slate-800`): Cards, the lobby panel and pickers. It's the main surface everything sits on.
- **Set Panel Raised** (`slate-700`): Rows and media areas nested inside a panel, like player rows and the game-card image well.
- **Rig Line** (`slate-700`) and **Rig Line Strong** (`slate-600`): 1px borders on panels, and on nested rows and unselected pickers.
- **Ink Bright** (white): Headings, button labels and player names.
- **Ink Soft** (`slate-300`): Lead copy under hero headings.
- **Ink Muted** (`slate-400`): Body copy and descriptions. This is the most common text color.
- **Ink Faint** (`slate-500`): Helper text, captions, field labels and footer copy.

### Named Rules
**The Spotlight Rule.** Gold means "this is the thing that just happened or matters most": a score, a leader, a correct pick. It never decorates chrome, and it never appears on more than one focal element per moment.

**The One Set Light Rule.** Each game view uses its own set accent plus the shared gold and green/red feedback colors. Never borrow another game's accent, and never use house purple for in-game selection inside a game that has its own set light.

**The Gradient Is a Signature Rule.** The purple→pink sweep is reserved for the one primary "get into a room" CTA in each view (Start a game, Join game, Enter Lobby). It isn't a general fill, and it never colors text. The secondary CTA beside it is always the tonal button.

## Typography

**Display Font:** System UI sans (`ui-sans-serif, system-ui, sans-serif`)
**Body Font:** The same system UI sans
**Label/Mono Font:** System monospace (`ui-monospace, SFMono-Regular, Menlo, monospace`)

**Character:** It's the native system face pushed to black weight. It's clear, fast, and familiar on every phone and TV browser, with no web-font load. The monospace does the scoreboard work: room codes, scores, timers and grids read like a studio's numeric display.

### Hierarchy
- **Display** (800–900, 3–3.75rem, line-height 1, tight tracking): The home hero wordmark in solid white, plus big host-screen moments like countdowns and round numbers. Host screens step up to 3.75–6rem for numbers read across a room.
- **Headline** (900/800, 2.25rem): Page titles (About, Privacy), the lobby game name, and section heads like "How it works" (1.875rem, 700).
- **Title** (700, 1.5rem): Game-card names and panel headings. Panel headings drop to 1.25rem.
- **Body** (400, 1rem, 1.5): Descriptions and explanatory copy in Ink Muted. Long-form pages cap at about 65ch (`max-w-2xl`/`max-w-3xl`).
- **Body Lead** (400–600, 1.125–1.25rem): Hero sub-lines. The tagline is in `purple-300` and the supporting line in Ink Muted.
- **Label** (900, 0.75rem, `tracking-widest` 0.1em, uppercase): Field labels ("YOUR NICKNAME", "NUMBER OF ROUNDS"), picker captions and button labels on host-critical actions. This is the system's most-repeated text style.
- **Room Code** (mono 900, 1.25rem, letter-spacing 0.4em, uppercase): Room codes everywhere, including inputs, the lobby and the join screen.
- **Score** (mono 900): Scores, timers, coordinates and grid digits.

### Named Rules
**The Readable-From-The-Sofa Rule.** Anything the room must read on the host screen, like a prompt, a number or a winner, is 1.5rem or larger and set at weight 700–900. Small type (0.75rem) is only for phone-side helper text and labels.

**The Monospace Means Machine Rule.** Use mono for anything that is a code, count, coordinate or score, and never for prose.

## Layout

The page shell is a full-height Stage Floor background. Public pages (Home, Games, Join, About, Contact, Privacy) open with the 64px site header, while room, lobby and game screens never show it. Public pages center their content in a container (`max-w-6xl` for Home sections and the Join page, `max-w-7xl` for the catalog, `max-w-2xl`–`max-w-4xl` for reading pages and the lobby) with horizontal padding of 16–32px (`px-4 sm:px-6 lg:px-8`). A slim footer on Studio Black closes every page except the in-game screen. Game screens fill the display edge to edge with no footer.

Spacing follows Tailwind's 4px scale. The common steps are 12px (`py-3`, `gap-3`), 16px, 24px (`p-6`, card padding) and 32px (`p-8`, panel padding, `gap-8` grid gutters). Big sections are separated by 48–96px (`mb-16`, `mt-24`). Home sections use 80–112px vertical padding (`py-20 sm:py-28`), divided by 1px `slate-800` rules. One band, "More than a game", sits on a 60% Studio Black wash for rhythm.

Responsive behavior:
- The game catalog grid goes from 1 column, to 2 at `md`, to 3 at `lg`.
- Home's hero and the Join page are two columns at `lg` (copy left, product mock right) and stack below that, with copy first.
- The lobby splits into two columns at `md`: game info and QR on the left, players on the right.
- Phone views are a single centered column at `max-w-sm`/`max-w-xs`.
- Host views assume a landscape TV or laptop.

## Elevation & Depth

Depth comes mostly from tonal stacking. Each layer is one slate step lighter than the one beneath it: floor → panel → raised row. A 1px Rig Line marks the edges. Shadows are a secondary cue. Large, soft, dark drop shadows (`shadow-xl`, `shadow-2xl`) sit under panels, and the QR card floats as a white island on a `shadow-2xl`. Colored glows are rare and tinted with the house hue (`shadow-purple-900/20`) under primary buttons.

### Shadow Vocabulary
- **Panel lift** (`shadow-xl`): The lobby players panel. Catalog game cards are flat, using tonal layering and a border only.
- **Spotlight lift** (`shadow-2xl`): The join card and the QR code plate. These are the single focal object on screen.
- **Button glow** (`shadow-lg shadow-purple-900/20`): Purple primary buttons.

### Named Rules
**The Lighter-Means-Closer Rule.** To bring a surface forward, raise it one slate step and give it a border. Don't stack shadows inside shadows.

## Shapes

The shapes are soft and friendly but not bubbly:
- Panels and cards use generous rounding (16px `rounded-2xl`, or 24px `rounded-3xl` for primary panels like the lobby and join card).
- Interactive controls (buttons, inputs, picker options, nested rows) use 12px (`rounded-xl`).
- Pills, status badges and avatar discs are fully round.
- Borders are 1px on surfaces and 2px on inputs and picker options, where the border carries the state.
- Square corners (`rounded`/`rounded-sm`) appear only inside game boards, such as grid cells and board tiles, where tiling demands them.

## Components

The chrome is clean and calm. Controls are clear and unadorned so the game moments carry the energy.

### Buttons
- **Shape:** Gently rounded (12px).
- **Primary (tonal):** The catalog's repeated action ("Play Now", "Switch to this game"). At rest it's a 15% House Purple Lit tint with a 30% purple border and `purple-100` semibold label. On hover it fills solid House Purple with white text. Nine of these sit on one page, so they stay quiet until pointed at. 12px × 16px padding, full width inside cards.
- **Primary sweep:** A purple→pink gradient with a white black-weight label, used only for the primary "get in the room" action (Start a game, Join game, Enter Lobby). On hover each end steps one shade lighter. On Home it pairs with a tonal "Join a game" at the same size (18px label, 16px × 32px padding).
- **Go (host start):** Go Green fill, Stage Floor text, black-weight uppercase label at `tracking-widest`, 16px vertical padding, full width.
- **Hover / Press:** Color transitions at 150–200ms. Primary CTAs press down to 95% scale on `:active`.
- **Text links:** House Purple Glow, brightening to `purple-300` on hover. Footer links go from Ink Muted to white.

### Chips
- **Status pill:** House Purple fill, white text at 0.75rem, fully round, 4px × 12px padding (for example "Waiting...").
- **Badge on media:** The same pill, absolutely positioned top-right on a game card ("Current game").

### Cards / Containers
- **Game card:** An `<article>` with a Set Panel background, 16px radius, 1px Rig Line border, no shadow, 192px media well (Set Panel Raised) holding the game's instruction image, 24px body padding, 24px grid gap. On hover the border turns 70% House Purple Lit and the image eases to 103% over 500ms.
- **Lobby panel:** Set Panel background, 24px radius, 32px padding, 1px Rig Line border, at least 400px tall.
- **Config section:** A translucent Stage Floor (`slate-900/50`) well with 16px radius and 24px padding that groups each picker.

### Inputs / Fields
- **Style:** A Stage Floor well with a 2px Rig Line border, 12px radius, 12px × 16px padding, white bold text, centered.
- **Room-code input:** The same well, with monospace black-weight uppercase text tracked to 0.4em and a placeholder in `slate-600`.
- **Focus:** The border shifts to House Purple Lit with no outline ring, over a 150ms color transition. Buttons and links get a 2px `purple-400` focus-visible outline, offset 2px.
- **Error:** The border turns 70% Miss Red, and the hint line below swaps to a Miss Red message (`role="alert"`, linked via `aria-describedby`). Placeholders use Ink Muted (`slate-400`) at semibold so they stay readable.
- **Labels:** Label style (0.75rem, black weight, widest tracking) in Ink Faint, above the field.

### Browser Surfaces
The document declares `color-scheme: dark`, so scrollbars and native controls stay dark. `accent-color` is `purple-500`, text selection is a 45% `purple-500` wash with white text, and the input caret is `purple-400`. A game without an instruction image shows a drawn 1.5px-stroke gamepad icon in Ink Faint, never an emoji.

### Navigation
- **Site header:** a 64px Stage Floor bar with a 1px `slate-800` bottom rule. The left side has the white extrabold "Grouparty" wordmark, linking Home. The right side has Home and Games as 14px semibold text links (Ink Muted → white, white with `aria-current="page"` when active). Join is a tonal button that fills solid House Purple on the Join page. It stays one row down to 390px.
- **Skip link:** the first Tab stop on every page is a "Skip to content" pill in House Purple.
- **Info pages:** a "← Back to games" text link in House Purple Glow above the page title.
- **Footer:** a Studio Black row with the copyright in Ink Faint and About / Contact / Privacy Policy links (Ink Muted → white, padded to about 36px tap height). It stacks vertically on mobile.

### Product Mock (signature component)
These are miniatures of the real host screen, built in HTML instead of images: a Set Panel bezel around a Studio Black 16:9 screen with the game name, `ROOM: K7QX` in House Purple Glow mono, a white QR plate and a players list. Home overlaps a tilted phone showing the 4-slot code and "You're in!". The Join page circles the room code with a `purple-400` ring. The sample code is always `Room::EXAMPLE_CODE`, which can never be a real room. Mocks are `aria-hidden` or `role="img"` with a plain description.

### Use-Case Row
On Home, each setting (Classrooms, Work teams, Family & friends) is a row. On the left is a `purple-300` label, a 24–30px bold headline and Ink Muted copy. On the right are three 2:3 instruction-image thumbnails of games that suit it, from `HomeController::USE_CASE_GAMES`, each linking to its game page. Rows are separated by 1px `slate-800` dividers. It isn't a card grid.

### Game Page (`/games/:slug`)
A public page per game, lit with that game's accent from `GamePagesHelper::ACCENTS`. Games without a set light in their views get one here: Battle City amber, Guess the Color orange, Count Birds sky, Sequence Memory indigo, Matching Pairs rose, and The Fisherman stays house purple. The accent is used for section labels, the tagline (300 step), step numbers, badge icons and the player meter. The Start game button is still the purple→pink sweep.

The sections run from top to bottom: hero (category label, name, tagline, description, at-a-glance pills, Start game, the instruction image tilted 2° that straightens on hover), an ad, "What is…?", numbered step cards on a 60% Studio Black band, a player meter (mono range plus a row of dots lit from the minimum up), tip cards, "Perfect for…" (all five settings, with the ones that don't fit dashed and dimmed), a `<details>` FAQ, an ad, related games, and a closing CTA. Icons are 2px-stroke SVGs, never emojis. Sections fade up 16px as they scroll in (`reveal_controller.js`), which is skipped for reduced motion and leaves content visible without JS. The share image (`public/games/<code>/og.png`) is generated by `bin/rails games:og_images`.

### Benefit List
This is a definition list in two columns. Each item has a 1px Rig Line top rule, an 18px bold white title and one line of Ink Muted copy. No icons and no cards. A sticky heading column sits beside it on desktop.

### Option Picker (signature component)
This is the pre-game config control. A grid of three radio tiles uses Set Panel fill and a 2px Rig Line border at 12px radius. Each tile has a big black-weight value (1.5rem) with a small Ink Faint caption ("Quick", "Standard", "Marathon"). The selected tile's border takes the game's set accent, and the tile gets a 10% tint of that accent as its fill.

### Room-Code Slots (signature component)
This is the Join page's code entry. Four 80–96px Studio Black slots with 2px Rig Line borders and 16px radius show the code in black-weight 2.25–3rem monospace. They sit over one real, invisible text input that keeps paste, autofill and screen readers working. The next slot to fill gets a `purple-400` border and a 10% purple tint, filled slots get `slate-500`, and every slot turns 70% Miss Red on an error. The form submits on its own at the 4th character, and without JS the plain input shows instead.

### Player Row (signature component)
This is the lobby roster entry. It's a Set Panel Raised row with a 1px Rig Line Strong border, 12px radius and 16px padding. A 40px House Purple Lit avatar disc shows the nickname's initial in bold, followed by the nickname in white bold. While players are joining, a pulsing skeleton row sits at the end of the list.

### Toasts and Reveals (game-side)
In-game feedback is injected per game. Toasts slide in and out, badges pop in on a spring curve (`cubic-bezier(0.34, 1.56, 0.64, 1)`), groups and categories enter with a short slide-up, and misses shake. These motions belong to game moments only. Site chrome does not bounce.

## Do's and Don'ts

### Do:
- **Do** build every surface from the slate stack. Stage Floor is the page, Set Panel the card, and Set Panel Raised the nested row, each with a 1px Rig Line.
- **Do** give each game exactly one set accent and use it for selection, key borders and emphasis inside that game.
- **Do** reserve Spotlight Gold for scores, winners and correct or current highlights (The Spotlight Rule).
- **Do** set codes, scores, timers and grid digits in black-weight monospace.
- **Do** keep host-screen text at 1.5rem or larger and weight 700–900 so it can be read across a room.
- **Do** use the Label style (0.75rem, weight 900, widest tracking, uppercase) for field labels and picker headers.
- **Do** keep site chrome calm, using color transitions and a 95% press-down. Save springy motion for game moments.

### Don't:
- **Don't** introduce a light theme or white surfaces. The only white surface is the QR code plate.
- **Don't** look like a casino: no flashing lights, slot-machine glare, stacked neon glows or everything-animating-at-once.
- **Don't** go childish or cartoonish: no mascots, bubbly comic fonts or toy-like chrome. The studio has to suit colleagues and classrooms as well as families.
- **Don't** use the purple→pink gradient beyond the primary start/join CTA, never twice side by side, and never as gradient text.
- **Don't** let two set accents, or house purple plus a set accent, compete inside one game view.
- **Don't** use type smaller than 0.75rem, or put Ink Faint text on Set Panel Raised, where contrast drops too low.
