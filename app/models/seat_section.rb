# app/models/seat_section.rb
class SeatSection < ApplicationRecord
  belongs_to :restaurant
  has_many :seats, dependent: :destroy

  validates :name, presence: true
  validates :capacity, numericality: { greater_than: 0 }, allow_nil: true
  # ^ If your seat_section.capacity is optional, allow_nil: true
end
