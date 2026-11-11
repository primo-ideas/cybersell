# Proves an address belongs to the player before any alert goes to it.
class AccountMailer < ApplicationMailer
  def email_confirmation(user)
    @user = user
    @url = confirm_email_account_url(token: user.generate_token_for(:email_confirmation))
    mail to: user.email, subject: "Confirm your address for Ludeal alerts"
  end
end
