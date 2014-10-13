class ChangeListIdName < ActiveRecord::Migration
  def change
    change_table :notifications do |t|
      t.string :change_title,:row_css
    end
  end
end
