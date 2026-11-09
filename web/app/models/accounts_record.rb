# What players save: their account, lists, trades and preferences. These tables live in
# the site's own database, apart from the market data, which only the fetcher writes.
class AccountsRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { writing: :accounts, reading: :accounts }
end
