# app/controllers/availability_controller.rb
class AvailabilityController < ApplicationController
  # GET /availability?date=YYYY-MM-DD&party_size=4
  def index
    date_str   = params[:date]
    party_size = params[:party_size].to_i

    # For your MVP, we hardcode Restaurant.find(1), or adjust as needed
    restaurant = Restaurant.find(1)

    # 1) Generate timeslots for that date
    slots = generate_timeslots_for_date(restaurant, date_str)

    # 2) Check seat availability for each timeslot
    average_dining_duration = 60.minutes
    available_slots = []

    slots.each do |slot|
      # For each slot => slot + 60min, see if we can accommodate `party_size`
      if can_accommodate?(restaurant, party_size, slot, slot + average_dining_duration)
        available_slots << slot
      end
    end

    # Return them in HH:MM format (could also return as full ISO strings)
    render json: {
      slots: available_slots.map { |ts| ts.strftime("%H:%M") }
    }
  end

  private

  # Generate the list of timeslots from opening_time..closing_time in interval steps
  def generate_timeslots_for_date(restaurant, date_str)
    return [] if date_str.blank?

    date = Date.parse(date_str) rescue nil
    return [] unless date

    open_time  = restaurant.opening_time   # e.g. 17:00
    close_time = restaurant.closing_time   # e.g. 21:00
    interval   = restaurant.time_slot_interval || 30

    # Build date/time objects for that day
    base_open  = DateTime.new(date.year, date.month, date.day, open_time.hour,  open_time.min)
    base_close = DateTime.new(date.year, date.month, date.day, close_time.hour, close_time.min)

    slots = []
    current = base_open
    while current < base_close
      slots << current
      current += interval.minutes
    end

    slots
  end

  # Decide if we can seat a party of size `party_size` from start_dt..end_dt
  def can_accommodate?(restaurant, party_size, start_dt, end_dt)
    seats = restaurant.current_seats  # <— Only seats for the current layout

    free_count = 0

    seats.each do |seat|
      # If a seat_allocation overlaps [start_dt..end_dt) => seat is NOT free
      conflict = SeatAllocation
        .where(seat_id: seat.id)
        .where(released_at: nil)
        .where("start_time < ? AND end_time > ?", end_dt, start_dt)
        .exists?

      free_count += 1 unless conflict
    end

    # If free_count >= party_size, we say "yes"
    free_count >= party_size
  end
end
