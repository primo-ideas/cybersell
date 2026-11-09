# A purchase or a sale a player writes down in their journal: a quantity of a product at
# a unit price, on a realm. The price of a sale is what it was listed at, before the
# auction house takes its cut.
class Trade < AccountsRecord
  SIDES = %w[buy sell].freeze
  # A stack is 1,000 at most in game: this leaves room for several, and none for typos
  # in the billions.
  MAX_QUANTITY = 1_000_000

  belongs_to :user

  normalizes :note, with: ->(note) { note.strip.presence }

  validates :item_id, numericality: { only_integer: true, in: 1..999_999_999 }
  validates :series, format: { with: FollowedProducts::SERIES }
  validates :side, inclusion: { in: SIDES }
  validates :quantity, numericality: { only_integer: true, in: 1..MAX_QUANTITY }
  validates :unit_price, numericality: { only_integer: true, in: 1..MoneyInput::MAX }
  validates :region, inclusion: { in: Realm::REGION_NAMES.keys }
  validates :realm_slug, presence: true, length: { maximum: 100 }
  validates :traded_at, presence: true
  validates :note, length: { maximum: 200 }
  validate :not_in_the_future

  def buy? = side == "buy"

  def sell? = side == "sell"

  def total = unit_price * quantity

  private

  def not_in_the_future
    errors.add(:traded_at, "is in the future") if traded_at && traded_at > 1.hour.from_now
  end
end
