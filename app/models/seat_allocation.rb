# app/models/seat_allocation.rb
class SeatAllocation < ApplicationRecord
  belongs_to :reservation
  belongs_to :seat
end