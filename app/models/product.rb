class Product < ActiveRecord::Base
  @@thread_compare_working = false

  def self.create_products_notifications
    unless @@thread_compare_working
      Thread.new do
        compare_products
      end
    end
  end

  def self.compare_products(products = Product.all, checked = [], notifications = [])
    @@thread_compare_working = true

    begin
      unless checked.size == Product.count
        products.each do |product|
          sleep(1) if checked.size % 3 == 0
          p checked.size if checked.size % 10 == 0
          amazon_item = Amazon::Ecs.item_lookup(product.amazon_asin_number,
                                                :response_group => 'ItemAttributes,Images',
                                                :id_type => 'ASIN',
                                                'ItemSearch.Shared.ResponseGroup' => 'Large').items.first
          checked << product.id
          price = amazon_item.get_element('Offers/Offer') && amazon_item.get_element('Offers/Offer').get_element('OfferListing/Price').get('Amount').to_f / 100
          prime = price && amazon_item.get_element('Offers/Offer').get_element('OfferListing').get('IsEligibleForSuperSaverShipping') == '1'

          diff = product.serializable_attributes.slice(:old_price, :prime).diff({
                                                                                    'old_price' => price,
                                                                                    'prime' => prime
                                                                                })
          syms = HashWithIndifferentAccess.new(
              {
                  :old_price => {
                      :attrs => [:amazon_old_price, :amazon_new_price],
                      :extra_attrs => proc do |ebay_price, attrs|
                        attrs.merge!(:ebay_old_price => ebay_price, :ebay_new_price => attrs[:amazon_old_price])
                      end
                  },
                  :prime => {
                      :attrs => [:old_prime, :new_prime]
                  }
              }
          )

          # update amazon old_price & prime
          update_attributes :old_price => price, :prime => prime

          diff.each_pair do |sym, details|
            price_change = details.inject { |a, b| a - b }
            n_attrs =Hash[syms[sym][:attrs].zip(details)].merge(:title => product.title)
            ebay_price = Ebayr.call(:GetItem, :ItemID => product.ebay_item_id, :auth_token => Ebayr.auth_token)[:item][:buy_it_now_price]
            syms[sym][:extra_attrs].call(ebay_price, n_attrs) if syms[sym][:extra_attrs]
            notifications <<{ :text => I18n.t("notifications.#{sym}", n_attrs.merge(:title => product.title)),
                              :product => product }
            # Ebayr.call(:ReviseItem, :item => { :ItemID => product.ebay_item_id, :BuyItNowPrice => ebay_price + price_change }, :auth_token => Ebayr.auth_token)
          end
        end
      end
    rescue
      p 'fail'
      p checked.size
      compare_products(Product.where("id NOT IN (#{ checked.empty? ? 'null' : checked.join(',')})"), checked, notifications)
    else
      p Time.now
      p 'finished!'
      @@thread_compare_working = false
      UserMailer.send_email('',
                            I18n.t('notifications.compare_complete',
                                   :compare_time => I18n.l(DateTime.now.in_time_zone('Jerusalem'),:format => :long),
                                   :new_notifications_count => notifications.count),
                            'roiekoper@gmail.com').deliver
      notifications.each { |notification| Notification.create! notification }
    end
  end

  def create_with_requests
    amazon_item = Amazon::Ecs.item_lookup(amazon_asin_number,
                                          :response_group => 'ItemAttributes,Images',
                                          :id_type => 'ASIN',
                                          'ItemSearch.Shared.ResponseGroup' => 'Large').items.first
    if amazon_item
      self.old_price = amazon_item.get_element('Offers/Offer') && amazon_item.get_element('Offers/Offer').get_element('OfferListing/Price').get('Amount').to_f / 100
      self.prime = old_price && amazon_item.get_element('Offers/Offer').get_element('OfferListing').get('IsEligibleForSuperSaverShipping') == '1'
      self.image_url = amazon_item.get_element('MediumImage').get('URL')
      save!
    else
      { :errs => I18n.t('errors.product') }
    end
  end
end
