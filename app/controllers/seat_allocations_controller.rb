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

      occupant_name       = nil
      occupant_party_size = nil
      occupant_status     = nil

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
        seat_label: alloc.seat.label,
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

  # ------------------------------------------------------------------
  # occupant physically arrives => occupant => "seated", seats => "occupied"
  # POST /seat_allocations/multi_create
  # ------------------------------------------------------------------
  def multi_create
    sa_params = params.require(:seat_allocation).permit(:occupant_type, :occupant_id, :allocated_at, seat_ids: [])

    occupant_type = sa_params[:occupant_type]
    occupant_id   = sa_params[:occupant_id]
    seat_ids      = sa_params[:seat_ids] || []
    allocated_at  = sa_params[:allocated_at].presence || Time.current

    if occupant_type.blank? || occupant_id.blank? || seat_ids.empty?
      return render json: { error: "Must provide occupant_type, occupant_id, seat_ids" }, status: :unprocessable_entity
    end

    occupant =
      case occupant_type
      when "reservation" then Reservation.find_by(id: occupant_id)
      when "waitlist"    then WaitlistEntry.find_by(id: occupant_id)
      end
    return render json: { error: "Could not find occupant" }, status: :not_found unless occupant

    ActiveRecord::Base.transaction do
      # occupant must not be seated/finished/etc.
      if occupant.is_a?(Reservation)
        if %w[seated finished canceled no_show].include?(occupant.status)
          raise ActiveRecord::Rollback, "Already seated or done."
        end
      else
        if %w[seated removed no_show].include?(occupant.status)
          raise ActiveRecord::Rollback, "Already seated or removed."
        end
      end

      seat_ids.each do |sid|
        seat = Seat.find(sid)
        raise ActiveRecord::Rollback, "Seat #{sid} not free" unless seat.status == "free"

        seat.update!(status: "occupied")
        sa = SeatAllocation.new(seat_id: seat.id, allocated_at: allocated_at)
        occupant_type == "reservation" ? sa.reservation_id = occupant.id : sa.waitlist_entry_id = occupant.id
        sa.save!
      end

      occupant.update!(status: "seated")
    end

    render json: { message: "Seats allocated (occupied) successfully" }, status: :created

  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # occupant => "reserved", seat => "reserved"
  # POST /seat_allocations/reserve
  # ------------------------------------------------------------------
  def reserve
    ra_params = params.require(:seat_allocation).permit(:occupant_type, :occupant_id, :allocated_at, seat_ids: [])

    occupant_type = ra_params[:occupant_type]
    occupant_id   = ra_params[:occupant_id]
    seat_ids      = ra_params[:seat_ids] || []
    allocated_at  = ra_params[:allocated_at].presence || Time.current

    if occupant_type.blank? || occupant_id.blank? || seat_ids.empty?
      return render json: { error: "Must provide occupant_type, occupant_id, seat_ids" }, status: :unprocessable_entity
    end

    occupant =
      case occupant_type
      when "reservation" then Reservation.find_by(id: occupant_id)
      when "waitlist"    then WaitlistEntry.find_by(id: occupant_id)
      end
    return render json: { error: "Could not find occupant" }, status: :not_found unless occupant

    ActiveRecord::Base.transaction do
      if occupant.is_a?(Reservation)
        if %w[seated finished canceled no_show].include?(occupant.status)
          raise ActiveRecord::Rollback, "Already seated or done."
        end
        # occupant => "reserved"
        occupant.update!(status: "reserved")
      else
        if %w[seated removed no_show].include?(occupant.status)
          raise ActiveRecord::Rollback, "Already seated or removed."
        end
        # For waitlist, you could do occupant.update!(status: "reserved") or keep them "waiting".
      end

      seat_ids.each do |sid|
        seat = Seat.find(sid)
        raise ActiveRecord::Rollback, "Seat #{sid} not free" unless seat.status == "free"

        seat.update!(status: "reserved")
        sa = SeatAllocation.new(seat_id: seat.id, allocated_at: allocated_at)
        occupant_type == "reservation" ? sa.reservation_id = occupant.id : sa.waitlist_entry_id = occupant.id
        sa.save!
      end
    end

    render json: { message: "Seats reserved successfully" }, status: :created

  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # occupant => "seated", seats => "occupied" (if occupant was reserved)
  # POST /seat_allocations/arrive
  # For "Arrive Now" scenario
  # ------------------------------------------------------------------
  def arrive
    occ_params = params.permit(:occupant_type, :occupant_id)
    occupant_type = occ_params[:occupant_type]
    occupant_id   = occ_params[:occupant_id]

    if occupant_type.blank? || occupant_id.blank?
      return render json: { error: "Must provide occupant_type, occupant_id" }, status: :unprocessable_entity
    end

    occupant =
      case occupant_type
      when "reservation" then Reservation.find_by(id: occupant_id)
      when "waitlist"    then WaitlistEntry.find_by(id: occupant_id)
      end
    return render json: { error: "Could not find occupant" }, status: :not_found unless occupant

    ActiveRecord::Base.transaction do
      if occupant.is_a?(Reservation)
        # occupant must be "reserved" (or "booked") in your logic
        unless occupant.status == "reserved"
          raise ActiveRecord::Rollback, "Occupant is not in reserved state"
        end
      else
        # waitlist occupant => if you're using "reserved" for waitlist, check similarly
        unless occupant.status == "waiting" || occupant.status == "reserved"
          raise ActiveRecord::Rollback, "Occupant is not in waiting/reserved state"
        end
      end

      # find occupant's seat_allocations
      occupant_allocs =
        if occupant_type == "reservation"
          SeatAllocation.where(reservation_id: occupant.id, released_at: nil)
        else
          SeatAllocation.where(waitlist_entry_id: occupant.id, released_at: nil)
        end

      occupant_allocs.each do |alloc|
        seat = alloc.seat
        raise ActiveRecord::Rollback, "Seat #{seat.id} is not reserved" unless seat.status == "reserved"

        seat.update!(status: "occupied") # occupant arrived physically
      end

      occupant.update!(status: "seated")
    end

    render json: { message: "Arrived. Seats => occupied, occupant => seated" }, status: :ok

  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # DELETE /seat_allocations/:id => occupant => "finished"/"removed", seat => "free"
  def destroy
    seat_allocation = SeatAllocation.find(params[:id])
    occupant = seat_allocation.reservation || seat_allocation.waitlist_entry
    occupant_type = seat_allocation.reservation_id.present? ? "reservation" : "waitlist"

    ActiveRecord::Base.transaction do
      occupant_allocs =
        if occupant_type == "reservation"
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
        occupant.update!(status: "finished") # or "canceled", or "no_show"
      else
        occupant.update!(status: "removed")
      end
    end

    head :no_content
  end
end
