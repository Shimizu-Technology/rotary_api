# app/models/layout.rb
class Layout < ApplicationRecord
  belongs_to :restaurant

  # We'll store seat-sections data in sections_data (a JSON or JSONB column).
  # Something like: { sections: [ { id: "1", name: "Left Counter", ... } ], active: true, etc. }
  # Make sure you've added appropriate validations if needed.

  # Example validation:
  validates :sections_data, presence: true
end
