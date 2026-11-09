# A player, as Battle.net knows them: signing in is all there is to having an account,
# and no password is stored here. What they save and customise hangs off it.
class User < AccountsRecord
  # Plenty for a player, and keeps one account from filling the database.
  MAX_LISTS = 20
  MAX_PRODUCTS = 1_000
  MAX_TRADES = 10_000
  DEFAULT_LIST = "Watchlist".freeze
  TIME_ZONES = ActiveSupport::TimeZone.all.map(&:name).freeze

  has_many :sessions
  has_many :characters, -> { order(:region, :realm_name, :name) }
  has_many :favorite_realms, -> { order(:created_at, :id) }
  has_many :lists, -> { order(:position, :id) }
  has_many :saved_products
  has_many :trades

  normalizes :email, with: ->(email) { email.strip.downcase.presence }

  validates :battletag, presence: true, length: { maximum: 100 }
  validates :time_zone, inclusion: { in: TIME_ZONES }
  validates :chart_period, inclusion: { in: ItemHistory::PERIODS.keys }
  validates :listing_sort, inclusion: { in: MarketListing::SORTS.keys }
  validates :listing_dir, inclusion: { in: %w[asc desc] }, allow_nil: true
  validates :deal_min_margin, numericality: { only_integer: true, in: 0..95, message: "must be between 0 and 95" }
  validates :deal_min_profit, numericality: { only_integer: true, in: 0..MoneyInput::MAX, message: "is not an amount: write it like 1g or 50s" }
  validates :email, length: { maximum: 254 }, format: { with: /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/ }, allow_nil: true

  # Changing the address means proving the new one is theirs too.
  before_save -> { self.email_confirmed_at = nil }, if: :will_save_change_to_email?

  generates_token_for :email_confirmation, expires_in: 2.days do
    email
  end

  # In every alert, to stop them in one click without signing in. A new address makes
  # the links sent to the old one useless.
  generates_token_for :unsubscribe do
    email
  end

  # Signs in, creating the account the first time. `characters` replaces those known,
  # unless Battle.net could not list them.
  def self.from_battlenet(battlenet_id:, battletag:, characters: nil)
    user = find_or_initialize_by(battlenet_id: battlenet_id)
    user.battletag = battletag.to_s.first(100).presence || "Player"
    transaction do
      user.save!
      user.replace_characters(characters) if characters
      user.default_list
    end
    user
  end

  def replace_characters(list)
    characters.delete_all(:delete_all)
    rows = list.first(200).map { |character| character.merge(user_id: id) }
    Character.insert_all(rows, unique_by: %i[user_id region realm_slug name]) if rows.any?
    characters.reset
  end

  # The list a product goes to when the player stars it.
  def default_list
    lists.first || lists.create!(name: DEFAULT_LIST)
  end

  # The realm the next visit starts from. Nil until one is visited, or if it is no longer known.
  def realm
    return @realm if defined?(@realm) && @realm_key == [ realm_region, realm_slug ]

    @realm_key = [ realm_region, realm_slug ]
    @realm = realm_slug.present? ? Realm.find_by_route(realm_region, realm_slug) : nil
  end

  def remember_realm(realm)
    return if realm_region == realm.region && realm_slug == realm.slug

    update_columns(realm_region: realm.region, realm_slug: realm.slug, updated_at: Time.current)
  end

  def favorite?(realm) = favorite_realms.any? { |favorite| favorite.region == realm.region && favorite.slug == realm.slug }

  def email_confirmed? = email.present? && email_confirmed_at.present?

  def alerts_active? = email_confirmed? && alerts_enabled?

  def deal_min_margin_fraction = deal_min_margin / 100.0

  # Everything the account holds, for the player to keep a copy.
  def export
    {
      battletag: battletag,
      created_at: created_at,
      realm: realm_slug && "#{realm_region}/#{realm_slug}",
      preferences: {
        time_zone: time_zone, chart_period: chart_period, listing_sort: listing_sort, listing_dir: listing_dir,
        deal_min_margin_percent: deal_min_margin, deal_min_profit_copper: deal_min_profit
      },
      email: email, email_confirmed: email_confirmed?, alerts_enabled: alerts_enabled,
      favorite_realms: favorite_realms.map { |favorite| "#{favorite.region}/#{favorite.slug}" },
      characters: characters.map { |character| character.slice(:region, :realm_slug, :name, :level, :character_class, :faction) },
      lists: lists.includes(:saved_products).map { |list|
        { name: list.name, products: list.saved_products.map { |saved| saved.slice(:item_id, :series, :target_price, :note) } }
      },
      trades: trades.order(:traded_at, :id).map { |trade|
        trade.slice(:item_id, :series, :region, :realm_slug, :side, :quantity, :unit_price, :traded_at, :note)
      }
    }
  end
end
