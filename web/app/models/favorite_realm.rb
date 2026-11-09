# A realm the player keeps at hand, to switch to it from the realm picker.
class FavoriteRealm < AccountsRecord
  MAX = 20

  belongs_to :user

  validates :region, inclusion: { in: Realm::REGION_NAMES.keys }
  validates :slug, presence: true, length: { maximum: 100 }
end
