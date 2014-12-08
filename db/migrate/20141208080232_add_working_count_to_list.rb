class AddWorkingCountToList < ActiveRecord::Migration
  def change
    List.create!(:kind => :compare_count, :title => 2)
    add_index :lists, :kind
  end
end
