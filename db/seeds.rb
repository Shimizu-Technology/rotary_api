# db/seeds.rb
# This file is idempotent (safe to run multiple times).
# You can run: bin/rails db:seed

require 'faker'

puts "== Seeding the database with Faker =="

# 1) Create the Restaurant (Rotary Sushi)
restaurant = Restaurant.find_or_create_by!(
  name: "Rotary Sushi",
  address: "744 N Marine Corps Dr, Harmon Industrial Park, 96913, Guam",
  opening_hours: "5pm till 10pm everyday",
  layout_type: "sushi bar"
)

puts "Created or found Restaurant: #{restaurant.name}"

# 2) Create two admin users
# Faker can generate random names, but let's pick or combine them manually for clarity
admin1 = User.create!(
  first_name: "Alice",
  last_name: "Admin",
  email: "admin.alice@example.com",
  phone: Faker::PhoneNumber.cell_phone_in_e164,
  password: "admin123",
  password_confirmation: "admin123",
  role: "admin",
  restaurant_id: restaurant.id
)

admin2 = User.create!(
  first_name: "Bob",
  last_name: "Admin",
  email: "admin.bob@example.com",
  phone: Faker::PhoneNumber.cell_phone_in_e164,
  password: "admin123",
  password_confirmation: "admin123",
  role: "admin",
  restaurant_id: restaurant.id
)

puts "Created Admin Users: #{admin1.email}, #{admin2.email}"

# 3) Create 10 regular users (customers)
10.times do |i|
  first_name = Faker::Name.first_name
  last_name  = Faker::Name.last_name

  user = User.create!(
    first_name: first_name,
    last_name: last_name,
    email: Faker::Internet.unique.email,
    phone: Faker::PhoneNumber.cell_phone_in_e164,
    password: "password",
    password_confirmation: "password",
    role: "customer",
    restaurant_id: restaurant.id
  )
  puts "Created Customer User: #{user.email} (#{user.first_name} #{user.last_name})"
end

# 4) (Optional) Create seat sections & seats, so you can test seating
# For example, a sushi bar seat section with 8 seats:
bar_section = SeatSection.find_or_create_by!(
  name: "Sushi Bar Counter",
  section_type: "counter",
  orientation: "horizontal",
  offset_x: 0,
  offset_y: 0,
  capacity: 8,
  restaurant: restaurant
)

# Create seats if they don't exist (or you can simply re-generate them each time)
if bar_section.seats.empty?
  8.times do |i|
    Seat.create!(
      label: "Seat #{i + 1}",
      position_x: 50 * i,  # simplistic positions
      position_y: 0,
      status: "free",
      seat_section: bar_section
    )
  end
  puts "Created 8 seats for the sushi bar."
end

# 5) (Optional) Create a main Menu & some MenuItems (idempotent)
main_menu = Menu.find_or_create_by!(
  name: "Main Menu",
  restaurant: restaurant
)
main_menu.update!(active: true)

# Example menu items if they don't exist
if main_menu.menu_items.empty?
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

  puts "Created a couple of menu items on the main menu."
end

puts "== Seeding complete! =="
