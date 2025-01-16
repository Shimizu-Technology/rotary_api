# app/models/reservation.rb
class Reservation < ApplicationRecord
  belongs_to :restaurant

  # If you want to see which seats are occupied by this reservation:
  has_many :seat_allocations, dependent: :nullify
  has_many :seats, through: :seat_allocations

  # Basic validations
  validates :restaurant_id, presence: true
  validates :start_time, presence: true
  validates :party_size, presence: true,
                         numericality: { greater_than: 0 }
  validates :contact_name, presence: true

  # Example statuses: "booked", "canceled", "seated", "finished", etc.
end
