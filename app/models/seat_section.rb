# app/models/seat_section.rb
class SeatSection < ApplicationRecord
  belongs_to :restaurant
  has_many :seats, dependent: :destroy
end