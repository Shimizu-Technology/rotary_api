# app/controllers/seats_controller.rb

class SeatsController < ApplicationController
  before_action :authorize_request

  # GET /seats
  def index
    # If you do multi-tenant, you might do:
    # seats = Seat.joins(:seat_section).where(
    #   seat_sections: { restaurant_id: current_user.restaurant_id }
    # )
    # For now, we’ll just return all:
    seats = Seat.all
    render json: seats
  end

  # POST /seats
  def create
    seat_params = params.require(:seat).permit(
      :seat_section_id, :label, :position_x, :position_y, 
      :status, :capacity
    )

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
    # Instead of Seat.find(...), use find_by so we can gracefully handle nil
    seat = Seat.find_by(id: params[:id])
    return head :no_content unless seat  # If not found, just return 204, silently ignoring

    ActiveRecord::Base.transaction do
      # If you’re also removing seat_allocations or have other logic, do it here
      # For example, remove seat_allocations for that seat:
      SeatAllocation.where(seat_id: seat.id).each do |alloc|
        alloc.destroy
      end

      seat.destroy
    end

    head :no_content
  end
end
