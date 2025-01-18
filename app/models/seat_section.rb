class SeatSection < ApplicationRecord
  belongs_to :layout
  has_many :seats, dependent: :destroy

  validates :name, presence: true
  validates :capacity, numericality: { greater_than: 0 }, allow_nil: true

  # -- DEBUG LOGS --

  before_validation :debug_before_validation
  after_validation :debug_after_validation
  after_create :debug_after_create
  after_update :debug_after_update

  private

  def debug_before_validation
    Rails.logger.debug "SeatSection#before_validation => #{attributes.inspect}"
    puts "SeatSection#before_validation => #{attributes.inspect}"
  end

  def debug_after_validation
    if errors.any?
      Rails.logger.debug "SeatSection#after_validation => ERRORS: #{errors.full_messages}"
      puts "SeatSection#after_validation => ERRORS: #{errors.full_messages}"
    else
      Rails.logger.debug "SeatSection#after_validation => no validation errors. seat_section=#{attributes.inspect}"
      puts "SeatSection#after_validation => no validation errors. seat_section=#{attributes.inspect}"
    end
  end

  def debug_after_create
    Rails.logger.debug "SeatSection#after_create => record created: #{attributes.inspect}"
    puts "SeatSection#after_create => record created: #{attributes.inspect}"
  end

  def debug_after_update
    Rails.logger.debug "SeatSection#after_update => record updated: #{attributes.inspect}"
    puts "SeatSection#after_update => record updated: #{attributes.inspect}"
  end
end