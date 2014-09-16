class ChangeProductToImageNotification < ActiveRecord::Migration
  def change
    change_table :notifications do |t|
      t.string :image_url
      t.references :list
    end

    Notification.reset_column_information

    Notification.all.each do |n|
      if n.product
        n.update_attribute :image_url, n.product.image_url
      end
    end

    change_table :products do |t|
      t.remove :new_price,:seen
      t.rename :old_price, :amazon_price
    end
  end
end
