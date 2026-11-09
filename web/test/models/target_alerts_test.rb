require "test_helper"

class TargetAlertsTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @market = create_market
    @realm = create_realm(@market)
    create_snapshot(@market, NOW)
    create_item(2589, name: "Linen Cloth")
    create_item(2592, name: "Wool Cloth")
    create_price(@market, 2589, NOW, median: 2_000, min: 900)
    create_price(@market, 2592, NOW, median: 2_000, min: 900)
    @user = create_alerted_user(@realm)
    @watchlist = AccountWatchlist.new(@user)
  end

  def reprice(item_id, min)
    ListedProduct.unscoped.where(auction_house_id: @market.id, item_id: item_id).update_all(min_price: min)
  end

  test "production only offers alerts with an SMTP server to send them" do
    production = ActiveSupport::EnvironmentInquirer.new("production")
    development = ActiveSupport::EnvironmentInquirer.new("development")

    assert_not TargetAlerts.available?(env: production, smtp: nil)
    assert_not TargetAlerts.available?(env: production, smtp: "")
    assert TargetAlerts.available?(env: production, smtp: "smtp.example.com")
    assert TargetAlerts.available?(env: development, smtp: nil)
  end

  test "one email for all the products that just reached their target" do
    @watchlist.set_target("2589", "", 1_000)
    @watchlist.set_target("2592", "", 950)

    assert_emails(1) { assert_equal 2, TargetAlerts.deliver_all(now: NOW) }

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "thrall@example.com" ], mail.to
    assert_match "2 products are at your target price on Hyjal", mail.subject
    assert_match "Linen Cloth", mail.text_part.body.to_s
    assert_match "/eu/hyjal/items/2589", mail.html_part.body.to_s
    assert_match "alerts/unsubscribe", mail["List-Unsubscribe"].value
    assert_equal "List-Unsubscribe=One-Click", mail["List-Unsubscribe-Post"].value
  end

  test "names the product when there is only one" do
    @watchlist.set_target("2589", "", 1_000)

    TargetAlerts.deliver_all(now: NOW)

    assert_equal "Linen Cloth is at your target price on Hyjal", ActionMailer::Base.deliveries.last.subject
  end

  test "says so once, and remembers at what price" do
    @watchlist.set_target("2589", "", 1_000)

    TargetAlerts.deliver_all(now: NOW)

    assert_no_emails { TargetAlerts.deliver_all(now: NOW + 1.hour) }
    saved = @user.saved_products.first
    assert_equal NOW, saved.alerted_at
    assert_equal 900, saved.alerted_price
  end

  test "says so again once the price has gone back above the target and come down" do
    @watchlist.set_target("2589", "", 1_000)
    TargetAlerts.deliver_all(now: NOW)

    reprice(2589, 5_000)
    assert_no_emails { TargetAlerts.deliver_all(now: NOW + 1.hour) }
    assert_nil @user.saved_products.first.alerted_at

    reprice(2589, 800)
    assert_emails(1) { TargetAlerts.deliver_all(now: NOW + 2.hours) }
  end

  test "a product no longer on sale keeps its state: it says nothing either way" do
    @watchlist.set_target("2589", "", 1_000)
    TargetAlerts.deliver_all(now: NOW)

    ListedProduct.unscoped.where(item_id: 2589).delete_all
    TargetAlerts.deliver_all(now: NOW + 1.hour)

    assert_equal NOW, @user.saved_products.first.alerted_at
  end

  test "nothing above the target, nor without one" do
    @watchlist.set_target("2589", "", 500)
    @watchlist.toggle("2592", "")

    assert_no_emails { assert_equal 0, TargetAlerts.deliver_all(now: NOW) }
  end

  test "looks at the player's own realm" do
    other_market = create_market(connected_realm_id: 1302, name: "Archimonde")
    other_realm = create_realm(other_market, name: "Archimonde")
    create_snapshot(other_market, NOW)
    create_price(other_market, 2589, NOW, median: 2_000, min: 50_000)
    @watchlist.set_target("2589", "", 1_000)
    @user.update_columns(realm_slug: other_realm.slug)

    assert_no_emails { TargetAlerts.deliver_all(now: NOW) }
  end

  test "nobody who has not asked for them gets them" do
    @watchlist.set_target("2589", "", 1_000)

    @user.update_columns(alerts_enabled: false)
    assert_no_emails { TargetAlerts.deliver_all(now: NOW) }

    @user.update_columns(alerts_enabled: true, email_confirmed_at: nil)
    assert_no_emails { TargetAlerts.deliver_all(now: NOW) }

    @user.update_columns(email_confirmed_at: NOW, realm_slug: nil)
    assert_no_emails { TargetAlerts.deliver_all(now: NOW) }
  end

  test "one player's failure does not keep the others from theirs" do
    @watchlist.set_target("2589", "", 1_000)
    other = create_alerted_user(@realm, email: "jaina@example.com", battlenet_id: 2, battletag: "Jaina#1")
    AccountWatchlist.new(other).set_target("2589", "", 1_000)

    # Delivered first, by id: this address is refused by the message itself.
    @user.update_columns(email: "broken\r\nBcc: x@example.com")
    calls = 0
    original = AlertMailer.method(:targets_reached)
    AlertMailer.define_singleton_method(:targets_reached) do |user, realm, rows|
      calls += 1
      raise IOError, "refused" if user.email.start_with?("broken")

      original.call(user, realm, rows)
    end

    assert_emails(1) { assert_equal 1, TargetAlerts.deliver_all(now: NOW) }
    assert_equal 2, calls
  ensure
    AlertMailer.singleton_class.send(:remove_method, :targets_reached)
  end
end
