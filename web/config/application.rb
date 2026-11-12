require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
# require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Web
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    config.time_zone = "Paris"
    config.i18n.default_locale = :en
    config.i18n.available_locales = [ :en ]

    # Other sites may share the domain: cookies stay within this one's path.
    config.session_store :cookie_store, key: "_playdeals_session", path: ENV["RAILS_RELATIVE_URL_ROOT"].presence || "/",
      secure: ENV["SITE_HOST"].present?

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Tests build the accounts database from its migrations, as they do the market one
    # from the fetcher's: there is no schema file to keep in step.
    config.active_record.dump_schema_after_migration = false

    # Emails say when a product reaches its target. Without an SMTP server, production
    # sends none, and the account page does not offer them.
    if ENV["SMTP_ADDRESS"].present?
      config.action_mailer.delivery_method = :smtp
      config.action_mailer.smtp_settings = {
        address: ENV["SMTP_ADDRESS"],
        port: ENV.fetch("SMTP_PORT", 587).to_i,
        user_name: ENV["SMTP_USERNAME"].presence,
        password: ENV["SMTP_PASSWORD"].presence,
        enable_starttls_auto: true
      }.compact
    end
    config.action_mailer.default_options = {
      from: ENV["MAIL_FROM"].presence || "Play Deals <alerts@#{ENV["SITE_HOST"].presence || "localhost"}>"
    }
    config.action_mailer.default_url_options = {
      host: ENV["SITE_HOST"].presence || "127.0.0.1",
      port: (ENV.fetch("PORT", 3000).to_i unless ENV["SITE_HOST"].present?),
      protocol: ENV["SITE_HOST"].present? ? "https" : "http",
      script_name: ENV["RAILS_RELATIVE_URL_ROOT"].presence
    }.compact
  end
end
