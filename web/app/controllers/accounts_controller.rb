# A player's account: their preferences, characters, favourite realms, email for alerts
# and the browsers signed in. They can take a copy of all of it, or delete it.
class AccountsController < ApplicationController
  before_action :require_user

  def show
    @user = current_user
    @sessions = @user.sessions.order(updated_at: :desc)
    @favorites = @user.favorite_realms.filter_map { |favorite| Realm.find_by_route(favorite.region, favorite.slug) }
  end

  def update
    @user = current_user
    attributes = params.fetch(:user, {}).permit(:time_zone, :chart_period, :listing_sort, :listing_dir, :deal_min_margin, :alerts_enabled)
    attributes[:listing_dir] = attributes[:listing_dir].presence if attributes.key?(:listing_dir)
    if params.dig(:user, :deal_min_profit)
      text = params[:user][:deal_min_profit].to_s.strip
      attributes[:deal_min_profit] = text.empty? || text == "0" ? 0 : MoneyInput.parse(text) || -1
    end

    if @user.update(attributes)
      redirect_to account_path(anchor: params[:section].to_s[/\A[a-z-]{1,20}\z/]), notice: "Saved."
    else
      redirect_to account_path, alert: @user.errors.full_messages.to_sentence
    end
  end

  def export
    send_data JSON.pretty_generate(current_user.export), type: "application/json",
      filename: "wow-trading-#{current_user.battletag.parameterize}-#{Date.current.iso8601}.json"
  end

  # Everything goes, at once: lists, trades, preferences and every browser signed in.
  def destroy
    unless params[:confirm] == "1"
      return redirect_to(account_path(anchor: "delete"), alert: "Tick the box to confirm that your account should be deleted.")
    end

    user = current_user
    end_session
    user.destroy!
    redirect_to root_path, notice: "Your account and everything in it are deleted."
  end

  def sign_out_session
    current_user.sessions.where.not(id: Current.session.id).find(params[:id]).destroy
    redirect_to account_path(anchor: "sessions"), notice: "That browser is signed out."
  end

  def sign_out_other_sessions
    current_user.sessions.where.not(id: Current.session.id).destroy_all
    redirect_to account_path(anchor: "sessions"), notice: "Every other browser is signed out."
  end
end
