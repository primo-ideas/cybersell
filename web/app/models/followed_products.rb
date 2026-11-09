# What a reader follows, read the same whether it lives in a cookie (Watchlist) or in
# their account (AccountWatchlist): `entries` respond to item_id, series and target.
module FollowedProducts
  ITEM_ID = /\A\d{1,9}\z/
  SERIES = /\A(?:pet:(\d{1,9}))?\z/

  def include?(item_id, series) = !entry_for(item_id, series).nil?

  def target_for(item_id, series) = entry_for(item_id, series)&.target

  def empty? = entries.empty?

  def size = entries.size

  def targets? = entries.any?(&:target)

  # What is on sale on these markets at their latest snapshot, with its name and icon.
  def products(markets)
    return [] if empty? || markets.empty?

    @products ||= {}
    @products[markets.map(&:id)] ||= ListedProduct.find_by_sql([ <<~SQL, houses: markets.map(&:id), items: entries.map(&:item_id).uniq ])
      SELECT listed.*, #{ListedProduct::LABELS}
      #{ListedProduct::FROM_WITH_LABELS}
      WHERE listed.auction_house_id IN (:houses) AND listed.item_id IN (:items)
      ORDER BY #{ListedProduct::NAME} COLLATE "und-x-icu", listed.item_id, listed.series
    SQL
      .select { |row| include?(row.item_id, row.series) }
  end

  def not_on_sale(markets) = size - products(markets).size

  # Whether the cheapest listing of this product is at or below its target.
  def at_target?(row)
    target = target_for(row.item_id, row.series)
    !target.nil? && row.min_price <= target
  end

  # The products whose cheapest listing has come down to their target on these markets.
  def at_target(markets)
    targets? ? products(markets).select { |row| at_target?(row) } : []
  end

  private

  def entry_for(item_id, series)
    entries.find { |entry| entry.item_id == item_id && entry.series == series }
  end

  def valid_product?(item_id, series)
    item_id.to_s.match?(ITEM_ID) && series.to_s.match?(SERIES)
  end

  def forget_products
    @products = nil
  end
end
