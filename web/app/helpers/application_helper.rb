module ApplicationHelper
  # Where a game's pages start.
  def game_path(game) = public_send("#{game.slug.underscore}_path")
end
