# app/controllers/seat_sections_controller.rb
class SeatSectionsController < ApplicationController
  before_action :authorize_request

  def index
    # Return all seat sections (or filter by the current user’s restaurant if needed)
    seat_sections = SeatSection.all
    render json: seat_sections
  end

  def show
    seat_section = SeatSection.find_by(id: params[:id])
    return render json: { error: "Seat section not found" }, status: :not_found unless seat_section

    render json: seat_section
  end

  def create
    # IMPORTANT: You must provide a valid restaurant_id so it can belong_to that restaurant
    section_params = params.require(:seat_section).permit(
      :name, :section_type, :orientation, :offset_x, :offset_y, :capacity, :restaurant_id
    )

    seat_section = SeatSection.new(section_params)
    if seat_section.save
      render json: seat_section, status: :created
    else
      render json: { errors: seat_section.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    seat_section = SeatSection.find_by(id: params[:id])
    return render json: { error: "Seat section not found" }, status: :not_found unless seat_section

    update_params = params.require(:seat_section).permit(
      :name, :section_type, :orientation, :offset_x, :offset_y, :capacity
    )

    if seat_section.update(update_params)
      render json: seat_section
    else
      render json: { errors: seat_section.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    seat_section = SeatSection.find_by(id: params[:id])
    return head :no_content unless seat_section  # If not found, just respond 204

    seat_section.destroy
    head :no_content
  end
end
