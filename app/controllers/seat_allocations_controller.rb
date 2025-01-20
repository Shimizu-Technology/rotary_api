# app/controllers/seat_allocations_controller.rb

class SeatAllocationsController < ApplicationController
  before_action :authorize_request

  # GET /seat_allocations
  def index
    Rails.logger.debug "===== [SeatAllocationsController#index] listing seat allocations with params=#{params.inspect}"

    # Start with active seat_allocations (not released)
    base = SeatAllocation.includes(:seat, :reservation, :waitlist_entry)
                         .where(released_at: nil)

    # If ?date=YYYY-MM-DD is given, we join both occupant tables
    # and keep only seat_allocations where occupant's date matches
    if params[:date].present?
      begin
        date_filter = Date.parse(params[:date])

        base = base
          .joins("LEFT JOIN reservations ON seat_allocations.reservation_id = reservations.id")
          .joins("LEFT JOIN waitlist_entries ON seat_allocations.waitlist_entry_id = waitlist_entries.id")
          .where(%{
            (seat_allocations.reservation_id IS NOT NULL AND DATE(reservations.start_time) = :df)
            OR
            (seat_allocations.waitlist_entry_id IS NOT NULL AND DATE(waitlist_entries.check_in_time) = :df)
          }, df: date_filter)

      rescue ArgumentError
        Rails.logger.warn "[SeatAllocationsController#index] invalid date param=#{params[:date]}"
        # base = base.none
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
  # => occupant => "seated", seats => "occupied"
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

    occupant = (occupant_type == "reservation") \
      ? Reservation.find_by(id: occupant_id)
      : WaitlistEntry.find_by(id: occupant_id)

    unless occupant
      return render json: { error: "Could not find occupant" }, status: :not_found
    end

    ActiveRecord::Base.transaction do
      # Mark occupant “seated” unless they were already seated
      occupant.update!(status: "seated") unless %w[seated finished canceled no_show removed].include?(occupant.status)

      seat_ids.each do |sid|
        seat = Seat.find_by(id: sid)
        raise ActiveRecord::Rollback, "Seat #{sid} not found" unless seat
        raise ActiveRecord::Rollback, "Seat #{sid} not free" unless seat.status == "free"

        seat.update!(status: "occupied")
        SeatAllocation.create!(
          seat_id: seat.id,
          reservation_id: occupant.is_a?(Reservation) ? occupant.id : nil,
          waitlist_entry_id: occupant.is_a?(WaitlistEntry) ? occupant.id : nil,
          allocated_at: allocated_at
        )
      end
    end

    render json: { message: "Seats allocated (occupied) successfully" }, status: :created
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/reserve
  # => occupant => "reserved", seats => "reserved"
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

    occupant = (occupant_type == "reservation") \
      ? Reservation.find_by(id: occupant_id)
      : WaitlistEntry.find_by(id: occupant_id)
    unless occupant
      return render json: { error: "Could not find occupant" }, status: :not_found
    end

    ActiveRecord::Base.transaction do
      # Mark occupant “reserved” unless already seated/done
      occupant.update!(status: "reserved") unless %w[seated finished canceled no_show removed].include?(occupant.status)

      seat_ids.each do |sid|
        seat = Seat.find_by(id: sid)
        raise ActiveRecord::Rollback, "Seat #{sid} not found" unless seat
        raise ActiveRecord::Rollback, "Seat #{sid} not free" unless seat.status == "free"

        seat.update!(status: "reserved")
        SeatAllocation.create!(
          seat_id: seat.id,
          reservation_id: occupant.is_a?(Reservation) ? occupant.id : nil,
          waitlist_entry_id: occupant.is_a?(WaitlistEntry) ? occupant.id : nil,
          allocated_at: allocated_at
        )
      end
    end

    render json: { message: "Seats reserved successfully" }, status: :created
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/arrive
  # => occupant => "seated", seats => "occupied"
  # ------------------------------------------------------------------
  def arrive
    Rails.logger.debug "===== [arrive] params=#{params.inspect}"
    puts "===== [arrive] params=#{params.inspect}"

    occ_params = params.permit(:occupant_type, :occupant_id)
    occupant_type = occ_params[:occupant_type]
    occupant_id   = occ_params[:occupant_id]

    if occupant_type.blank? || occupant_id.blank?
      Rails.logger.warn "[arrive] occupant_type/occupant_id missing!"
      puts "[arrive] occupant_type/occupant_id missing!"
      return render json: { error: "Must provide occupant_type, occupant_id" }, status: :unprocessable_entity
    end

    occupant = case occupant_type
               when "reservation" then Reservation.find_by(id: occupant_id)
               when "waitlist"    then WaitlistEntry.find_by(id: occupant_id)
               end
    unless occupant
      Rails.logger.warn "[arrive] occupant not found => occupant_id=#{occupant_id}"
      puts "[arrive] occupant not found => occupant_id=#{occupant_id}"
      return render json: { error: "Could not find occupant" }, status: :not_found
    end

    ActiveRecord::Base.transaction do
      Rails.logger.debug ">>> occupant #{occupant.id} => status=#{occupant.status}"
      puts ">>> occupant #{occupant.id} => status=#{occupant.status}"

      if occupant.is_a?(Reservation)
        unless %w[reserved booked].include?(occupant.status)
          Rails.logger.warn "[arrive] occupant #{occupant.id} not in reserved/booked"
          puts "[arrive] occupant #{occupant.id} not in reserved/booked"
          raise ActiveRecord::Rollback, "Occupant not in reserved/booked state"
        end
      else
        unless %w[waiting reserved].include?(occupant.status)
          Rails.logger.warn "[arrive] occupant #{occupant.id} not in waiting/reserved"
          puts "[arrive] occupant #{occupant.id} not in waiting/reserved"
          raise ActiveRecord::Rollback, "Occupant not in waiting/reserved"
        end
      end

      occupant_allocs =
        if occupant_type == "reservation"
          SeatAllocation.where(reservation_id: occupant.id, released_at: nil)
        else
          SeatAllocation.where(waitlist_entry_id: occupant.id, released_at: nil)
        end
      Rails.logger.debug "... occupant_allocs => #{occupant_allocs.map(&:id)} seats => #{occupant_allocs.map(&:seat_id)}"
      puts "... occupant_allocs => #{occupant_allocs.map(&:id)} seats => #{occupant_allocs.map(&:seat_id)}"

      occupant_allocs.each do |alloc|
        seat = alloc.seat
        Rails.logger.debug ">>> occupant #{occupant.id} => seat #{seat.id} checking seat.status=#{seat.status}"
        puts ">>> occupant #{occupant.id} => seat #{seat.id} checking seat.status=#{seat.status}"
        raise ActiveRecord::Rollback, "Seat #{seat.id} not reserved" unless seat.status == "reserved"
        seat.update!(status: "occupied")
        Rails.logger.debug "... seat #{seat.id} updated to 'occupied'"
        puts "... seat #{seat.id} updated to 'occupied'"
      end

      occupant.update!(status: "seated")
      Rails.logger.debug "... occupant #{occupant.id} updated => 'seated'"
      puts "... occupant #{occupant.id} updated => 'seated'"
    end

    render json: { message: "Arrived. Seats => occupied, occupant => seated" }, status: :ok
  rescue => e
    Rails.logger.error "[arrive] Error => #{e.message}"
    puts "[arrive] Error => #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/no_show
  # => occupant => "no_show", seats => "free"
  # ------------------------------------------------------------------
  def no_show
    Rails.logger.debug "===== [no_show] params=#{params.inspect}"
    puts "===== [no_show] params=#{params.inspect}"

    ns_params = params.permit(:occupant_type, :occupant_id)
    occupant_type = ns_params[:occupant_type]
    occupant_id   = ns_params[:occupant_id]

    if occupant_type.blank? || occupant_id.blank?
      Rails.logger.warn "[no_show] occupant_type/occupant_id missing!"
      puts "[no_show] occupant_type/occupant_id missing!"
      return render json: { error: "Must provide occupant_type, occupant_id" }, status: :unprocessable_entity
    end

    occupant = case occupant_type
               when "reservation" then Reservation.find_by(id: occupant_id)
               when "waitlist"    then WaitlistEntry.find_by(id: occupant_id)
               end
    unless occupant
      Rails.logger.warn "[no_show] occupant not found => id=#{occupant_id}"
      puts "[no_show] occupant not found => id=#{occupant_id}"
      return render json: { error: "Could not find occupant" }, status: :not_found
    end

    ActiveRecord::Base.transaction do
      occupant_allocs =
        if occupant_type == "reservation"
          SeatAllocation.where(reservation_id: occupant.id, released_at: nil)
        else
          SeatAllocation.where(waitlist_entry_id: occupant.id, released_at: nil)
        end
      Rails.logger.debug "... occupant_allocs => #{occupant_allocs.map(&:id)} seats => #{occupant_allocs.map(&:seat_id)}"
      puts "... occupant_allocs => #{occupant_allocs.map(&:id)} seats => #{occupant_allocs.map(&:seat_id)}"

      occupant_allocs.each do |alloc|
        seat = alloc.seat
        Rails.logger.debug ">>> occupant #{occupant.id} => freeing seat #{seat.id}"
        puts ">>> occupant #{occupant.id} => freeing seat #{seat.id}"
        seat.update!(status: "free")
        alloc.update!(released_at: Time.current)
      end

      occupant.update!(status: "no_show")
      Rails.logger.debug "... occupant #{occupant.id} => 'no_show'"
      puts "... occupant #{occupant.id} => 'no_show'"
    end

    render json: { message: "Marked occupant as no_show; seats => free" }, status: :ok
  rescue => e
    Rails.logger.error "[no_show] Error => #{e.message}"
    puts "[no_show] Error => #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/cancel
  # => occupant => "canceled", seats => "free"
  # ------------------------------------------------------------------
  def cancel
    Rails.logger.debug "===== [cancel] params=#{params.inspect}"
    puts "===== [cancel] params=#{params.inspect}"

    c_params = params.permit(:occupant_type, :occupant_id)
    occupant_type = c_params[:occupant_type]
    occupant_id   = c_params[:occupant_id]

    if occupant_type.blank? || occupant_id.blank?
      Rails.logger.warn "[cancel] occupant_type/occupant_id missing!"
      puts "[cancel] occupant_type/occupant_id missing!"
      return render json: { error: "Must provide occupant_type, occupant_id" }, status: :unprocessable_entity
    end

    occupant = case occupant_type
               when "reservation" then Reservation.find_by(id: occupant_id)
               when "waitlist"    then WaitlistEntry.find_by(id: occupant_id)
               end
    unless occupant
      Rails.logger.warn "[cancel] occupant not found => id=#{occupant_id}"
      puts "[cancel] occupant not found => id=#{occupant_id}"
      return render json: { error: "Could not find occupant" }, status: :not_found
    end

    ActiveRecord::Base.transaction do
      occupant_allocs =
        if occupant_type == "reservation"
          SeatAllocation.where(reservation_id: occupant.id, released_at: nil)
        else
          SeatAllocation.where(waitlist_entry_id: occupant.id, released_at: nil)
        end
      Rails.logger.debug "... occupant_allocs => #{occupant_allocs.map(&:id)} seats => #{occupant_allocs.map(&:seat_id)}"
      puts "... occupant_allocs => #{occupant_allocs.map(&:id)} seats => #{occupant_allocs.map(&:seat_id)}"

      occupant_allocs.each do |alloc|
        seat = alloc.seat
        Rails.logger.debug ">>> occupant #{occupant.id} => freeing seat #{seat.id}"
        puts ">>> occupant #{occupant.id} => freeing seat #{seat.id}"
        seat.update!(status: "free")
        alloc.update!(released_at: Time.current)
      end

      occupant.update!(status: "canceled")
      Rails.logger.debug "... occupant #{occupant.id} => 'canceled'"
      puts "... occupant #{occupant.id} => 'canceled'"
    end

    render json: { message: "Canceled occupant & freed seats" }, status: :ok
  rescue => e
    Rails.logger.error "[cancel] Error => #{e.message}"
    puts "[cancel] Error => #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # ------------------------------------------------------------------
  # DELETE /seat_allocations/:id
  # => occupant => 'finished'/'removed', seats => 'free'
  # ------------------------------------------------------------------
  def destroy
    Rails.logger.debug "===== [destroy] params=#{params.inspect}"
    puts "===== [destroy] params=#{params.inspect}"

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
      Rails.logger.debug ">>> occupant_type=#{occupant_type}, occupant.id=#{occupant.id}, occupant_allocs=#{occupant_allocs.map(&:id)}"
      puts ">>> occupant_type=#{occupant_type}, occupant.id=#{occupant.id}, occupant_allocs=#{occupant_allocs.map(&:id)}"

      occupant_allocs.each do |alloc|
        seat = alloc.seat
        Rails.logger.debug "... seat #{seat.id} => 'free'"
        puts "... seat #{seat.id} => 'free'"
        seat.update!(status: "free") 
        alloc.update!(released_at: Time.current)
      end

      if occupant_type == "reservation"
        occupant.update!(status: "finished")
      else
        occupant.update!(status: "removed")
      end
      Rails.logger.debug "... occupant #{occupant.id} => '#{occupant.status}'"
      puts "... occupant #{occupant.id} => '#{occupant.status}'"
    end

    head :no_content
  end

  # ------------------------------------------------------------------
  # POST /seat_allocations/finish
  # => occupant => "finished"/"removed", seats => "free"
  # ------------------------------------------------------------------
  def finish
    Rails.logger.debug "===== [finish] params=#{params.inspect}"
    puts "===== [finish] params=#{params.inspect}"

    f_params = params.permit(:occupant_type, :occupant_id)
    occupant_type = f_params[:occupant_type]
    occupant_id   = f_params[:occupant_id]

    if occupant_type.blank? || occupant_id.blank?
      Rails.logger.warn "[finish] occupant_type/occupant_id missing!"
      puts "[finish] occupant_type/occupant_id missing!"
      return render json: { error: "Must provide occupant_type, occupant_id" }, status: :unprocessable_entity
    end

    occupant = case occupant_type
               when "reservation" then Reservation.find_by(id: occupant_id)
               when "waitlist"    then WaitlistEntry.find_by(id: occupant_id)
               end
    unless occupant
      Rails.logger.warn "[finish] occupant not found => id=#{occupant_id}"
      puts "[finish] occupant not found => id=#{occupant_id}"
      return render json: { error: "Could not find occupant" }, status: :not_found
    end

    ActiveRecord::Base.transaction do
      occupant_allocs =
        if occupant_type == "reservation"
          SeatAllocation.where(reservation_id: occupant.id, released_at: nil)
        else
          SeatAllocation.where(waitlist_entry_id: occupant.id, released_at: nil)
        end
      Rails.logger.debug "... occupant_allocs => #{occupant_allocs.map(&:id)} seats => #{occupant_allocs.map(&:seat_id)}"
      puts "... occupant_allocs => #{occupant_allocs.map(&:id)} seats => #{occupant_allocs.map(&:seat_id)}"

      occupant_allocs.each do |alloc|
        seat = alloc.seat
        Rails.logger.debug ">>> occupant #{occupant.id} => freeing seat #{seat.id}"
        puts ">>> occupant #{occupant.id} => freeing seat #{seat.id}"
        seat.update!(status: "free")
        alloc.update!(released_at: Time.current)
      end

      if occupant_type == "reservation"
        occupant.update!(status: "finished")
      else
        occupant.update!(status: "removed")
      end
      Rails.logger.debug "... occupant #{occupant.id} => '#{occupant.status}'"
      puts "... occupant #{occupant.id} => '#{occupant.status}'"
    end

    render json: { message: "Occupant finished; seats freed" }, status: :ok
  rescue => e
    Rails.logger.error "[finish] Error => #{e.message}"
    puts "[finish] Error => #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
