# db/seeds.rb
# Run: bin/rails db:seed
# This file is idempotent (safe to run multiple times).
# If you want a fully clean DB each time, do:
#   rails db:drop db:create db:migrate db:seed

require 'active_record'

puts "== (Optional) Cleaning references =="
# Uncomment to truncate tables and reset IDs if needed:
# ActiveRecord::Base.connection.execute("TRUNCATE reservations, waitlist_entries, users, restaurants, menus, menu_items, layouts, seat_sections, seats, seat_allocations RESTART IDENTITY CASCADE")

puts "== Seeding the database =="

# 1) Restaurant
restaurant = Restaurant.find_or_create_by!(
  name: "Rotary Sushi",
  address: "744 N Marine Corps Dr, Harmon Industrial Park, 96913, Guam",
  opening_hours: "5pm till 10pm everyday",
  layout_type: "sushi bar"
)
puts "Created/found Restaurant: #{restaurant.name}"

# 2) Users
admin_user = User.find_or_create_by!(email: "admin@example.com") do |u|
  u.first_name = "Admin"
  u.last_name  = "User"
  u.phone      = "671-123-9999"
  u.password   = "password"
  u.password_confirmation = "password"
  u.role       = "admin"
  u.restaurant_id = restaurant.id
end
puts "Created Admin User: #{admin_user.email} / password"

regular_user = User.find_or_create_by!(email: "user@example.com") do |u|
  u.first_name = "Regular"
  u.last_name  = "User"
  u.phone      = "671-555-1111"
  u.password   = "password"
  u.password_confirmation = "password"
  u.role       = "customer"
  u.restaurant_id = restaurant.id
end
puts "Created Regular User: #{regular_user.email} / password"

# 3) Reservations
puts "Creating sample Reservations across multiple days and times..."

reservation_data = [
  { name: "Leon Shimizu",         time: Time.current + 1.day,          party_size: 2, status: "booked" },
  { name: "Kami Shimizu",         time: Time.current + 2.days,         party_size: 4, status: "booked" },
  { name: "Dinner Group",         time: Time.current + 2.hours,        party_size: 5, status: "booked" },
  { name: "Late Nighter",         time: Time.current + 12.hours,       party_size: 3, status: "booked" },
  { name: "Weekend Brunch",       time: Time.current + 5.days + 10.hours, party_size: 6, status: "booked" },
  { name: "Family Gathering",     time: Time.current + 3.days + 8.hours,  party_size: 8, status: "booked" },
  { name: "Early Bird Special",   time: Time.current + 7.hours,        party_size: 2, status: "booked" },
  { name: "Canceled Example",     time: Time.current + 1.day,          party_size: 2, status: "canceled" },
  { name: "No-Show Example",      time: Time.current - 1.day,          party_size: 3, status: "no_show" },
  { name: "Finished Party",       time: Time.current - 2.days,         party_size: 4, status: "finished" }
]

reservation_data.each do |res_data|
  Reservation.find_or_create_by!(
    restaurant_id: restaurant.id,
    contact_name:  res_data[:name],
    start_time:    res_data[:time]
  ) do |res|
    res.party_size    = res_data[:party_size]
    res.contact_phone = "671-#{rand(100..999)}-#{rand(1000..9999)}"
    res.contact_email = "#{res_data[:name].parameterize}@example.com"
    res.status        = res_data[:status]
  end
end
puts "Reservations seeded."

# 4) WaitlistEntries
puts "Creating sample Waitlist Entries for the current day..."

waitlist_data = [
  { name: "Walk-in Joe",         time: Time.current,               party_size: 3, status: "waiting" },
  { name: "Party of Six",        time: Time.current - 30.minutes,  party_size: 6, status: "waiting" },
  { name: "Seated Sarah",        time: Time.current - 1.hour,      party_size: 2, status: "seated" },
  { name: "Afternoon Visitor",   time: Time.current - 3.hours,     party_size: 4, status: "seated" }
]

waitlist_data.each do |wl_data|
  WaitlistEntry.find_or_create_by!(
    restaurant_id: restaurant.id,
    contact_name:  wl_data[:name],
    check_in_time: wl_data[:time]
  ) do |w|
    w.party_size = wl_data[:party_size]
    w.status     = wl_data[:status]
  end
end
puts "Waitlist entries seeded."

# 5) Layout, Seat Sections, Seats
puts "Creating Layouts & Seats..."

main_layout = Layout.find_or_create_by!(name: "Main Sushi Layout", restaurant_id: restaurant.id)

# A single seat section for demonstration
bar_section = SeatSection.find_or_create_by!(
  layout_id: main_layout.id,
  name: "Sushi Bar Front",
  offset_x: 100,
  offset_y: 100
)

# Create 6 sample seats
(1..6).each do |i|
  Seat.find_or_create_by!(
    seat_section_id: bar_section.id,
    label: "Seat ##{i}",
    position_x: 0,
    position_y: 60 * (i - 1)
  ) do |s|
    s.capacity = 1
    # no need to set s.status; that column is removed or ignored
  end
end
puts "Created seats for Sushi Bar Front."

# 6) Main Menu & MenuItems
main_menu = Menu.find_or_create_by!(
  name: "Main Menu",
  restaurant: restaurant
)
main_menu.update!(active: true)

if main_menu.menu_items.empty?
  MenuItem.create!(
    name: "Salmon Nigiri",
    description: "Fresh salmon on sushi rice",
    price: 3.50,
    menu: main_menu
  )

  MenuItem.create!(
    name: "Tuna Roll",
    description: "Classic tuna roll (6 pieces).",
    price: 5.00,
    menu: main_menu
  )

  MenuItem.create!(
    name: "Dragon Roll",
    description: "Eel, cucumber, avocado on top",
    price: 12.00,
    menu: main_menu
  )

  MenuItem.create!(
    name: "Tempura Udon",
    description: "Udon noodle soup with shrimp tempura",
    price: 10.50,
    menu: main_menu
  )

  puts "Created sample menu items on the main menu."
else
  puts "Main Menu items already exist."
end

puts "== Seeding complete! =="
