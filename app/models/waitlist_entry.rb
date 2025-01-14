# app/models/waitlist_entry.rb
class WaitlistEntry < ApplicationRecord
  belongs_to :restaurant
end