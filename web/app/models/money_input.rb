# An amount as a player types it, in copper: "12g 50s", "12g50s3c", "1,234g", "12.5g" or
# "12,5g", thousands of gold as players write them in chat, "15k" or "1.5k", or a plain
# number of gold, "12.5" or "12,5". Anything else is nil, and so is zero.
module MoneyInput
  COPPER = { "g" => 10_000, "s" => 100, "c" => 1 }.freeze
  # Far above anything sold, and well within a bigint.
  MAX = 10**12
  COINS = /\A(?:(\d+)g)?(?:(\d+)s)?(?:(\d+)c)?\z/
  GOLD = /\A(\d{1,8})(?:[.,](\d{1,4}))?\z/
  # A comma followed by three digits separates thousands, as in "1,234g".
  DECIMAL_GOLD = /\A(\d{1,8})(?:\.|,(?!\d{3}g))(\d{1,4})g\z/
  # Two decimals at most, so that "1,500k" is not read as 1.5k.
  THOUSANDS = /\A(\d{1,5})(?:[.,](\d{1,2}))?k\z/

  module_function

  def parse(text)
    text = text.to_s.downcase.gsub(/[[:space:]]/, "")
    return if text.empty? || text.length > 30

    copper = if (match = text.match(THOUSANDS))
      gold(match) * 1_000 * COPPER["g"]
    elsif (match = text.match(DECIMAL_GOLD))
      gold(match) * COPPER["g"]
    elsif text.match?(/[gsc]/)
      coins(text.delete(","))
    elsif (match = text.match(GOLD))
      gold(match) * COPPER["g"]
    end
    copper = copper&.round
    copper if copper&.positive? && copper <= MAX
  end

  def coins(text)
    match = text.match(COINS)
    return unless match && match.captures.any?

    match.captures.zip(COPPER.values).sum { |amount, unit| amount.to_i * unit }
  end

  # Whole and decimal parts, exactly.
  def gold(match) = match[1].to_r + (match[2] ? "0.#{match[2]}".to_r : 0)
end
