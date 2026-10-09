xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
# Every page once per language, each listing all its languages (hreflang) as Google asks.
locales = I18n.available_locales.map { |l| [ l, (l == I18n.default_locale ? nil : l) ] }

pages = [ [ :root_url, "weekly", "1.0" ], [ :games_url, "weekly", "0.8" ], [ :find_room_url, "weekly", "0.8" ] ]
pages += Game.visible.where(:slug.nin => [ nil, "" ]).map { |game| [ :game_url, "monthly", "0.8", game ] }
pages += [ [ :about_url, "monthly", "0.5" ], [ :contact_url, "monthly", "0.5" ], [ :privacy_url, "monthly", "0.5" ] ]

xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9", "xmlns:xhtml" => "http://www.w3.org/1999/xhtml" do
  pages.each do |helper, changefreq, priority, game|
    urls = locales.to_h { |locale, prefix| [ locale, game ? send(helper, game, locale: prefix) : send(helper, locale: prefix) ] }

    urls.each_value do |loc|
      xml.url do
        xml.loc loc
        urls.each { |locale, href| xml.tag! "xhtml:link", rel: "alternate", hreflang: locale, href: href }
        xml.tag! "xhtml:link", rel: "alternate", hreflang: "x-default", href: urls[I18n.default_locale]
        xml.lastmod game.updated_at.to_date.iso8601 if game&.updated_at
        xml.changefreq changefreq
        xml.priority priority
      end
    end
  end
end
