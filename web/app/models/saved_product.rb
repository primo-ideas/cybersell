# A product in one of a player's lists, with the price they would buy at and a note.
class SavedProduct < AccountsRecord
  belongs_to :user
  belongs_to :list

  normalizes :note, with: ->(note) { note.strip.presence }

  validates :item_id, numericality: { only_integer: true, in: 1..999_999_999 }
  validates :series, format: { with: FollowedProducts::SERIES }
  validates :target_price, numericality: { only_integer: true, in: 1..MoneyInput::MAX }, allow_nil: true
  validates :note, length: { maximum: 500 }
  validate :list_of_the_same_player

  # As the cookie watchlist names it, so that both read the same.
  def target = target_price

  private

  def list_of_the_same_player
    errors.add(:list, "is not one of yours") if list && list.user_id != user_id
  end
end
