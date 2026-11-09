# A character of the player, as Battle.net listed it when they last signed in.
class Character < AccountsRecord
  belongs_to :user

  # Nil when the site does not know that realm, or does not follow it.
  def realm = Realm.find_by_route(region, realm_slug)
end
