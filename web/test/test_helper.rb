ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# The site runs on the fetcher's schema, so tests load its actual migrations: a
# change there that breaks the site fails here.
module FetcherSchema
  MIGRATIONS = Rails.root.join("../fetcher/migrations/*.sql")

  def self.load
    connection = ActiveRecord::Base.lease_connection
    # This wipes the database: never let it reach anything but a test one.
    unless connection.current_database.end_with?("_test")
      raise "Refusing to wipe '#{connection.current_database}': tests need a database named *_test"
    end

    connection.execute("DROP SCHEMA public CASCADE")
    connection.execute("CREATE SCHEMA public")
    Dir[MIGRATIONS.to_s].sort.each { |file| connection.execute(File.read(file)) }

    # The fetcher creates one partition per day: tests can do with a catch-all.
    %w[price_points sales_points].each do |table|
      connection.execute("CREATE TABLE #{table}_all PARTITION OF #{table} DEFAULT")
    end
    ActiveRecord::Base.descendants.each(&:reset_column_information)
  end
end

# What players save has its own database, built from its actual migrations too.
module AccountsSchema
  def self.load
    pool = AccountsRecord.connection_pool
    pool.with_connection do |connection|
      unless connection.current_database.end_with?("_test")
        raise "Refusing to wipe '#{connection.current_database}': tests need a database named *_test"
      end

      connection.execute("DROP SCHEMA public CASCADE")
      connection.execute("CREATE SCHEMA public")
    end
    # As `db:migrate` does: migrations run on whichever database this makes the current one.
    config = ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "accounts")
    ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do
      ActiveRecord::Migration.suppress_messages { ActiveRecord::Tasks::DatabaseTasks.migrate }
    end
    AccountsRecord.descendants.each(&:reset_column_information)
  end
end

FetcherSchema.load
AccountsSchema.load

# Battle.net as the site sees it, without the network.
class FakeBattleNet
  attr_writer :identity
  attr_accessor :characters_by_region, :failing_regions, :token_error

  def initialize
    @identity = BattleNet::Identity.new(id: 4242, battletag: "Thrall#1234")
    @characters_by_region = {}
    @failing_regions = []
  end

  def configured? = true

  def identity(_token) = @identity

  def authorize_url(redirect_uri:, state:)
    "https://oauth.battle.net/authorize?#{URI.encode_www_form(redirect_uri: redirect_uri, state: state)}"
  end

  def access_token(code:, redirect_uri:)
    raise BattleNet::Error, token_error if token_error

    "token-for-#{code}"
  end

  def characters(_token, region)
    raise BattleNet::Error, "down" if failing_regions.include?(region)

    characters_by_region.fetch(region, [])
  end
end

module MarketData
  NOW = Time.utc(2026, 11, 5, 12)

  def create_market(region: "eu", connected_realm_id: 1390, name: "Hyjal")
    id = AuctionHouse.insert_all!(
      [ { region: region, connected_realm_id: connected_realm_id, name: name } ],
      returning: :id
    ).first["id"]
    AuctionHouse.find(id)
  end

  def create_realm(market, name: "Hyjal", slug: name.parameterize)
    Realm.insert_all!([ { region: market.region, slug: slug, name: name, auction_house_id: market.id } ])
    Realm.find_by_route(market.region, slug)
  end

  def create_commodities(region: "eu")
    create_market(region: region, connected_realm_id: nil, name: "Commodities")
  end

  def create_item(id, name: "Linen Cloth", quality: "COMMON", item_class: "Tradeskill", item_subclass: "Cloth", icon_url: nil)
    Item.insert_all!([ { id: id, name: name, quality: quality, item_class: item_class, item_subclass: item_subclass, icon_url: icon_url } ])
    Item.find(id)
  end

  def create_pet(species_id, name: "Mechanical Squirrel", icon_url: "https://render.example/pet.jpg")
    Pet.insert_all!([ { species_id: species_id, name: name, icon_url: icon_url } ])
    Pet.find(species_id)
  end

  def create_snapshot(market, taken_at, auction_count: 10)
    Snapshot.insert_all!([ {
      auction_house_id: market.id,
      taken_at: taken_at,
      fetched_at: taken_at,
      auction_count: auction_count,
      unpriced_count: 0
    } ])
    refresh_listed_products(market)
  end

  def create_price(market, item_id, taken_at, median: 1_000, min: median / 2, quantity: 5, auctions: 1, variant: "")
    PricePoint.insert_all!([ {
      auction_house_id: market.id,
      item_id: item_id,
      taken_at: taken_at,
      min_price: min,
      p25_price: median - 10,
      median_price: median,
      p75_price: median + 10,
      mean_price: median,
      quantity: quantity,
      auction_count: auctions,
      variant: variant
    } ])
    refresh_listed_products(market)
  end

  def create_sale(market, item_id, taken_at, quantity: 2, value: 2_000, variant: "")
    SalesPoint.insert_all!([ {
      auction_house_id: market.id,
      item_id: item_id,
      taken_at: taken_at,
      sold_quantity: quantity,
      sold_value: value,
      sold_auctions: 1,
      variant: variant
    } ])
    refresh_listed_products(market)
  end

  def insert_daily_price(market, item_id, day, median:, variant: "")
    insert_daily("price_points_daily", market, item_id, day, variant,
      "min_price, p25_price, median_price, p75_price, mean_price, quantity, auction_count",
      [ median, median, median, median, median, 7, 1 ])
  end

  def insert_daily_sale(market, item_id, day, quantity:, value:, variant: "")
    insert_daily("sales_points_daily", market, item_id, day, variant,
      "sold_value, sold_quantity, sold_auctions", [ value, quantity, 1 ])
  end

  def create_user(battlenet_id: 1, battletag: "Thrall#1234", **attributes)
    user = User.from_battlenet(battlenet_id: battlenet_id, battletag: battletag)
    user.update!(attributes) if attributes.any?
    user
  end

  # A player whose alerts can go out: their address confirmed, and a realm to watch.
  def create_alerted_user(realm, email: "thrall@example.com", **attributes)
    user = create_user(realm_region: realm.region, realm_slug: realm.slug, email: email, **attributes)
    user.update_columns(email_confirmed_at: NOW)
    user
  end

  private

  # As the fetcher does when it stores a snapshot, with the same function.
  def refresh_listed_products(market)
    ActiveRecord::Base.lease_connection.execute("SELECT refresh_listed_products(#{market.id})")
  end

  def insert_daily(table, market, item_id, day, variant, columns, values)
    connection = ActiveRecord::Base.lease_connection
    connection.execute(<<~SQL)
      INSERT INTO #{table} (auction_house_id, item_id, day, variant, #{columns})
      VALUES (#{market.id}, #{item_id}, #{connection.quote(day.to_s)}, #{connection.quote(variant)}, #{values.join(", ")})
    SQL
  end
end

module ActiveSupport
  class TestCase
    include MarketData
  end
end
