class AddWishListProducts < ActiveRecord::Migration
  def up
    p Time.now
    count = 0
    File.open(Dir.pwd + '/config/initializers/files/WishListItemIds.txt', 'r') do |f|
      f.each_line do |item_id|
        p count if count.size % 50 == 0
        sleep(4) if count % 4 == 0
        amazon_item = Amazon::Ecs.item_lookup(item_id.chomp,
                                              :response_group => 'ItemAttributes,Images',
                                              :id_type => 'ASIN',
                                              'ItemSearch.Shared.ResponseGroup' => 'Large').items.first
        if amazon_item
          medium_image = amazon_item.get_element('MediumImage').get('URL')
          price = amazon_item.get_element('Offers/Offer')


          Product.create! item_id: item_id.chomp,
                          title: amazon_item.get('ItemAttributes/Title'),
                          image_url: (medium_image ||
                              amazon_item.get('ImageSets/ImageSet/MediumImage/URL')),
                          old_price: price && price.get_element('OfferListing').get('SalePrice/Amount').to_f / 100,
                          prime: price && amazon_item.get_element('Offers/Offer').get_element('OfferListing').get('IsEligibleForSuperSaverShipping'),
                          seen: false
        end
        count += 1
      end
    end
    p Time.now
  end
end