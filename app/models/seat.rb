# app/models/seat.rb
class Seat < ApplicationRecord
  belongs_to :seat_section
  # has_many :seat_allocations
  # has_many :reservations, through: :seat_allocations
end