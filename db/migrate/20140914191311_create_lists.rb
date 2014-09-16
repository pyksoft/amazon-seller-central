class CreateLists < ActiveRecord::Migration
  def change
    create_table :lists do |t|
      t.string :kind,:title
    end
  end
end
