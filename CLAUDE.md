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
| `impostor` | Impostor | TODO stub in GameFactory |

FIFA World Cup has data models only (no game logic).

### Key Models (Mongoid — no ActiveRecord migrations)

- **Game** — Static game definitions (name, `code`, description). Seeded. `code` drives routing + GameFactory.
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
8. **`db/seeds.rb`** — Add `Game.find_or_create_by!(code: '{code}')`.

### ActionCable — Two-Layer Model

**Layer 1 — Lobby:** `GameChannel` (`game_{room_code}`) — present before game starts. Broadcasts `player_joined`, `game_started`, `game_changed`.

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

### Mongoid `game_state` Patterns

```ruby
# Atomic nested-field update — preferred for mid-game partial updates
@room.set("game_state.scores" => scores, "game_state.status" => "collecting")

# Full document update — used in setup_game! and status transitions
@room.update!(status: "playing", game_state: @room.game_state.merge({ ... }))

# Always reload before reading state inside background threads
@room.reload
```

### Routing

```
GET   /                        → home#index
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
