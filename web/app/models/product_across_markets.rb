# The same product on the other realms of a region. Gold stays within a region, so that
# is where comparing prices makes sense. Connected realms share a market, so each row
# stands for one or more realms.
class ProductAcrossMarkets
  LIMIT = 12

  def initialize(market, item_id, series, realm: nil)
    @market = market
    @item_id = item_id
    @series = series
    @realm = realm
  end

  # The cheapest first. The reader's own market comes last when it is not among them, so
  # that there is always something to compare to.
  def rows
    @rows ||= begin
      cheapest = listed.order(:min_price, :auction_house_id).limit(LIMIT).to_a
      own = listed.find_by(auction_house_id: @market.id) if cheapest.none? { |row| current?(row) }
      own ? cheapest + [ own ] : cheapest
    end
  end

  def comparable? = rows.many?

  def current?(row) = row.auction_house_id == @market.id

  # How many markets of the region have it on sale.
  def market_count
    @market_count ||= listed.count
  end

  # Where the reader's own market stands among them, 1 for the cheapest. Nil when it is
  # not on sale there.
  def rank
    return @rank if defined?(@rank)

    own = rows.find { |row| current?(row) }
    @rank = own && listed.where("listed_products.min_price < ?", own.min_price).count + 1
  end

  # The realms of a row, by name, with the reader's own first on its row.
  def realms_of(row)
    realms = realms_by_market.fetch(row.auction_house_id, [])
    current?(row) && @realm ? [ @realm, *realms.reject { |realm| realm == @realm } ] : realms
  end

  private

  def listed
    ListedProduct
      .joins("JOIN auction_houses houses ON houses.id = listed_products.auction_house_id")
      .where(item_id: @item_id, series: @series)
      .where(houses: { region: @market.region })
  end

  def realms_by_market
    @realms_by_market ||= Realm.where(auction_house_id: rows.map(&:auction_house_id)).by_name.group_by(&:auction_house_id)
  end
end
