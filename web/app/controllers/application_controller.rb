class ApplicationController < ActionController::Base
  helper_method :current_realm, :watchlist, :watchlist_hits, :current_user, :signed_in?

  # The fetcher creates the schema on its first run, which may not have happened yet.
  rescue_from ActiveRecord::StatementInvalid do |error|
    raise error unless error.cause.is_a?(PG::UndefinedTable)

    # The header shows the realm, from a table that is missing as well.
    @current_realm = nil
    Current.session = nil
    render "errors/not_ready", status: :service_unavailable
  end

  # Times show in the player's time zone once they have chosen one, else Paris time.
  around_action :use_time_zone

  private

  def use_time_zone(&)
    Time.use_zone(current_user&.time_zone || Time.zone_default, &)
  end

  # Accounts

  def current_user
    resume_session
    Current.user
  end

  def signed_in? = !current_user.nil?

  def resume_session
    return if @session_resumed

    @session_resumed = true
    id = cookies.signed[:session_id]
    Current.session = id.is_a?(Integer) ? Session.includes(:user).find_by(id: id) : nil
    # For the account page to say when each browser was last seen, roughly.
    Current.session&.touch if Current.session && Current.session.updated_at < 1.hour.ago
  end

  def require_user
    return if signed_in?

    redirect_to sign_in_path(return_to: request.get? ? request.fullpath : nil)
  end

  # A new session in a new Rails session, so that nothing set before signing in carries
  # over to the account.
  def start_session_for(user)
    reset_session
    session_record = user.sessions.create!(user_agent: request.user_agent.to_s.first(255), ip_address: request.remote_ip)
    @session_resumed = true
    Current.session = session_record
    cookies.signed[:session_id] = cookie_options.merge(value: session_record.id, httponly: true)
  end

  def end_session
    Current.session&.destroy
    Current.session = nil
    cookies.delete(:session_id, path: cookie_options[:path])
    reset_session
  end

  def tracked_markets
    @tracked_markets ||= AuctionHouse.tracked.to_a
  end

  # The realm of the page, or else the one the player picked last.
  def current_realm
    return @current_realm if defined?(@current_realm)

    @current_realm = remembered_realm
  end

  # An account remembers it on every device; a browser, in a cookie.
  def remembered_realm
    return @remembered_realm if defined?(@remembered_realm)

    @remembered_realm = current_user&.realm || cookie_realm
  end

  def cookie_realm
    region, slug = cookies[:realm].to_s.split("/", 2)
    slug.present? ? Realm.find_by_route(region, slug) : nil
  end

  # The realm in the address, which becomes the player's: the next visit starts there.
  def load_realm
    @current_realm = find_realm
    current_user&.remember_realm(@current_realm)
    unless cookie_realm == @current_realm
      cookies[:realm] = cookie_options.merge(value: "#{@current_realm.region}/#{@current_realm.slug}")
    end
  end

  def find_realm
    Realm.find_by_route(params[:region], params[:realm]) or raise ActiveRecord::RecordNotFound
  end

  # A signed-in player's lists, or else what this browser keeps in a cookie.
  def watchlist
    @watchlist ||= if signed_in?
      AccountWatchlist.new(current_user)
    else
      cookie_watchlist
    end
  end

  def cookie_watchlist
    Watchlist.new(cookies[:watched], legacy: cookies[:watchlist])
  end

  # How many products followed have come down to their target on the reader's realm: the
  # header says so from any page. Nothing is looked up without a target.
  def watchlist_hits
    @watchlist_hits ||= current_realm && watchlist.targets? ? watchlist.at_target(current_realm.markets).size : 0
  end

  # Other sites may share the domain: this one's cookies stay within its path.
  def cookie_options
    { expires: 1.year, same_site: :lax, path: request.script_name.presence || "/", secure: request.ssl? }
  end

  # Only a path of this site: never somewhere else a crafted link would send the player.
  def safe_return_path(path)
    path = path.to_s
    path if path.start_with?("/") && !path.start_with?("//") && !path.include?("\\") && path.length <= 500
  end
end
