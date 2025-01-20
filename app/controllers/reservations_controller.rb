# app/controllers/reservations_controller.rb

class ReservationsController < ApplicationController
  # For the entire controller, we require a valid JWT (authorize_request),
  # except we skip it for :create so that an anonymous user can create a reservation.
  before_action :authorize_request, except: [:create]

  def index
    # If you want staff/admin to see all reservations for the restaurant:
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    # Base scope: reservations for the current user's restaurant
    scope = Reservation.where(restaurant_id: current_user.restaurant_id)

    # If ?date=YYYY-MM-DD was provided, filter by that date portion
    if params[:date].present?
      begin
        date_filter = Date.parse(params[:date]) # may raise ArgumentError
        scope = scope.where("DATE(start_time) = ?", date_filter)
      rescue ArgumentError
        # If the date param is invalid, you can ignore or return empty, etc.
        Rails.logger.warn "[ReservationsController#index] invalid date param=#{params[:date]}"
        # scope = scope.none  # or do nothing
      end
    end

    # Now fetch the final list
    reservations = scope.all
    render json: reservations
  end

  def show
    # If you want to limit to staff/admin only:
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    reservation = Reservation.find(params[:id])
    render json: reservation
  end

  # CREATE = public
  def create
    @reservation = Reservation.new(reservation_params)
    if current_user
      unless current_user.role == 'super_admin'
        @reservation.restaurant_id = current_user.restaurant_id
      end
    else
      @reservation.restaurant_id ||= 1
    end

    if @reservation.save
      # Example: send confirmation emails/texts
      if @reservation.contact_email.present?
        ReservationMailer.booking_confirmation(@reservation).deliver_later
      end
      if @reservation.contact_phone.present?
        message_body = <<~MSG.squish
          Hi #{@reservation.contact_name}, your Rotary Sushi reservation is confirmed
          on #{@reservation.start_time.strftime("%B %d at %I:%M %p")}.
          We look forward to seeing you!
        MSG
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
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    reservation = Reservation.find(params[:id])
    if reservation.update(reservation_params)
      render json: reservation
    else
      render json: { errors: reservation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

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
