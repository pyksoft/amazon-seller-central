class AddWishListProducts < ActiveRecord::Migration
  def up
    count = 0
    File.open(Dir.pwd + '/config/initializers/files/WishListItemIds.txt', 'r') do |f|
      f.each_line do |item_id|
        if count % 50 == 0
          sleep(3)
        end
        p count
        sleep 0.5
        amazon_item = $req.item_lookup(query: {
            'IdType' => 'ASIN',
            'ItemId' => item_id.chomp,
            'ItemSearch.Shared.ResponseGroup' => 'Large'
        }).to_h
        medium_image = amazon_item['ItemLookupResponse']['Items']['Item']['MediumImage']
        price = amazon_item['ItemLookupResponse']['Items']['Item']['Offers']['Offer']


        Product.create! item_id: item_id.chomp,
                        title: amazon_item['ItemLookupResponse']['Items']['Item']['ItemAttributes']['Title'],
                        image_url: (medium_image ||
                            [amazon_item['ItemLookupResponse']['Items']['Item']['ImageSets']['ImageSet']].flatten.first['MediumImage'])['URL'],
                        old_price: price && price['OfferListing']['Price']['Amount'].to_f / 100,
                        prime: price && amazon_item['ItemLookupResponse']['Items']['Item']['Offers']['Offer']['OfferListing']['IsEligibleForSuperSaverShipping'],
                        seen: false
        count += 1
      end
    end
  end
end