class AddUrlToProducts < ActiveRecord::Migration
  def change
    add_column :products, :url_page, :string
  end
end
