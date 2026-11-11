# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

# A domain the World of Warcraft pages once had to themselves leads to this site.
if ENV["SITE_HOST"].present?
  use OldDomainRedirect, hosts: ENV["WOW_HOSTS"],
    site: "https://#{ENV["SITE_HOST"]}#{Rails.application.config.relative_url_root}"
end

# Under a path of its own when it shares a domain with other sites: see deploy/README.md.
map Rails.application.config.relative_url_root.presence || "/" do
  run Rails.application
end
Rails.application.load_server
