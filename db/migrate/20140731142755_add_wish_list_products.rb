class AddWishListProducts < ActiveRecord::Migration
  def up
    p Time.now
    count = 0
    File.open(Dir.pwd + '/config/initializers/files/WishListItemIds.txt', 'r') do |f|
      f.each_line do |products_numbers|
        begin
          amazon_asin_number,ebay_item_id = products_numbers.chomp.split(',')
          p count if count.size % 50 == 0
          sleep(2) if count % 5 == 0
          amazon_item = Amazon::Ecs.item_lookup(amazon_asin_number,
                                                :response_group => 'ItemAttributes,Images',
                                                :id_type => 'ASIN',
                                                'ItemSearch.Shared.ResponseGroup' => 'Large').items.first
          if amazon_item
            medium_image = amazon_item.get_element('MediumImage').get('URL')
            price = amazon_item.get_element('Offers/Offer')

            Product.create! amazon_asin_number: amazon_asin_number,
                            ebay_item_id: ebay_item_id,
                            title: amazon_item.get('ItemAttributes/Title'),
                            image_url: (medium_image ||
                                amazon_item.get('ImageSets/ImageSet/MediumImage/URL')),
                            old_price: price && price.get_element('OfferListing/Price').get('Amount').to_f / 100,
                            prime: price && amazon_item.get_element('Offers/Offer').get_element('OfferListing').get('IsEligibleForSuperSaverShipping'),
                            seen: false
          end
          count += 1
        rescue
          p 'fails'
          sleep 5
        end
      end
    end
    p Time.now
  end
end