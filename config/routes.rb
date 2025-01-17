# config/routes.rb

Rails.application.routes.draw do
  # Authentication
  post '/signup', to: 'users#create'
  post '/login',  to: 'sessions#create'

  # Standard RESTful
  resources :restaurants, only: [:index, :show, :create, :update, :destroy]
  resources :seat_sections, only: [:index, :show, :create, :update, :destroy]
  resources :seats, only: [:index, :show, :create, :update, :destroy]
  resources :reservations, only: [:index, :show, :create, :update, :destroy]
  resources :waitlist_entries, only: [:index, :show, :create, :update, :destroy]

  # SeatAllocations
  resources :seat_allocations, only: [:index, :create, :update, :destroy] do
    collection do
      post :multi_create    # occupant => seated
      post :reserve        # occupant => reserved
      post :arrive         # occupant => 'seated' from 'reserved'
      post :no_show        # occupant => 'no_show'
      post :cancel         # occupant => 'canceled'
    end
  end

  # Menus & Items
  resources :menus, only: [:index, :show, :create, :update, :destroy]
  resources :menu_items, only: [:index, :show, :create, :update, :destroy]

  # Notifications
  resources :notifications, only: [:index, :show, :create, :update, :destroy]

  # Layouts
  resources :layouts, only: [:index, :show, :create, :update, :destroy]
end
