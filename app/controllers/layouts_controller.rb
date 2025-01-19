class LayoutsController < ApplicationController
  before_action :authorize_request
  before_action :set_layout, only: [:show, :update, :destroy]

  # GET /layouts
  def index
    if current_user.role == 'super_admin'
      layouts = Layout.all
    else
      layouts = Layout.where(restaurant_id: current_user.restaurant_id)
    end
    render json: layouts
  end

  # GET /layouts/:id
  # Returns expanded seat data under "seat_sections."
  def show
    # Load seat sections (and seats) from the DB
    seat_sections = @layout.seat_sections.includes(:seats)

    # (Optional) occupant info injection
    seat_allocations = SeatAllocation
      .includes(:reservation, :waitlist_entry)
      .where(seat_id: seat_sections.flat_map(&:seats).pluck(:id), released_at: nil)

    occupant_map = {}
    seat_allocations.each do |alloc|
      occupant = alloc.reservation || alloc.waitlist_entry
      occupant_map[alloc.seat_id] = {
        occupant_type: (alloc.reservation_id ? "reservation" : "waitlist"),
        occupant_name: occupant.contact_name,
        occupant_party_size: occupant.try(:party_size),
        occupant_status: occupant.status
      }
    end

    data = {
      id: @layout.id,
      name: @layout.name,
      # We can keep or remove the raw sections_data if you want a fallback
      sections_data: @layout.sections_data,

      # The important part: real seat data with DB IDs
      seat_sections: seat_sections.map do |sec|
        {
          id: sec.id,
          name: sec.name,
          offset_x: sec.offset_x,
          offset_y: sec.offset_y,
          orientation: sec.orientation,
          seats: sec.seats.map do |seat|
            occ = occupant_map[seat.id]
            {
              id: seat.id,
              label: seat.label,
              position_x: seat.position_x,
              position_y: seat.position_y,
              capacity: seat.capacity,
              status: occ ? "occupied" : seat.status,
              occupant_info: occ
            }
          end
        }
      end
    }

    render json: data
  end

  # POST /layouts
  #
  # NOW also creates seat_sections/seats on first save (using the same logic as update).
  def create
    assigned_restaurant_id =
      if current_user.role == 'super_admin'
        layout_params[:restaurant_id]
      else
        current_user.restaurant_id
      end

    @layout = Layout.new(
      name: layout_params[:name],
      restaurant_id: assigned_restaurant_id,
      sections_data: layout_params[:sections_data] || {}
    )

    ActiveRecord::Base.transaction do
      if @layout.save
        # Parse the seat/section data out of the JSON
        sections_array = layout_params.dig(:sections_data, :sections) || []

        section_ids_in_use = []

        sections_array.each do |sec_data|
          existing_section_id = sec_data["id"].to_i if sec_data["id"].to_s.match?(/^\d+$/)
          seat_section = nil

          # For a brand-new layout, there's typically no existing_section_id,
          # but we keep this check if the client passes one.
          if existing_section_id && existing_section_id > 0
            seat_section = @layout.seat_sections.find_by(id: existing_section_id)
          end

          seat_section ||= @layout.seat_sections.build
          seat_section.name         = sec_data["name"]
          seat_section.section_type = sec_data["type"] # or sec_data["section_type"]
          seat_section.orientation  = sec_data["orientation"]
          seat_section.offset_x     = sec_data["offsetX"]
          seat_section.offset_y     = sec_data["offsetY"]
          seat_section.save!

          section_ids_in_use << seat_section.id

          seats_array = sec_data["seats"] || []
          seat_ids_in_use = []

          seats_array.each do |seat_data|
            existing_seat_id = seat_data["id"].to_i if seat_data["id"].to_s.match?(/^\d+$/)
            seat = nil

            if existing_seat_id && existing_seat_id > 0
              seat = seat_section.seats.find_by(id: existing_seat_id)
            end

            seat ||= seat_section.seats.build
            seat.label       = seat_data["label"]
            seat.position_x  = seat_data["position_x"]
            seat.position_y  = seat_data["position_y"]
            seat.status      = seat_data["status"] || "free"
            seat.capacity    = seat_data["capacity"] || 1
            seat.save!

            seat_ids_in_use << seat.id
          end

          # Remove seats that no longer exist in the array
          seat_section.seats.where.not(id: seat_ids_in_use).destroy_all
        end

        # Remove seat_sections that were deleted on the client side
        @layout.seat_sections.where.not(id: section_ids_in_use).destroy_all

        @layout.save!
        render json: @layout, status: :created
      else
        render json: { errors: @layout.errors.full_messages }, status: :unprocessable_entity
      end
    end
  end

  # PATCH/PUT /layouts/:id
  #
  # Still handles seat/section creation using the JSON in layout_params[:sections_data].
  def update
    if current_user.role != 'super_admin'
      @layout.restaurant_id = current_user.restaurant_id
    else
      @layout.restaurant_id = layout_params[:restaurant_id] if layout_params[:restaurant_id]
    end

    @layout.name = layout_params[:name] if layout_params[:name]
    @layout.sections_data = layout_params[:sections_data] if layout_params.key?(:sections_data)

    sections_array = layout_params.dig(:sections_data, :sections) || []

    ActiveRecord::Base.transaction do
      section_ids_in_use = []

      sections_array.each do |sec_data|
        existing_section_id = sec_data["id"].to_i if sec_data["id"].to_s.match?(/^\d+$/)
        seat_section = nil

        if existing_section_id && existing_section_id > 0
          seat_section = @layout.seat_sections.find_by(id: existing_section_id)
        end

        seat_section ||= @layout.seat_sections.build
        seat_section.name         = sec_data["name"]
        seat_section.section_type = sec_data["type"]
        seat_section.orientation  = sec_data["orientation"]
        seat_section.offset_x     = sec_data["offsetX"]
        seat_section.offset_y     = sec_data["offsetY"]
        seat_section.save!

        section_ids_in_use << seat_section.id

        seats_array = sec_data["seats"] || []
        seat_ids_in_use = []

        seats_array.each do |seat_data|
          existing_seat_id = seat_data["id"].to_i if seat_data["id"].to_s.match?(/^\d+$/)
          seat = nil

          if existing_seat_id && existing_seat_id > 0
            seat = seat_section.seats.find_by(id: existing_seat_id)
          end

          seat ||= seat_section.seats.build
          seat.label       = seat_data["label"]
          seat.position_x  = seat_data["position_x"]
          seat.position_y  = seat_data["position_y"]
          seat.status      = seat_data["status"] || "free"
          seat.capacity    = seat_data["capacity"] || 1
          seat.save!

          seat_ids_in_use << seat.id
        end

        # Remove seats that no longer exist in the array
        seat_section.seats.where.not(id: seat_ids_in_use).destroy_all
      end

      # Remove seat_sections that were deleted on the client
      @layout.seat_sections.where.not(id: section_ids_in_use).destroy_all

      @layout.save!
    end

    render json: @layout
  rescue => e
    Rails.logger.error("Error updating layout with seat sections: #{e.message}")
    render json: { errors: [e.message] }, status: :unprocessable_entity
  end

  # DELETE /layouts/:id
  def destroy
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
end
