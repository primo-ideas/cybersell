# The front page: the games the site covers.
class GamesController < ApplicationController
  def index
    @games = Game.all
  end
end
