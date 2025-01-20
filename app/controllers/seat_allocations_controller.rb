# app/controllers/seat_allocations_controller.rb

class SeatAllocationsController < ApplicationController
  before_action :authorize_request

  # GET /seat_allocations?date=YYYY-MM-DD
  # Returns active seat_allocations with occupant info.
  def index
    Rails.logger.debug "[SeatAllocationsController#index] params=#{params.inspect}"

    base = SeatAllocation.includes(:seat, :reservation, :waitlist_entry)
                         .where(released_at: nil)

    # If ?date=YYYY-MM-DD, filter seat_allocations whose [start_time, end_time) touches that date
    # For a simpler “same calendar day” match, do:
    if params[:date].present?
      begin
        date_filter = Date.parse(params[:date])
        # We'll do a naive approach: seat_allocations whose start_time is on that date
        # or you could do more advanced logic if you want partial overlaps with the day
        base = base.where("DATE(start_time) = ?", date_filter)
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
        id:                  alloc.id,
        seat_id:             alloc.seat_id,
        seat_label:          alloc.seat&.label,
        occupant_type:       occupant_type,
        occupant_id:         occupant_id,
        occupant_name:       occupant_name,
        occupant_party_size: occupant_party_size,
        occupant_status:     occupant_status,
        start_time:          alloc.start_time,
        end_time:            alloc.end_time,
        released_at:         alloc.released_at
      }
    end

    render json: results
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/multi_create
  # => occupant => "seated", create multiple seat_allocations
  # for occupant with start_time/end_time, if seats are free.
  # ------------------------------------------------------------------
  def multi_create
    sa_params = params.require(:seat_allocation)
                      .permit(:occupant_type, :occupant_id,
                              :start_time, :end_time, seat_ids: [])

    occupant_type = sa_params[:occupant_type]
    occupant_id   = sa_params[:occupant_id]
    seat_ids      = sa_params[:seat_ids] || []

    # If front end didn't supply start_time / end_time, we fallback:
    # e.g. occupant’s start_time + 60 minutes if reservation, 45 if waitlist
    # In a real app, you'd do more robust logic.
    st = sa_params[:start_time].presence && Time.parse(sa_params[:start_time]) rescue Time.current
    en = sa_params[:end_time].presence   && Time.parse(sa_params[:end_time])   rescue nil

    if occupant_type.blank? || occupant_id.blank? || seat_ids.empty?
      return render json: { error: "Must provide occupant_type, occupant_id, seat_ids" }, status: :unprocessable_entity
    end

    occupant = (occupant_type == "reservation") \
      ? Reservation.find_by(id: occupant_id)
      : WaitlistEntry.find_by(id: occupant_id)
    unless occupant
      return render json: { error: "Could not find occupant" }, status: :not_found
    end

    # If user didn't pass end_time, default 60 min for reservations, 45 min for waitlist
    unless en
      if occupant.is_a?(Reservation)
        en = (st || occupant.start_time || Time.current) + 60.minutes
      else
        en = (st || occupant.check_in_time || Time.current) + 45.minutes
      end
    end

    if st >= en
      return render json: { error: "start_time must be before end_time" }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      # Mark occupant “seated” unless they’re already finished/canceled
      occupant.update!(status: "seated") unless %w[seated finished canceled no_show removed].include?(occupant.status)

      seat_ids.each do |sid|
        seat = Seat.find_by(id: sid)
        raise ActiveRecord::RecordNotFound, "Seat #{sid} not found" unless seat

        # Overlap check: any seat_allocations with (start_time < en) and (end_time > st)
        conflict = SeatAllocation
          .where(seat_id: sid, released_at: nil)
          .where("start_time < ? AND end_time > ?", en, st)
          .exists?

        if conflict
          raise ActiveRecord::RecordInvalid, "Seat #{sid} is not free from #{st} to #{en}"
        end

        SeatAllocation.create!(
          seat_id:           seat.id,
          reservation_id:    occupant.is_a?(Reservation) ? occupant.id : nil,
          waitlist_entry_id: occupant.is_a?(WaitlistEntry) ? occupant.id : nil,
          start_time:        st,
          end_time:          en,
          released_at:       nil
        )
      end
    end

    msg = "Seats allocated from #{st.strftime('%H:%M')} to #{en.strftime('%H:%M')} for occupant #{occupant.id}"
    render json: { message: msg }, status: :created

  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/reserve
  # occupant => "reserved", seats => allocated with start_time/end_time
  # Similar logic to multi_create, just occupant.status => "reserved"
  # ------------------------------------------------------------------
  def reserve
    ra_params = params.require(:seat_allocation)
                      .permit(:occupant_type, :occupant_id,
                              :start_time, :end_time, seat_ids: [])

    occupant_type = ra_params[:occupant_type]
    occupant_id   = ra_params[:occupant_id]
    seat_ids      = ra_params[:seat_ids] || []

    st = ra_params[:start_time].presence && Time.parse(ra_params[:start_time]) rescue Time.current
    en = ra_params[:end_time].presence   && Time.parse(ra_params[:end_time])   rescue nil

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

    # Default end_time if not given
    unless en
      if occupant.is_a?(Reservation)
        en = (st || occupant.start_time || Time.current) + 60.minutes
      else
        en = (st || occupant.check_in_time || Time.current) + 45.minutes
      end
    end

    if st >= en
      return render json: { error: "start_time must be before end_time" }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      occupant.update!(status: "reserved") unless %w[seated finished canceled no_show removed].include?(occupant.status)

      seat_ids.each do |sid|
        seat = Seat.find_by(id: sid)
        raise ActiveRecord::RecordNotFound, "Seat #{sid} not found" unless seat

        conflict = SeatAllocation
          .where(seat_id: sid, released_at: nil)
          .where("start_time < ? AND end_time > ?", en, st)
          .exists?

        if conflict
          raise ActiveRecord::RecordInvalid, "Seat #{sid} not free from #{st} to #{en}"
        end

        SeatAllocation.create!(
          seat_id:           seat.id,
          reservation_id:    occupant.is_a?(Reservation) ? occupant.id : nil,
          waitlist_entry_id: occupant.is_a?(WaitlistEntry) ? occupant.id : nil,
          start_time:        st,
          end_time:          en,
          released_at:       nil
        )
      end
    end

    msg = "Seats reserved from #{st.strftime('%H:%M')} to #{en.strftime('%H:%M')}."
    render json: { message: msg }, status: :created

  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/arrive
  # occupant => "seated"
  # (We don't modify seat_allocations here, just occupant's status)
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
      if occupant.is_a?(Reservation)
        raise ActiveRecord::RecordInvalid, "Not in reserved/booked" unless %w[reserved booked].include?(occupant.status)
      else
        raise ActiveRecord::RecordInvalid, "Not in waiting/reserved" unless %w[waiting reserved].include?(occupant.status)
      end

      occupant.update!(status: "seated")
    end

    render json: { message: "Arrived => occupant is now 'seated'" }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/no_show
  # occupant => "no_show", seat_allocations => released_at = now
  # ------------------------------------------------------------------
  def no_show
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

    render json: { message: "Marked occupant as no_show; seat_allocations released" }, status: :ok
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/cancel
  # occupant => "canceled", seat_allocations => released_at = now
  # ------------------------------------------------------------------
  def cancel
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

    render json: { message: "Canceled occupant & freed seats" }, status: :ok
  end

  # ------------------------------------------------------------------
  # DELETE /seat_allocations/:id
  # => occupant => finished/removed if no seat_allocations remain
  # ------------------------------------------------------------------
  def destroy
    seat_allocation = SeatAllocation.find(params[:id])
    occupant = seat_allocation.reservation || seat_allocation.waitlist_entry
    occupant_type = seat_allocation.reservation_id.present? ? "reservation" : "waitlist"

    ActiveRecord::Base.transaction do
      seat_allocation.update!(released_at: Time.current)

      active_allocs =
        if occupant_type == "reservation"
          SeatAllocation.where(reservation_id: occupant.id, released_at: nil)
        else
          SeatAllocation.where(waitlist_entry_id: occupant.id, released_at: nil)
        end

      if active_allocs.none?
        occupant.update!(status: occupant_type == "reservation" ? "finished" : "removed")
      end
    end

    head :no_content
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/finish
  # occupant => "finished"/"removed", release all seat_allocations
  # ------------------------------------------------------------------
  def finish
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

      new_status = occupant_type == "reservation" ? "finished" : "removed"
      occupant.update!(status: new_status)
    end

    render json: { message: "Occupant => #{occupant.status}; seats freed" }, status: :ok
  end
end
