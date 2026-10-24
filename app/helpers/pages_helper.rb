# The about page and /llms.txt: plain facts about the site that people, search engines and AI
# assistants can quote.
module PagesHelper
  # [fewest, most] players across the public games, e.g. [1, 30].
  def site_players_range(games = Game.visible.to_a)
    [ games.filter_map(&:min_players).min || 1, games.filter_map(&:max_players).max ]
  end

  # schema.org JSON-LD for the about page: who runs the site, the site itself and its FAQ
  # (`faq` is [[question, answer], …], the same list the page shows).
  def about_structured_data(faq)
    organization = { "@type" => "Organization", "@id" => "#{root_url}#organization", "name" => SeoHelper::SITE_NAME,
                     "url" => root_url, "email" => PagesController::CONTACT_EMAIL,
                     "founder" => { "@type" => "Person", "name" => "Daniel Arenas", "sameAs" => PagesController::GITHUB_URL },
                     "sameAs" => SeoHelper::SOCIAL_LINKS.values }
    website = { "@type" => "WebSite", "@id" => "#{root_url}#website", "name" => SeoHelper::SITE_NAME, "url" => root_url,
                "inLanguage" => I18n.available_locales.map(&:to_s), "publisher" => { "@id" => organization["@id"] } }
    about = { "@type" => "AboutPage", "url" => about_url, "inLanguage" => I18n.locale.to_s,
              "about" => { "@id" => organization["@id"] }, "isPartOf" => { "@id" => website["@id"] } }
    questions = { "@type" => "FAQPage", "@id" => "#{about_url}#faq",
                  "mainEntity" => faq.map { |q, a| { "@type" => "Question", "name" => q, "acceptedAnswer" => { "@type" => "Answer", "text" => a } } } }

    { "@context" => "https://schema.org", "@graph" => [ organization, website, about, questions ] }
  end
end
