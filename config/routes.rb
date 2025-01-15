# config/routes.rb

Rails.application.routes.draw do
  # Authentication endpoints
  post '/signup', to: 'users#create'
  post '/login',  to: 'sessions#create'

  # For standard RESTful controllers:
  resources :restaurants, only: [:index, :show, :create, :update, :destroy]
  resources :seat_sections, only: [:index, :show, :create, :update, :destroy]
  resources :seats, only: [:index, :show, :create, :update, :destroy]

  resources :reservations, only: [:index, :show, :create, :update, :destroy]
  resources :waitlist_entries, only: [:index, :show, :create, :update, :destroy]

  # If seat_allocations:
  resources :seat_allocations, only: [:create, :update, :destroy]

  # Menus & MenuItems
  resources :menus, only: [:index, :show, :create, :update, :destroy]
  resources :menu_items, only: [:index, :show, :create, :update, :destroy]

  # Notifications
  resources :notifications, only: [:index, :show, :create, :update, :destroy]

  # Layouts
  resources :layouts, only: [:index, :show, :create, :update, :destroy]

  # For seats occupancy updates, you might do custom routes:
  # put "/seats/:id/occupy", to: "seats#occupy"
  # put "/seats/:id/free",   to: "seats#free"
end
