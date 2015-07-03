class Notification < ActiveRecord::Base
  belongs_to :product

  def self.sorted_notifications
    unseen_notifications = Notification.where('seen is null OR seen = false').includes(:product)

    sorted_notifications = unseen_notifications.select do |notification|
      notification.change_title && notification.change_title.include?('price')
    end.sort_by do |notification|
      notification.change_title.delete('_price').to_f.abs
    end.reverse
    (unseen_notifications - sorted_notifications).sort_by do |notification|
      case notification.change_title
        when 'amazon_unavailable'
          0
        when 'ebay_unavailable'
          1
        when 'false_prime'
          2
        when 'true_prime'
          3
        else
          4
      end
    end + sorted_notifications
  end

  def change_accepted
    if product
      result = product.change_accepted(change_title)
      destroy! unless result[:errs].present?
      result
    else
      { :errs => I18n.t('messages.not_exists_product') }
    end
  end

  def self.delete_old_notifications
    if Notification.count > 7000
      ids = Notification.where(:seen => true).limit(2000).pluck(:id)
      Notification.where(:id => ids).delete_all
    end
  end


  def self.notifications_json
    notifications = sorted_notifications
    notifications = create(:text => 'Empty Notification') if notifications.empty?

    {
        :notifications => notifications.inject([]) do |arr, notification|
          arr << notification.values_at(%i[id text image_url row_css change_title skip_accepted]).merge(
              :product => {
                  :title => notification.title || notification.product.try(:title),
                  :ebay_item_id => notification.ebay_item_id || notification.product.try(:ebay_item_id),
                  :amazon_asin_number => notification.amazon_asin_number || notification.product.try(:amazon_asin_number),
                  :amazon_url => notification.product.try(:item_url) || Product.new(notification.values_at(:amazon_asin_number)).item_url
              }
          )
        end,
        :progress_count => get_progress_count,
        :compare_title => 'Wishlist Compare'
        # :compare_title => ((List.compare_count % 2).zero? ? 'Prime' : 'Wishlist') + ' Compare'
    }
  end
end