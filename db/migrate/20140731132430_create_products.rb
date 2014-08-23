class CreateProducts < ActiveRecord::Migration
  def change
    create_table :products do |t|

      t.string :ebay_item_id,:amazon_asin_number
      t.text :title,:image_url
      t.float :old_price,:new_price
      t.boolean :prime,:seen

      t.timestamps
    end
  end
end