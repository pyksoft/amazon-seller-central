class AddTitles < ActiveRecord::Migration
  def change
    Product.all.each do |product|
      sleep 0.4
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
