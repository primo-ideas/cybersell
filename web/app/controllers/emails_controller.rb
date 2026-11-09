# The address alerts go to: set in the account, confirmed from a link sent to it, and
# stopped from a link in every alert, without having to sign in.
class EmailsController < ApplicationController
  before_action :require_user, only: %i[update resend]
  # Links already sent keep working, even if the site stopped sending emails since.
  before_action :require_alerts, only: %i[update resend]
  # The token in the link is what proves who is asking, and mail clients post without
  # a form of this site.
  skip_forgery_protection only: :stop_alerts
  rate_limit to: 5, within: 10.minutes, only: %i[update resend], with: -> { redirect_to account_path(anchor: "alerts"), alert: "Too many emails asked for: wait a few minutes." }

  def update
    user = current_user
    if user.update(email: params[:email].to_s.first(254))
      if user.email
        AccountMailer.email_confirmation(user).deliver_now
        redirect_to account_path(anchor: "alerts"), notice: "Check your inbox: a link there confirms #{user.email}."
      else
        redirect_to account_path(anchor: "alerts"), notice: "Address removed: no more alerts by email."
      end
    else
      redirect_to account_path(anchor: "alerts"), alert: "“#{params[:email].to_s.first(60)}” is not an email address."
    end
  end

  def resend
    user = current_user
    if user.email && !user.email_confirmed?
      AccountMailer.email_confirmation(user).deliver_now
      redirect_to account_path(anchor: "alerts"), notice: "Sent again to #{user.email}."
    else
      redirect_to account_path(anchor: "alerts")
    end
  end

  def confirm
    user = User.find_by_token_for(:email_confirmation, params[:token].to_s)
    if user
      user.update_columns(email_confirmed_at: Time.current, updated_at: Time.current)
      redirect_to(signed_in? ? account_path(anchor: "alerts") : root_path, notice: "#{user.email} is confirmed: alerts will go there.")
    else
      redirect_to(signed_in? ? account_path(anchor: "alerts") : root_path, alert: "That link has expired, or the address changed since. Ask for a new one from your account.")
    end
  end

  # From the link in an alert: a page with a button, as mail scanners follow links.
  def unsubscribe
    @user = User.find_by_token_for(:unsubscribe, params[:token].to_s)
    @token = params[:token].to_s
  end

  # The button, and mail clients' own unsubscribe (RFC 8058), which posts here directly.
  def stop_alerts
    user = User.find_by_token_for(:unsubscribe, params[:token].to_s)
    user&.update_columns(alerts_enabled: false, updated_at: Time.current)
    respond_to do |format|
      format.html { redirect_to root_path, notice: user ? "No more alerts by email. Turn them back on from your account." : "That link is no longer valid." }
      format.any { head :ok }
    end
  end

  private

  def require_alerts
    head :not_found unless TargetAlerts.available?
  end
end
