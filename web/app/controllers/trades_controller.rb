# The journal: what a player bought and sold, what they still hold and what they made.
class TradesController < ApplicationController
  before_action :require_user
  PAGE_SIZE = 50

  def index
    trades = current_user.trades.to_a
    @ledger = TradeLedger.new(trades)
    @products = products_of(trades)
    @prices = current_realm ? cheapest_on(current_realm, @ledger.positions) : {}
    @page = params[:page].to_s.to_i.clamp(1, [ (trades.size.to_f / PAGE_SIZE).ceil, 1 ].max)
    @page_count = [ (trades.size.to_f / PAGE_SIZE).ceil, 1 ].max
    @trades = trades.sort_by { |trade| [ -trade.traded_at.to_i, -trade.id ] }.slice((@page - 1) * PAGE_SIZE, PAGE_SIZE) || []
    @realm_names = Realm.where(slug: @trades.map(&:realm_slug).uniq).to_h { |realm| [ [ realm.region, realm.slug ], realm.name ] }
  end

  def create
    realm = Realm.find_by_route(params[:region], params[:realm]) or raise ActiveRecord::RecordNotFound
    if current_user.trades.count >= User::MAX_TRADES
      return redirect_back_or_to(trades_path, alert: "Your journal holds #{number_with_delimiter(User::MAX_TRADES)} trades at most.")
    end

    price = MoneyInput.parse(params[:unit_price])
    trade = current_user.trades.new(
      item_id: params[:item_id], series: params[:series].to_s, region: realm.region, realm_slug: realm.slug,
      side: params[:side], quantity: params[:quantity], unit_price: price, traded_at: traded_at, note: params[:note].to_s.first(200)
    )
    if price.nil?
      flash[:alert] = "“#{params[:unit_price].to_s.first(30)}” is not a price: write it like 12g 50s, 12.5 for gold, or 1.5k for 1,500 gold."
    elsif trade.save
      flash[:notice] = "#{trade.buy? ? "Purchase" : "Sale"} written down in your journal."
    else
      flash[:alert] = "Not written down: #{trade.errors.full_messages.to_sentence.downcase}."
    end
    redirect_back_or_to trades_path, status: :see_other
  end

  def destroy
    current_user.trades.find(params[:id]).destroy!
    redirect_back_or_to trades_path, status: :see_other, notice: "Trade removed from your journal."
  end

  private

  # A day as the player typed it, at the current time when it is today, else at noon in
  # their time zone: when in the day hardly matters for a journal.
  def traded_at
    day = Date.iso8601(params[:traded_on].to_s) rescue nil
    return Time.current if day.nil? || day == Date.current

    Time.zone.local(day.year, day.month, day.day, 12)
  end

  def products_of(trades)
    keys = trades.map { |trade| [ trade.item_id, trade.series ] }.uniq
    # A product is the same item in either edition: its name as the reader's realm knows it.
    preferred = current_realm&.edition
    items = Item.where(id: keys.map(&:first).uniq).group_by(&:id)
      .transform_values { |rows| rows.min_by { |item| item.edition == preferred ? 0 : 1 } }
    keys.to_h do |item_id, series|
      item = items[item_id] || Item.new(id: item_id, edition: preferred || "retail")
      [ [ item_id, series ], Product.new(item, series) ]
    end
  end

  # The cheapest listing of each product held, on the reader's realm: what it would sell
  # against right now.
  def cheapest_on(realm, positions)
    held = positions.select { |position| position.stock.positive? }
    return {} if held.empty?

    ListedProduct.where(auction_house_id: realm.market_ids, item_id: held.map(&:item_id).uniq)
      .pluck(:item_id, :series, :min_price)
      .to_h { |item_id, series, price| [ [ item_id, series ], price ] }
  end

  def number_with_delimiter(number) = ActiveSupport::NumberHelper.number_to_delimited(number)
end
