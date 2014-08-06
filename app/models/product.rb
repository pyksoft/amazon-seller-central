class Product < ActiveRecord::Base
  def self.compare_products(products = Product.all, checked = [], notifications = [])
    p Time.now
    begin
      unless checked.size == Product.count
        products.each do |product|
          p checked.size if checked.size % 50 == 0
          amazon_item = Amazon::Ecs.item_lookup(product.item_id,
                                                :response_group => 'ItemAttributes,Images',
                                                :id_type => 'ASIN',
                                                'ItemSearch.Shared.ResponseGroup' => 'Large').items.first
          # medium_image = amazon_item.get_element('MediumImage')
          checked << product.id
          price = amazon_item.get_element('Offers/Offer') && amazon_item.get_element('Offers/Offer').get_element('OfferListing/Price').get('Amount').to_f / 100
          prime = price && amazon_item.get_element('Offers/Offer').get_element('OfferListing').get('IsEligibleForSuperSaverShipping') == '1'

          diff = product.serializable_attributes.slice(:old_price, :prime).diff({
                                                                                    'old_price' => price,
                                                                                    'prime' => prime
                                                                                })

          syms = HashWithIndifferentAccess.new({ :old_price => [:old_price, :new_price], :prime => [:old_prime, :new_prime] })

          diff.each_pair do |sym, details|
            notifications << { :text => I18n.t("notifications.#{sym}", Hash[syms[sym].zip(details)].merge(:item_id => product.item_id)),
                               :product => product }
          end
        end
      end
    rescue
      p 'fail'
      p checked.size
      sleep(8)
      self.compare_products(Product.where("id NOT IN (#{ checked.empty? ? 'null' : checked.join(',')})"), checked, notifications)
    else
      p Time.now
      p 'finished!'
      notifications.each { |notification| Notification.create! notification }
    end
  end
end
