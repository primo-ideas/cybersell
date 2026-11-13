# One row per edition: Classic and retail share ids, not always names or levels. Always
# looked up with the edition of the realm it is seen from.
class Item < ApplicationRecord
  # The table's key is (edition, id): with the edition always given, `id` is enough, and
  # stays a number rather than a pair everywhere an item is linked to.
  self.primary_key = "id"

  scope :of, ->(edition) { where(edition: edition) }

  # `name` stays empty until the fetcher has looked the item up, and for good when
  # the item API does not know it.
  def display_name = name.presence || "Item ##{id}"
end
