# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Development

```bash
# Start MongoDB (required before running the app)
docker compose up -d

# Start the dev server (Rails + Tailwind watcher via Foreman)
bin/dev

# Seed the database with games and questions
bin/rails db:seed
```

### Testing

```bash
# Run all unit and integration tests
bin/rails test

# Run a single test file
bin/rails test test/models/room_test.rb

# Run system tests (requires browser/Selenium)
bin/rails test:system
```

### Linting & Security

```bash
rubocop
rubocop -f github          # GitHub-style output (used in CI)
brakeman
bundler-audit check --update
```

## Architecture

### What This App Does

A real-time multiplayer game platform. A host creates a **Room**, shares a QR code, and players join via their phones. Games run over WebSockets (ActionCable). The host screen stays on a TV/laptop; players interact on their phones.

### Implemented Games

| Code | Name | Notes |
|------|------|-------|
| `fisherman` | The Fisherman | Social deduction with roles (fisherman/impostor/knower) |
| `how_want_be_billionare` | How Want Be Billionaire | Timed trivia |
| `battle_city` | Battle City | Full |
| `guess_the_color` | Guess The Color | Full |
| `count_birds` | Count Birds | Full |
| `sequence_memory` | Sequence Memory | Full |
| `submarine_combat` | Submarine Combat | Ship placement + battle loop |
| `mind_match` | Mind Match | Word-matching telepathy game |
| `soup_of_numbers` | Soup of Numbers | Digit word-search race; first to tap the host's number scores |
| `doodle_dash` | Doodle Dash | Drawing + guessing: artist draws on their phone, the drawing shows on the TV only |
| `impostor` | Impostor | TODO stub in GameFactory |

FIFA World Cup has data models only (no game logic).

### Key Models (Mongoid — no ActiveRecord migrations)

- **Game** — Static game definitions (name, `code`, description) plus the public game page content. Seeded from `db/seeds/games/*.yml`; the seeds upsert by `code`, so game IDs stay stable. `code` drives GameFactory; `slug` is the public URL (`to_param`). `listed: false` in the YAML hides a game from the public site in production while it's being built (`Game.visible`; development shows everything). Lists use `Game.catalog`: games with a `position` (set in the YAML) first, then the rest by `rooms_count` (+1 per room created; recount with `bin/rails games:count_rooms`).
- **Room** — A live session. Unique 4-char `code`. `status`: `lobby` → `playing` → `finished`. `game_state` Hash stores all transient runtime state — shape varies by game.
- **Player** — Belongs to a Room. `nickname`, `role`, `connected` (Boolean). Identity tracked via `session[:player_id]`.

### Service Layer

**`GameFactory.build(room)`** — Entry point from `rooms#start`. Returns the correct service based on `room.game.code`.

**`GameServices::Base`** — Shared helpers: `start_points!`, `broadcast_start`.

Each game service implements at minimum:
- `setup_game!` — Initializes `game_state`, sets `room.status = "playing"`, calls `broadcast_start`.
- Game logic methods (scoring, round progression, answer handling, etc.)

### Adding a New Game — Required Files

1. **`app/services/game_services/{code}.rb`** — Inherits `Base`. Implements `setup_game!` + game logic.
2. **`app/channels/games/{code}_channel.rb`** — Handles WebSocket actions. Streams from `{code}_room_{room_code}`.
3. **`app/services/game_factory.rb`** — Add `when '{code}' then GameServices::{Name}.new(room)`.
4. **`app/controllers/rooms_controller.rb`** — Add `"{code}" => "{code}_room_"` to `GAME_STREAM_PREFIXES`.
5. **`app/views/rooms/games/{code}/_index.html.erb`** — In-game view. Rendered dynamically by `rooms#playing`. Root element needs `data-controller`, `data-{ctrl}-room-code-value`, `data-{ctrl}-player-id-value`.
6. **`app/javascript/controllers/{code}_host_controller.js`** + **`{code}_player_controller.js`**
7. *(Optional)* **`app/views/rooms/games/{code}/_edit.html.erb`** — Pre-game config pickers.
8. **`db/seeds/games/{code}.yml`** + add `{code}` to `GAME_CODES` in `db/seeds.rb` — name, `slug` (public URL `/games/{slug}`, never change it once live), description and the game page content (tagline, long_description, min/max_players, players_note, duration_minutes, age, category, how_to_play, tips, perfect_for, faq). Write it from the real rules in the service/channel. `games_controller_test.rb` checks every file is complete.
9. **Winner celebration (required)** — the player controller's game-over handler must call the shared celebration for the winner(s). See *Winner Celebration* below.
10. **Game page assets** — add the game's accent to `GamePagesHelper::ACCENTS`, then run `bin/rails games:og_images ONLY={code}` to build `public/games/{code}/og.png` (1200×630 share image, made from `instructions.png`; needs ImageMagick + pngquant).

### ActionCable — Two-Layer Model

**Layer 1 — Lobby:** `GameChannel` (`game_{room_code}`) — present before game starts. Broadcasts `player_joined`, `game_started`, `game_changed`.

