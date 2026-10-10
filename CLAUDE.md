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

# Import game questions (both languages; safe to re-run, never deletes)
bin/rails questions:billionaire:import
bin/rails questions:fisherman:import
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
8. **`db/seeds/games/{code}.yml`** + add `{code}` to `GAME_CODES` in `db/seeds.rb` — name, `slug` (public URL `/games/{slug}`, never change it once live), description and the game page content (tagline, long_description, min/max_players, players_note, duration_minutes, age, category, how_to_play, tips, perfect_for, faq). Write it from the real rules in the service/channel, then the Spanish version of the text fields under `translations: es:` (see *Languages*). `games_controller_test.rb` checks every file is complete in both languages.
9. **Winner celebration (required)** — the player controller's game-over handler must call the shared celebration for the winner(s). See *Winner Celebration* below.
10. **Game page assets** — add the game's accent to `GamePagesHelper::ACCENTS`, then run `bin/rails games:webp ONLY={code}` (the WebP copies pages actually show: 400/640 px, full and top-cropped "card"; needs libvips) and `bin/rails games:og_images ONLY={code}` (`og.png`, the 1200×630 share image; needs ImageMagick + pngquant). Both are made from `instructions.png`. Show game images with `game_image_tag` (srcset + `?v=` digest, since public files are cached for a year), never `image_tag` on the PNG.

### ActionCable — Two-Layer Model

**Layer 1 — Lobby:** `GameChannel` (`game_{room_code}`) — present before game starts. Broadcasts `player_joined`, `game_started`, `game_changed`.

**Player presence:** every channel loads the player with `find_player` (rejects removed players) and calls `track_player_subscribed` / `track_player_unsubscribed` (helpers in `ApplicationCable::Channel`). When a player's last subscription closes, `PlayerRemover` deletes them after a 30s grace period, drops their keys from `game_state`, broadcasts `player_left`, and calls the game service's `player_removed!` hook.

