class Notification < ActiveRecord::Base
  belongs_to :product

  def self.sorted_notifications
    unseen_notifications = Notification.where('seen is null OR seen = false')

    sorted_notifications = unseen_notifications.select do |notification|
      notification.change_title && notification.change_title.include?('price')
    end.sort_by do |notification|
      notification.change_title.delete('_price').to_f
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
end
