# app/models/restaurant.rb
class Restaurant < ApplicationRecord
  has_many :users
  has_many :seat_sections
  has_many :reservations
  has_many :waitlist_entries
  has_many :menus
  # has_many :layouts
end