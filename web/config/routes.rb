Rails.application.routes.draw do
  # run.ps1 polls this to know when the site is up.
  get "up" => "rails/health#show", as: :rails_health_check

  # The games the site covers. Each has a section of its own under its short name.
  root "games#index"

  # Accounts: signing in is with Battle.net only, so no passwords live here.
  get "sign-in" => "sessions#new", as: :sign_in
  post "auth/battlenet" => "sessions#create", as: :auth_battlenet
  get "auth/battlenet/callback" => "sessions#callback", as: :auth_battlenet_callback
  post "auth/stub" => "sessions#stub", as: :auth_stub
  delete "sign-out" => "sessions#destroy", as: :sign_out

  resource :account, only: %i[show update destroy] do
    get :export
    delete "sessions/:id" => "accounts#sign_out_session", as: :session
    delete "sessions" => "accounts#sign_out_other_sessions", as: :other_sessions
    patch "email" => "emails#update", as: :email
    post "email/confirmation" => "emails#resend", as: :email_confirmation
    get "email/confirm" => "emails#confirm", as: :confirm_email
  end
  get "alerts/unsubscribe" => "emails#unsubscribe", as: :unsubscribe
  post "alerts/unsubscribe" => "emails#stop_alerts"

  # World of Warcraft.
  scope "wow" do
    get "/" => "realms#home", as: :wow

    get "realms" => "realms#index", as: :realms

    resource :watchlist, only: %i[show update]
    patch "watchlist/target" => "watchlists#target", as: :watchlist_target

    patch "favorites" => "favorite_realms#toggle", as: :favorite_realm
    resources :lists, only: %i[create update destroy]
    resources :saved_products, only: :update
    resources :trades, only: %i[index create destroy], path: "journal"

    # Everything is seen from a player's realm: /eu/hyjal, /eu/hyjal/items/2589. Mists of
    # Pandaria Classic realms are in regions of their own: /classic-eu/everlook.
    constraints region: /(classic-)?(us|eu|kr|tw)/, realm: %r{[^/.]+} do
      get ":region/:realm" => "realms#show", as: :realm
      get ":region/:realm/deals" => "realms#deals", as: :realm_deals
      get ":region/:realm/search" => "search#show", as: :realm_search
      get ":region/:realm/items/:id" => "items#show", as: :realm_item, constraints: { id: /\d{1,9}/ }
      get ":region/:realm/items/:id/tooltip" => "items#tooltip", as: :realm_item_tooltip, constraints: { id: /\d{1,9}/ }
    end

    # Addresses from when the site was organised by market, which bookmarks may still hold.
    get "search" => "legacy#search"
    get "markets" => "legacy#markets"
    get "markets/:id" => "legacy#market", constraints: { id: /\d{1,9}/ }
    get "markets/:id/deals" => "legacy#deals", constraints: { id: /\d{1,9}/ }
    get "markets/:market_id/items/:id" => "legacy#item", constraints: { market_id: /\d{1,9}/, id: /\d{1,9}/ }
  end
end
