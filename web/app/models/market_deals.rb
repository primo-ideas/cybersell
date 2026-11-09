# What sells well below its usual price on a realm's markets, measured on the cheapest listing:
# see `usual_min_price` in the fetcher's migrations for why not on asking prices or sales.
class MarketDeals
  LIMIT = 100
  # Below this, a good percentage is still only small change: one gold, in copper.
  MIN_PROFIT = 10_000
  MIN_MARGIN = 0.2
  PROFIT = "(listed.usual_min_price * #{1 - Flip::AUCTION_HOUSE_CUT} - listed.min_price)".freeze
  # A variant added up with others says nothing: a low item level is not a bargain.
  CONDITIONS = <<~SQL.squish.freeze
    #{ListedProduct::NAME} IS NOT NULL
    AND listed.variant_count = 1
    AND listed.min_price > 0
    AND listed.usual_min_points >= :min_points
    AND #{PROFIT} >= :min_profit
    AND #{PROFIT} >= listed.min_price * :min_margin
  SQL
  SORTS = {
    "profit" => "#{PROFIT} DESC",
    "discount" => "listed.min_price::float8 / listed.usual_min_price ASC",
    "sold" => "listed.sold_quantity DESC NULLS LAST"
  }.freeze
  DEFAULT_SORT = "profit"

  attr_reader :sort, :min_margin, :min_profit

  # A player can ask for bigger or smaller deals than these from their account.
  def initialize(markets, sort: nil, min_margin: MIN_MARGIN, min_profit: MIN_PROFIT)
    @ids = Array(markets).map(&:id)
    @query = MarketQuery.new(markets)
    @sort = SORTS.key?(sort) ? sort : DEFAULT_SORT
    @min_margin = min_margin
    @min_profit = min_profit
  end

  def default_thresholds? = min_margin == MIN_MARGIN && min_profit == MIN_PROFIT

  def latest_taken_at = @query.latest_taken_at

  def rows
    @rows ||= @query.products(where: CONDITIONS, binds: binds, order: SORTS.fetch(sort), limit: LIMIT)
  end

  def total
    @total ||= @query.count(where: CONDITIONS, binds: binds)
  end

  # Whether any product has enough history for this list to mean something.
  def ready?
    ListedProduct
      .where(auction_house_id: @ids)
      .where(usual_min_points: ListedProduct::MIN_USUAL_POINTS..)
      .exists?
  end

  # How far along the furthest market is, for a page that has to wait.
  def snapshots_so_far
    return 0 unless latest_taken_at

    Snapshot.where(auction_house_id: @ids, taken_at: (latest_taken_at - 3.days)..)
      .group(:auction_house_id).count.values.max.to_i
  end

  private

  def binds = { min_points: ListedProduct::MIN_USUAL_POINTS, min_profit: min_profit, min_margin: min_margin }
end
