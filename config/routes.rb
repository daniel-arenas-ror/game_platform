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
