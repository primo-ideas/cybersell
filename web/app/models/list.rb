# A named list of products a player follows: what they farm, what they craft with, what
# they flip. Every account has at least one.
class List < AccountsRecord
  belongs_to :user
  has_many :saved_products

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, length: { maximum: 40 }, uniqueness: { scope: :user_id, case_sensitive: false }
end
