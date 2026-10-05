# The public game pages (/games/:slug). Each game page is lit with its game's set accent.
module GamePagesHelper
  # Full class names, so Tailwind finds them when it scans this file.
  ACCENTS = {
    "fisherman"              => { text: "text-purple-400",  soft: "text-purple-300",  tint: "bg-purple-500/10",  border: "border-purple-500/40",  dot: "bg-purple-400" },
    "how_want_be_billionare" => { text: "text-blue-400",    soft: "text-blue-300",    tint: "bg-blue-500/10",    border: "border-blue-500/40",    dot: "bg-blue-400" },
    "battle_city"            => { text: "text-amber-400",   soft: "text-amber-300",   tint: "bg-amber-500/10",   border: "border-amber-500/40",   dot: "bg-amber-400" },
    "guess_the_color"        => { text: "text-orange-400",  soft: "text-orange-300",  tint: "bg-orange-500/10",  border: "border-orange-500/40",  dot: "bg-orange-400" },
    "count_birds"            => { text: "text-sky-400",     soft: "text-sky-300",     tint: "bg-sky-500/10",     border: "border-sky-500/40",     dot: "bg-sky-400" },
    "sequence_memory"        => { text: "text-indigo-400",  soft: "text-indigo-300",  tint: "bg-indigo-500/10",  border: "border-indigo-500/40",  dot: "bg-indigo-400" },
    "submarine_combat"       => { text: "text-cyan-400",    soft: "text-cyan-300",    tint: "bg-cyan-500/10",    border: "border-cyan-500/40",    dot: "bg-cyan-400" },
    "mind_match"             => { text: "text-violet-400",  soft: "text-violet-300",  tint: "bg-violet-500/10",  border: "border-violet-500/40",  dot: "bg-violet-400" },
    "soup_of_numbers"        => { text: "text-emerald-400", soft: "text-emerald-300", tint: "bg-emerald-500/10", border: "border-emerald-500/40", dot: "bg-emerald-400" },
    "matching_pairs"         => { text: "text-rose-400",    soft: "text-rose-300",    tint: "bg-rose-500/10",    border: "border-rose-500/40",    dot: "bg-rose-400" }
  }.freeze

  CATEGORY_LABELS = {
    "social" => "Social game", "trivia" => "Trivia game", "action" => "Action game",
    "perception" => "Quick-eye game", "memory" => "Memory game", "puzzle" => "Puzzle race",
    "strategy" => "Strategy game"
  }.freeze

  # Game::PERFECT_FOR key => [label, icon]
  SETTINGS = {
    "party"      => [ "Parties", :party ],
    "family"     => [ "Family time", :home ],
    "classroom"  => [ "Classrooms", :school ],
    "work"       => [ "Work teams", :briefcase ],
    "video_call" => [ "Video calls", :video ]
  }.freeze

  # Shown on every game page, after the game's own questions.
  GENERAL_FAQ = [
    { "q" => "Do players need to download an app?",
      "a" => "No. Players scan the QR code on the host screen with their phone camera and play in the browser. No app, no account." },
    { "q" => "Is it free?",
      "a" => "Yes, every game on %{site} is free to play." }
  ].freeze

  # Lucide-style 24×24 stroke paths.
  ICON_PATHS = {
    users:     '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
    clock:     '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
    cake:      '<path d="M20 21v-8a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8M4 16s.5-1 2-1 2.5 2 4 2 2.5-2 4-2 2.5 2 4 2 2-1 2-1M2 21h20M7 8v3M12 8v3M17 8v3M7 4h.01M12 4h.01M17 4h.01"/>',
    phone:     '<rect width="14" height="20" x="5" y="2" rx="2"/><path d="M12 18h.01"/>',
    bulb:      '<path d="M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5M9 18h6M10 22h4"/>',
    party:     '<path d="M5.8 11.3 2 22l10.7-3.79M4 3h.01M22 8h.01M15 2h.01M22 20h.01"/><path d="m22 2-2.24.75a2.9 2.9 0 0 0-1.96 3.12c.1.86-.57 1.63-1.45 1.63h-.38c-.86 0-1.6.6-1.76 1.44L14 10M22 13l-.82-.33c-.86-.34-1.82.2-1.98 1.11-.11.7-.72 1.22-1.43 1.22H17M11 2l.33.82c.34.86-.2 1.82-1.11 1.98-.7.1-1.22.72-1.22 1.43V7"/><path d="M11 13c1.93 1.93 2.83 4.17 2 5-.83.83-3.07-.07-5-2-1.93-1.93-2.83-4.17-2-5 .83-.83 3.07.07 5 2Z"/>',
    home:      '<path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><path d="M9 22V12h6v10"/>',
    school:    '<path d="M22 10 12 5 2 10l10 5 10-5Z"/><path d="M6 12v5c3 3 9 3 12 0v-5"/>',
    briefcase: '<rect width="20" height="14" x="2" y="7" rx="2"/><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/>',
    video:     '<path d="m22 8-6 4 6 4V8Z"/><rect width="14" height="12" x="2" y="6" rx="2"/>',
    check:     '<path d="M20 6 9 17l-5-5"/>',
    chevron:   '<path d="m6 9 6 6 6-6"/>'
  }.freeze

  def game_accent(game)
    ACCENTS.fetch(game.code, ACCENTS["fisherman"])
  end

  def game_category_label(game)
    CATEGORY_LABELS.fetch(game.category.to_s, "Party game")
  end

  def game_page_icon(name, css: "size-5")
    tag.svg(ICON_PATHS.fetch(name).html_safe, class: css, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
            "stroke-width": 2, "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": true)
  end

  def game_players_label(game)
    return "Any group" if game.min_players.blank? || game.max_players.blank?
    return "#{game.min_players} players" if game.min_players == game.max_players

    "#{game.min_players}–#{game.max_players} players"
  end

  def game_faq(game)
    game.faq + GENERAL_FAQ.map { |f| f.merge("a" => format(f["a"], site: SeoHelper::SITE_NAME)) }
  end

  def game_instruction_image?(game)
    File.exist?(Rails.public_path.join("games", game.code, "instructions.png"))
  end
end
