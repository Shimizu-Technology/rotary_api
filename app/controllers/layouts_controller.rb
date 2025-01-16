# app/controllers/layouts_controller.rb
class LayoutsController < ApplicationController
  before_action :authorize_request
  before_action :set_layout, only: [:show, :update, :destroy]

  def index
    # Return all layouts for the current restaurant, or all if super_admin
    if current_user.role == 'super_admin'
      layouts = Layout.all
    else
      layouts = Layout.where(restaurant_id: current_user.restaurant_id)
    end
    render json: layouts
  end

  def show
    layout = Layout.find(params[:id])
    render json: @layout
  end

  def create
    # We expect JSON in `sections_data`
    @layout = Layout.new(layout_params)
    @layout.restaurant_id ||= current_user.restaurant_id unless current_user.role == 'super_admin'

    if @layout.save
      render json: @layout, status: :created
    else
      render json: { errors: @layout.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @layout.update(layout_params)
      render json: @layout
    else
      render json: { errors: @layout.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @layout.destroy
    head :no_content
  end

  private

  def set_layout
    @layout = Layout.find(params[:id])
  end

  def layout_params
    params.require(:layout).permit(:name, :restaurant_id, sections_data: {})
  end
end
