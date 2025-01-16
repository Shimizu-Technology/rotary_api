# app/controllers/seat_allocations_controller.rb
class SeatAllocationsController < ApplicationController
  before_action :authorize_request

  # GET /seat_allocations
  def index
    seat_allocations = SeatAllocation
      .includes(:seat, :reservation, :waitlist_entry)
      .where(released_at: nil)  # or all, if you prefer

    results = seat_allocations.map do |alloc|
      occupant_type = if alloc.reservation_id.present?
                        "reservation"
                      elsif alloc.waitlist_entry_id.present?
                        "waitlist"
                      else
                        nil
                      end

      occupant_name        = nil
      occupant_party_size  = nil
      occupant_status      = nil
      seat_label           = alloc.seat.label

      if occupant_type == "reservation" && alloc.reservation
        occupant_name       = alloc.reservation.contact_name
        occupant_party_size = alloc.reservation.party_size
        occupant_status     = alloc.reservation.status
      elsif occupant_type == "waitlist" && alloc.waitlist_entry
        occupant_name       = alloc.waitlist_entry.contact_name
        occupant_party_size = alloc.waitlist_entry.party_size
        occupant_status     = alloc.waitlist_entry.status
      end

      {
        id: alloc.id,
        seat_id: alloc.seat_id,
        seat_label: seat_label,
        occupant_type: occupant_type,
        occupant_name: occupant_name,
        occupant_party_size: occupant_party_size,
        occupant_status: occupant_status,
        allocated_at: alloc.allocated_at,
        released_at: alloc.released_at,
        reservation_id: alloc.reservation_id,
        waitlist_entry_id: alloc.waitlist_entry_id
      }
    end

    render json: results
  end

  # POST /seat_allocations
  #
  # This version checks occupant.party_size vs. seat.capacity.
  # If seat.capacity >= occupant.party_size, occupant only needs 1 seat.
  # Otherwise, occupant needs occupant.party_size seats of capacity=1 (assuming each seat capacity=1).
  def create
    sa_params = params.require(:seat_allocation)
                      .permit(:seat_id, :reservation_id, :waitlist_entry_id, :allocated_at)

    seat = Seat.find_by(id: sa_params[:seat_id])
    return render json: { error: "Seat not found" }, status: :not_found unless seat

    occupant = find_occupant(sa_params)
    return unless occupant # If find_occupant rendered error

    occupant_type = sa_params[:reservation_id].present? ? :reservation : :waitlist
    occupant_party_size = occupant.party_size || 1

    # ============== Logic ==============
    if seat.capacity >= occupant_party_size
      # Just seat them in this one seat
      seat_one!(seat, occupant, occupant_type, sa_params)
    else
      # occupant_party_size seats are required
      # We'll assume seat.capacity=1 for each seat if you want to fill multiple seats
      # => find occupant_party_size consecutive seats (starting from seat_id) in the same seat_section
      seats_in_section = Seat.where(seat_section_id: seat.seat_section_id).order(:id).to_a
      start_index = seats_in_section.find_index { |s| s.id == seat.id }
      if start_index.nil?
        return render json: { error: "Could not locate seat in its seat_section" }, status: 422
      end

      needed = occupant_party_size
      free_slots = []
      i = start_index
      while free_slots.size < needed && i < seats_in_section.size
        s = seats_in_section[i]
        break unless s.status == "free" && s.capacity == 1
        free_slots << s
        i += 1
      end

      # Did we find enough?
      if free_slots.size < needed
        return render json: {
          error: "Not enough consecutive free seats to seat party of #{needed}"
        }, status: :unprocessable_entity
      end

      # Seat them all
      free_slots.each_with_index do |slot, idx|
        # skip_render so we only render once
        seat_one!(slot, occupant, occupant_type, sa_params, skip_render: true)
      end

      # occupant update => "seated"
      occupant.update!(status: "seated")

      # Return a success message or array of seat allocations
      seat_allocs = free_slots.map { |s| s.seat_allocations.last }
      render json: {
        message: "Allocated party of #{needed} to seats: #{free_slots.map(&:label).join(', ')}",
        seat_allocations: seat_allocs
      }, status: :created
    end
  end

  # DELETE /seat_allocations/:id
  def destroy
    seat_allocation = SeatAllocation.find(params[:id])
    seat = seat_allocation.seat
    occupant = seat_allocation.reservation || seat_allocation.waitlist_entry

    # Mark seat free
    seat.update!(status: "free")

    # occupant => maybe we do occupant.update!(status: "finished") or "removed"
    if occupant.is_a?(Reservation)
      occupant.update!(status: "finished")
    elsif occupant.is_a?(WaitlistEntry)
      occupant.update!(status: "removed")
    end

    seat_allocation.update!(released_at: Time.current)
    seat_allocation.destroy
    head :no_content
  end

  private

  # Finds occupant (Reservation or WaitlistEntry). Renders error if not found.
  def find_occupant(sa_params)
    if sa_params[:reservation_id].present?
      occupant = Reservation.find_by(id: sa_params[:reservation_id])
      unless occupant
        render json: { error: "Reservation not found" }, status: :not_found
        return nil
      end
      occupant
    elsif sa_params[:waitlist_entry_id].present?
      occupant = WaitlistEntry.find_by(id: sa_params[:waitlist_entry_id])
      unless occupant
        render json: { error: "Waitlist entry not found" }, status: :not_found
        return nil
      end
      occupant
    else
      render json: { error: "Must provide reservation_id or waitlist_entry_id" }, status: :unprocessable_entity
      return nil
    end
  end

  # Helper to seat occupant in one seat
  def seat_one!(seat, occupant, occupant_type, sa_params, skip_render: false)
    if seat.status == "occupied"
      return if skip_render
      render json: { error: "Seat #{seat.label} is already occupied" }, status: :unprocessable_entity
      return
    end

    # Mark seat + occupant
    seat.update!(status: "occupied")

    # We might set occupant status at the end, if we want them "seated" only if all seats allocated
    # But for simplicity here, we do occupant.update!(status: "seated")

    seat_alloc = SeatAllocation.create!(
      seat_id: seat.id,
      reservation_id: occupant_type == :reservation ? occupant.id : nil,
      waitlist_entry_id: occupant_type == :waitlist ? occupant.id : nil,
      allocated_at: sa_params[:allocated_at].presence || Time.current
    )

    unless skip_render
      occupant.update!(status: "seated")
      render json: seat_alloc, status: :created
    end
  end
end