**Players panel (every room screen):** `shared/_room_players` is rendered by `rooms/show` (lobby) and `rooms/playing`, so every game gets it with no per-game code. The host sees a "Players" button (bottom-left) that lists everyone (`GET /rooms/:id/players`) and removes a player (the lobby list also has a Remove button per row; both use `controllers/shared/remove_player.js` → `DELETE /rooms/:id/players/:player_id` → `PlayerRemover`, the same cleanup as a disconnect, so games waiting for every answer go on). Both actions are host-only (no `session[:player_id]`). `RoomChannel` (`room_{code}`, no presence counting) tells the removed phone to go to the join page. Keep the game's own fixed elements away from the bottom-left corner.

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
GET   /<admin_path>            → admin/dashboard#show (hidden super admin, Devise login at /<admin_path>/login)
```

### Admin & Stats

- **`Event`** — append-only log for the admin stats: `room_created` (Room `after_create`), `player_joined` (Player `after_create`), `game_started` (wrapped around every service's `setup_game!` by `GameServices::Base::TrackStart`; `again: true` for play again). Never store nicknames. Days are counted in **UTC**. `bin/rails events:backfill_rooms` rebuilds `room_created` for old rooms (players and games played can't be rebuilt: players are deleted when they leave).
- **Admin** — Devise `AdminUser` (lockable, timeoutable, trackable; no sign-up or password reset). The address is the secret `admin_path` in the encrypted credentials (dev/test fall back to `/admin` without it; production has no admin without it). Never link to it, put it in the sitemap or robots.txt. Admin pages use `layouts/admin` (no ads, noindex) and inherit `Admin::BaseController`.
- **Dashboard** — `AdminStats` (app/services/admin_stats.rb) counts everything with Mongo aggregations on `Event`: rolling periods (today / 7 / 30 days / all) compared with the window before, 30 UTC days per day for the server-drawn SVG charts (`AdminHelper#admin_daily_chart`), and the game ranking by games played. Stats tests use a random far-past `now:` each, since tests share one DB in parallel.
- **Menu** (`AdminHelper#admin_menu`, in `layouts/admin`): Dashboard (the admin root) and Rooms. Add new admin pages there.
- **Rooms** (`Admin::RoomsController`): every room newest first, 50 a page, filtered by status, game or code; a room's page shows its players now (online/offline, score), its `Event` history and the raw `game_state`. Admin pages are English only and times are UTC.
- `bin/rails admin:create EMAIL=…` creates an admin or resets the password (asks in a terminal; prints a generated one when there's no terminal, e.g. `script/aws_run.sh`). Also `admin:list`, `admin:delete EMAIL=…`.

### Languages (i18n)

English and Spanish (`config/initializers/locale.rb`). Strings live in `config/locales/en.yml` / `es.yml` with the same keys.

- **URLs:** English has no prefix (`/games`), Spanish uses `/es` (`/es/games`); routes sit in `scope "(:locale)"`. `default_url_options` adds the prefix, so always build links with route helpers, never hard-coded paths on public pages. Slugs are the same in both languages.
- **Header picker** (`shared/_locale_picker`) → `GET /language?lang=es&return_to=…` (`LocalesController`) sets the `locale` cookie and returns to the same page in that language. Unprefixed public pages redirect to `/es` when the cookie (or, on a first visit, `Accept-Language`) prefers Spanish.
- **Rooms keep their language:** `Room#locale` is set from the page that created the room. `RoomsController#room_locale` (and `GamesController` in change-game mode) force that language whatever the URL or cookie, so a phone scanning the QR code sees the host's language. Room screens have no picker.
- **In-game strings** live in `config/locales/games/<code>.en.yml` / `.es.yml`: the view's lazy keys (`rooms.games.<code>.index.*`) and the JS keys (`js.<code>.*`). Words every game uses (Room:, GAME OVER, Play Again, place titles…) are in `games/shared.*.yml`. A page only embeds its own game's `js.<code>` strings.
- **JS strings:** `import { t, num, placeTitle } from "controllers/shared/i18n"` → `t("game.key", { name })` (`%{name}` interpolation, `one`/`other` plurals with `count`), `num(1000)` formats in the room's language, `placeTitle(rank)` gives "🥇 You Win!" / "2nd Place". Tests fail when a `t("…")` key in the JS is missing in either language, and the test env raises on missing view keys.
- **Escape player text in HTML:** nicknames, guesses and words are typed by players. Use `textContent`, or `escapeHtml()` from `controllers/shared/html` (or the controller's `esc`) before putting them in an `innerHTML` template — also when they go through `t()`.
- **Game content per language:** every room gets content in its own language.
  - Billionaire: `db/questions/how_want_be_billionare/*.yml` (English) and `es/*.yml` (Spanish, same order and points). Fisherman: `db/questions/fisherman/{en,es}.yml`. Both models include `LocalizedQuestion` (`locale` field; no locale = English; a language with no questions falls back to English). Re-run the import tasks after editing.
  - Doodle Dash: `config/doodle_dash/words.yml` / `words.es.yml`; `blocked_words.yml` covers both languages (keep drawable words out of it — a test checks).
  - Mind Match: `MindMatch::CATEGORIES` per locale; `normalize_word` ignores accents and folds English or Spanish plurals by room language.
  - Matching Pairs: `Catalog::LABELS["es"]` names every card (image alt text).
- **SEO:** each public page has hreflang alternates + `og:locale`; the sitemap lists every page in both languages.
- **Game content:** `Game::TRANSLATED_FIELDS` (name, description, tagline, how_to_play, faq…) read `translations[locale]` and fall back to English; the Spanish lives in each `db/seeds/games/<code>.yml` under `translations: es:`. Re-run `bin/rails db:seed` after editing.
- **Prose pages** (about, privacy, contact) are one template per language (`about.es.html.erb`); keep both in sync. Everything else uses lazy keys (`t(".title")`). A test fails when en.yml and es.yml don't have the same keys.

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
