class ReservationsController < ApplicationController
  before_action :authorize_request

  def index
    # Optionally scope by current_user.restaurant_id to enforce multi-tenancy
    # e.g. reservations = Reservation.where(restaurant_id: current_user.restaurant_id)
    reservations = Reservation.all
    render json: reservations
  end

  def show
    reservation = Reservation.find(params[:id])
    render json: reservation
  end

  def create
    reservation = Reservation.new(reservation_params)
    # Optional enforcement for multi-tenant:
    # reservation.restaurant_id = current_user.restaurant_id unless current_user.role == 'super_admin'

    if reservation.save
      render json: reservation, status: :created
    else
      render json: { errors: reservation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    reservation = Reservation.find(params[:id])
    if reservation.update(reservation_params)
      render json: reservation
    else
      render json: { errors: reservation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    reservation = Reservation.find(params[:id])
    reservation.destroy
    head :no_content
  end

  private

  def reservation_params
    params.require(:reservation).permit(
      :restaurant_id,
      :start_time,
      :end_time,
      :party_size,
      :contact_name,
      :contact_phone,
      :contact_email,
      :deposit_amount,
      :reservation_source,
      :special_requests,
      :status
    )
  end
end
