Review the file(s) or feature specified by the user against this project's Rails + frontend conventions. Check each of the following and report findings grouped by category. Only report issues you actually find — skip categories that are clean.

## Ruby / Rails

- **Mongoid patterns**: Use `@room.set(...)` for partial `game_state` updates mid-game. Use `@room.update!(...)` only for top-level field changes or full `game_state` replacement in `setup_game!`. Always call `@room.reload` before reading state inside background threads or channel actions.
- **Thread safety**: Game loop threads must check `@stop_loop` before each blocking operation. Rescue all exceptions inside `Thread.new` blocks, log them, broadcast `game_error`, and reset room status.
- **Channel host guard**: Channel actions that only the host may call must start with `return unless host?` (where `host?` is `@player.nil?`).
- **No `p` statements**: Use `Rails.logger.error/warn/info` instead.
- **Service layer**: Game logic belongs in `GameServices::*`, not in channels or controllers. Channels only route messages and call service methods.
- **Rubocop**: Run `rubocop` and fix any offenses before considering work complete.

## Stimulus / JavaScript

- **Disconnect cleanup**: `disconnect()` must call `this.channel?.unsubscribe()` and `clearInterval` / `cancelAnimationFrame` for every timer or animation frame started in `connect()` or message handlers.
- **Style injection**: CSS keyframes must be injected once via a `<style id="...">` tag — check for the existing tag before inserting (`if (document.getElementById("...")) return`).
- **XSS safety**: All user-supplied strings rendered into `innerHTML` must be passed through an `esc()` helper that escapes `& < > "`.
- **Target guards**: Access targets defensively (`this.someTarget?.textContent = ...` or check `this.hasSomTarget`) when a target might not exist on all views.
- **Phase switching**: Use a `showPhase(name)` method that iterates all phase target names and toggles `.hidden`. Don't scatter individual `classList.add/remove("hidden")` calls.

## Views / HTML

- **Dark theme consistency**: Base background `bg-slate-950`, cards `bg-slate-800`, subtle borders `border-slate-700`. Each game has one accent color applied consistently (e.g., `violet` for Mind Match, `cyan` for Submarine Combat).
- **Mobile-first**: Player views are phone-sized. Avoid fixed widths that overflow on small screens. Use `w-full max-w-sm` for player content and `max-w-xl` or `max-w-2xl` for host content.
- **Tailwind only**: No inline `style=` attributes except for dynamic values that can't be expressed as classes (e.g., `style="width: 42%"` for animated progress bars).
- **Targets wired up**: Every `data-{controller}-target="foo"` in the view must have a matching entry in the controller's `static targets` array, and vice versa.

## Game-Specific Checklist (when adding/editing a game)

- [ ] `GameFactory.build` has a `when '{code}'` case
- [ ] `GAME_STREAM_PREFIXES` in `rooms_controller.rb` has the `"{code}" => "{code}_room_"` entry
- [ ] `db/seeds.rb` has `Game.find_or_create_by!(code: '{code}')`
- [ ] `setup_game!` merges into existing `game_state` (to preserve host-configured settings like `total_rounds`)
- [ ] `loop_running` flag set/cleared to prevent duplicate game loops on host reconnect
- [ ] `state_snapshot` transmit includes `nicknames` map and any per-player state a reconnecting client needs
