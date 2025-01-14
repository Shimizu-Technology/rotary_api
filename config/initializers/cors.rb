# config/initializers/cors.rb
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins 'http://localhost:3000'
    # Add your React dev or production URLs here

    resource '*',
      headers: :any,
      expose: %w[Authorization],
      methods: %i[get post put patch delete options head]
  end
end
