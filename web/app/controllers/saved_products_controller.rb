# The note on a product a player follows, and which of their lists holds it.
class SavedProductsController < ApplicationController
  before_action :require_user

  def update
    saved = current_user.saved_products.find(params[:id])
    attributes = {}
    attributes[:note] = params[:note].to_s.first(500) if params.key?(:note)
    attributes[:list] = current_user.lists.find(params[:list_id]) if params[:list_id].present?

    unless saved.update(attributes)
      flash[:alert] = saved.errors.full_messages.to_sentence
    end
    redirect_back_or_to watchlist_path, status: :see_other
  end
end
