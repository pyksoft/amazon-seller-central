class AddNotificationsColumnsAmazonEbay < ActiveRecord::Migration
  def change
    change_table :notifications do |t|
      t.string :amazon_asin_number,:ebay_item_id,:title
    end
  end
end
