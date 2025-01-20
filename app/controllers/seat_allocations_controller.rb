class SeatAllocationsController < ApplicationController
  before_action :authorize_request

  # GET /seat_allocations
  #
  # Returns all active seat_allocations (where released_at is nil).
  # If ?date=YYYY-MM-DD is specified, filters to only seat_allocations
  # with occupant's date = that day.
  def index
    Rails.logger.debug "===== [SeatAllocationsController#index] listing seat allocations with params=#{params.inspect}"

    base = SeatAllocation
      .includes(:seat, :reservation, :waitlist_entry)
      .where(released_at: nil)

    if params[:date].present?
      begin
        date_filter = Date.parse(params[:date])
        # Join occupant tables to match occupant date
        base = base
          .joins("LEFT JOIN reservations r ON seat_allocations.reservation_id = r.id")
          .joins("LEFT JOIN waitlist_entries w ON seat_allocations.waitlist_entry_id = w.id")
          .where(%{
            (seat_allocations.reservation_id IS NOT NULL AND DATE(r.start_time) = :df)
            OR
            (seat_allocations.waitlist_entry_id IS NOT NULL AND DATE(w.check_in_time) = :df)
          }, df: date_filter)
      rescue ArgumentError
        Rails.logger.warn "[SeatAllocationsController#index] invalid date param=#{params[:date]}"
      end
    end

    seat_allocations = base.all

    results = seat_allocations.map do |alloc|
      occupant_type =
        if alloc.reservation_id.present?
          "reservation"
        elsif alloc.waitlist_entry_id.present?
          "waitlist"
        else
          nil
        end

      occupant_id         = nil
      occupant_name       = nil
      occupant_party_size = nil
      occupant_status     = nil

      if occupant_type == "reservation" && alloc.reservation
        occupant_id         = alloc.reservation.id
        occupant_name       = alloc.reservation.contact_name
        occupant_party_size = alloc.reservation.party_size
        occupant_status     = alloc.reservation.status
      elsif occupant_type == "waitlist" && alloc.waitlist_entry
        occupant_id         = alloc.waitlist_entry.id
        occupant_name       = alloc.waitlist_entry.contact_name
        occupant_party_size = alloc.waitlist_entry.party_size
        occupant_status     = alloc.waitlist_entry.status
      end

      {
        id: alloc.id,
        seat_id: alloc.seat_id,
        seat_label: alloc.seat&.label,
        occupant_type: occupant_type,
        occupant_id: occupant_id,
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
  # POST /seat_allocations/multi_create
  #
  # Example usage: occupant => "seated", create multiple seat_allocations
  # for that occupant. We do NOT mark the seat itself "occupied"—
  # we simply create seat_allocations if there's no conflict on that occupant's date.
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
      if occupant_type == "reservation"
        Reservation.find_by(id: occupant_id)
      else
        WaitlistEntry.find_by(id: occupant_id)
      end

    unless occupant
      return render json: { error: "Could not find occupant" }, status: :not_found
    end

    occupant_date = occupant.is_a?(Reservation) ? occupant.start_time&.to_date : occupant.check_in_time&.to_date
    if occupant_date.nil?
      return render json: { error: "Occupant missing date/time field" }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      # Mark occupant “seated” (optional logic)
      occupant.update!(status: "seated") unless %w[seated finished canceled no_show removed].include?(occupant.status)

      seat_ids.each do |sid|
        seat = Seat.find_by(id: sid)
        raise ActiveRecord::RecordNotFound, "Seat #{sid} not found" unless seat

        # Check for conflict on occupant_date
        conflict = SeatAllocation
          .joins("LEFT JOIN reservations r ON seat_allocations.reservation_id = r.id")
          .joins("LEFT JOIN waitlist_entries w ON seat_allocations.waitlist_entry_id = w.id")
          .where(seat_id: sid, released_at: nil)
          .where("
            (reservation_id IS NOT NULL AND DATE(r.start_time) = ?)
             OR
            (waitlist_entry_id IS NOT NULL AND DATE(w.check_in_time) = ?)
          ", occupant_date, occupant_date)
          .exists?

        if conflict
          raise ActiveRecord::RecordInvalid, "Seat #{sid} is already allocated on #{occupant_date}"
        end

        # If no conflict, create seat_allocation
        SeatAllocation.create!(
          seat_id:           seat.id,
          reservation_id:    occupant.is_a?(Reservation) ? occupant.id : nil,
          waitlist_entry_id: occupant.is_a?(WaitlistEntry) ? occupant.id : nil,
          allocated_at:      allocated_at
        )
      end
    end

    render json: { message: "Seats allocated for occupant on date #{occupant_date}" }, status: :created

  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/reserve
  #
  # occupant => "reserved", create seat_allocations if no conflicts.
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
      if occupant_type == "reservation"
        Reservation.find_by(id: occupant_id)
      else
        WaitlistEntry.find_by(id: occupant_id)
      end

    unless occupant
      return render json: { error: "Could not find occupant" }, status: :not_found
    end

    occupant_date = occupant.is_a?(Reservation) ? occupant.start_time&.to_date : occupant.check_in_time&.to_date
    if occupant_date.nil?
      return render json: { error: "Occupant missing date/time field" }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      occupant.update!(status: "reserved") unless %w[seated finished canceled no_show removed].include?(occupant.status)

      seat_ids.each do |sid|
        seat = Seat.find_by(id: sid)
        raise ActiveRecord::RecordNotFound, "Seat #{sid} not found" unless seat

        # Check for conflict
        conflict = SeatAllocation
          .joins("LEFT JOIN reservations r ON seat_allocations.reservation_id = r.id")
          .joins("LEFT JOIN waitlist_entries w ON seat_allocations.waitlist_entry_id = w.id")
          .where(seat_id: sid, released_at: nil)
          .where("
            (reservation_id IS NOT NULL AND DATE(r.start_time) = ?)
             OR
            (waitlist_entry_id IS NOT NULL AND DATE(w.check_in_time) = ?)
          ", occupant_date, occupant_date)
          .exists?

        if conflict
          raise ActiveRecord::RecordInvalid, "Seat #{sid} is already allocated on #{occupant_date}"
        end

        # Create seat_allocation
        SeatAllocation.create!(
          seat_id:           seat.id,
          reservation_id:    occupant.is_a?(Reservation) ? occupant.id : nil,
          waitlist_entry_id: occupant.is_a?(WaitlistEntry) ? occupant.id : nil,
          allocated_at:      allocated_at
        )
      end
    end

    render json: { message: "Seats reserved for date #{occupant_date}" }, status: :created

  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/arrive
  #
  # occupant => "seated"
  # Typically you might ensure occupant was "reserved" or "booked".
  # Then do no changes to seat records, just occupant status + seat_allocation remains.
  # ------------------------------------------------------------------
  def arrive
    Rails.logger.debug "[arrive] params=#{params.inspect}"
    occ_params = params.permit(:occupant_type, :occupant_id)

    occupant_type = occ_params[:occupant_type]
    occupant_id   = occ_params[:occupant_id]
    if occupant_type.blank? || occupant_id.blank?
      return render json: { error: "Must provide occupant_type, occupant_id" }, status: :unprocessable_entity
    end

    occupant =
      if occupant_type == "reservation"
        Reservation.find_by(id: occupant_id)
      else
        WaitlistEntry.find_by(id: occupant_id)
      end
    unless occupant
      return render json: { error: "Could not find occupant" }, status: :not_found
    end

    ActiveRecord::Base.transaction do
      # Example: occupant must be 'reserved' or 'booked' to "arrive"
      if occupant.is_a?(Reservation)
        raise ActiveRecord::RecordInvalid, "Not in reserved/booked" unless %w[reserved booked].include?(occupant.status)
      else
        raise ActiveRecord::RecordInvalid, "Not in waiting/reserved" unless %w[waiting reserved].include?(occupant.status)
      end

      # Mark occupant => seated
      occupant.update!(status: "seated")
    end

    render json: { message: "Arrived => occupant is now 'seated'" }, status: :ok

  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/no_show
  #
  # occupant => "no_show"
  # seat_allocations => set released_at = Time.current
  # ------------------------------------------------------------------
  def no_show
    Rails.logger.debug "[no_show] params=#{params.inspect}"
    ns_params = params.permit(:occupant_type, :occupant_id)

    occupant_type = ns_params[:occupant_type]
    occupant_id   = ns_params[:occupant_id]
    if occupant_type.blank? || occupant_id.blank?
      return render json: { error: "Must provide occupant_type, occupant_id" }, status: :unprocessable_entity
    end

    occupant =
      if occupant_type == "reservation"
        Reservation.find_by(id: occupant_id)
      else
        WaitlistEntry.find_by(id: occupant_id)
      end
    unless occupant
      return render json: { error: "Could not find occupant" }, status: :not_found
    end

    ActiveRecord::Base.transaction do
      # release seat allocations
      occupant_allocs =
        if occupant_type == "reservation"
          SeatAllocation.where(reservation_id: occupant.id, released_at: nil)
        else
          SeatAllocation.where(waitlist_entry_id: occupant.id, released_at: nil)
        end

      occupant_allocs.each do |alloc|
        alloc.update!(released_at: Time.current)
      end

      occupant.update!(status: "no_show")
    end

    render json: { message: "Occupant => no_show; seat_allocations released" }, status: :ok
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/cancel
  #
  # occupant => "canceled"
  # seat_allocations => set released_at = Time.current
  # ------------------------------------------------------------------
  def cancel
    Rails.logger.debug "[cancel] params=#{params.inspect}"
    c_params = params.permit(:occupant_type, :occupant_id)

    occupant_type = c_params[:occupant_type]
    occupant_id   = c_params[:occupant_id]
    if occupant_type.blank? || occupant_id.blank?
      return render json: { error: "Must provide occupant_type, occupant_id" }, status: :unprocessable_entity
    end

    occupant =
      if occupant_type == "reservation"
        Reservation.find_by(id: occupant_id)
      else
        WaitlistEntry.find_by(id: occupant_id)
      end
    unless occupant
      return render json: { error: "Could not find occupant" }, status: :not_found
    end

    ActiveRecord::Base.transaction do
      occupant_allocs =
        if occupant_type == "reservation"
          SeatAllocation.where(reservation_id: occupant.id, released_at: nil)
        else
          SeatAllocation.where(waitlist_entry_id: occupant.id, released_at: nil)
        end

      occupant_allocs.each do |alloc|
        alloc.update!(released_at: Time.current)
      end

      occupant.update!(status: "canceled")
    end

    render json: { message: "Canceled occupant & freed seat_allocations" }, status: :ok
  end

  # ------------------------------------------------------------------
  # DELETE /seat_allocations/:id
  #
  # A single seat_allocation is destroyed => occupant => "finished"/"removed"
  # or you can do occupant => "finished" only when ALL seat_allocations are destroyed
  # by checking occupant_allocs count, etc.
  # ------------------------------------------------------------------
  def destroy
    Rails.logger.debug "[destroy] params=#{params.inspect}"

    seat_allocation = SeatAllocation.find(params[:id])
    occupant = seat_allocation.reservation || seat_allocation.waitlist_entry
    occupant_type = seat_allocation.reservation_id.present? ? "reservation" : "waitlist"

    ActiveRecord::Base.transaction do
      # Mark this seat_allocation as released
      seat_allocation.update!(released_at: Time.current)

      # Optionally check if occupant has any other seat_allocations left
      active_allocs =
        if occupant_type == "reservation"
          SeatAllocation.where(reservation_id: occupant.id, released_at: nil)
        else
          SeatAllocation.where(waitlist_entry_id: occupant.id, released_at: nil)
        end

      if active_allocs.none?
        # Mark occupant as "finished" or "removed" if no seats remain
        occupant.update!(status: occupant_type == "reservation" ? "finished" : "removed")
      end
    end

    head :no_content
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/finish
  #
  # occupant => "finished"/"removed"
  # releases all occupant seat_allocations
  # ------------------------------------------------------------------
  def finish
    Rails.logger.debug "[finish] params=#{params.inspect}"
    f_params = params.permit(:occupant_type, :occupant_id)

    occupant_type = f_params[:occupant_type]
    occupant_id   = f_params[:occupant_id]
    if occupant_type.blank? || occupant_id.blank?
      return render json: { error: "Must provide occupant_type, occupant_id" }, status: :unprocessable_entity
    end

    occupant =
      if occupant_type == "reservation"
        Reservation.find_by(id: occupant_id)
      else
        WaitlistEntry.find_by(id: occupant_id)
      end
    unless occupant
      return render json: { error: "Could not find occupant" }, status: :not_found
    end

    ActiveRecord::Base.transaction do
      occupant_allocs =
        if occupant_type == "reservation"
          SeatAllocation.where(reservation_id: occupant.id, released_at: nil)
        else
          SeatAllocation.where(waitlist_entry_id: occupant.id, released_at: nil)
        end

      occupant_allocs.each do |alloc|
        alloc.update!(released_at: Time.current)
      end

      # occupant => "finished" or "removed"
      new_status = occupant_type == "reservation" ? "finished" : "removed"
      occupant.update!(status: new_status)
    end

    render json: { message: "Occupant => #{occupant.status}; seats released" }, status: :ok
  end
end
