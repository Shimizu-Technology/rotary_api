class LayoutsController < ApplicationController
  before_action :authorize_request
  before_action :set_layout, only: [:show, :update, :destroy]

  def index
    # Return all layouts for super_admin, or the user’s restaurant
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

    # Gather seat IDs from sections
    sections.each do |sec|
      next unless sec["seats"].is_a?(Array)
      sec["seats"].each do |seat_hash|
        seat_ids << seat_hash["id"] if seat_hash["id"].present?
      end
    end

    # Possibly filter out or log seats that are missing:
    existing_seat_ids = Seat.where(id: seat_ids).pluck(:id)
    if existing_seat_ids.size < seat_ids.size
      missing_ids = seat_ids - existing_seat_ids
      Rails.logger.warn "Some seats in layout JSON are missing from DB: #{missing_ids.inspect}"
      # Optionally remove or mark them
      # For now, we’ll keep them, but your choice:
      # seat_ids = existing_seat_ids
    end

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
          # If occupant is "booked/waiting" but seat is allocated,
          # you might treat seat as "reserved" too
          "reserved"
        else
          # fallback => "occupied" if occupant is in some other state
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

    # Merge occupant data into seats
    sections.each do |sec|
      sec["seats"].each do |seat_hash|
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
          seat_hash["status"] = "free"
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
    @layout = Layout.new(layout_params)
    @layout.restaurant_id ||= current_user.restaurant_id unless current_user.role == 'super_admin'
    if @layout.save
      render json: @layout, status: :created
    else
      render json: { errors: @layout.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @layout.update(layout_params)
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
    params.require(:layout).permit(:name, :restaurant_id, sections_data: {})
  end
end
