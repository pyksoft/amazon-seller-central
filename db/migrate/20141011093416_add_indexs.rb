class AddIndexs < ActiveRecord::Migration
  def change
    add_index :products,:amazon_asin_number
    add_index :notifications,:seen
  end
end
