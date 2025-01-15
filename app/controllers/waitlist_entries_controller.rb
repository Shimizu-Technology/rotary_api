# app/controllers/waitlist_entries_controller.rb
class WaitlistEntriesController < ApplicationController
  before_action :authorize_request

  def index
    # If you want to scope to the current_user's restaurant:
    # waitlist = WaitlistEntry.where(restaurant_id: current_user.restaurant_id)
    # For now, let's return all
    waitlist = WaitlistEntry.all
    render json: waitlist
  end

  def show
    entry = WaitlistEntry.find(params[:id])
    render json: entry
  end

  def create
    entry = WaitlistEntry.new(waitlist_entry_params)
    # Optionally enforce current_user.restaurant_id:
    # entry.restaurant_id = current_user.restaurant_id if current_user.restaurant_id.present?

    if entry.save
      render json: entry, status: :created
    else
      render json: { errors: entry.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    entry = WaitlistEntry.find(params[:id])
    if entry.update(waitlist_entry_params)
      render json: entry
    else
      render json: { errors: entry.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    entry = WaitlistEntry.find(params[:id])
    entry.destroy
    head :no_content
  end

  private

  def waitlist_entry_params
    # Adjust as needed, depending on your WaitlistEntry model columns
    params.require(:waitlist_entry).permit(
      :restaurant_id,
      :contact_name,
      :party_size,
      :check_in_time,
      :status
    )
  end
end
