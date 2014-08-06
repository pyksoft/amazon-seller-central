class CreateNotifications < ActiveRecord::Migration
  def change
    create_table :notifications do |t|
      t.text :text
      t.references :product
      t.datetime :created_at
      t.boolean :seen
    end
  end
end
