Rails.application.routes.draw do
  root "home#index"
  get "games", to: "games#index", as: :games
  get "games/:slug", to: "games#show", as: :game
  get "sitemap.xml", to: "home#sitemap", defaults: { format: :xml }, as: :sitemap
  get "robots.txt", to: "home#robots", defaults: { format: :text }, as: :robots

  get "privacy", to: "pages#privacy", as: :privacy
  get "about",   to: "pages#about",   as: :about
  get "contact", to: "pages#contact", as: :contact

  get "up" => "rails/health#show", as: :rails_health_check

  # Hidden super admin. Its address is a secret kept in the encrypted credentials (admin_path), so
  # nothing in the code or on the site points to it; any other address is the normal 404.
  # Without the credential, production has no admin at all.
  if (admin_path = Rails.application.credentials.admin_path.presence || ("admin" unless Rails.env.production?))
    devise_for :admin_users, path: admin_path, path_names: { sign_in: "login", sign_out: "logout" },
                             controllers: { sessions: "admin/sessions" }
    namespace :admin, path: admin_path do
      root "dashboard#show"
    end
  end

  resources :rooms, only: [:create, :show, :edit, :update] do
    member do
      post "start"
      get "playing"
      post "change_game"
    end
  end

  get "join", to: "join#show", as: :find_room
  get "join/:code", to: "rooms#join", as: :join_room
  post "join/:code", to: "rooms#player_join", as: :submit_join
end
