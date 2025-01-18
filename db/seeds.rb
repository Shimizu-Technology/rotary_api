# db/seeds.rb
# Run: bin/rails db:seed
# This file is idempotent (safe to run multiple times).
# If you want a fully clean DB each time, do:
#   rails db:drop db:create db:migrate db:seed

require 'active_record'

puts "== (Optional) Cleaning references =="
# Uncomment if you want a truly clean DB each time:
# ActiveRecord::Base.connection.execute("TRUNCATE reservations, waitlist_entries, users, restaurants, menus, menu_items RESTART IDENTITY CASCADE")

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
# We'll create multiple example reservations with different party sizes and times
puts "Creating sample Reservations..."

Reservation.find_or_create_by!(
  restaurant_id: restaurant.id,
  contact_name: "Leon Shimizu",
  start_time: Time.current + 1.day,
) do |res|
  res.party_size       = 2
  res.contact_phone    = "671-483-0219"
  res.contact_email    = "leon@example.com"
  res.status           = "booked"   # could be "reserved" or "booked"
end

Reservation.find_or_create_by!(
  restaurant_id: restaurant.id,
  contact_name: "Kami Shimizu",
  start_time: Time.current + 2.days,
) do |res|
  res.party_size       = 4
  res.contact_phone    = "671-777-9724"
  res.contact_email    = "kami@example.com"
  res.status           = "booked"
end

Reservation.find_or_create_by!(
  restaurant_id: restaurant.id,
  contact_name: "Dinner Group",
  start_time: Time.current + 2.hours,
) do |res|
  res.party_size       = 5
  res.contact_phone    = "671-222-9999"
  res.contact_email    = "group@example.com"
  res.status           = "booked"
end

Reservation.find_or_create_by!(
  restaurant_id: restaurant.id,
  contact_name: "Late Nighter",
  start_time: Time.current + 12.hours,
) do |res|
  res.party_size       = 3
  res.contact_phone    = "671-123-4444"
  res.contact_email    = "night@example.com"
  res.status           = "booked"
end

Reservation.find_or_create_by!(
  restaurant_id: restaurant.id,
  contact_name: "Canceled Example",
  start_time: Time.current + 1.day,
) do |res|
  res.party_size       = 2
  res.contact_phone    = "671-555-0000"
  res.contact_email    = "cancel@example.com"
  res.status           = "canceled"
end

puts "Reservations seeded."

# 4) WaitlistEntries
# We'll create multiple waitlist entries with different party sizes
puts "Creating sample Waitlist Entries..."

WaitlistEntry.find_or_create_by!(
  restaurant_id: restaurant.id,
  contact_name: "Walk-in Joe",
  check_in_time: Time.current,
) do |w|
  w.party_size = 3
  w.status     = "waiting"
end

WaitlistEntry.find_or_create_by!(
  restaurant_id: restaurant.id,
  contact_name: "Party of Six",
  check_in_time: Time.current - 30.minutes,
) do |w|
  w.party_size = 6
  w.status     = "waiting"
end

WaitlistEntry.find_or_create_by!(
  restaurant_id: restaurant.id,
  contact_name: "No-Show Nancy",
  check_in_time: Time.current - 1.hour,
) do |w|
  w.party_size = 2
  w.status     = "no_show"
end

WaitlistEntry.find_or_create_by!(
  restaurant_id: restaurant.id,
  contact_name: "Reserved Rita",
  check_in_time: Time.current - 15.minutes,
) do |w|
  w.party_size = 4
  w.status     = "reserved"
end

puts "Waitlist entries seeded."

# 5) Main Menu & MenuItems
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
