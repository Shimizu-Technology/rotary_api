# app/controllers/waitlist_entries_controller.rb
class WaitlistEntriesController < ApplicationController
  # For now, require JWT for all actions
  before_action :authorize_request

  def index
    # Only staff/admin/super_admin can list the entire waitlist
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    # Possibly scope to current_user.restaurant_id:
    # waitlist = WaitlistEntry.where(restaurant_id: current_user.restaurant_id)
    waitlist = WaitlistEntry.all
    render json: waitlist
  end

  def show
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    entry = WaitlistEntry.find(params[:id])
    # optionally check same restaurant
    render json: entry
  end

  def create
    # This requires being logged in; you can loosen it if you want guests to join waitlist
    # If you do want guests to join, skip_before_action :authorize_request, only: [:create]

    entry = WaitlistEntry.new(waitlist_entry_params)
    # Enforce multi-tenancy if desired:
    # entry.restaurant_id = current_user.restaurant_id if current_user.restaurant_id.present?

    if entry.save
      render json: entry, status: :created
    else
      render json: { errors: entry.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    entry = WaitlistEntry.find(params[:id])
    if entry.update(waitlist_entry_params)
      render json: entry
    else
      render json: { errors: entry.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    unless current_user && %w[admin staff super_admin].include?(current_user.role)
      return render json: { error: "Forbidden: staff/admin only" }, status: :forbidden
    end

    entry = WaitlistEntry.find(params[:id])
    entry.destroy
    head :no_content
  end

  private

  def waitlist_entry_params
    params.require(:waitlist_entry).permit(
      :restaurant_id,
      :contact_name,
      :party_size,
      :check_in_time,
      :status,
      :contact_phone
    )
  end
end
