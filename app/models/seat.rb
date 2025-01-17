# app/models/seat.rb
class Seat < ApplicationRecord
  belongs_to :seat_section
  has_many :seat_allocations, dependent: :destroy
  has_many :reservations, through: :seat_allocations
  has_many :waitlist_entries, through: :seat_allocations

  # seat.status can be "free", "reserved", "occupied"
  # seat.capacity = how many people this seat can hold (e.g. 1 for bar stool, 4 for a table).
  validates :capacity, numericality: { greater_than: 0 }

  # Example: default status to "free" on creation:
  after_initialize do
    self.status ||= "free"
  end
end
