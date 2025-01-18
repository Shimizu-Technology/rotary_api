class LayoutsController < ApplicationController
  before_action :authorize_request
  before_action :set_layout, only: [:show, :update, :destroy]

  def index
    Rails.logger.debug "LayoutsController#index => current_user=#{current_user.id}, role=#{current_user.role}"
    puts "LayoutsController#index => current_user=#{current_user.id}, role=#{current_user.role}"

    if current_user.role == 'super_admin'
      layouts = Layout.all
    else
      layouts = Layout.where(restaurant_id: current_user.restaurant_id)
    end

    Rails.logger.debug "LayoutsController#index => returning #{layouts.size} layouts"
    puts "LayoutsController#index => returning #{layouts.size} layouts"
    render json: layouts
  end

  def show
    Rails.logger.debug "LayoutsController#show => layout_id=#{@layout.id}, injecting occupant info"
    puts "LayoutsController#show => layout_id=#{@layout.id}, injecting occupant info"

    sections = @layout.sections_data["sections"] || []
    seat_ids = []

    sections.each do |sec|
      next unless sec["seats"].is_a?(Array)
      sec["seats"].each do |seat_hash|
        seat_ids << seat_hash["id"] if seat_hash["id"].present?
      end
    end

    existing_seat_ids = Seat.where(id: seat_ids).pluck(:id)
    if existing_seat_ids.size < seat_ids.size
      missing_ids = seat_ids - existing_seat_ids
      Rails.logger.warn "Some seats in layout JSON are missing in DB => #{missing_ids.inspect}"
      puts "Some seats in layout JSON are missing in DB => #{missing_ids.inspect}"
    end

    seat_allocations = SeatAllocation
                         .includes(:reservation, :waitlist_entry)
                         .where(seat_id: existing_seat_ids, released_at: nil)

    occupant_map = {}
    seat_allocations.each do |sa|
      occupant = sa.reservation || sa.waitlist_entry
      occupant_status = occupant&.status

      seat_status =
        case occupant_status
        when "seated"
          "occupied"
        when "reserved", "booked", "waiting"
          "reserved"
        else
          "occupied"
        end

      occupant_map[sa.seat_id] = {
        seat_status:         seat_status,
        occupant_type:       sa.reservation_id ? "reservation" : "waitlist",
        occupant_id:         occupant.id,
        occupant_name:       occupant.contact_name,
        occupant_party_size: occupant.party_size,
        occupant_status:     occupant.status,
        allocation_id:       sa.id
      }
    end

    # Merge occupant data back into the JSON
    sections.each do |sec|
      sec["seats"]&.each do |seat_hash|
        sid = seat_hash["id"]
        if occupant_map[sid]
          occ = occupant_map[sid]
          seat_hash["status"]              = occ[:seat_status]
          seat_hash["occupant_type"]       = occ[:occupant_type]
          seat_hash["occupant_id"]         = occ[:occupant_id]
          seat_hash["occupant_name"]       = occ[:occupant_name]
          seat_hash["occupant_party_size"] = occ[:occupant_party_size]
          seat_hash["allocationId"]        = occ[:allocation_id]
        else
          seat_hash["status"]              = "free"
          seat_hash["occupant_type"]       = nil
          seat_hash["occupant_id"]         = nil
          seat_hash["occupant_name"]       = nil
          seat_hash["occupant_party_size"] = nil
          seat_hash["allocationId"]        = nil
        end
      end
    end

    render json: @layout
  end

  def create
    Rails.logger.debug "LayoutsController#create => params=#{layout_params.inspect}"
    puts "LayoutsController#create => params=#{layout_params.inspect}"

    # 1) Build a new layout (without persisting seat-sections data yet)
    @layout = Layout.new(
      name: layout_params[:name],
      restaurant_id: layout_params[:restaurant_id] || current_user.restaurant_id,
      sections_data: {}
    )

    # If not super_admin, ensure restaurant_id is user's
    if current_user.role != 'super_admin'
      @layout.restaurant_id = current_user.restaurant_id
    end

    Rails.logger.debug "Built Layout => #{@layout.attributes.inspect}"
    puts "Built Layout => #{@layout.attributes.inspect}"

    ActiveRecord::Base.transaction do
      # Save the layout so it has an ID
      @layout.save!
      Rails.logger.debug "Layout saved => id=#{@layout.id}, name=#{@layout.name}"
      puts "Layout saved => id=#{@layout.id}, name=#{@layout.name}"

      # Now upsert seat sections & seats
      incoming_sections_data = layout_params[:sections_data] || {}
      Rails.logger.debug "Process sections => #{incoming_sections_data.inspect}"
      puts "Process sections => #{incoming_sections_data.inspect}"
      process_sections_data(incoming_sections_data)

      # Finally, store the final JSON (with real seat IDs, etc.)
      @layout.sections_data = incoming_sections_data
      @layout.save!
      Rails.logger.debug "Layout updated with final sections_data => #{@layout.sections_data.inspect}"
      puts "Layout updated with final sections_data => #{@layout.sections_data.inspect}"
    end

    render json: @layout, status: :created
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Layout create failed => #{e.record.errors.full_messages}"
    puts "Layout create failed => #{e.record.errors.full_messages}"
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def update
    Rails.logger.debug "LayoutsController#update => layout_id=#{@layout.id}, params=#{layout_params.inspect}"
    puts "LayoutsController#update => layout_id=#{@layout.id}, params=#{layout_params.inspect}"

    @layout.assign_attributes(
      name: layout_params[:name],
      restaurant_id: layout_params[:restaurant_id] || @layout.restaurant_id
    )
    if current_user.role != 'super_admin'
      @layout.restaurant_id = current_user.restaurant_id
    end

    sections_data = layout_params[:sections_data] || {}

    ActiveRecord::Base.transaction do
      @layout.save!
      Rails.logger.debug "Layout updated => #{@layout.attributes.inspect}"
      puts "Layout updated => #{@layout.attributes.inspect}"

      process_sections_data(sections_data)

      @layout.sections_data = sections_data
      @layout.save!
      Rails.logger.debug "Layout updated with final sections_data => #{@layout.sections_data.inspect}"
      puts "Layout updated with final sections_data => #{@layout.sections_data.inspect}"
    end

    render json: @layout
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Layout update failed => #{e.record.errors.full_messages}"
    puts "Layout update failed => #{e.record.errors.full_messages}"
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy
    Rails.logger.debug "LayoutsController#destroy => layout_id=#{@layout.id}"
    puts "LayoutsController#destroy => layout_id=#{@layout.id}"
    @layout.destroy
    head :no_content
  end

  private

  def set_layout
    @layout = Layout.find(params[:id])
  end

  def layout_params
    params.require(:layout).permit(:name, :restaurant_id, sections_data: {})
  end

  # ---------------------------------------
  # Ensures seat_sections & seats in the DB match the JSON
  # Layout must already be saved (persisted) before calling.
  # ---------------------------------------
  def process_sections_data(sections_data_param)
    Rails.logger.debug "process_sections_data => sections_data=#{sections_data_param.inspect}"
    puts "process_sections_data => sections_data=#{sections_data_param.inspect}"

    # Convert ActionController::Parameters to a plain Ruby Hash
    sections_data = sections_data_param.to_h
    Rails.logger.debug "process_sections_data => after to_h => #{sections_data.inspect}"
    puts "process_sections_data => after to_h => #{sections_data.inspect}"

    sections_arr = sections_data["sections"] || []

    kept_section_ids = []

    sections_arr.each do |sec_hash|
      seat_section = upsert_seat_section(sec_hash)
      kept_section_ids << seat_section.id
      Rails.logger.debug "Kept seat_section => #{seat_section.inspect}"
      puts "Kept seat_section => #{seat_section.inspect}"

      kept_seat_ids = []
      (sec_hash["seats"] || []).each do |seat_hash|
        seat = upsert_seat(seat_hash, seat_section)
        seat_hash["id"] = seat.id
        kept_seat_ids << seat.id
        Rails.logger.debug "Created/updated seat => #{seat.inspect}"
        puts "Created/updated seat => #{seat.inspect}"
      end

      # Remove seats that were deleted in the JSON
      to_remove = seat_section.seats.where.not(id: kept_seat_ids)
      Rails.logger.debug "Removing seats => #{to_remove.pluck(:id).inspect}"
      puts "Removing seats => #{to_remove.pluck(:id).inspect}"
      to_remove.destroy_all

      sec_hash["dbId"] = seat_section.id
    end

    remove_old_sections(kept_section_ids)
  end

  def upsert_seat_section(sec_hash)
    Rails.logger.debug "upsert_seat_section => sec_hash=#{sec_hash.inspect}"
    puts "upsert_seat_section => sec_hash=#{sec_hash.inspect}"
    db_id = sec_hash["dbId"]

    if db_id.present?
      seat_section = @layout.seat_sections.find_by(id: db_id)
      if seat_section
        seat_section.update!(
          name:         sec_hash["name"],
          section_type: sec_hash["type"],
          orientation:  sec_hash["orientation"],
          offset_x:     sec_hash["offsetX"] || 0,
          offset_y:     sec_hash["offsetY"] || 0
        )
        Rails.logger.debug "Updated existing seat_section => #{seat_section.inspect}"
        puts "Updated existing seat_section => #{seat_section.inspect}"
        return seat_section
      end
    end

    new_section = @layout.seat_sections.create!(
      name:         sec_hash["name"],
      section_type: sec_hash["type"],
      orientation:  sec_hash["orientation"],
      offset_x:     sec_hash["offsetX"] || 0,
      offset_y:     sec_hash["offsetY"] || 0
    )
    Rails.logger.debug "Created new seat_section => #{new_section.inspect}"
    puts "Created new seat_section => #{new_section.inspect}"
    new_section
  end

  def upsert_seat(seat_hash, seat_section)
    Rails.logger.debug "upsert_seat => seat_hash=#{seat_hash.inspect}"
    puts "upsert_seat => seat_hash=#{seat_hash.inspect}"
    seat_id = seat_hash["id"]
    if seat_id.present?
      seat = seat_section.seats.find_by(id: seat_id)
      if seat
        seat.update!(
          label:      seat_hash["label"],
          position_x: seat_hash["position_x"],
          position_y: seat_hash["position_y"],
          status:     seat_hash["status"] || "free",
          capacity:   seat_hash["capacity"] || 1
        )
        Rails.logger.debug "Updated existing seat => #{seat.inspect}"
        puts "Updated existing seat => #{seat.inspect}"
        return seat
      end
    end

    created_seat = seat_section.seats.create!(
      label:      seat_hash["label"],
      position_x: seat_hash["position_x"],
      position_y: seat_hash["position_y"],
      status:     seat_hash["status"] || "free",
      capacity:   seat_hash["capacity"] || 1
    )
    Rails.logger.debug "Created new seat => #{created_seat.inspect}"
    puts "Created new seat => #{created_seat.inspect}"
    created_seat
  end

  def remove_old_sections(kept_section_ids)
    to_remove = @layout.seat_sections.where.not(id: kept_section_ids)
    Rails.logger.debug "Removing seat_sections => #{to_remove.pluck(:id).inspect}"
    puts "Removing seat_sections => #{to_remove.pluck(:id).inspect}"
    to_remove.destroy_all
  end
end