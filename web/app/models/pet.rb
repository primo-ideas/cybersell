# One row per edition, as for items.
class Pet < ApplicationRecord
  self.primary_key = "species_id"

  scope :of, ->(edition) { where(edition: edition) }
end
