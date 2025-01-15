# app/models/reservation.rb
class Reservation < ApplicationRecord
  belongs_to :restaurant

  validates :restaurant_id, presence: true
  validates :start_time, presence: true
  validates :party_size, presence: true, numericality: { greater_than: 0 }
  validates :contact_name, presence: true
end
