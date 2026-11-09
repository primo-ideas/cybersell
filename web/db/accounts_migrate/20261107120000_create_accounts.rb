# Players sign in with Battle.net: no password is ever stored here.
class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.bigint :battlenet_id, null: false, index: { unique: true }
      t.string :battletag, null: false

      # The realm last visited, which the next visit starts from, on any device.
      t.string :realm_region
      t.string :realm_slug

      # Preferences. Named as ActiveSupport::TimeZone names them.
      t.string :time_zone, null: false, default: "Paris"
      t.string :chart_period, null: false, default: "7d"
      t.string :listing_sort, null: false, default: "value"
      t.string :listing_dir
      t.integer :deal_min_margin, null: false, default: 20
      t.bigint :deal_min_profit, null: false, default: 10_000

      # Where alerts go, once the player has confirmed it is theirs.
      t.string :email
      t.datetime :email_confirmed_at
      t.boolean :alerts_enabled, null: false, default: true

      t.timestamps
    end
    add_check_constraint :users, "deal_min_margin BETWEEN 0 AND 95", name: "users_deal_min_margin"
    add_check_constraint :users, "deal_min_profit >= 0", name: "users_deal_min_profit"

    # One per browser signed in, so that each can be signed out from the others.
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :user_agent
      t.string :ip_address
      t.timestamps
    end

    # As Battle.net lists them when the player signs in, to offer their realms.
    create_table :characters do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :region, null: false
      t.string :realm_slug, null: false
      t.string :realm_name, null: false
      t.string :name, null: false
      t.integer :level
      t.string :character_class
      t.string :faction
      t.index %i[user_id region realm_slug name], unique: true
    end

    create_table :favorite_realms do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :region, null: false
      t.string :slug, null: false
      t.datetime :created_at, null: false
      t.index %i[user_id region slug], unique: true
    end

    create_table :lists do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index %i[user_id name], unique: true
    end

    # A product followed, in one of the player's lists. `series` is as in the market
    # data: empty, or pet:<species> for a caged pet.
    create_table :saved_products do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :list, null: false, foreign_key: { on_delete: :cascade }
      t.integer :item_id, null: false
      t.string :series, null: false, default: ""
      t.bigint :target_price
      t.string :note
      # When an email last said it reached its target, and at what price. Cleared once
      # it goes back above, so that the next time it comes down says so again.
      t.datetime :alerted_at
      t.bigint :alerted_price
      t.timestamps
      t.index %i[user_id item_id series], unique: true
    end
    add_check_constraint :saved_products, "target_price IS NULL OR target_price > 0", name: "saved_products_target"

    # The journal: what a player bought and sold, to work out what they made.
    create_table :trades do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.integer :item_id, null: false
      t.string :series, null: false, default: ""
      t.string :region, null: false
      t.string :realm_slug, null: false
      t.string :side, null: false
      t.integer :quantity, null: false
      t.bigint :unit_price, null: false
      t.datetime :traded_at, null: false
      t.string :note
      t.timestamps
      t.index %i[user_id item_id series traded_at]
    end
    add_check_constraint :trades, "side IN ('buy', 'sell')", name: "trades_side"
    add_check_constraint :trades, "quantity > 0", name: "trades_quantity"
    add_check_constraint :trades, "unit_price > 0", name: "trades_unit_price"
  end
end
