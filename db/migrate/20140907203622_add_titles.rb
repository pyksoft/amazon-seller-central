class AddTitles < ActiveRecord::Migration
  def change
    Product.all.each_with_index do |product,i|
      sleep 0.5
      p i
      amazon_item = Amazon::Ecs.item_lookup(product.amazon_asin_number,
                                            :response_group => 'ItemAttributes,Images',
                                            :id_type => 'ASIN',
                                            'ItemSearch.Shared.ResponseGroup' => 'Large').items.first
      if amazon_item
        product.update_attribute :title,amazon_item.get('ItemAttributes/Title')
      end
    end
  end
end
