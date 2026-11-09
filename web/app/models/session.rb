# A browser signed in to an account. Its id travels in a signed cookie.
class Session < AccountsRecord
  belongs_to :user
end
