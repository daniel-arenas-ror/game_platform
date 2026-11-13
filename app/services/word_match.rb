# Compares words that players type: no accents, any case, outer punctuation and extra spaces ignored,
# singular and plural fold to the same word in the room's language. Used by Mind Match and Letter Wheel.
module WordMatch
  module_function

  def normalize(raw, locale)
    fold(clean(raw), locale)
  end

  def clean(raw)
    raw.to_s
       .unicode_normalize(:nfkd).gsub(/\p{Mn}/, "") # no accents: "camión" = "camion"
       .downcase
       .strip
       .gsub(/[[:punct:]]+\z/, "")   # strip trailing punctuation
       .gsub(/\A[[:punct:]]+/, "")   # strip leading punctuation
       .gsub(/\s+/, " ")             # collapse internal spaces
  end

  def fold(w, locale)
    locale.to_s == "es" ? fold_spanish_plural(w) : fold_english_plural(w)
  end

  # "cats" → "cat", but keep "grass", "plus", "virus"
  def fold_english_plural(w)
    return w.chomp("s") if w.length > 3 && w.end_with?("s") && !w.end_with?("ss", "us", "is", "as", "os")

    w
  end

  # Singular and plural fold to the same stem, so they match whichever one people type:
  # "gato"/"gatos" → "gato", "flor"/"flores" → "flor", "clase"/"clases" → "clas", "luz"/"luces" → "luz".
  def fold_spanish_plural(w)
    return w if w.length < 4 || w.include?(" ")
    return w.sub(/ces\z/, "z") if w.match?(/[aeiou]ces\z/)

    w = w.chomp("s")
    w = w.chomp("e") if w.match?(/[^aeiou]e\z/)
    w
  end
end
