# app/controllers/seat_allocations_controller.rb
class SeatAllocationsController < ApplicationController
  before_action :authorize_request

  # GET /seat_allocations
  def index
    seat_allocations = SeatAllocation
      .includes(:seat, :reservation, :waitlist_entry)
      .all

    results = seat_allocations.map do |alloc|
      occupant_type =
        if alloc.reservation_id.present?
          "reservation"
        elsif alloc.waitlist_entry_id.present?
          "waitlist"
        else
          nil
        end

      seat_label = alloc.seat.label

      occupant_name        = nil
      occupant_party_size  = nil
      occupant_status      = nil

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
        released_at: alloc.released_at
      }
    end

    render json: results
  end

  # POST /seat_allocations/multi_create
  def multi_create
    sa_params = params.require(:seat_allocation)
                      .permit(:occupant_type, :occupant_id, :allocated_at, seat_ids: [])

    occupant_type = sa_params[:occupant_type]
    occupant_id   = sa_params[:occupant_id]
    seat_ids      = sa_params[:seat_ids] || []
    allocated_at  = sa_params[:allocated_at].presence || Time.current

    if occupant_type.blank? || occupant_id.blank? || seat_ids.empty?
      return render json: { error: "Must provide occupant_type, occupant_id, and seat_ids" }, status: :unprocessable_entity
    end

    # 1) Find occupant
    occupant =
      case occupant_type
      when "reservation" then Reservation.find_by(id: occupant_id)
      when "waitlist"    then WaitlistEntry.find_by(id: occupant_id)
      end

    unless occupant
      return render json: { error: "Could not find occupant" }, status: :not_found
    end

    # 1a) Check occupant’s status => if occupant is not seatable, raise
    # E.g. "booked" or "waiting" => good; "seated" / "finished" / "removed" => not seatable
    if occupant.is_a?(Reservation)
      if %w[seated finished canceled].include?(occupant.status)
        raise ActiveRecord::Rollback, "Reservation already seated or finished."
      end
    else
      # waitlist
      if %w[seated removed].include?(occupant.status)
        raise ActiveRecord::Rollback, "Waitlist entry already seated or removed."
      end
    end

    # 2) Attempt to allocate seats in a transaction
    ActiveRecord::Base.transaction do
      seat_ids.each do |sid|
        seat = Seat.find_by(id: sid)
        unless seat
          raise ActiveRecord::Rollback, "Seat ID=#{sid} not found"
        end

        if seat.status == "occupied"
          raise ActiveRecord::Rollback, "Seat ID=#{sid} is already occupied"
        end

        # Mark seat as occupied
        seat.update!(status: "occupied")

        # Create seat_allocation
        sa = SeatAllocation.new(seat_id: seat.id, allocated_at: allocated_at)
        occupant_type == "reservation" ? sa.reservation_id = occupant.id : sa.waitlist_entry_id = occupant.id
        sa.save! # might raise if invalid
      end

      # occupant => "seated"
      occupant.update!(status: "seated")
    end

    render json: { message: "Seats allocated successfully" }, status: :created

  rescue => e
    Rails.logger.warn("[SeatAllocationsController] multi_create => Error: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /seat_allocations/:id
  # Frees ALL seats for that occupant
  def destroy
    seat_allocation = SeatAllocation.find(params[:id])
    occupant = seat_allocation.reservation || seat_allocation.waitlist_entry
    occupant_type = seat_allocation.reservation_id.present? ? "reservation" : "waitlist"

    ActiveRecord::Base.transaction do
      occupant_allocs = if occupant_type == "reservation"
        SeatAllocation.where(reservation_id: occupant.id, released_at: nil)
      else
        SeatAllocation.where(waitlist_entry_id: occupant.id, released_at: nil)
      end

      occupant_allocs.each do |alloc|
        seat = alloc.seat
        seat.update!(status: "free")
        alloc.update!(released_at: Time.current)
      end

      if occupant_type == "reservation"
        occupant.update!(status: "finished")
      else
        occupant.update!(status: "removed")
      end
    end

    head :no_content
  end
end
