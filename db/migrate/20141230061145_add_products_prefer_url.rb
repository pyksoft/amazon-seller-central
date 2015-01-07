class AddProductsPreferUrl < ActiveRecord::Migration
  def change
    change_table :products do |t|
      t.boolean :prefer_url, :default => false
    end
  end
end
