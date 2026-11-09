require "test_helper"

class TradeLedgerTest < ActiveSupport::TestCase
  def trade(side, quantity, unit_price, day: 1, item_id: 1, series: "")
    Trade.new(side: side, quantity: quantity, unit_price: unit_price, traded_at: NOW + day.days, item_id: item_id, series: series)
  end

  def position(*trades) = TradeLedger.new(trades).positions.first

  test "what is held costs the average of what was paid" do
    held = position(trade("buy", 10, 100), trade("buy", 10, 200, day: 2))

    assert_equal 20, held.stock
    assert_equal 3_000, held.cost
    assert_equal 150, held.average_cost
    assert_equal 0, held.realised
  end

  test "a sale takes out units at their average cost, and pays the auction house's cut" do
    sold = position(trade("buy", 10, 100), trade("buy", 10, 200, day: 2), trade("sell", 5, 400, day: 3))

    assert_equal 15, sold.stock
    assert_equal 2_250, sold.cost
    assert_equal 150, sold.average_cost
    assert_equal 1_900, sold.received
    # 5 × 400, less 5%, less 5 × 150.
    assert_equal 1_150, sold.realised
  end

  test "trades count in the order they happened, whatever the order given" do
    sold = position(trade("sell", 5, 400, day: 3), trade("buy", 10, 100, day: 1))

    assert_equal 5, sold.stock
    assert_equal 0, sold.unmatched
    assert_equal 1_400, sold.realised
  end

  test "units sold with no purchase written down have no known cost, and make no profit" do
    sold = position(trade("buy", 2, 100), trade("sell", 5, 1_000, day: 2))

    assert_equal 0, sold.stock
    assert_equal 3, sold.unmatched
    assert_equal 4_750, sold.received
    # Only the 2 units whose cost is known: 2 × 1,000, less 5%, less 200.
    assert_equal 1_700, sold.realised
  end

  test "a loss is a loss" do
    assert_equal(-525, position(trade("buy", 5, 200), trade("sell", 5, 100, day: 2)).realised)
  end

  test "what is held is worth what it would sell for now, after the cut" do
    held = position(trade("buy", 10, 100))

    assert_equal 1_900, held.value_at(200)
    assert_equal 900, held.unrealised_at(200)
    assert_nil held.value_at(nil)
    assert_nil held.unrealised_at(nil)
  end

  test "nothing held is worth nothing and has no average cost" do
    closed = position(trade("buy", 1, 100), trade("sell", 1, 200, day: 2))

    assert_nil closed.average_cost
    assert_nil closed.value_at(500)
  end

  test "products are kept apart, a caged pet by its species, the latest traded first" do
    ledger = TradeLedger.new([
      trade("buy", 1, 100, item_id: 82800, series: "pet:39", day: 1),
      trade("buy", 1, 200, item_id: 82800, series: "pet:40", day: 3),
      trade("buy", 1, 300, item_id: 2589, day: 2)
    ])

    assert_equal [ [ 82800, "pet:40" ], [ 2589, "" ], [ 82800, "pet:39" ] ], ledger.positions.map { |held| [ held.item_id, held.series ] }
    assert_equal 200, ledger.position_of(82800, "pet:40").cost
    assert_nil ledger.position_of(1, "")
  end

  test "totals add up every product" do
    ledger = TradeLedger.new([
      trade("buy", 1, 100), trade("sell", 1, 200, day: 2),
      trade("buy", 1, 1_000, item_id: 2), trade("sell", 1, 2_000, item_id: 2, day: 2)
    ])

    assert_equal 90 + 900, ledger.realised
    assert_equal 1_100, ledger.spent
    assert_equal 190 + 1_900, ledger.received
  end
end
