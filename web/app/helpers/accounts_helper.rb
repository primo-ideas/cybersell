module AccountsHelper
  PERIOD_LABELS = { "24h" => "24 hours", "7d" => "7 days", "30d" => "30 days", "90d" => "90 days", "all" => "The whole history" }.freeze
  SORT_LABELS = {
    "value" => "Value sold over 24h",
    "sold" => "Units sold over 24h",
    "name" => "Name",
    "price" => "Median price",
    "min" => "Minimum price",
    "change" => "Change over 24h",
    "quantity" => "Units for sale"
  }.freeze
  # Where players of the regions the site covers are likely to be, first in the list.
  PRIORITY_ZONES = [
    "Paris", "London", "Berlin", "Madrid", "Eastern Time (US & Canada)", "Central Time (US & Canada)",
    "Mountain Time (US & Canada)", "Pacific Time (US & Canada)", "Seoul", "Taipei", "Sydney"
  ].filter_map { |name| ActiveSupport::TimeZone[name] }.freeze

  def player_name(user) = user.battletag.split("#").first

  # "Firefox on Windows": enough to tell one's browsers apart, without a library.
  def browser_label(user_agent)
    agent = user_agent.to_s
    browser = case agent
    when /Edg\//i then "Edge"
    when /OPR\//i then "Opera"
    when /Firefox\//i then "Firefox"
    when /Chrome\//i then "Chrome"
    when /Safari\//i then "Safari"
    end
    system = case agent
    when /Windows/i then "Windows"
    when /iPhone|iPad/i then "iOS"
    when /Android/i then "Android"
    when /Mac OS X/i then "macOS"
    when /Linux/i then "Linux"
    end
    return "Unknown browser" unless browser || system

    [ browser || "A browser", system ].compact.join(" on ")
  end

  # How the page names the time zone it shows times in.
  def time_zone_label(zone = Time.zone)
    zone.name.include?("Time") ? zone.name : "#{zone.name} time"
  end
end
