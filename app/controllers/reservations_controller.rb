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

    # Staff or admin => see reservations for their restaurant:
    reservations = Reservation.where(restaurant_id: current_user.restaurant_id)
    render json: reservations
  end

  def show
    # If you want to limit to staff/admin only:
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    reservation = Reservation.find(params[:id])
    # Optionally ensure it belongs to the same restaurant_id:
    # if reservation.restaurant_id != current_user.restaurant_id
    #   return render json: { error: "Not found" }, status: :not_found
    # end

    render json: reservation
  end

  # CREATE = public
  # (skip_before_action above, so no JWT required)
  def create
    @reservation = Reservation.new(reservation_params)

    # If the user is logged in, use their restaurant_id (unless super_admin)
    if current_user
      unless current_user.role == 'super_admin'
        @reservation.restaurant_id = current_user.restaurant_id
      end
    else
      # If not logged in, fallback to restaurant_id=1 or param if provided
      @reservation.restaurant_id ||= 1
    end

    if @reservation.save
      # 1) Send email confirmation if contact_email present
      if @reservation.contact_email.present?
        ReservationMailer.booking_confirmation(@reservation).deliver_later
      end

      # 2) Send text confirmation if contact_phone present
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
    # optionally check reservation.restaurant_id == current_user.restaurant_id
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
    # optionally check belongs to same restaurant
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
