# Room screens: lobby, join form and settings.
module RoomsHelper
  # Solid avatar discs, picked from the nickname so a player keeps one colour on every screen,
  # including the preview on the join form. Keep in step with AVATAR_COLORS in
  # controllers/shared/avatar.js (same list, same order).
  AVATAR_COLORS = %w[bg-purple-500 bg-pink-500 bg-sky-500 bg-emerald-500 bg-orange-500 bg-violet-500 bg-rose-500 bg-cyan-600].freeze

  def player_avatar_color(nickname)
    AVATAR_COLORS[nickname.to_s.each_char.sum(&:ord) % AVATAR_COLORS.size]
  end
end
