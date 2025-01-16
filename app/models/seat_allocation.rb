# app/models/seat_allocation.rb
class SeatAllocation < ApplicationRecord
  belongs_to :seat
  belongs_to :reservation, optional: true
  belongs_to :waitlist_entry, optional: true

  # Example: occupant is either a reservation or a waitlist entry
  # Optional: ensure at least one occupant is present
  # validate :must_have_one_occupant

  # def must_have_one_occupant
  #   if reservation_id.nil? && waitlist_entry_id.nil?
  #     errors.add(:base, "Must have either a reservation or a waitlist entry")
  #   end
  # end

  # If you want to store seat_allocation timestamps:
  #   t.datetime :allocated_at
  #   t.datetime :released_at
end
