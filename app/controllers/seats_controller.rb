# app/controllers/seats_controller.rb
class SeatsController < ApplicationController
  before_action :authorize_request

  # GET /seats
  def index
    # If multi-tenant:
    # seats = Seat.joins(:seat_section).where(seat_sections: { restaurant_id: current_user.restaurant_id })
    seats = Seat.all
    render json: seats
  end

  # POST /seats
  def create
    seat_params = params.require(:seat).permit(
      :seat_section_id,
      :label,
      :position_x,
      :position_y,
      :status,
      :capacity
    )

    # Optional: ensure seat_section belongs to user’s restaurant

    seat = Seat.new(seat_params)
    if seat.save
      render json: seat, status: :created
    else
      render json: { errors: seat.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /seats/:id
  def show
    seat = Seat.find(params[:id])
    render json: seat
  end

  # PATCH/PUT /seats/:id
  def update
    seat = Seat.find(params[:id])
    update_params = params.require(:seat).permit(
      :label, :position_x, :position_y, :status, :capacity
    )
    if seat.update(update_params)
      render json: seat
    else
      render json: { errors: seat.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /seats/:id
  def destroy
    seat = Seat.find(params[:id])
    seat.destroy
    head :no_content
  end
end
