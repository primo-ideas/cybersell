# Signing in with Battle.net, and out. Signing in moves what the browser followed into
# the account, and lists the player's characters to offer their realms.
class SessionsController < ApplicationController
  # Each try costs calls to Battle.net.
  rate_limit to: 20, within: 1.minute, only: %i[create callback stub], with: -> { redirect_to sign_in_path, alert: "Too many tries: wait a minute." }

  def new
    return redirect_to(account_path) if signed_in?

    @return_to = safe_return_path(params[:return_to])
    @battlenet = BattleNet.client.configured?
    @stub = stub_sign_in?
  end

  # Off to Battle.net, which sends the player back to `callback`.
  def create
    return redirect_to(sign_in_path, alert: "Signing in with Battle.net is not set up on this site.") unless BattleNet.client.configured?

    state = SecureRandom.urlsafe_base64(32)
    session[:oauth_state] = state
    session[:return_to] = safe_return_path(params[:return_to])
    redirect_to BattleNet.client.authorize_url(redirect_uri: callback_url, state: state), allow_other_host: true
  end

  def callback
    expected = session.delete(:oauth_state)
    return_to = session.delete(:return_to)

    if params[:error].present?
      return redirect_to(sign_in_path, alert: "Battle.net did not sign you in: #{params[:error_description].presence || params[:error]}".first(200))
    end
    # A callback this browser did not start: someone else's sign-in, or an old tab.
    unless expected.is_a?(String) && params[:state].is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(expected, params[:state])
      return redirect_to(sign_in_path, alert: "That sign-in had expired: try again.")
    end

    client = BattleNet.client
    token = client.access_token(code: params[:code].to_s, redirect_uri: callback_url)
    identity = client.identity(token)
    user = User.from_battlenet(battlenet_id: identity.id, battletag: identity.battletag, characters: characters_of(client, token))
    sign_in(user, return_to)
  rescue BattleNet::Error => error
    Rails.logger.warn("Battle.net sign-in failed: #{error.message}")
    redirect_to sign_in_path, alert: "Battle.net could not be reached to sign you in: try again in a moment."
  end

  # Without Battle.net, on a computer trying the site out: see `stub_sign_in?`.
  def stub
    return head(:not_found) unless stub_sign_in?

    characters = Realm.followed(tracked_markets).first(3).each_with_index.map do |realm, index|
      { region: realm.region, realm_slug: realm.slug, realm_name: realm.name, name: %w[Thrallia Mageston Huntara][index],
        level: 80, character_class: %w[Warrior Mage Hunter][index], faction: index.even? ? "Horde" : "Alliance" }
    end
    sign_in(User.from_battlenet(battlenet_id: 1, battletag: "TestPlayer#1234", characters: characters), safe_return_path(params[:return_to]))
  end

  def destroy
    end_session
    redirect_to root_path, notice: "Signed out. What you saved stays in your account."
  end

  private

  def callback_url = auth_battlenet_callback_url

  # A Battle.net account belongs to one region: its characters are found by asking each
  # region the site follows. Nil if none could be asked, to keep those already known.
  def characters_of(client, token)
    # Retail characters only: Classic ones are in other namespaces, not asked for yet.
    regions = Realm.distinct.pluck(:region).reject { |region| Realm.edition_of(region) == "classic" }
    found = false
    characters = regions.flat_map do |region|
      client.characters(token, region).tap { found = true }
    rescue BattleNet::Error => error
      Rails.logger.warn("Battle.net characters in #{region}: #{error.message}")
      []
    end
    found ? characters : nil
  end

  def sign_in(user, return_to)
    cookie_list = cookie_watchlist
    realm = remembered_realm
    start_session_for(user)

    imported = AccountWatchlist.new(user).import(cookie_list)
    cookies.delete(:watched, path: cookie_options[:path])
    cookies.delete(:watchlist, path: cookie_options[:path])
    user.remember_realm(realm) if realm && user.realm_slug.blank?

    notice = "Signed in as #{user.battletag}."
    notice += " The #{"product".pluralize(imported)} you followed in this browser #{imported == 1 ? "is" : "are"} now in your account." if imported.positive?
    redirect_to return_to || (user.realm ? realm_path(user.realm.region, user.realm.slug) : wow_path), notice: notice
  end

  # Only in development, and only when asked for: run.ps1 -Stub does, as its data is fake.
  def stub_sign_in?
    Rails.env.local? && ENV["PLAYDEALS_STUB_SIGN_IN"] == "1"
  end
end
