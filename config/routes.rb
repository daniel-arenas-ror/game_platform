Rails.application.routes.draw do
  root "home#index"
  get "sitemap.xml", to: "home#sitemap", defaults: { format: :xml }, as: :sitemap
  get "robots.txt", to: "home#robots", defaults: { format: :text }, as: :robots

  get "up" => "rails/health#show", as: :rails_health_check

  resources :rooms, only: [:create, :show, :edit, :update] do
    member do
      post "start"
      get "playing"
      post "change_game"
    end
  end

  get "join/:code", to: "rooms#join", as: :join_room
  post "join/:code", to: "rooms#player_join", as: :submit_join
end
