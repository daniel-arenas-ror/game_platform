xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  xml.url do
    xml.loc root_url
    xml.changefreq "weekly"
    xml.priority "1.0"
  end

  [ about_url, contact_url, privacy_url ].each do |url|
    xml.url do
      xml.loc url
      xml.changefreq "monthly"
      xml.priority "0.5"
    end
  end
end
