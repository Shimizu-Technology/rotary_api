# app/controllers/layouts_controller.rb
class LayoutsController < ApplicationController
  before_action :authorize_request
  before_action :set_layout, only: [:show, :update, :destroy]

  def index
    # Return all layouts for the current restaurant, or all if super_admin
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

    # Gather seat IDs
    sections.each do |sec|
      next unless sec["seats"].is_a?(Array)
      sec["seats"].each do |seat_hash|
        seat_ids << seat_hash["id"] if seat_hash["id"].present?
      end
    end

    # Active seat_allocations
    seat_allocations = SeatAllocation
      .includes(:reservation, :waitlist_entry)
      .where(seat_id: seat_ids, released_at: nil)

    occupant_map = {}
    seat_allocations.each do |sa|
      occupant_map[sa.seat_id] = {
        occupant_type: sa.reservation_id ? "reservation" : "waitlist",
        occupant_id: sa.reservation_id || sa.waitlist_entry_id,
        occupant_name: sa.reservation&.contact_name || sa.waitlist_entry&.contact_name,
        occupant_party_size: (sa.reservation&.party_size || sa.waitlist_entry&.party_size),
        allocation_id: sa.id
      }
    end

    sections.each do |sec|
      sec["seats"].each do |seat_hash|
        seat_id = seat_hash["id"]
        occ = occupant_map[seat_id]
        if occ
          seat_hash["status"] = "occupied"
          seat_hash["occupant_type"] = occ[:occupant_type]
          seat_hash["occupant_id"] = occ[:occupant_id]
          seat_hash["occupant_name"] = occ[:occupant_name]
          seat_hash["occupant_party_size"] = occ[:occupant_party_size]
          seat_hash["allocationId"] = occ[:allocation_id]
        else
          seat_hash["status"] = "free"
          seat_hash["occupant_type"] = nil
          seat_hash["occupant_id"] = nil
          seat_hash["occupant_name"] = nil
          seat_hash["occupant_party_size"] = nil
          seat_hash["allocationId"] = nil
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
