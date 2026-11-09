# Emails a player when products they follow come down to their target price on their
# realm: one email for all those that just did. A product says so once, and again only
# after its cheapest listing has gone back above the target. Run by `rails alerts:deliver`,
# which a timer starts after the fetcher's cycles.
module TargetAlerts
  module_function

  # Production needs an SMTP server; elsewhere, emails land in a folder or in tests.
  def available?(env: Rails.env, smtp: ENV["SMTP_ADDRESS"]) = env.local? || smtp.present?

  # Returns how many products were announced, all players together.
  def deliver_all(now: Time.current)
    return 0 unless available?

    candidates = User.where(alerts_enabled: true).where.not(email: nil).where.not(email_confirmed_at: nil)
      .where.not(realm_slug: nil).where(id: SavedProduct.where.not(target_price: nil).select(:user_id))
    candidates.find_each.sum do |user|
      deliver(user, now: now)
    rescue StandardError => error
      # One player's address or data must not keep the others from their alerts.
      Rails.logger.error("Alerts for user #{user.id} failed: #{error.class}: #{error.message}")
      0
    end
  end

  def deliver(user, now: Time.current)
    realm = user.realm or return 0
    watchlist = AccountWatchlist.new(user)
    rows = watchlist.products(realm.markets)
    reached = rows.select { |row| watchlist.at_target?(row) }

    # Back above its target: the next time it comes down is news again. Not on sale at
    # all says nothing either way, so it keeps its state.
    rows.each do |row|
      entry = watchlist.entry(row.item_id, row.series)
      entry.update_columns(alerted_at: nil, alerted_price: nil) if entry.alerted_at && !watchlist.at_target?(row)
    end

    news = reached.reject { |row| watchlist.entry(row.item_id, row.series).alerted_at }
    return 0 if news.empty?

    AlertMailer.targets_reached(user, realm, news).deliver_now
    news.each do |row|
      watchlist.entry(row.item_id, row.series).update_columns(alerted_at: now, alerted_price: row.min_price)
    end
    news.size
  end
end
