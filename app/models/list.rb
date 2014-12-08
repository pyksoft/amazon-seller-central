class List < ActiveRecord::Base

  def self.compare_count
    List.find_by_kind(:compare_count).title.to_i
  end

  def self.update_compare_count(count = nil)
    compare_count_attr = List.find_by_kind(:compare_count)
    compare_count_attr.update_attribute :title,"#{count || (compare_count_attr.title.to_i + 1)}"
  end
end
