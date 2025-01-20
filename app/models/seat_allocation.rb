class SeatAllocation < ApplicationRecord
  belongs_to :seat
  belongs_to :reservation, optional: true
  belongs_to :waitlist_entry, optional: true

  # Example validation (optional):
  # validate :must_have_one_occupant
  #
  # def must_have_one_occupant
  #   if reservation_id.nil? && waitlist_entry_id.nil?
  #     errors.add(:base, "Must have either a reservation or a waitlist entry")
  #   end
  # end

  # t.datetime :allocated_at
  # t.datetime :released_at
end
