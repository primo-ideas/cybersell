require "test_helper"

class UserTest < ActiveSupport::TestCase
  CHARACTER = { region: "eu", realm_slug: "hyjal", realm_name: "Hyjal", name: "Thrallia", level: 80,
                character_class: "Shaman", faction: "Horde" }.freeze

  test "the first sign-in creates the account, with a first list" do
    user = User.from_battlenet(battlenet_id: 7, battletag: "Thrall#1234", characters: [ CHARACTER ])

    assert_equal "Thrall#1234", user.battletag
    assert_equal [ User::DEFAULT_LIST ], user.lists.map(&:name)
    assert_equal [ "Thrallia" ], user.characters.map(&:name)
  end

  test "the next ones update it, and keep what it holds" do
    first = User.from_battlenet(battlenet_id: 7, battletag: "Thrall#1234", characters: [ CHARACTER ])
    first.saved_products.create!(list: first.default_list, item_id: 1)

    second = User.from_battlenet(battlenet_id: 7, battletag: "Warchief#1234", characters: [ CHARACTER.merge(name: "Other") ])

    assert_equal first.id, second.id
    assert_equal "Warchief#1234", second.battletag
    assert_equal [ "Other" ], second.characters.map(&:name)
    assert_equal 1, second.saved_products.count
    assert_equal 1, second.lists.count
  end

  test "characters stay as they were when Battle.net could not list them" do
    User.from_battlenet(battlenet_id: 7, battletag: "Thrall#1234", characters: [ CHARACTER ])

    user = User.from_battlenet(battlenet_id: 7, battletag: "Thrall#1234", characters: nil)

    assert_equal [ "Thrallia" ], user.characters.map(&:name)
  end

  test "an address is confirmed only for itself" do
    user = create_user(email: "  Thrall@Example.com ")

    assert_equal "thrall@example.com", user.email
    assert_not user.email_confirmed?

    token = user.generate_token_for(:email_confirmation)
    user.update_columns(email_confirmed_at: NOW)
    assert user.email_confirmed?
    assert_equal user, User.find_by_token_for(:email_confirmation, token)

    user.update!(email: "other@example.com")

    assert_not user.email_confirmed?
    assert_nil User.find_by_token_for(:email_confirmation, token)
  end

  test "saving the same address again does not undo its confirmation" do
    user = create_user(email: "thrall@example.com")
    user.update_columns(email_confirmed_at: NOW)

    user.update!(email: "THRALL@example.com ", time_zone: "Seoul")

    assert user.email_confirmed?
  end

  test "a link to stop the emails dies with the address" do
    user = create_user(email: "thrall@example.com")
    token = user.generate_token_for(:unsubscribe)

    assert_equal user, User.find_by_token_for(:unsubscribe, token)

    user.update!(email: "other@example.com")

    assert_nil User.find_by_token_for(:unsubscribe, token)
  end

  test "an email address is optional, but has to look like one" do
    assert create_user.email.nil?
    assert_not create_user.update(email: "not an address")
    assert_not create_user.update(email: "a@b")
    assert create_user.update(email: "")
    assert_nil create_user.reload.email
  end

  test "preferences are limited to what the site knows" do
    user = create_user

    assert_not user.update(time_zone: "Azeroth/Orgrimmar")
    user.reload
    assert_not user.update(chart_period: "1y")
    user.reload
    assert_not user.update(listing_sort: "1; DROP")
    user.reload
    assert_not user.update(listing_dir: "sideways")
    user.reload
    assert_not user.update(deal_min_margin: 96)
    user.reload
    assert_not user.update(deal_min_profit: -1)
    user.reload
    assert user.update(time_zone: "Eastern Time (US & Canada)", chart_period: "all", listing_sort: "name", listing_dir: "asc",
      deal_min_margin: 0, deal_min_profit: 0)
  end

  test "remembers the last realm, and finds it again" do
    market = create_market
    realm = create_realm(market)
    user = create_user

    assert_nil user.realm

    user.remember_realm(realm)

    assert_equal realm, User.find(user.id).realm
  end

  test "a realm the site no longer knows is no realm" do
    assert_nil create_user(realm_region: "eu", realm_slug: "gone").realm
  end

  test "deleting an account takes everything in it" do
    user = create_user
    user.saved_products.create!(list: user.default_list, item_id: 1)
    user.sessions.create!
    user.favorite_realms.create!(region: "eu", slug: "hyjal")
    user.replace_characters([ CHARACTER ])
    user.trades.create!(item_id: 1, region: "eu", realm_slug: "hyjal", side: "buy", quantity: 1, unit_price: 1, traded_at: NOW)

    user.destroy!

    [ SavedProduct, List, Session, FavoriteRealm, Character, Trade ].each { |model| assert_equal 0, model.count, model.name }
  end

  test "the export holds what the account holds, and no session" do
    user = create_user
    user.saved_products.create!(list: user.default_list, item_id: 1, target_price: 500, note: "Hello")
    user.trades.create!(item_id: 1, region: "eu", realm_slug: "hyjal", side: "buy", quantity: 2, unit_price: 3, traded_at: NOW)
    user.sessions.create!(ip_address: "203.0.113.9")

    export = user.export

    assert_equal "Thrall#1234", export[:battletag]
    assert_equal 500, export[:lists].first[:products].first["target_price"]
    assert_equal "Hello", export[:lists].first[:products].first["note"]
    assert_equal 2, export[:trades].first["quantity"]
    assert_not_includes export.to_json, "203.0.113.9"
  end
end