**Player presence:** every channel loads the player with `find_player` (rejects removed players) and calls `track_player_subscribed` / `track_player_unsubscribed` (helpers in `ApplicationCable::Channel`). When a player's last subscription closes, `PlayerRemover` deletes them after a 30s grace period, drops their keys from `game_state`, broadcasts `player_left`, and calls the game service's `player_removed!` hook.

**Layer 2 — Game-specific:** `Games::{Name}Channel` (`{code}_room_{room_code}`) — subscribed by Stimulus when the playing view loads. Drives all in-game events.

### Stimulus Controller Conventions

```javascript
static values  = { roomCode: String, playerId: String }
static targets = [ "phaseWaiting", "phaseRound", "phaseReveal", "phaseGameOver", ... ]

connect() {
  this.channel = consumer.subscriptions.create(
    { channel: "Games::XChannel", room_code: this.roomCodeValue, player_id: this.playerIdValue },
    { connected: () => this.onConnected(), received: (data) => this.handleMessage(data) }
  )
}

handleMessage(data) {
  switch (data.action) { /* route to handlers */ }
}

showPhase(name) {
  ["phaseWaiting", ...].forEach(p => {
    this[`${p}Target`].classList.toggle("hidden", p !== name)
  })
}
```

- **Host** = `player_id` is blank. Host calls `channel.perform("start_game_loop", {})` in `onConnected()`.
- **Player** = `player_id` from `session[:player_id]`.
- Always `unsubscribe()` and `clearInterval()` in `disconnect()`.
- Inject CSS animations once via `<style id="...">` — check for existing tag before inserting.

### Winner Celebration (every game)

Every game plays the same celebration on the winning player's phone at game over: confetti plus a
pop-in on the game-over title. It lives in `app/javascript/controllers/shared/celebration.js`. Don't
write a game-specific version.

```javascript
import { celebrateWin, isTopScore } from "controllers/shared/celebration"

onGameOver(data) {
  // … fill in the game-over screen, show the phase …
  if (isTopScore(data.scores, this.playerIdValue)) celebrateWin(this.gameOverTitleTarget)
}
```

- Call it **after** the game-over phase is visible, so the pop on the title shows.
- `isTopScore` counts tied players as winners. Games with an explicit winner (e.g. `data.winner_id`) use that instead.
- `celebrateWin()` without an element still plays the confetti.
- `confetti(count)` and `pop(el)` are also exported for other moments (board cleared, host game over).

### Mongoid `game_state` Patterns

```ruby
# Atomic nested-field update — preferred for mid-game partial updates
@room.atomic_set("game_state.scores" => scores, "game_state.status" => "collecting")

# ⚠️ Don't use Mongoid's @room.set("game_state.x" => …): on a Hash field it writes the WHOLE
# game_state from the in-memory copy, wiping writes made by other connections (player answers).
# For "write only if …" (e.g. one answer per player) use Room.collection.update_one with a filter.

# Full document update — used in setup_game! and status transitions
@room.update!(status: "playing", game_state: @room.game_state.merge({ ... }))

# Always reload before reading state inside background threads
@room.reload
```

### Routing

```
GET   /                        → home#index
GET   /games                   → games#index (catalog; ?room=CODE = change-game mode)
GET   /games/:slug             → games#show (public SEO game page + Start game)
POST  /rooms                   → rooms#create
GET   /rooms/:id               → rooms#show (lobby + QR)
PATCH /rooms/:id               → rooms#update (config)
POST  /rooms/:id/start         → rooms#start → GameFactory → setup_game!
GET   /rooms/:id/playing       → rooms#playing (renders game partial)
POST  /rooms/:id/change_game   → rooms#change_game
GET   /join/:code              → rooms#join
POST  /join/:code              → rooms#player_join
```

### Frontend

- **Tailwind CSS** via `tailwindcss-rails`. Dark theme: `bg-slate-950` base, `bg-slate-800` cards, `border-slate-700` borders. Per-game accent colors (violet for Mind Match, cyan for Submarine Combat, etc.).
- **Stimulus** auto-loaded via `eagerLoadControllersFrom("controllers", application)` — no manual registration.
- **Importmap** — no Node/bundler. Use ES6 `import` only.
- Turbo is available but game views use direct DOM manipulation via Stimulus, not Turbo Frames.

### Infrastructure

- **MongoDB** via Docker Compose. `config/mongoid.yml` for connection.
- **ActionCable** uses `async` adapter in dev, **Redis** (`REDIS_URL`) in production (`config/cable.yml`).
- **CI** (GitHub Actions): RuboCop → Brakeman/bundler-audit → unit tests → system tests.

### Known Issues

- `Fisherman::Question` has a typo: field is `answerds` (not `answers`). The service and game_state reference this typo — do not "fix" it without updating all references.
- `p` debug statements exist in `FishermanChannel` and `MillionaireChannel` — not production-safe.
- `HowWantBeBillionareChannel` uses BSON::ObjectId casting with rescue blocks for question ID lookups.
