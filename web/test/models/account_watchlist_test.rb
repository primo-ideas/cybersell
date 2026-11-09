require "test_helper"

class AccountWatchlistTest < ActiveSupport::TestCase
  setup do
    @user = create_user
    @watchlist = AccountWatchlist.new(@user)
  end

  test "a product starred goes to the first list, and comes off again" do
    assert @watchlist.toggle("2589", "")
    assert @watchlist.include?(2589, "")
    assert_equal @user.default_list, @watchlist.entry(2589, "").list

    assert @watchlist.toggle("2589", "")
    assert_not @watchlist.include?(2589, "")
    assert @watchlist.empty?
  end

  test "anything malformed changes nothing" do
    assert_not @watchlist.toggle("abc", "")
    assert_not @watchlist.toggle("1", "bonus:12")
    assert_not @watchlist.set_target("1", "", 0)
    assert_not @watchlist.set_target("1", "", MoneyInput::MAX + 1)
    assert @watchlist.empty?
  end

  test "a target follows the product, and comes off without unfollowing it" do
    @watchlist.set_target("2589", "", 5_000)

    assert_equal 5_000, @watchlist.target_for(2589, "")
    assert @watchlist.targets?

    @watchlist.set_target("2589", "", nil)

    assert @watchlist.include?(2589, "")
    assert_nil @watchlist.target_for(2589, "")
  end

  test "a new target can be reached again, so its alert is forgotten" do
    @watchlist.set_target("2589", "", 5_000)
    @watchlist.entry(2589, "").update_columns(alerted_at: NOW, alerted_price: 4_000)

    @watchlist.set_target("2589", "", 3_000)

    assert_nil @watchlist.entry(2589, "").alerted_at
    assert_nil @watchlist.entry(2589, "").alerted_price
  end

  test "what the browser followed comes along, without touching what the account has" do
    @watchlist.set_target("2589", "", 1_000)
    cookie = Watchlist.new("2589-9000_82800.39-500_100")

    assert_equal 2, @watchlist.import(cookie)

    assert_equal 1_000, @watchlist.target_for(2589, "")
    assert_equal 500, @watchlist.target_for(82800, "pet:39")
    assert @watchlist.include?(100, "")
  end

  test "stops at the limit of an account" do
    stub_const(User, :MAX_PRODUCTS, 2) do
      assert @watchlist.toggle("1", "")
      assert @watchlist.toggle("2", "")

      assert_not @watchlist.toggle("3", "")
      assert_not @watchlist.set_target("3", "", 100)
      assert_equal 0, @watchlist.import(Watchlist.new("3"))
      assert_equal 2, @watchlist.size
      # Taking one off still works.
      assert @watchlist.toggle("1", "")
    end
  end

  test "reads the market data like the cookie watchlist" do
    market = create_market
    create_snapshot(market, NOW)
    create_item(2589)
    create_price(market, 2589, NOW, median: 2_000, min: 900)
    @watchlist.set_target("2589", "", 1_000)
    @watchlist.toggle("777", "")

    assert_equal [ 2589 ], @watchlist.products([ market ]).map(&:item_id)
    assert_equal 1, @watchlist.not_on_sale([ market ])
    assert_equal [ 2589 ], @watchlist.at_target([ market ]).map(&:item_id)
  end

  test "with a list, only what that list holds" do
    other = @user.lists.create!(name: "Farming", position: 1)
    @user.saved_products.create!(list: other, item_id: 1)
    @user.saved_products.create!(list: @user.default_list, item_id: 2)

    assert_equal [ 1 ], AccountWatchlist.new(@user, list: other).entries.map(&:item_id)
    assert_equal 2, AccountWatchlist.new(@user).size
  end

  test "each player has their own" do
    other = create_user(battlenet_id: 2, battletag: "Jaina#1")
    @watchlist.toggle("1", "")

    assert_not AccountWatchlist.new(other).include?(1, "")
  end

  test "a product cannot go into someone else's list" do
    other = create_user(battlenet_id: 2, battletag: "Jaina#1")
    saved = @user.saved_products.create!(list: @user.default_list, item_id: 1)

    assert_not saved.update(list: other.default_list)
  end
end
