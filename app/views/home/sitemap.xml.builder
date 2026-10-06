xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  xml.url do
    xml.loc root_url
    xml.changefreq "weekly"
    xml.priority "1.0"
  end

  [ games_url, find_room_url ].each do |url|
    xml.url do
      xml.loc url
      xml.changefreq "weekly"
      xml.priority "0.8"
    end
  end

  Game.visible.where(:slug.nin => [ nil, "" ]).each do |game|
    xml.url do
      xml.loc game_url(game)
      xml.lastmod game.updated_at.to_date.iso8601 if game.updated_at
      xml.changefreq "monthly"
      xml.priority "0.8"
    end
  end

  [ about_url, contact_url, privacy_url ].each do |url|
    xml.url do
      xml.loc url
      xml.changefreq "monthly"
      xml.priority "0.5"
    end
  end
end
