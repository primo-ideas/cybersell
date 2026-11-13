# A game the site has prices for, as the front page offers them. Each starts at the path
# its slug names: wow_path, wow_classic_path. Mists of Pandaria Classic shares the World of
# Warcraft section, but players look for it as a game of its own.
Game = Data.define(:slug, :name, :summary) do
  def self.all = Game::ALL

  def self.find(slug) = Game::ALL.find { |game| game.slug == slug }
end

Game::ALL = [
  Game.new(
    slug: "wow",
    name: "World of Warcraft",
    summary: "Auction house prices, realm by realm: trends, estimated sales and deals, about once an hour."
  ),
  Game.new(
    slug: "wow-classic",
    name: "WoW: Mists of Pandaria Classic",
    summary: "The same for the auction houses of Mists of Pandaria Classic realms, in every region."
  )
].freeze
