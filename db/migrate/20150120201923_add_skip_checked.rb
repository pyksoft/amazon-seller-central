class AddSkipChecked < ActiveRecord::Migration
  def change
    change_table :notifications do |t|
      t.boolean :skip_accepted, :default => false
    end
  end
end
