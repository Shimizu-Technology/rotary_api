# db/seeds.rb
# This file is idempotent (safe to run multiple times).
# You can run: bin/rails db:seed

puts "== Seeding the database =="

# 1) Create the Restaurant
restaurant = Restaurant.create!(
  name: "Rotary Sushi",
  address: "744 N Marine Corps Dr, Harmon Industrial Park, 96913, Guam",
  opening_hours: "5pm till 10pm everyday",
  layout_type: "sushi bar"
)

puts "Created Restaurant: #{restaurant.name}"

# 2) Create two admin users
admin1 = User.create!(
  name: "Admin Alice",
  email: "admin.alice@example.com",
  password: "admin123",
  password_confirmation: "admin123",
  role: "admin",
  restaurant_id: restaurant.id
)

admin2 = User.create!(
  name: "Admin Bob",
  email: "admin.bob@example.com",
  password: "admin123",
  password_confirmation: "admin123",
  role: "admin",
  restaurant_id: restaurant.id
)

puts "Created Admin Users: #{admin1.email}, #{admin2.email}"

# 3) Create ten regular users
10.times do |i|
  user = User.create!(
    name: "Staff #{i + 1}",
    email: "staff#{i+1}@example.com",
    password: "staff123",
    password_confirmation: "staff123",
    role: "user",
    restaurant_id: restaurant.id
  )
  puts "Created User: #{user.email}"
end

# 4) (Optional) Create seat sections & seats, so you can test seating
# For example, a sushi bar seat section with 8 seats:
bar_section = SeatSection.create!(
  name: "Sushi Bar Counter",
  section_type: "counter",
  orientation: "horizontal",
  offset_x: 0,
  offset_y: 0,
  capacity: 8,
  restaurant: restaurant
)

8.times do |i|
  Seat.create!(
    label: "Seat #{i + 1}",
    position_x: 50 * i,  # simplistic positions
    position_y: 0,
    status: "free",
    seat_section: bar_section
  )
end

puts "Created 1 seat section with 8 seats for the sushi bar."

# 5) (Optional) Create a Menu & MenuItems
main_menu = Menu.create!(
  name: "Main Menu",
  active: true,
  restaurant: restaurant
)

MenuItem.create!(
  name: "Salmon Nigiri",
  description: "Fresh salmon on sushi rice.",
  price: 3.50,
  menu: main_menu
)

MenuItem.create!(
  name: "Tuna Roll",
  description: "Classic tuna roll (6 pieces).",
  price: 5.00,
  menu: main_menu
)

puts "Created a menu and a couple of menu items."

puts "== Seeding complete! =="
