class WatchlistsController < ApplicationController
  def show
    if signed_in?
      @lists = current_user.lists.to_a
      @list = @lists.find { |list| list.id.to_s == params[:list].to_s }
      @shown = AccountWatchlist.new(current_user, list: @list)
    else
      @shown = watchlist
    end
    @products = current_realm ? @shown.products(current_realm.markets) : []
    @at_target = current_realm ? @shown.at_target(current_realm.markets) : []
  end

  def update
    unless watchlist.toggle(params[:item_id], params[:series]) == false
      save_watchlist
    else
      flash[:alert] = "Your lists hold #{User::MAX_PRODUCTS} products at most: remove some first." if watchlist.account? && watchlist.full?
    end
    redirect_back_or_to watchlist_path, status: :see_other
  end

  # An empty field takes the target off. What cannot be read as an amount changes nothing.
  def target
    text = params[:target].to_s.strip
    target = MoneyInput.parse(text)
    if text.empty? || target
      watchlist.set_target(params[:item_id], params[:series], target)
      save_watchlist
    else
      flash[:alert] = "“#{text.first(30)}” is not an amount: write it like 12g 50s, 12.5 for gold, or 1.5k for 1,500 gold."
    end
    redirect_back_or_to watchlist_path, status: :see_other
  end

  private

  # An account saves as it goes: only the cookie needs writing.
  def save_watchlist
    return if watchlist.account?

    cookies[:watched] = cookie_options.merge(value: watchlist.to_cookie)
    cookies.delete(:watchlist, path: cookie_options[:path])
  end
end
