class NotificationsController < ApplicationController
  respond_to :json
  before_filter :init_headers

  def init_headers
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS'
    headers['Access-Control-Allow-Headers'] = 'X-Requested-With, X-Prototype-Version'
  end

  def index
    @notifications = Notification.where('seen is null OR seen = false')
    respond_with(@notifications)
  end
end
