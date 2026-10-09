module SeoHelper
  SITE_NAME = "Grouparty".freeze

  # Views set these with `content_for :title` / `content_for :description`.
  def page_title
    content_for?(:title) ? "#{content_for(:title)} | #{SITE_NAME}" : t("seo.default_title", site: SITE_NAME)
  end

  def page_description
    content_for?(:description) ? content_for(:description) : t("seo.default_description")
  end

  def canonical_url
    "#{request.base_url}#{request.path}"
  end

  # Views can swap the 1200×630 share image with `content_for :og_image, "/games/<code>/og.png"`.
  def og_image_url
    "#{request.base_url}#{content_for?(:og_image) ? content_for(:og_image) : "/og-image.png"}"
  end
end
