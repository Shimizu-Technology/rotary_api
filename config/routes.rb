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

  # Now allow index for seat_allocations
  resources :seat_allocations, only: [:index, :create, :update, :destroy]

  # Menus & MenuItems
  resources :menus, only: [:index, :show, :create, :update, :destroy]
  resources :menu_items, only: [:index, :show, :create, :update, :destroy]

  # Notifications
  resources :notifications, only: [:index, :show, :create, :update, :destroy]

  # Layouts
  resources :layouts, only: [:index, :show, :create, :update, :destroy]
end
