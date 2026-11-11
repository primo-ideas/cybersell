# A game the site has prices for. Each lives under its slug: /wow.
Game = Data.define(:slug, :name, :summary) do
  def self.all = Game::ALL

  def self.find(slug) = Game::ALL.find { |game| game.slug == slug }
end

Game::ALL = [
  Game.new(
    slug: "wow",
    name: "World of Warcraft",
    summary: "Auction house prices, realm by realm: trends, estimated sales and deals, about once an hour."
  )
].freeze
