# app/controllers/reservations_controller.rb

class ReservationsController < ApplicationController
  before_action :authorize_request
  # Allow anonymous users to create reservations without JWT
  skip_before_action :authorize_request, only: [:create]

  def index
    # Potentially scope to current_user.restaurant_id
    reservations = Reservation.all
    render json: reservations
  end

  def show
    reservation = Reservation.find(params[:id])
    render json: reservation
  end

  def create
    # Build a new reservation from the incoming params
    @reservation = Reservation.new(reservation_params)

    # If the user is logged in, enforce multi-tenancy
    if current_user
      unless current_user.role == 'super_admin'
        @reservation.restaurant_id = current_user.restaurant_id
      end
    else
      # If no user is logged in, default to restaurant ID = 1 if none was passed
      @reservation.restaurant_id ||= 1
    end

    if @reservation.save
      # 1) Send email confirmation if contact_email is present
      if @reservation.contact_email.present?
        ReservationMailer.booking_confirmation(@reservation).deliver_later
      end

      # 2) Send text confirmation if contact_phone is present
      if @reservation.contact_phone.present?
        message_body = <<~MSG.squish
          Hi #{@reservation.contact_name}, your Rotary Sushi reservation is confirmed
          on #{@reservation.start_time.strftime("%B %d at %I:%M %p")}.
          We look forward to seeing you!
        MSG

        # Attempt to send via Clicksend
        ClicksendClient.send_text_message(
          to:   @reservation.contact_phone,
          body: message_body,
          from: 'RotarySushi'
        )
      end

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

  # Strong parameters for reservations
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
