# app/models/layout.rb
class Layout < ApplicationRecord
  belongs_to :restaurant
  
  # Let each layout own many seat_sections
  has_many :seat_sections, dependent: :destroy
  
  # If you store seat-sections in a JSON, that's separate from the real DB link.
  # But your code can still rely on seat_sections being physically in the DB.
  
  # validates :sections_data, presence: true
end