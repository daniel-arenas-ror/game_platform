# Game questions written in one language. A room only gets questions in its own language, and
# English ones while its language has none yet. Questions saved before languages existed have no
# locale and count as English.
module LocalizedQuestion
  extend ActiveSupport::Concern

  included do
    field :locale, type: String, default: "en"
  end

  class_methods do
    # A $match stage for the room's language.
    def match_for(locale)
      locale = locale.to_s
      return { "locale" => { "$in" => [ nil, "en" ] } } if locale == "en"

      where(locale: locale).exists? ? { "locale" => locale } : match_for("en")
    end
  end
end
