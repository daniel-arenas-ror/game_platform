Apply consistent Tailwind CSS styling to the file(s) the user specifies, following this project's design system. Make only styling changes — do not alter logic, structure, or copy.

## Design System

### Color Palette

| Layer | Class |
|-------|-------|
| Page background | `bg-slate-950` |
| Section / card | `bg-slate-800` or `bg-slate-900/50` |
| Card border | `border border-slate-700` |
| Body text | `text-white` |
| Secondary text | `text-slate-400` |
| Muted / label text | `text-slate-500` |
| Mono labels (uppercase tracking) | `text-slate-400 font-mono text-xs uppercase tracking-widest` |

### Per-Game Accent Colors

Each game uses one accent color across all its views and controllers. Do not mix accents within a game.

| Game | Accent |
|------|--------|
| Mind Match | `violet` |
| Submarine Combat | `cyan` |
| Fisherman | `emerald` (use existing) |
| Guess The Color | `pink` (use existing) |
| Count Birds | `sky` (use existing) |
| Sequence Memory | `indigo` (use existing) |
| Battle City | `orange` (use existing) |
| How Want Be Billionaire | `yellow` (use existing) |

### Cards & Containers

```
bg-slate-800 border-2 border-{accent}-500 rounded-2xl px-5 py-4       ← active / selected
bg-slate-800 border-2 border-slate-700   rounded-2xl px-5 py-4       ← inactive
bg-slate-900/50 border border-slate-700  rounded-2xl p-6             ← config section
```

### Buttons

```
Primary action:
  px-8 py-4 bg-{accent}-600 text-white font-black text-lg rounded-2xl
  hover:bg-{accent}-500 transition-colors

Disabled state (add to primary):
  disabled:opacity-30 disabled:cursor-not-allowed

Destructive / secondary:
  px-6 py-3 bg-slate-700 text-white font-semibold rounded-xl hover:bg-slate-600 transition-colors
```

### Inputs

```
w-full bg-slate-800 border-2 border-slate-600 rounded-2xl px-5 py-4
text-white text-xl text-center font-semibold placeholder-slate-600
focus:outline-none focus:border-{accent}-500 transition-colors
```

### Timer Ring

```
w-16 h-16 rounded-full border-4 border-{accent}-500
flex items-center justify-center
text-{accent}-400 font-black text-xl tabular-nums
```
When urgent (≤ 5 s): swap `{accent}` for `red`.

### Player / Score Badges

```
Rank badge:  px-4 py-2 bg-slate-800 border border-{accent}-500/40 rounded-full text-{accent}-300 text-sm font-semibold
Score row:   flex items-center justify-between px-5 py-3 bg-slate-800 rounded-xl
  name:  text-white font-semibold
  score: text-{accent}-300 font-black
Winner highlight row: border border-{accent}-500/60 bg-{accent}-500/10 rounded-xl
```

### Layout

- **Host views**: center column, `max-w-2xl` for content grids, `max-w-sm` for score lists.
- **Player views**: full-width mobile, `max-w-sm` for cards and inputs. Use `min-h-screen` with flex center for phase screens.
- **Phase screens**: `flex flex-col items-center justify-center min-h-screen p-6 text-center`

### Config Pickers (_edit.html.erb)

```erb
<div class="space-y-4 bg-slate-900/50 p-6 rounded-2xl border border-slate-700">
  <label class="block text-xs font-bold text-slate-400 mb-3 tracking-widest">LABEL</label>
  <div class="grid grid-cols-3 gap-3">
    <label class="relative cursor-pointer">
      <input type="radio" class="peer hidden" ...>
      <div class="text-center py-4 bg-slate-800 border-2 border-slate-700 rounded-xl transition-all
                  peer-checked:border-{accent}-500 peer-checked:bg-{accent}-500/10">
        <p class="text-white font-black text-2xl">...</p>
        <p class="text-slate-500 text-xs mt-1">...</p>
      </div>
    </label>
  </div>
</div>
```

### Toast Notifications

```
fixed bottom-6 left-1/2 -translate-x-1/2 z-50 flex flex-col items-center gap-3 pointer-events-none
```

Individual toast:
```
px-5 py-3 rounded-2xl border shadow-xl text-white text-sm font-semibold max-w-xs text-center
```
Colors: match/win → `bg-{accent}-700 border-{accent}-400`, neutral → `bg-slate-700 border-slate-500`, miss/error → `bg-red-900 border-red-500`.

## What to Check

When styling a file, verify:
1. Background layers use the correct slate scale.
2. The game's accent color is applied consistently — no mixing with other games' accents.
3. All interactive elements have `hover:` and `transition-colors`.
4. Radio picker cards use the `peer-checked:` pattern (not JavaScript-toggled active classes).
5. Disabled buttons have `disabled:opacity-30 disabled:cursor-not-allowed`.
6. No inline `style=` except for dynamic values (progress bar widths, animation delays).
7. Mobile player screens never overflow horizontally (no fixed widths wider than viewport).
