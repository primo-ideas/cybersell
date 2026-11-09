require "test_helper"

class AccountsTest < ActionDispatch::IntegrationTest
  include RealmsHelper
  include ActionMailer::TestHelper

  CHARACTER = { region: "eu", realm_slug: "hyjal", realm_name: "Hyjal", name: "Thrallia", level: 80,
                character_class: "Shaman", faction: "Horde" }.freeze

  setup do
    @battlenet = FakeBattleNet.new
    BattleNet.client = @battlenet
    @market = create_market(name: "Hyjal")
    @realm = create_realm(@market, name: "Hyjal")
    create_snapshot(@market, NOW)
    create_item(2589, name: "Linen Cloth")
    create_price(@market, 2589, NOW, median: 20_000, min: 10_000)
  end

  teardown { BattleNet.client = nil }

  def sign_in(return_to: nil)
    post auth_battlenet_path, params: { return_to: return_to }.compact
    state = Rack::Utils.parse_query(URI(response.location).query)["state"]
    get auth_battlenet_callback_path, params: { code: "abc", state: state }
  end

  def user = User.find_by!(battlenet_id: 4242)

  def item_page(id = 2589, **options) = item_on_realm_path(@realm, id, **options)

  # Signing in

  test "signing in sends the player to Battle.net, and creates their account on the way back" do
    @battlenet.characters_by_region = { "eu" => [ CHARACTER ] }

    post auth_battlenet_path

    assert_response :redirect
    assert response.location.start_with?("https://oauth.battle.net/authorize")
    assert_includes response.location, CGI.escape(auth_battlenet_callback_url)

    state = Rack::Utils.parse_query(URI(response.location).query)["state"]
    get auth_battlenet_callback_path, params: { code: "abc", state: state }

    assert_redirected_to root_path
    assert_equal "Thrall#1234", user.battletag
    assert_equal [ "Thrallia" ], user.characters.map(&:name)

    follow_redirect!
    assert_select ".flash-notice", /Signed in as Thrall#1234/
    assert_select ".header-account", "Thrall"
    assert_select ".header-sign-in", false
  end

  test "a way back this browser did not start signs nobody in" do
    post auth_battlenet_path

    get auth_battlenet_callback_path, params: { code: "abc", state: "forged" }

    assert_redirected_to sign_in_path
    assert_equal 0, User.count
    follow_redirect!
    assert_select ".flash", /expired/
  end

  test "a way back without having left signs nobody in" do
    get auth_battlenet_callback_path, params: { code: "abc", state: "" }

    assert_redirected_to sign_in_path
    assert_equal 0, User.count
  end

  test "a way back only works once" do
    post auth_battlenet_path
    state = Rack::Utils.parse_query(URI(response.location).query)["state"]
    get auth_battlenet_callback_path, params: { code: "abc", state: state }
    delete sign_out_path

    get auth_battlenet_callback_path, params: { code: "abc", state: state }

    assert_redirected_to sign_in_path
    assert_equal 0, user.sessions.count
  end

  test "refusing on Battle.net's page comes back with a word of explanation" do
    post auth_battlenet_path

    get auth_battlenet_callback_path, params: { error: "access_denied", error_description: "The user denied" }

    assert_redirected_to sign_in_path
    follow_redirect!
    assert_select ".flash", /The user denied/
    assert_equal 0, User.count
  end

  test "Battle.net being down is said plainly" do
    @battlenet.token_error = "boom"

    sign_in

    assert_redirected_to sign_in_path
    follow_redirect!
    assert_select ".flash", /could not be reached/
    assert_equal 0, User.count
  end

  test "signing in comes back to the page the player was on, and only of this site" do
    sign_in(return_to: "/watchlist?list=1")
    assert_redirected_to "/watchlist?list=1"

    delete sign_out_path

    [ "//evil.example", "https://evil.example/", "/\\evil.example", "evil" ].each do |target|
      sign_in(return_to: target)
      assert_redirected_to root_path, target
      delete sign_out_path
    end
  end

  test "characters stay as they were when no region could list them" do
    @battlenet.characters_by_region = { "eu" => [ CHARACTER ] }
    sign_in
    delete sign_out_path

    @battlenet.failing_regions = [ "eu" ]
    sign_in

    assert_equal [ "Thrallia" ], user.characters.map(&:name)
  end

  test "what the browser followed moves to the account, and the browser forgets it" do
    cookies[:watched] = "2589-5000"

    sign_in

    assert_equal 5_000, user.saved_products.find_by!(item_id: 2589).target_price
    assert cookies[:watched].blank?

    follow_redirect!
    assert_select ".flash-notice", /product you followed in this browser is now in your account/
    assert_select ".header-link small", "1"
  end

  test "the realm of the browser becomes the account's when it has none" do
    get realm_home_path(@realm)

    sign_in

    assert_equal @realm, user.realm
    assert_redirected_to realm_home_path(@realm)
  end

  test "signing out ends the session for good" do
    sign_in
    old_cookie = cookies[:session_id]

    delete sign_out_path

    assert_redirected_to root_path
    get account_path
    assert_redirected_to sign_in_path(return_to: account_path)

    cookies[:session_id] = old_cookie
    get account_path
    assert_redirected_to sign_in_path(return_to: account_path)
    assert_equal 0, user.sessions.count
  end

  test "a made-up session cookie is nobody" do
    cookies[:session_id] = "1"

    get account_path

    assert_redirected_to sign_in_path(return_to: account_path)
  end

  test "pages of an account send to sign in, and back" do
    get account_path
    assert_redirected_to sign_in_path(return_to: account_path)

    get trades_path
    assert_redirected_to sign_in_path(return_to: trades_path)
  end

  test "the sign-in page offers Battle.net, and says when it is not set up" do
    get sign_in_path
    assert_select "form[action=?] button", auth_battlenet_path, "Sign in with Battle.net"

    BattleNet.client = BattleNet.new("", "")
    get sign_in_path
    assert_select "form[action=?]", auth_battlenet_path, false
    assert_select ".note", /not set up/

    post auth_battlenet_path
    assert_redirected_to sign_in_path
  end

  test "the test player does not exist unless asked for" do
    post auth_stub_path

    assert_response :not_found
    assert_equal 0, User.count
  end

  test "the test player signs in without Battle.net when asked for" do
    ENV["WOW_TRADING_STUB_SIGN_IN"] = "1"
    BattleNet.client = BattleNet.new("", "")

    get sign_in_path
    assert_select "form[action=?] button", auth_stub_path, "Sign in as a test player"

    post auth_stub_path

    assert_response :redirect
    assert_equal "TestPlayer#1234", User.first.battletag
    assert_equal [ "hyjal" ], User.first.characters.map(&:realm_slug)
  ensure
    ENV.delete("WOW_TRADING_STUB_SIGN_IN")
  end

  # Lists

  test "a star saves to the account" do
    sign_in

    patch watchlist_path, params: { item_id: 2589, series: "" }

    assert_equal [ 2589 ], user.saved_products.pluck(:item_id)
    assert cookies[:watched].blank?

    get realm_home_path(@realm)
    get watchlist_path
    assert_select "a.product-link", "Linen Cloth"
  end

  test "a target saves to the account" do
    sign_in

    patch watchlist_target_path, params: { item_id: 2589, series: "", target: "2g" }

    assert_equal 20_000, user.saved_products.find_by!(item_id: 2589).target_price

    get item_page
    assert_select ".target-hit", /At your target/
  end

  test "lists are created, renamed, reordered and deleted with what they hold" do
    sign_in

    post lists_path, params: { name: "  Farming  " }
    farming = user.lists.find_by!(name: "Farming")
    assert_redirected_to watchlist_path(list: farming.id)

    patch list_path(farming), params: { name: "Herbs" }
    assert_equal "Herbs", farming.reload.name

    patch list_path(farming), params: { move: "up" }
    assert_equal "Herbs", user.lists.first.name

    user.saved_products.create!(list: farming, item_id: 2589)
    delete list_path(farming)

    assert_not List.exists?(farming.id)
    assert_equal 0, user.saved_products.count
    follow_redirect!
    assert_select ".flash-notice", /Herbs/
  end

  test "the last list stays, and two lists cannot share a name" do
    sign_in

    delete list_path(user.default_list)
    assert_equal 1, user.lists.count
    assert_redirected_to watchlist_path(list: user.default_list.id)

    post lists_path, params: { name: "WATCHLIST" }
    assert_equal 1, user.lists.count
    follow_redirect!
    assert_select ".flash", /already been taken/
  end

  test "the watchlist shows one list at a time, with its notes" do
    sign_in
    farming = user.lists.create!(name: "Farming", position: 1)
    create_item(2592, name: "Wool Cloth")
    create_price(@market, 2592, NOW)
    user.saved_products.create!(list: farming, item_id: 2589, note: "Farm in Elwynn")
    user.saved_products.create!(list: user.default_list, item_id: 2592)
    get realm_home_path(@realm)

    get watchlist_path

    assert_select "table a.product-link", 2
    assert_select ".saved-note", "Farm in Elwynn"
    assert_select ".list-tabs a", /Farming/

    get watchlist_path(list: farming.id)

    assert_select "table a.product-link", 1
    assert_select "table a.product-link", "Linen Cloth"
    assert_select ".list-tabs a.is-selected", /Farming/
  end

  test "an item page holds the note and the list of a product followed" do
    sign_in
    farming = user.lists.create!(name: "Farming", position: 1)

    get item_page
    assert_select ".saved-panel", false

    patch watchlist_path, params: { item_id: 2589, series: "" }
    saved = user.saved_products.first
    get item_page
    assert_select ".saved-panel select option[selected]", "Watchlist"

    patch saved_product_path(saved), params: { note: " Sell on Sundays ", list_id: farming.id }

    assert_equal "Sell on Sundays", saved.reload.note
    assert_equal farming, saved.list
  end

  test "nobody touches another player's list, product, trade or browser" do
    other = create_user(battlenet_id: 2, battletag: "Jaina#1")
    saved = other.saved_products.create!(list: other.default_list, item_id: 1)
    trade = other.trades.create!(item_id: 1, region: "eu", realm_slug: "hyjal", side: "buy", quantity: 1, unit_price: 1, traded_at: NOW)
    session_record = other.sessions.create!
    sign_in

    patch list_path(other.default_list), params: { name: "Mine" }
    assert_response :not_found
    delete list_path(other.default_list)
    assert_response :not_found
    patch saved_product_path(saved), params: { note: "Mine" }
    assert_response :not_found
    delete trade_path(trade)
    assert_response :not_found
    delete session_account_path(session_record)
    assert_response :not_found

    assert_equal "Watchlist", other.default_list.reload.name
    assert_nil saved.reload.note
    assert Trade.exists?(trade.id)
    assert Session.exists?(session_record.id)

    own_list = user.default_list
    own = user.saved_products.create!(list: own_list, item_id: 5)
    patch saved_product_path(own), params: { list_id: other.default_list.id }
    assert_response :not_found
    assert_equal own_list, own.reload.list
  end

  # Preferences

  test "preferences are saved, and an impossible one says so" do
    sign_in

    patch account_path, params: { user: { time_zone: "Seoul", chart_period: "30d", listing_sort: "name", listing_dir: "desc",
      deal_min_margin: "50", deal_min_profit: "5g" } }

    user.reload.then do |player|
      assert_equal "Seoul", player.time_zone
      assert_equal "30d", player.chart_period
      assert_equal "name", player.listing_sort
      assert_equal "desc", player.listing_dir
      assert_equal 50, player.deal_min_margin
      assert_equal 50_000, player.deal_min_profit
    end

    patch account_path, params: { user: { time_zone: "Azeroth", deal_min_profit: "lots" } }
    follow_redirect!
    assert_select ".flash", /Time zone/
    assert_equal "Seoul", user.reload.time_zone
  end

  test "a player's time zone shows on the site, and not on anyone else's page" do
    sign_in
    user.update!(time_zone: "Seoul")

    get realm_home_path(@realm)
    assert_select ".freshness[data-tip*=?]", "21:00"

    delete sign_out_path
    get realm_home_path(@realm)
    assert_select ".freshness[data-tip*=?]", "13:00"
  end

  test "when a product sells is told in the player's time zone" do
    sign_in
    user.update!(time_zone: "Seoul")
    (0..3).each do |days|
      create_snapshot(@market, NOW - days.days) unless days.zero?
      create_sale(@market, 2589, NOW - days.days)
    end

    get item_page

    assert_select ".rhythm-head p", /Seoul time/
  end

  test "an item page opens on the player's period, unless asked for another" do
    sign_in
    user.update!(chart_period: "30d")

    get item_page
    assert_select ".segmented a.is-selected", "30d"

    get item_page(period: "24h")
    assert_select ".segmented a.is-selected", "24h"
  end

  test "the listing opens on the player's sort, unless asked for another" do
    sign_in
    user.update!(listing_sort: "name", listing_dir: "desc")

    get realm_home_path(@realm)
    assert_select "th[aria-sort=descending] a.is-sorted", /Product/

    get realm_home_path(@realm, sort: "price")
    assert_select "th[aria-sort=descending] a.is-sorted", /Median/
  end

  test "deals follow the player's thresholds" do
    ListedProduct.unscoped.where(item_id: 2589).update_all(
      min_price: 100_000, usual_min_price: 200_000, usual_min_points: ListedProduct::MIN_USUAL_POINTS
    )
    sign_in

    get realm_deals_path(@realm.region, @realm.slug)
    assert_select "a.product-link", "Linen Cloth"

    user.update!(deal_min_margin: 95)
    get realm_deals_path(@realm.region, @realm.slug)
    assert_select "a.product-link", false

    user.update!(deal_min_margin: 20, deal_min_profit: 100_000)
    get realm_deals_path(@realm.region, @realm.slug)
    assert_select "a.product-link", false
    assert_select ".note", /10g/
  end

  # Realms

  test "a realm can be kept at hand, and tops the realm picker with those of the characters" do
    other = create_realm(create_market(connected_realm_id: 1302, name: "Archimonde"), name: "Archimonde")
    create_snapshot(AuctionHouse.find(other.auction_house_id), NOW)
    @battlenet.characters_by_region = { "eu" => [ CHARACTER, CHARACTER.merge(realm_slug: "gone", realm_name: "Gone", name: "Lost") ] }
    sign_in

    get realm_home_path(other)
    assert_select ".favorite-button[aria-pressed=false]", "☆"

    patch favorite_realm_path, params: { region: "eu", slug: "archimonde" }
    assert_equal [ "archimonde" ], user.favorite_realms.map(&:slug)

    get realms_path
    assert_select ".own-realm", 2
    assert_select ".own-realm:first-of-type .realm-name", /Archimonde/
    assert_select ".own-realm-list li:first-child .favorite-mark"
    assert_select ".own-realm", /Thrallia/
    assert_select ".own-realm", { text: /Lost/, count: 0 }

    patch favorite_realm_path, params: { region: "eu", slug: "archimonde" }
    assert_empty user.favorite_realms.reload
  end

  test "a realm the site does not know cannot be a favourite" do
    sign_in

    patch favorite_realm_path, params: { region: "eu", slug: "nowhere" }

    assert_response :not_found
  end

  test "the last realm follows the player to another browser" do
    sign_in
    get realm_home_path(@realm)

    other_browser = open_session
    other_browser.post auth_battlenet_path
    state = Rack::Utils.parse_query(URI(other_browser.response.location).query)["state"]
    other_browser.get auth_battlenet_callback_path, params: { code: "abc", state: state }
    other_browser.get root_path

    other_browser.assert_redirected_to realm_home_path(@realm)
  end

  test "each browser can be signed out from another" do
    sign_in
    first = user.sessions.first

    other_browser = open_session
    other_browser.post auth_battlenet_path
    state = Rack::Utils.parse_query(URI(other_browser.response.location).query)["state"]
    other_browser.get auth_battlenet_callback_path, params: { code: "abc", state: state }

    get account_path
    assert_select "#sessions .pill", "This one"
    assert_select "#sessions li", 2

    delete session_account_path(user.sessions.where.not(id: first.id).first)
    assert_equal 1, user.sessions.count

    other_browser.get account_path
    other_browser.assert_redirected_to sign_in_path(return_to: account_path)
  end

  test "a browser cannot sign itself out from the list, and every other can go at once" do
    sign_in
    current = user.sessions.first
    user.sessions.create!
    user.sessions.create!

    delete session_account_path(current)
    assert_response :not_found

    delete other_sessions_account_path
    assert_equal [ current.id ], user.sessions.pluck(:id)
  end

  # Journal

  test "a trade is written down from a product's page, and adds up in the journal" do
    sign_in

    post trades_path, params: { item_id: 2589, series: "", region: "eu", realm: "hyjal", side: "buy", quantity: 10, unit_price: "1g", traded_on: "2026-11-01", note: "Cheap day" }
    post trades_path, params: { item_id: 2589, series: "", region: "eu", realm: "hyjal", side: "sell", quantity: 4, unit_price: "2g" }

    assert_equal %w[buy sell], user.trades.order(:traded_at).pluck(:side)

    get trades_path
    assert_response :success
    assert_select ".summary-facts dd.gain .money[aria-label=?]", "3g 60s"
    assert_select "table tr", /Linen Cloth/
    assert_select ".trade-note", "Cheap day"
    assert_select ".pill-buy", /Bought/
    assert_select ".pill-sell", /Sold/
  end

  test "an item page tells what the player holds of it" do
    sign_in
    user.trades.create!(item_id: 2589, region: "eu", realm_slug: "hyjal", side: "buy", quantity: 3, unit_price: 5_000, traded_at: NOW)

    get item_page

    assert_select ".journal-facts dd", "3"
    assert_select ".journal-facts .money[aria-label=?]", "50s"
    assert_select ".trade-list li", /Bought/
  end

  test "an item page offers to write down a trade, at the cheapest price" do
    sign_in

    get item_page

    assert_select "form[action=?] input[name=unit_price][value=?]", trades_path, "1g"
    assert_select "form[action=?] input[type=hidden][name=realm][value=?]", trades_path, "hyjal"
  end

  test "a price that cannot be read, or an impossible trade, writes nothing down" do
    sign_in
    base = { item_id: 2589, series: "", region: "eu", realm: "hyjal", side: "buy", quantity: 1, unit_price: "1g" }

    post trades_path, params: base.merge(unit_price: "lots")
    follow_redirect!
    assert_select ".flash", /is not a price/

    post trades_path, params: base.merge(quantity: 0)
    follow_redirect!
    assert_select ".flash", /Not written down/

    post trades_path, params: base.merge(side: "stolen")
    post trades_path, params: base.merge(series: "bonus:1")

    assert_equal 0, user.trades.count
  end

  test "a trade needs a realm the site knows" do
    sign_in

    post trades_path, params: { item_id: 2589, series: "", region: "eu", realm: "nowhere", side: "buy", quantity: 1, unit_price: "1g" }

    assert_response :not_found
  end

  test "a day in the journal is taken in the player's time zone" do
    sign_in
    user.update!(time_zone: "Seoul")

    post trades_path, params: { item_id: 2589, series: "", region: "eu", realm: "hyjal", side: "buy", quantity: 1, unit_price: "1g", traded_on: "2026-11-01" }

    assert_equal Time.utc(2026, 11, 1, 3), user.trades.first.traded_at
  end

  test "a trade can be taken back" do
    sign_in
    trade = user.trades.create!(item_id: 2589, region: "eu", realm_slug: "hyjal", side: "buy", quantity: 1, unit_price: 1, traded_at: NOW)

    delete trade_path(trade)

    assert_not Trade.exists?(trade.id)
  end

  test "an empty journal says how to start, and a product no longer known still shows" do
    sign_in
    get trades_path
    assert_select ".empty-state", /Write down a trade/

    user.trades.create!(item_id: 777_777, region: "eu", realm_slug: "hyjal", side: "buy", quantity: 1, unit_price: 1, traded_at: NOW)
    get trades_path
    assert_response :success
    assert_select "table", /Item #777777/
  end

  # Email alerts

  test "an address is confirmed from a link sent to it" do
    sign_in

    assert_emails(1) { patch email_account_path, params: { email: "Thrall@example.com" } }

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "thrall@example.com" ], mail.to
    link = mail.text_part.body.to_s[%r{http://\S+}]
    assert_includes link, confirm_email_account_path

    get account_path
    assert_select ".status-waiting", /thrall@example.com/

    get URI(link).request_uri
    assert user.reload.email_confirmed?
    follow_redirect!
    assert_select ".flash-notice", /confirmed/
    assert_select ".status-ok"
  end

  test "an expired or forged confirmation confirms nothing" do
    sign_in
    patch email_account_path, params: { email: "thrall@example.com" }

    get confirm_email_account_path(token: "forged")

    assert_not user.reload.email_confirmed?
    follow_redirect!
    assert_select ".flash", /expired/
  end

  test "an address that is not one is refused, and sends nothing" do
    sign_in

    assert_no_emails { patch email_account_path, params: { email: "nope" } }

    follow_redirect!
    assert_select ".flash", /is not an email address/
    assert_nil user.reload.email
  end

  test "an address can be taken off, and a new confirmation asked for" do
    sign_in
    patch email_account_path, params: { email: "thrall@example.com" }

    assert_emails(1) { post email_confirmation_account_path }

    patch email_account_path, params: { email: "" }
    assert_nil user.reload.email
  end

  test "alerts can be turned off and on from the account" do
    sign_in
    user.update!(email: "thrall@example.com")
    user.update_columns(email_confirmed_at: NOW)

    patch account_path, params: { user: { alerts_enabled: "false" } }
    assert_not user.reload.alerts_enabled

    patch account_path, params: { user: { alerts_enabled: "true" } }
    assert user.reload.alerts_enabled
  end

  test "an alert can be stopped from its link, without signing in" do
    player = create_user(email: "thrall@example.com")
    token = player.generate_token_for(:unsubscribe)

    get unsubscribe_path(token: token)
    assert_response :success
    assert_select "h1", /Stop alerts/
    assert player.reload.alerts_enabled

    post unsubscribe_path(token: token)
    assert_not player.reload.alerts_enabled
  end

  test "a mail client's one-click unsubscribe works without a form" do
    player = create_user(email: "thrall@example.com")

    ActionController::Base.allow_forgery_protection = true
    post unsubscribe_path(token: player.generate_token_for(:unsubscribe)), params: { "List-Unsubscribe" => "One-Click" }, as: :url_encoded_form
  ensure
    ActionController::Base.allow_forgery_protection = false
    assert_not player.reload.alerts_enabled
  end

  test "a forged link to stop alerts stops nothing" do
    player = create_user(email: "thrall@example.com")

    get unsubscribe_path(token: "forged")
    assert_select "h1", /no longer works/

    post unsubscribe_path(token: "forged")
    assert player.reload.alerts_enabled
  end

  # The account

  test "the account page shows what the account holds" do
    @battlenet.characters_by_region = { "eu" => [ CHARACTER ] }
    sign_in

    get account_path

    assert_response :success
    assert_select "h1", "Thrall#1234"
    assert_select ".characters", /Thrallia/
    assert_select ".characters a[href=?]", realm_home_path(@realm)
    assert_select "#user-time-zone option[selected]", /Paris/
    assert_select "#alerts"
  end

  test "a copy of the account can be downloaded" do
    sign_in
    user.saved_products.create!(list: user.default_list, item_id: 2589, note: "Keep")

    get export_account_path(format: :json)

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_match(/attachment; filename="wow-trading-thrall-1234-/, response.headers["Content-Disposition"])
    assert_equal "Keep", JSON.parse(response.body).dig("lists", 0, "products", 0, "note")
  end

  test "deleting the account takes a tick, and takes everything" do
    sign_in
    user.saved_products.create!(list: user.default_list, item_id: 2589)

    delete account_path
    assert_redirected_to account_path(anchor: "delete")
    assert_equal 1, User.count

    delete account_path, params: { confirm: "1" }

    assert_redirected_to root_path
    assert_equal 0, User.count
    assert_equal 0, SavedProduct.count
    assert_equal 0, Session.count
    get account_path
    assert_redirected_to sign_in_path(return_to: account_path)
  end

  # Without an account

  test "without an account, the site is as it was, and offers one" do
    get item_page

    assert_response :success
    assert_select ".header-sign-in[href*=?]", "return_to"
    assert_select ".journal-panel", false
    assert_select ".journal-teaser a", "Sign in"
    assert_select ".favorite-button", false

    get watchlist_path
    assert_select ".lead a", "sign in"
    assert_select ".list-tabs", false
  end
end
