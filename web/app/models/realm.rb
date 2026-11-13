# A realm as a player knows it: the one their characters live on. Behind it are two
# markets, which the site adds up so that a player never has to know: the auction house
# it shares with the realms connected to it, and the commodities of its region, where
# stackable goods trade.
#
# Mists of Pandaria Classic realms are realms too, in regions of their own named as
# Battle.net names them: `classic-eu` next to `eu`. Their auction house sells everything,
# as Classic has no commodities.
class Realm < ApplicationRecord
  self.primary_key = %i[region slug]

  belongs_to :auction_house

  REGION_NAMES = {
    "eu" => "Europe",
    "us" => "Americas & Oceania",
    "kr" => "Korea",
    "tw" => "Taiwan"
  }.freeze

  CLASSIC_PREFIX = "classic-".freeze
  CLASSIC_NAME = "Mists of Pandaria Classic".freeze

  # Every region the site may know, retail then Classic.
  REGIONS = (REGION_NAMES.keys + REGION_NAMES.keys.map { |code| "#{CLASSIC_PREFIX}#{code}" }).freeze

  # As in the `edition` columns of the market data.
  def self.edition_of(region) = region.to_s.start_with?(CLASSIC_PREFIX) ? "classic" : "retail"

  # The Battle.net region behind it: `eu` for `classic-eu` too.
  def self.region_code(region) = region.to_s.delete_prefix(CLASSIC_PREFIX)

  # As shown next to a realm's name: `EU`, or `MoP EU` for Classic.
  def self.short_region(region)
    code = region_code(region).upcase
    edition_of(region) == "classic" ? "MoP #{code}" : code
  end

  scope :by_name, -> { order(:region, Arel.sql('realms.name COLLATE "und-x-icu"')) }

  # What a player can pick: realms whose market is followed, and every realm of a region
  # whose commodities are, as those prices hold on all of them.
  def self.followed(tracked_markets)
    houses = tracked_markets.reject(&:commodities?).map(&:id)
    regions = tracked_markets.select(&:commodities?).map(&:region)
    where(auction_house_id: houses).or(where(region: regions)).by_name
  end

  def self.find_by_route(region, slug)
    find_by(region: region.to_s, slug: slug.to_s.delete("\0"))
  end

  def region_name
    name = REGION_NAMES.fetch(region_code, region_code.upcase)
    classic? ? "#{name} · #{CLASSIC_NAME}" : name
  end

  def region_code = self.class.region_code(region)

  def short_region = self.class.short_region(region)

  # Which items and pets its products are.
  def edition = self.class.edition_of(region)

  def classic? = edition == "classic"

  # Its own market first: what is on neither is looked for there.
  def markets
    @markets ||= AuctionHouse
      .where(id: auction_house_id)
      .or(AuctionHouse.where(region: region, connected_realm_id: nil))
      .order(Arel.sql("connected_realm_id IS NULL"))
      .to_a
  end

  def market_ids = markets.map(&:id)

  # When the market that lags behind was last updated, so that freshness is never
  # overstated. Nil before any snapshot.
  def latest_taken_at
    return @latest_taken_at if defined?(@latest_taken_at)

    @latest_taken_at = Snapshot.where(auction_house_id: market_ids).group(:auction_house_id).maximum(:taken_at).values.min
  end

  # Whether its own auction house is followed, and not only the commodities of its region.
  def own_market_followed?
    return @own_market_followed if defined?(@own_market_followed)

    @own_market_followed = Snapshot.where(auction_house_id: auction_house_id).exists?
  end

  # The market an item trades on from this realm: in practice, either its own or the
  # commodities of its region, never both.
  def market_of(item_id)
    return markets.first if markets.one?

    house = ListedProduct.where(auction_house_id: market_ids, item_id: item_id).pick(:auction_house_id) ||
      PricePoint.where(auction_house_id: market_ids, item_id: item_id).order(taken_at: :desc).pick(:auction_house_id)
    markets.find { |market| market.id == house } || markets.first
  end
end
