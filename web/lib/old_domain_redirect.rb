# Sends every address of a domain the World of Warcraft pages used to have to itself to
# the same page of this site, which now covers several games under one domain.
#
# It sits in front of the whole site (see config.ru), as such a domain reaches it at the
# root, whatever path the site itself is served under.
class OldDomainRedirect
  # What does not belong to a game: these addresses keep their place at the root.
  SITE_WIDE = %w[account sign-in sign-out auth alerts up assets].freeze

  # `hosts`: the old domains, separated by commas. `site`: where the site is now, like
  # https://example.com/playdeals. Without either, nothing is redirected.
  def initialize(app, hosts:, site:)
    @app = app
    @hosts = hosts.to_s.downcase.split(",").map(&:strip).reject(&:empty?)
    @site = site.to_s.chomp("/")
  end

  def call(env)
    return @app.call(env) if @hosts.empty? || @site.empty? || !@hosts.include?(host_of(env))

    path = "#{env["SCRIPT_NAME"]}#{env["PATH_INFO"]}"
    path = "" if path == "/"
    section = SITE_WIDE.include?(path.split("/")[1]) ? "" : "/wow"
    query = env["QUERY_STRING"].to_s.empty? ? "" : "?#{env["QUERY_STRING"]}"
    [ 301, { "location" => "#{@site}#{section}#{path}#{query}", "content-type" => "text/plain" }, [ "Moved" ] ]
  end

  private

  # A proxy in front may keep the name the reader asked for only in this header.
  def host_of(env)
    host = env["HTTP_X_FORWARDED_HOST"].to_s.split(",").last.to_s.strip
    host = env["HTTP_HOST"].to_s if host.empty?
    host = env["SERVER_NAME"].to_s if host.empty?
    host.downcase.sub(/:\d+\z/, "")
  end
end
