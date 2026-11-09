# A player's lists: created, renamed, reordered or deleted from the watchlist page.
class ListsController < ApplicationController
  before_action :require_user
  before_action :load_list, only: %i[update destroy]

  def create
    lists = current_user.lists
    if lists.count >= User::MAX_LISTS
      return redirect_to(watchlist_path, alert: "#{User::MAX_LISTS} lists at most: delete one first.")
    end

    list = lists.create(name: params[:name].to_s.first(100), position: lists.maximum(:position).to_i + 1)
    if list.persisted?
      redirect_to watchlist_path(list: list.id), status: :see_other
    else
      redirect_to watchlist_path, alert: "List not created: #{list.errors.full_messages.to_sentence.downcase}."
    end
  end

  def update
    if params.key?(:name) && !@list.update(name: params[:name].to_s.first(100))
      return redirect_to(watchlist_path(list: @list.id), alert: "Not renamed: #{@list.errors.full_messages.to_sentence.downcase}.")
    end
    move(params[:move]) if %w[up down].include?(params[:move])
    redirect_to watchlist_path(list: @list.id), status: :see_other
  end

  # What it holds goes with it. The last list stays: starring a product needs one.
  def destroy
    if current_user.lists.count <= 1
      return redirect_to(watchlist_path(list: @list.id), alert: "Your last list cannot be deleted.")
    end

    count = @list.saved_products.count
    @list.destroy!
    redirect_to watchlist_path, status: :see_other,
      notice: "“#{@list.name}” deleted#{", with the #{"product".pluralize(count)} it held" if count.positive?}."
  end

  private

  def load_list
    @list = current_user.lists.find(params[:id])
  end

  # Swaps it with its neighbour, numbering every list again so that ties cannot stick.
  def move(direction)
    lists = current_user.lists.to_a
    index = lists.index(@list)
    other = direction == "up" ? index - 1 : index + 1
    return unless other.between?(0, lists.size - 1)

    lists[index], lists[other] = lists[other], lists[index]
    List.transaction do
      lists.each_with_index { |list, position| list.update_columns(position: position) }
    end
  end
end
