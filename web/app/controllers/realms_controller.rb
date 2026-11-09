class RealmsController < ApplicationController
  before_action :load_realm, only: %i[show deals]

  # Straight to a returning player's realm.
  def home
    return redirect_to realm_path(remembered_realm.region, remembered_realm.slug) if remembered_realm

    index
    render :index
  end

  # Where a player picks their realm. With an item, picking leads to its page there.
  def index
    @realms = Realm.followed(tracked_markets).to_a
    @query = params[:q].to_s.delete("\0").strip.first(100)
    @item = Item.find_by(id: params[:item].to_s[/\A\d{1,9}\z/])
    @variant = params[:variant].to_s.delete("\0").presence if @item
    @own_realms = own_realms(@realms) if signed_in?
  end

  def show
    markets = current_realm.markets
    @listing = MarketListing.new(markets,
      query: params[:q], item_class: params[:item_class], quality: params[:quality],
      page: params[:page], **listing_order)
    @movers = MarketMovers.new(markets)
    @item_classes = Rails.cache.fetch("item_classes", expires_in: 1.hour) do
      Item.where.not(item_class: nil).distinct.pluck(:item_class)
        .sort_by { |name| ActiveSupport::Inflector.transliterate(name) }
    end
  end

  def deals
    thresholds = signed_in? ? { min_margin: current_user.deal_min_margin_fraction, min_profit: current_user.deal_min_profit } : {}
    @deals = MarketDeals.new(current_realm.markets, sort: params[:sort], **thresholds)
  end

  private

  # What the reader sorted by, or else what their account prefers.
  def listing_order
    return { sort: params[:sort], dir: params[:dir] } if params[:sort].present? || !signed_in?

    { sort: current_user.listing_sort, dir: params[:dir].presence || current_user.listing_dir }
  end

  # The realms a player keeps at hand, then those their characters live on, each once and
  # only if the site follows it: [realm, favourite?, characters there].
  def own_realms(followed)
    by_route = followed.index_by { |realm| [ realm.region, realm.slug ] }
    characters = current_user.characters.group_by { |character| [ character.region, character.realm_slug ] }
    favorites = current_user.favorite_realms.map { |favorite| [ favorite.region, favorite.slug ] }
    (favorites | characters.keys).filter_map do |route|
      realm = by_route[route] or next
      [ realm, favorites.include?(route), characters.fetch(route, []) ]
    end
  end
end
