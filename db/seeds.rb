# db/seeds.rb
# This file is idempotent (safe to run multiple times).
# You can run: bin/rails db:seed

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

# 3) Create seat section
bar_section = SeatSection.find_or_create_by!(
  name: "Sushi Bar Counter",
  section_type: "counter",      # "counter" or "table"
  orientation: "horizontal",    # for display
  offset_x: 0,
  offset_y: 0,
  capacity: 8,                  # if seat_section has a capacity field
  restaurant: restaurant
)

# Create seats if they don't exist
if bar_section.seats.empty?
  8.times do |i|
    Seat.create!(
      label: "Seat #{i + 1}",
      position_x: 50 * i,
      position_y: 0,
      status: "free",
      capacity: 1,              # each seat can hold 1 person
      seat_section: bar_section
    )
  end
  puts "Created 8 seats for the sushi bar."
else
  puts "Bar section seats already exist."
end

# 4) Create a couple of sample reservations
Reservation.create!(
  restaurant_id: restaurant.id,
  start_time: Time.current + 1.day, # tomorrow
  party_size: 2,
  contact_name: "Leon Shimizu",
  contact_phone: "671-483-0219",
  contact_email: "leon@example.com",
  status: "booked"
)

Reservation.create!(
  restaurant_id: restaurant.id,
  start_time: Time.current + 2.days,
  party_size: 4,
  contact_name: "Kami Shimizu",
  contact_phone: "671-777-9724",
  contact_email: "kami@example.com",
  status: "booked"
)

puts "Created some sample reservations."

# 5) Create a couple of waitlist entries
WaitlistEntry.create!(
  restaurant_id: restaurant.id,
  contact_name: "Walk-in Joe",
  party_size: 3,
  check_in_time: Time.current,
  status: "waiting"
)

WaitlistEntry.create!(
  restaurant_id: restaurant.id,
  contact_name: "Party of Six",
  party_size: 6,
  check_in_time: Time.current - 30.minutes,
  status: "waiting"
)
puts "Created some sample waitlist entries."

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
  puts "Created sample menu items on the main menu."
end

puts "== Seeding complete! =="
