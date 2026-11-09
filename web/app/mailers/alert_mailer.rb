# The products that just came down to the price a player would buy at.
class AlertMailer < ApplicationMailer
  def targets_reached(user, realm, rows)
    @user = user
    @realm = realm
    @rows = rows
    @watchlist = AccountWatchlist.new(user)
    @unsubscribe_url = unsubscribe_url(token: user.generate_token_for(:unsubscribe))
    # One click from the mail client stops them, without opening the site (RFC 8058).
    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    subject = rows.one? ? "#{rows.first.display_name} is at your target price on #{realm.name}" :
      "#{rows.size} products are at your target price on #{realm.name}"
    mail to: user.email, subject: subject
  end
end
