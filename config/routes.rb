Rails.application.routes.draw do
  get "home/index"
  root "home#index"

  get "up" => "rails/health#show", as: :rails_health_check

  resources :rooms, only: [:create, :show]
  get "join/:code", to: "rooms#join", as: :join_room
end
