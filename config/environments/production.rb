# config/environments/production.rb

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = true

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local = false

  # Ensures that a master key has been made available in ENV["RAILS_MASTER_KEY"], config/master.key, or an environment
  # key such as config/credentials/production.key. This key is used to decrypt credentials (and other encrypted files).
  # config.require_master_key = true

  # Disable serving static files from `public/`, relying on NGINX/Apache to do so instead.
  # config.public_file_server.enabled = false

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = "X-Sendfile" # for Apache
  # config.action_dispatch.x_sendfile_header = "X-Accel-Redirect" # for NGINX

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # Force all access to the app over SSL
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT by default
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  # Prepend all log lines with the following tags.
  config.log_tags = [:request_id]

  # "info" includes generic and useful information about system operation, 
  # but avoids logging too much info.
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Use a real queuing backend for Active Job
  # config.active_job.queue_adapter = :resque
  # config.active_job.queue_name_prefix = "rotary_reservations_api_production"

  # Disable caching for Action Mailer templates even if Action Controller
  # caching is enabled.

  # Raise errors if emails fail in production (optional).
  config.action_mailer.raise_delivery_errors = true

  # Use SMTP for SendGrid.
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    user_name: 'apikey',                # This is required by SendGrid
    password:  ENV['SENDGRID_API_KEY'], # Make sure you set this in Render/Heroku/wherever
    domain:    'rotary-sushi.netlify.app', 
      # or your own custom domain if you have one
    address:   'smtp.sendgrid.net',
    port:      587,
    authentication: :plain,
    enable_starttls_auto: true
  }

  # Where mailer-generated links (like password resets) should point.
  # Typically, you'd use your production frontend host if that's where
  # users land to confirm or reset password, etc.
  config.action_mailer.default_url_options = {
    host:     'rotary-sushi.netlify.app',
    protocol: 'https'  # ensures links are https://...
  }

  # Disable caching for Action Mailer templates even if you have caching on.
  config.action_mailer.perform_caching = false

  # If you want to see errors for bad email addresses:
  # config.action_mailer.raise_delivery_errors = true

  # i18n fallback
  config.i18n.fallbacks = true

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [:id]

  # Additional DNS rebind etc…
  # config.hosts = [...]
end
