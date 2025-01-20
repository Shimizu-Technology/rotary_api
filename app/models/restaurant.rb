# app/models/restaurant.rb
class Restaurant < ApplicationRecord
  # Existing associations
  has_many :users,               dependent: :destroy
  has_many :reservations,        dependent: :destroy
  has_many :waitlist_entries,    dependent: :destroy
  has_many :menus,               dependent: :destroy

  # Layout-related associations
  has_many :layouts,            dependent: :destroy
  # Through association so that Restaurant.seat_sections works
  has_many :seat_sections,      through: :layouts
  # Through association so that Restaurant.seats works
  has_many :seats,              through: :seat_sections

  # Which layout is "active" (e.g. used for seating right now)
  belongs_to :current_layout, class_name: "Layout", optional: true

  # OPTIONAL: If you have opening_time / closing_time columns:
  #   t.time :opening_time
  #   t.time :closing_time
  #   t.integer :time_slot_interval, default: 30

  #--------------------------------------------------------------------------
  # Returns only the seats belonging to the restaurant’s *current_layout*.
  # This is useful for seat checks if you only want to consider the "active" floor plan.
  #--------------------------------------------------------------------------
  def current_seats
    return [] unless current_layout

    # gather seats from all seat_sections in current_layout
    current_layout
      .seat_sections
      .includes(:seats)
      .flat_map(&:seats)
  end
end
