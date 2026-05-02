Rails.application.routes.draw do
  get "home/index"
  root "home#index"

  get "up" => "rails/health#show", as: :rails_health_check

  resources :rooms, only: [:create, :show] do
    member do
      post "start"
    end
  end

  get "join/:code", to: "rooms#join", as: :join_room
  post "join/:code", to: "rooms#player_join", as: :submit_join
end
