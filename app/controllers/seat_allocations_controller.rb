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
  # occupant arrives => occupant => "seated", seats => "occupied"
  # POST /seat_allocations/multi_create
  # ------------------------------------------------------------------
  def multi_create
    sa_params = params.require(:seat_allocation)
                      .permit(:occupant_type, :occupant_id, :allocated_at, seat_ids: [])

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
      if occupant.is_a?(Reservation)
        # Must not already be seated/finished/canceled/no_show
        if %w[seated finished canceled no_show].include?(occupant.status)
          raise ActiveRecord::Rollback, "Already seated or done."
        end
      else
        # waitlist occupant
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
    ra_params = params.require(:seat_allocation)
                      .permit(:occupant_type, :occupant_id, :allocated_at, seat_ids: [])

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
        # if occupant is "booked" => allow them to become "reserved"
        # block if occupant is already "seated", "finished", etc.
        if %w[seated finished canceled no_show].include?(occupant.status)
          raise ActiveRecord::Rollback, "Already seated or done."
        end
        occupant.update!(status: "reserved")  # occupant => "reserved"
      else
        # waitlist occupant
        if %w[seated removed no_show].include?(occupant.status)
          raise ActiveRecord::Rollback, "Already seated or removed."
        end
        occupant.update!(status: "reserved") # or keep them "waiting" if you prefer
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
        # occupant must be "reserved" or "booked" to seat them
        unless %w[reserved booked].include?(occupant.status)
          raise ActiveRecord::Rollback, "Occupant not in reserved/booked state"
        end
      else
        # waitlist occupant => "waiting"/"reserved"
        unless %w[waiting reserved].include?(occupant.status)
          raise ActiveRecord::Rollback, "Occupant not in waiting/reserved"
        end
      end

      occupant_allocs =
        if occupant_type == "reservation"
          SeatAllocation.where(reservation_id: occupant.id, released_at: nil)
        else
          SeatAllocation.where(waitlist_entry_id: occupant.id, released_at: nil)
        end

      occupant_allocs.each do |alloc|
        seat = alloc.seat
        # seat must be "reserved"
        raise ActiveRecord::Rollback, "Seat #{seat.id} not reserved" unless seat.status == "reserved"
        seat.update!(status: "occupied")
      end

      occupant.update!(status: "seated")
    end

    render json: { message: "Arrived. Seats => occupied, occupant => seated" }, status: :ok

  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # occupant => "no_show", seats => "free"
  # POST /seat_allocations/no_show
  # occupant never arrived
  # ------------------------------------------------------------------
  def no_show
    ns_params = params.permit(:occupant_type, :occupant_id)
    occupant_type = ns_params[:occupant_type]
    occupant_id   = ns_params[:occupant_id]

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

      occupant.update!(status: "no_show")
    end

    render json: { message: "Marked occupant as no_show; seats => free" }, status: :ok

  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # occupant => "canceled", seats => "free"
  # POST /seat_allocations/cancel
  # occupant canceled in advance
  # ------------------------------------------------------------------
  def cancel
    c_params = params.permit(:occupant_type, :occupant_id)
    occupant_type = c_params[:occupant_type]
    occupant_id   = c_params[:occupant_id]

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

      occupant.update!(status: "canceled")
    end

    render json: { message: "Canceled occupant & freed seats" }, status: :ok

  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # occupant => "finished"/"removed", seat => "free"
  # DELETE /seat_allocations/:id
  # Typically used if occupant actually finished dining
  # ------------------------------------------------------------------
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
        occupant.update!(status: "finished")
      else
        occupant.update!(status: "removed")
      end
    end

    head :no_content
  end
end
