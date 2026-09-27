class ApplicationController < ActionController::Base
  include Authentication
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def not_found
    head :not_found
  end
end
