require "net/http"

# Signing in with Battle.net: OAuth's authorization code flow, then who the player is
# and, with the wow.profile scope, their characters. The site uses the same client as
# the fetcher, whose redirect URLs must include the site's callback.
class BattleNet
  AUTHORIZE_URL = "https://oauth.battle.net/authorize".freeze
  TOKEN_URL = "https://oauth.battle.net/token".freeze
  USERINFO_URL = "https://oauth.battle.net/userinfo".freeze
  SCOPE = "openid wow.profile".freeze
  TIMEOUT = 5

  Error = Class.new(StandardError)
  Identity = Data.define(:id, :battletag)

  class << self
    # Tests swap in a stand-in.
    attr_writer :client

    def client = @client ||= new(ENV["BLIZZARD_CLIENT_ID"], ENV["BLIZZARD_CLIENT_SECRET"])
  end

  def initialize(client_id, client_secret)
    @client_id = client_id.to_s
    @client_secret = client_secret.to_s
  end

  def configured? = @client_id.present? && @client_secret.present?

  # Where to send the player to sign in. Battle.net sends them back to `redirect_uri`
  # with a code, and with `state` unchanged.
  def authorize_url(redirect_uri:, state:)
    query = { response_type: "code", client_id: @client_id, redirect_uri: redirect_uri, scope: SCOPE, state: state }
    "#{AUTHORIZE_URL}?#{URI.encode_www_form(query)}"
  end

  def access_token(code:, redirect_uri:)
    uri = URI(TOKEN_URL)
    request = Net::HTTP::Post.new(uri)
    request.basic_auth(@client_id, @client_secret)
    request.set_form_data(grant_type: "authorization_code", code: code, redirect_uri: redirect_uri)
    json(uri, request).fetch("access_token") { raise Error, "no access token in the answer" }
  end

  def identity(token)
    uri = URI(USERINFO_URL)
    body = json(uri, authorized(Net::HTTP::Get.new(uri), token))
    id = body["id"] || body["sub"]
    raise Error, "no account id in the answer" if id.blank?

    Identity.new(id: Integer(id), battletag: body["battletag"].to_s)
  end

  # The player's characters in a region, as rows for `characters`. Empty when they have
  # none there: a Battle.net account belongs to one region, and other regions say 404.
  def characters(token, region)
    uri = URI("https://#{region}.api.blizzard.com/profile/user/wow")
    uri.query = URI.encode_www_form(namespace: "profile-#{region}", locale: "en_US")
    body = json(uri, authorized(Net::HTTP::Get.new(uri), token), missing: {})
    Array(body["wow_accounts"]).flat_map { |account| Array(account["characters"]) }.filter_map do |character|
      slug = character.dig("realm", "slug")
      next if slug.blank? || character["name"].blank?

      {
        region: region,
        realm_slug: slug.to_s.first(100),
        realm_name: character.dig("realm", "name").to_s.first(100).presence || slug.to_s,
        name: character["name"].to_s.first(50),
        level: character["level"].is_a?(Integer) ? character["level"] : nil,
        character_class: character.dig("playable_class", "name").to_s.first(50).presence,
        faction: character.dig("faction", "name").to_s.first(20).presence
      }
    end
  end

  private

  def authorized(request, token)
    request["Authorization"] = "Bearer #{token}"
    request
  end

  def json(uri, request, missing: nil)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.request(request)
    end
    return missing if response.is_a?(Net::HTTPNotFound) && missing

    raise Error, "#{uri.host}#{uri.path} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => error
    raise Error, "#{uri.host}#{uri.path}: #{error.message}"
  end
end
