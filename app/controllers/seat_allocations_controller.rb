# app/controllers/seat_allocations_controller.rb
class SeatAllocationsController < ApplicationController
  before_action :authorize_request

  # POST /seat_allocations
  def create
    # seat_allocation: { seat_id: ..., reservation_id: OR waitlist_entry_id, allocated_at: ... }
    sa_params = params.require(:seat_allocation)
                      .permit(:seat_id, :reservation_id, :waitlist_entry_id, :allocated_at)

    seat = Seat.find_by(id: sa_params[:seat_id])
    return render json: { error: "Seat not found" }, status: :not_found unless seat

    # If seat is already occupied => 422
    if seat.status == "occupied"
      return render json: { error: "Seat is already occupied" }, status: :unprocessable_entity
    end

    # Figure out occupant: either a Reservation or a WaitlistEntry
    occupant = nil
    occupant_type = nil

    if sa_params[:reservation_id].present?
      occupant_type = :reservation
      occupant = Reservation.find_by(id: sa_params[:reservation_id])
      return render json: { error: "Reservation not found" }, status: :not_found unless occupant
    elsif sa_params[:waitlist_entry_id].present?
      occupant_type = :waitlist
      occupant = WaitlistEntry.find_by(id: sa_params[:waitlist_entry_id])
      return render json: { error: "Waitlist entry not found" }, status: :not_found unless occupant
    else
      return render json: { error: "Must provide reservation_id or waitlist_entry_id" },
                    status: :unprocessable_entity
    end

    # Optional capacity check if occupant has a party_size
    # if seat.capacity.present? && occupant.party_size.present? && occupant.party_size > seat.capacity
    #   return render json: { error: "Party size too large for this seat" }, status: :unprocessable_entity
    # end

    # Mark seat occupied
    seat.update!(status: "occupied")

    # Mark occupant as "seated" (if you want). For waitlist, you might do occupant.update!(status: "seated")
    occupant.update!(status: "seated")

    # Create seat_allocation
    seat_allocation = SeatAllocation.new(
      seat_id: seat.id,
      allocated_at: sa_params[:allocated_at].presence || Time.current
    )
    seat_allocation.reservation_id = occupant.id if occupant_type == :reservation
    seat_allocation.waitlist_entry_id = occupant.id if occupant_type == :waitlist

    if seat_allocation.save
      render json: seat_allocation, status: :created
    else
      render json: { errors: seat_allocation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /seat_allocations/:id
  def destroy
    seat_allocation = SeatAllocation.find(params[:id])
    seat = seat_allocation.seat

    # occupant can be seat_allocation.reservation or seat_allocation.waitlist_entry
    occupant = seat_allocation.reservation || seat_allocation.waitlist_entry

    # Mark seat free
    seat.update!(status: "free")

    # Optionally update occupant status
    if occupant.is_a?(Reservation)
      occupant.update!(status: "finished") 
      # or "completed" or "done"—depending on your flow
    elsif occupant.is_a?(WaitlistEntry)
      occupant.update!(status: "removed")
      # or "seated_and_removed" or whatever logic you prefer
    end

    seat_allocation.destroy
    head :no_content
  end
end
