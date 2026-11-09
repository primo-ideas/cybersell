# What a reader follows without an account, kept in a cookie: products, not prices on a
# given market, so that the list shows them on whatever realm the reader is on. Each may
# carry a target price, which its cheapest listing is compared to. Signing in moves it
# all to the account: see AccountWatchlist.
class Watchlist
  include FollowedProducts

  # A cookie holds 4 KB, which this stays under even with a target on every product. The
  # oldest entries go first.
  LIMIT = 100
  Entry = Data.define(:item_id, :series, :target)
  ENTRY = /\A(\d{1,9})(?:\.(\d{1,9}))?(?:-(\d{1,13}))?\z/
  # The cookie of the time products were followed market by market: market.item[.species].
  LEGACY_ENTRY = /\A\d{1,9}\.(\d{1,9})(?:\.(\d{1,9}))?\z/
  SERIES = FollowedProducts::SERIES

  attr_reader :entries

  def initialize(cookie, legacy: nil)
    texts, pattern = cookie.nil? ? [ legacy, LEGACY_ENTRY ] : [ cookie, ENTRY ]
    @entries = texts.to_s.split("_").filter_map { |text| parse(text, pattern) }
      .uniq { |entry| [ entry.item_id, entry.series ] }.last(LIMIT)
  end

  def account? = false

  # Adds the product, or removes it if it was there. Anything malformed changes nothing.
  def toggle(item_id, series)
    return unless valid_product?(item_id, series)

    item_id = item_id.to_i
    series = series.to_s
    @entries = if include?(item_id, series)
      entries.reject { |entry| same?(entry, item_id, series) }
    else
      (entries + [ Entry.new(item_id, series, nil) ]).last(LIMIT)
    end
    forget_products
  end

  # Sets the target price of a product, which follows it from then on; nil takes the
  # target off and keeps following it.
  def set_target(item_id, series, target)
    return unless valid_product?(item_id, series)
    return unless target.nil? || (target.is_a?(Integer) && target.between?(1, MoneyInput::MAX))

    item_id = item_id.to_i
    series = series.to_s
    entry = Entry.new(item_id, series, target)
    @entries = if include?(item_id, series)
      entries.map { |existing| same?(existing, item_id, series) ? entry : existing }
    else
      (entries + [ entry ]).last(LIMIT)
    end
    forget_products
  end

  # Only characters a cookie carries as they are, so that the limit above holds.
  def to_cookie
    entries.map do |entry|
      text = [ entry.item_id, entry.series.delete_prefix("pet:").presence ].compact.join(".")
      entry.target ? "#{text}-#{entry.target}" : text
    end.join("_")
  end

  private

  def same?(entry, item_id, series) = entry.item_id == item_id && entry.series == series

  def parse(text, pattern)
    item_id, species, target = text.match(pattern)&.captures
    return unless item_id

    target = target&.to_i
    Entry.new(item_id.to_i, species ? "pet:#{species}" : "", target&.between?(1, MoneyInput::MAX) ? target : nil)
  end
end
