class NotificationsController < ApplicationController
  respond_to :json
  before_filter :init_headers

  def init_headers
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS'
    headers['Access-Control-Allow-Headers'] = 'X-Requested-With, X-Prototype-Version'
  end

  def index
    @notifications = Notification.sorted_notifications
    respond_with(@notifications)
  end

  def change_accepted
    id = params.permit(:id)[:id]
    response = if id.present?
                 Notification.find(id).change_accepted
               else
                 { :errs => I18n.t('messages.not_exists_notifications') }
               end
    render({ :json => response})
  end
end
