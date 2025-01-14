# app/models/reservation.rb
class Reservation < ApplicationRecord
  belongs_to :restaurant
  # has_many :seat_allocations
  # has_many :seats, through: :seat_allocations
end