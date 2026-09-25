module SeoHelper
  SITE_NAME = "Grouparty".freeze
  DEFAULT_TITLE = "#{SITE_NAME} – Free Party Games You Play From Your Phone".freeze
  DEFAULT_DESCRIPTION = "Free multiplayer party games for groups. Put the host screen on your TV, " \
                        "friends join by scanning a QR code and play from their phones — no app, no sign-up.".freeze

  # Views set these with `content_for :title` / `content_for :description`.
  def page_title
    content_for?(:title) ? "#{content_for(:title)} | #{SITE_NAME}" : DEFAULT_TITLE
  end

  def page_description
    content_for?(:description) ? content_for(:description) : DEFAULT_DESCRIPTION
  end

  def canonical_url
    "#{request.base_url}#{request.path}"
  end

  def og_image_url
    "#{request.base_url}/og-image.png"
  end
end
