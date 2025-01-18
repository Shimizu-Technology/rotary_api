class LayoutsController < ApplicationController
  before_action :authorize_request
  before_action :set_layout, only: [:show, :update, :destroy]

  def index
    # Return all layouts for super_admin, or just the user’s restaurant
    if current_user.role == 'super_admin'
      layouts = Layout.all
    else
      layouts = Layout.where(restaurant_id: current_user.restaurant_id)
    end
    render json: layouts
  end

  def show
    Rails.logger.debug "LayoutsController#show => injecting occupant info"
    sections = @layout.sections_data["sections"] || []
    seat_ids = []

    # Gather seat IDs from sections JSON
    sections.each do |sec|
      next unless sec["seats"].is_a?(Array)
      sec["seats"].each do |seat_hash|
        seat_ids << seat_hash["id"] if seat_hash["id"].present?
      end
    end

    # Confirm that these seat IDs actually exist
    existing_seat_ids = Seat.where(id: seat_ids).pluck(:id)
    if existing_seat_ids.size < seat_ids.size
      missing_ids = seat_ids - existing_seat_ids
      Rails.logger.warn "Some seats in layout JSON are missing in DB: #{missing_ids.inspect}"
      # Optionally remove them from sections_data or mark them somehow
    end

    # Load occupant info from seat_allocations
    seat_allocations = SeatAllocation
      .includes(:reservation, :waitlist_entry)
      .where(seat_id: existing_seat_ids, released_at: nil)

    occupant_map = {}
    seat_allocations.each do |sa|
      occupant = sa.reservation || sa.waitlist_entry
      occupant_status = occupant&.status  # "booked", "reserved", "seated", etc.

      seat_status =
        case occupant_status
        when "seated"
          "occupied"
        when "reserved"
          "reserved"
        when "booked", "waiting"
          "reserved"  # treat them as “reserved” if seat_alloc
        else
          "occupied"
        end

      occupant_map[sa.seat_id] = {
        seat_status: seat_status,
        occupant_type: sa.reservation_id ? "reservation" : "waitlist",
        occupant_id: occupant.id,
        occupant_name: occupant.contact_name,
        occupant_party_size: occupant.party_size,
        occupant_status: occupant.status,
        allocation_id: sa.id
      }
    end

    # Merge occupant data into the JSON
    sections.each do |sec|
      sec["seats"]&.each do |seat_hash|
        sid = seat_hash["id"]
        if occupant_map[sid]
          occ = occupant_map[sid]
          seat_hash["status"]               = occ[:seat_status]
          seat_hash["occupant_type"]        = occ[:occupant_type]
          seat_hash["occupant_id"]          = occ[:occupant_id]
          seat_hash["occupant_name"]        = occ[:occupant_name]
          seat_hash["occupant_party_size"]  = occ[:occupant_party_size]
          seat_hash["allocationId"]         = occ[:allocation_id]
        else
          seat_hash["status"]               = "free"
          seat_hash["occupant_type"]        = nil
          seat_hash["occupant_id"]          = nil
          seat_hash["occupant_name"]        = nil
          seat_hash["occupant_party_size"]  = nil
          seat_hash["allocationId"]         = nil
        end
      end
    end

    render json: @layout
  end

  def create
    @layout = Layout.new(layout_params)
    # If not super_admin, force restaurant_id to current_user’s
    if current_user.role != 'super_admin'
      @layout.restaurant_id = current_user.restaurant_id
    end

    if @layout.save
      render json: @layout, status: :created
    else
      render json: { errors: @layout.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    # 1) update layout’s JSON
    if @layout.update(layout_params)
      # 2) (Optional) create real seat records from the JSON

      # Danger: we do a destructive approach => remove all seat_sections for this restaurant
      # Then re-create them from the JSON. If you have multiple layouts for the same restaurant,
      # this can conflict. But for a simple 1-layout scenario it works.
      SeatSection.where(restaurant_id: @layout.restaurant_id).destroy_all

      sections = @layout.sections_data["sections"] || []
      sections.each do |sec|
        # Create seat_section in DB
        seat_section = SeatSection.create!(
          restaurant_id:  @layout.restaurant_id,
          name:           sec["name"] || "Unnamed Section",
          section_type:   sec["type"] || "counter",
          orientation:    sec["orientation"] || "vertical",
          offset_x:       sec["offsetX"] || 0,
          offset_y:       sec["offsetY"] || 0,
          capacity:       (sec["seats"]&.size || 0)
        )

        # Create seats
        sec["seats"]&.each do |seat_hash|
          Seat.create!(
            seat_section_id: seat_section.id,
            label:      seat_hash["label"] || "Seat",
            position_x: seat_hash["position_x"] || 0,
            position_y: seat_hash["position_y"] || 0,
            capacity:   seat_hash["capacity"] || 1,
            status:     "free"  # or seat_hash["status"], up to you
          )
        end
      end

      render json: @layout
    else
      render json: { errors: @layout.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @layout.destroy
    head :no_content
  end

  private

  def set_layout
    @layout = Layout.find(params[:id])
  end

  def layout_params
    # sections_data is a JSON structure => permit :sections_data => {}
    params.require(:layout).permit(:name, :restaurant_id, sections_data: {})
  end
end
