# app/controllers/reservations_controller.rb

class ReservationsController < ApplicationController
  # By default, we authorize all actions
  before_action :authorize_request

  # But skip authorization for "create", so guests can create a reservation
  skip_before_action :authorize_request, only: [:create]

  def index
    # Possibly scope to current_user.restaurant_id if you want
    reservations = Reservation.all
    render json: reservations
  end

  def show
    reservation = Reservation.find(params[:id])
    render json: reservation
  end

  def create
    # If you want *anonymous* reservations as well as multi-tenant logic, you can do:
    #  - if logged in, enforce your multi-tenant code
    #  - if not logged in, allow them to pass restaurant_id themselves (or default to 1)

    @reservation = Reservation.new(reservation_params)

    if current_user
      # If the user *is* logged in, enforce multi-tenancy unless they’re super_admin
      unless current_user.role == 'super_admin'
        @reservation.restaurant_id = current_user.restaurant_id
      end
    else
      # If the user is *not* logged in, we do no special enforcement
      # (You might want to default to a "main" restaurant if none is passed.)
      @reservation.restaurant_id ||= 1
    end

    if @reservation.save
      render json: @reservation, status: :created
    else
      render json: { errors: @reservation.errors.full_messages }, status: :unprocessable_entity
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
    # restaurant_id, start_time, party_size, etc.
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
