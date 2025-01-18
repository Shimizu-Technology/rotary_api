# app/controllers/seats_controller.rb
class SeatsController < ApplicationController
  before_action :authorize_request

  def index
    # Return all seats or filter by restaurant if needed
    seats = Seat.all
    render json: seats
  end

  def create
    seat_params = params.require(:seat).permit(
      :seat_section_id, :label, :position_x, :position_y, 
      :status, :capacity
    )

    seat = Seat.new(seat_params)
    if seat.save
      render json: seat, status: :created
    else
      Rails.logger.error("Failed to create seat: #{seat.errors.full_messages}")  # Debug line
      render json: { errors: seat.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def show
    seat = Seat.find_by(id: params[:id])
    return render json: { error: "Seat not found" }, status: :not_found unless seat

    render json: seat
  end

  def update
    seat = Seat.find_by(id: params[:id])
    return render json: { error: "Seat not found" }, status: :not_found unless seat

    update_params = params.require(:seat).permit(:label, :position_x, :position_y, :status, :capacity)
    if seat.update(update_params)
      render json: seat
    else
      render json: { errors: seat.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    seat = Seat.find_by(id: params[:id])
    return head :no_content unless seat  # If not found, ignore.

    ActiveRecord::Base.transaction do
      # Remove seat_allocations for that seat
      SeatAllocation.where(seat_id: seat.id).destroy_all

      seat.destroy
    end

    head :no_content
  end
end
