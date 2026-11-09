# What a signed-in player follows, in the lists of their account: the same as the cookie
# watchlist, on every device, with notes, several lists, and email alerts. With a list,
# only what that list holds.
class AccountWatchlist
  include FollowedProducts

  attr_reader :user, :list

  def initialize(user, list: nil)
    @user = user
    @list = list
  end

  def account? = true

  def entries
    @entries ||= (list ? list.saved_products : user.saved_products).order(:created_at, :id).to_a
  end

  # The saved product itself, for its note and its list. Nil if not followed.
  def entry(item_id, series) = entry_for(item_id.to_i, series.to_s)

  def full? = user.saved_products.count >= User::MAX_PRODUCTS

  # Adds the product to the player's first list, or takes it off whichever holds it.
  # Returns false when nothing could be done.
  def toggle(item_id, series)
    return false unless valid_product?(item_id, series)

    existing = entry(item_id, series)
    if existing
      existing.destroy!
    else
      return false if full?

      user.saved_products.create!(list: user.default_list, item_id: item_id.to_i, series: series.to_s)
    end
    forget
    true
  end

  # Sets the price the player would buy at, following the product if it was not yet. A
  # new target can be reached again, so any alert about the old one is forgotten.
  def set_target(item_id, series, target)
    return false unless valid_product?(item_id, series)
    return false unless target.nil? || (target.is_a?(Integer) && target.between?(1, MoneyInput::MAX))

    existing = entry(item_id, series)
    if existing
      existing.update!(target_price: target, alerted_at: nil, alerted_price: nil)
    else
      return false if full?

      user.saved_products.create!(list: user.default_list, item_id: item_id.to_i, series: series.to_s, target_price: target)
    end
    forget
    true
  end

  # What a reader followed before signing in, kept with its targets. Returns how many
  # products were added.
  def import(watchlist)
    added = 0
    watchlist.entries.each do |cookie_entry|
      next if include?(cookie_entry.item_id, cookie_entry.series)
      break if full?

      user.saved_products.create!(list: user.default_list, item_id: cookie_entry.item_id, series: cookie_entry.series,
        target_price: cookie_entry.target)
      added += 1
      forget
    end
    added
  end

  private

  def forget
    @entries = nil
    forget_products
  end
end
