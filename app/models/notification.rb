class Notification < ActiveRecord::Base
  belongs_to :product

  def self.sorted_notifications
    unseen_notifications = Notification.where('seen is null OR seen = false')
    sorted_notifications = unseen_notifications.select{|notification| notification.change_title.include?('price')}.sort_by do |price_title|
      price_title.delete('_price').to_f
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
end
