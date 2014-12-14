class ChangeAllVarcharToText < ActiveRecord::Migration
  def change
    %w(icon image_url title change_title row_css amazon_asin_number ebay_item_id).each do |column|
      change_column :notifications, column, :text
    end

    %w(url_page).each do |column|
      change_column :products, column, :text
    end
  end
end
