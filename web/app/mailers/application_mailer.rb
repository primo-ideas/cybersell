class ApplicationMailer < ActionMailer::Base
  layout "mailer"
  helper MoneyHelper, ProductsHelper, RealmsHelper
end
