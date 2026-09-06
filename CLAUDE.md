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
# Run RuboCop linter
rubocop

# Run with GitHub-style output (used in CI)
rubocop -f github

# Security scan
brakeman
bundler-audit check --update
```

## Architecture

### What This App Does

A real-time multiplayer game platform where a host creates a **Room**, shares a QR code, and players join via their phones. Games run over WebSockets (ActionCable). Currently implemented games:

- **The Fisherman** (`fisherman`) — Social deduction: players are assigned roles (fisherman, impostor, knower). The fisherman guesses who the impostor is each round.
- **How Want Be Billionaire** (`how_want_be_billionare`) — Timed trivia/quiz with points.

Scaffolded but not yet implemented: Impostor, Quick Draw. FIFA World Cup has data models only.

### Key Models (Mongoid, not ActiveRecord)

- **Game** — Static game definitions (name, `code`, description). Seeded.
- **Room** — A live game session. Has a unique 4-char `code` used in URLs and QR codes. Tracks `status` (`lobby` → `playing` → `finished`). Stores all transient game state in a `game_state` Hash field and `answers_history` Array — no separate tables.
- **Player** — Belongs to a Room. Holds `nickname`, `role`, and `connected` status. Player identity is tracked via HTTP session (`session[:player_id]` → `current_player`).

The `game_state` hash inside Room stores the current question, scores, round count, and any other runtime data. Its shape varies by game type.

### Service Layer

**`GameFactory.build(room)`** — Returns the correct service instance based on `room.game.code`. Entry point from the controller when starting a game.

**`GameServices::Base`** — Shared helpers: `start_points!`, `broadcast_start`.

**`GameServices::Fisherman`** and **`GameServices::HowWantBeBillionare`** — Contain all game logic: setup, role assignment, scoring, round progression.

### ActionCable Channels

Two layers of channels:

1. **`GameChannel`** (`game_{room_code}`) — Lobby channel. Used to broadcast `player_joined` and `game_started` events before a game begins.
2. **`Games::FishermanChannel`** (`fisherman_room_{room_code}`) and **`Games::MillionaireChannel`** (`millionaire_room_{room_code}`) — Game-specific channels. Handle in-game actions like submitting guesses/answers and tracking connection status.

`MillionaireChannel#start_game_loop` runs in a separate thread to drive timed rounds.

### Routing & View Rendering

```
GET  /                   → home#index         (game selection)
POST /rooms              → rooms#create
GET  /rooms/:id          → rooms#show         (lobby + QR code)
POST /rooms/:id/start    → rooms#start        (triggers GameFactory & setup_game!)
GET  /rooms/:id/playing  → rooms#playing      (in-game view)
GET  /join/:code         → rooms#join
POST /join/:code         → rooms#player_join
```

The playing view dynamically renders a game-specific partial:
```ruby
render "rooms/games/#{game_code}/index"
# e.g. app/views/rooms/games/fisherman/_index.html.erb
```

Game configuration views follow the same pattern under `rooms/games/{code}/_edit.html.erb`.

### Frontend

- **Tailwind CSS** via `tailwindcss-rails` (dark theme, bg-slate-900 base)
- **Stimulus** controllers in `app/javascript/controllers/`
- **ActionCable JS** channels in `app/javascript/channels/`
- **Importmap** (no Node/bundler required)
- **Turbo Frames** wrap game state for targeted DOM updates

### Infrastructure Notes

- **MongoDB** via Docker Compose. No ActiveRecord migrations — document structure is defined in models.
- **Production ActionCable** requires Redis (`REDIS_URL` env var, see `config/cable.yml`).
- **CI** runs on GitHub Actions: RuboCop → Brakeman/bundler-audit → unit tests → system tests.

### Known Issues

- `Fisherman::Question` has a typo: the field is named `answerds` (not `answers`).
- Several `p` debug statements exist in the channel files; not suitable for production.
