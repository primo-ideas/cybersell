# Realms a player keeps at hand, from the star next to a realm's name.
class FavoriteRealmsController < ApplicationController
  before_action :require_user

  def toggle
    realm = Realm.find_by_route(params[:region], params[:slug]) or raise ActiveRecord::RecordNotFound
    favorites = current_user.favorite_realms
    existing = favorites.find_by(region: realm.region, slug: realm.slug)
    if existing
      existing.destroy!
    elsif favorites.count >= FavoriteRealm::MAX
      flash[:alert] = "#{FavoriteRealm::MAX} favourite realms at most: remove one first."
    else
      favorites.create!(region: realm.region, slug: realm.slug)
    end
    redirect_back_or_to realm_path(realm.region, realm.slug), status: :see_other
  end
end
