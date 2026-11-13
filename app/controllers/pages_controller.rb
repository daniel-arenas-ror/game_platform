# Static informational pages (privacy, about, contact, Christmas games), linked from the site footer.
class PagesController < ApplicationController
  CONTACT_EMAIL = "contact@grouparty.com".freeze
  GITHUB_URL    = "https://github.com/daniel-arenas-ror".freeze

  # The Christmas page's games for each get-together, best fit first; up to 3 shown, hidden games left out.
  CHRISTMAS_OCCASIONS = {
    family:     %w[guess_the_color doodle_dash letter_wheel color_chain],
    office:     %w[how_want_be_billionare mind_match fisherman tug_of_war],
    kids:       %w[count_birds character_hunt sequence_memory matching_pairs],
    video_call: %w[how_want_be_billionare mind_match soup_of_numbers]
  }.freeze

  before_action { expires_in 1.day, public: true }

  def privacy; end
  def about; end
  def contact; end

  # All year, so it keeps its place in search results for next Christmas (not tied to Christmas mode).
  def christmas
    games = Game.visible.where(:code.in => CHRISTMAS_OCCASIONS.values.flatten, :slug.nin => [ nil, "" ]).index_by(&:code)
    @occasions   = CHRISTMAS_OCCASIONS.transform_values { |codes| codes.filter_map { games[_1] }.first(3) }
    @billionaire = games["how_want_be_billionare"]
    @doodle_dash = games["doodle_dash"]
    @christmas_packs = games.values_at("mind_match", "letter_wheel", "guess_the_color")
    @christmas_questions = HowWantBeBillionare::Question.where(pack: "christmas")
                                                        .where(HowWantBeBillionare::Question.match_for(I18n.locale)).count
  end
end
