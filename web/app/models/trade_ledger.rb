# What a player's journal adds up to, product by product: what they still hold, what it
# cost them, and what they made selling. Each sale takes units out at the average price
# paid for those held at the time. Units sold beyond what the journal says was bought
# have no known cost: they are counted apart rather than as pure profit.
class TradeLedger
  Position = Struct.new(:item_id, :series, :bought, :spent, :sold, :received, :stock, :cost, :realised,
    :unmatched, :last_traded_at, keyword_init: true) do
    def average_cost = stock.positive? ? cost.fdiv(stock).round : nil

    # What selling everything held at this unit price would bring, after the cut.
    def value_at(price) = price && stock.positive? ? (price * stock * (1 - Flip::AUCTION_HOUSE_CUT)).floor : nil

    def unrealised_at(price) = value_at(price)&.-(cost)
  end

  def initialize(trades)
    @trades = trades
  end

  # The most recently traded first.
  def positions
    @positions ||= @trades.group_by { |trade| [ trade.item_id, trade.series ] }.map { |(item_id, series), trades|
      position(item_id, series, trades.sort_by { |trade| [ trade.traded_at, trade.id.to_i ] })
    }.sort_by { |position| [ -position.last_traded_at.to_i, position.item_id, position.series ] }
  end

  def position_of(item_id, series) = positions.find { |position| position.item_id == item_id && position.series == series }

  def realised = positions.sum(&:realised)

  def received = positions.sum(&:received)

  def spent = positions.sum(&:spent)

  def empty? = @trades.empty?

  private

  def position(item_id, series, trades)
    totals = { bought: 0, spent: 0, sold: 0, received: 0, stock: 0, cost: 0, realised: 0, unmatched: 0 }
    trades.each do |trade|
      if trade.buy?
        totals[:bought] += trade.quantity
        totals[:spent] += trade.total
        totals[:stock] += trade.quantity
        totals[:cost] += trade.total
      else
        proceeds = (trade.total * (1 - Flip::AUCTION_HOUSE_CUT)).floor
        matched = [ trade.quantity, totals[:stock] ].min
        matched_cost = totals[:stock].positive? ? (totals[:cost] * matched).fdiv(totals[:stock]).round : 0
        totals[:sold] += trade.quantity
        totals[:received] += proceeds
        totals[:realised] += (proceeds * matched).fdiv(trade.quantity).round - matched_cost
        totals[:unmatched] += trade.quantity - matched
        totals[:stock] -= matched
        totals[:cost] -= matched_cost
      end
    end
    Position.new(item_id: item_id, series: series, last_traded_at: trades.last.traded_at, **totals)
  end
end
