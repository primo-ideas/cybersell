require "test_helper"

class OldDomainRedirectTest < ActiveSupport::TestCase
  SITE = "https://example.com/playdeals".freeze

  def get(url, hosts: "wow.example, old.example", site: SITE, **headers)
    inner = ->(_env) { [ 200, {}, [ "the site" ] ] }
    app = OldDomainRedirect.new(inner, hosts: hosts, site: site)
    Rack::MockRequest.new(app).get(url, headers)
  end

  test "every page of an old domain leads to the same page of the World of Warcraft section" do
    response = get("http://wow.example/eu/hyjal/items/2589?variant=pet:39&period=30d")

    assert_equal 301, response.status
    assert_equal "#{SITE}/wow/eu/hyjal/items/2589?variant=pet:39&period=30d", response["location"]

    assert_equal "#{SITE}/wow", get("http://wow.example/")["location"]
    assert_equal "#{SITE}/wow", get("http://OLD.example:8080")["location"]
    assert_equal "#{SITE}/wow/watchlist", get("http://wow.example/watchlist")["location"]
    assert_equal "#{SITE}/wow/markets/3", get("http://wow.example/markets/3")["location"]
  end

  test "what belongs to no game keeps its place at the root" do
    assert_equal "#{SITE}/account", get("http://wow.example/account")["location"]
    assert_equal "#{SITE}/sign-in", get("http://wow.example/sign-in")["location"]
    assert_equal "#{SITE}/alerts/unsubscribe?token=abc", get("http://wow.example/alerts/unsubscribe?token=abc")["location"]
    assert_equal "#{SITE}/account/email/confirm?token=abc", get("http://wow.example/account/email/confirm?token=abc")["location"]
  end

  test "the name a proxy was asked for counts, not the one it calls the site by" do
    response = get("http://127.0.0.1:3000/eu/hyjal", "HTTP_X_FORWARDED_HOST" => "wow.example")

    assert_equal "#{SITE}/wow/eu/hyjal", response["location"]
  end

  test "the site itself, and a setup without an old domain, are left alone" do
    assert_equal "the site", get("http://example.com/playdeals/wow").body
    assert_equal "the site", get("http://wow.example/eu/hyjal", hosts: nil).body
    assert_equal "the site", get("http://wow.example/eu/hyjal", hosts: " , ").body
    assert_equal "the site", get("http://wow.example/eu/hyjal", site: "").body
  end
end
