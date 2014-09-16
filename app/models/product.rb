class Product < ActiveRecord::Base
  validates_uniqueness_of :ebay_item_id, :amazon_asin_number
  validates_presence_of :ebay_item_id, :amazon_asin_number
  validate :ebay_item_validation, :amazon_asin_number_validation
  validate :prime_validation, :on => :create

  @@thread_compare_working = false

  def self.ebay_product_ending?(ebay_product)
    !ebay_product[:item] || ebay_product[:item][:listing_details][:ending_reason]
  end

  def self.amazon_product_ending?(amazon_product)
    !amazon_product.get_hash['Offers'].match('AvailabilityType') ||
        amazon_product.get_hash['Offers'].string_between_markers('AvailabilityType', 'AvailabilityType').delete('></') != 'now'
  end

  def ebay_item_validation
    ebay_product = Ebayr.call(:GetItem, :ItemID => ebay_item_id, :auth_token => Ebayr.auth_token)
    reason = if ebay_product[:ack] == 'Failure'
               :unknown
             elsif self.class.ebay_product_ending?(ebay_product)
               :ending
             end
    errors.add(:ebay_item_id, reason) if reason
  end

  def amazon_asin_number_validation
    amazon_product = Amazon::Ecs.item_lookup(amazon_asin_number,
                                             :response_group => 'ItemAttributes,Images',
                                             :id_type => 'ASIN',
                                             'ItemSearch.Shared.ResponseGroup' => 'Large').items.first
    reason = if !amazon_product
               :unknown
             elsif self.class.amazon_product_ending?(amazon_product)
               :ending
             end
    errors.add(:amazon_asin_number, reason) if reason
  end

  def prime_validation
    amazon_item = Amazon::Ecs.item_lookup(amazon_asin_number,
                                          :response_group => 'ItemAttributes,Images',
                                          :id_type => 'ASIN',
                                          'ItemSearch.Shared.ResponseGroup' => 'Large').items.first

    unless amazon_item &&
        amazon_item.get_element('Offers/Offer') &&
        amazon_item.get_element('Offers/Offer').get_element('OfferListing').get('IsEligibleForSuperSaverShipping') == '1'
      errors.add(:amazon_asin_number, :not_prime)
    end
  end

  def self.create_products_notifications
    unless @@thread_compare_working
      Thread.new do
        compare_products
      end
    end
  end

  def self.compare_products(products = Product.all, checked = [], notifications = [])
    @@thread_compare_working = true
    Notification.where('seen is null OR seen = false').update_all(:seen => true)

    begin
      unless checked.size == Product.count
        products.each do |product|
          ending = false
          sleep(1) if checked.size % 3 == 0
          amazon_item = Amazon::Ecs.item_lookup(product.amazon_asin_number,
                                                :response_group => 'ItemAttributes,Images',
                                                :id_type => 'ASIN',
                                                'ItemSearch.Shared.ResponseGroup' => 'Large').items.first
          ebay_item = Ebayr.call(:GetItem, :ItemID => product.ebay_item_id, :auth_token => Ebayr.auth_token)
          checked << product.id
          price = amazon_item.get_element('Offers/Offer') && amazon_item.get_element('Offers/Offer').get_element('OfferListing/Price').get('Amount').to_f / 100
          prime = price && amazon_item.get_element('Offers/Offer').get_element('OfferListing').get('IsEligibleForSuperSaverShipping') == '1'

          if amazon_product_ending?(amazon_item)
            notifications << { :text => I18n.t('notifications.amazon_ending', :title => product.title),
                               :product => product, :image_url => product.image_url }
            # Ebayr.call(:EndItem, :ItemID => product.ebay_item_id, :auth_token => Ebayr.auth_token, :EndingReason => 'NotAvailable')
            product.destroy!
            ending = true
          end

          if ebay_product_ending?(ebay_item) && !ending
            notifications << { :text => I18n.t('notifications.ebay_ending', :title => product.title),
                               :product => product, :image_url => product.image_url }
            ending = true
            product.destroy!
          end

          unless ending
            diff = product.serializable_attributes.slice(:amazon_price, :prime).diff({
                                                                                         'amazon_price' => 30.0,
                                                                                         'prime' => prime
                                                                                     })
            syms = HashWithIndifferentAccess.new(
                {
                    :amazon_price => {
                        :attrs => [:amazon_old_price, :amazon_new_price],
                        :extra_attrs => proc do |ebay_old_price, ebay_new_price, attrs|
                          attrs.merge!(:ebay_old_price => ebay_old_price.to_f.round(2), :ebay_new_price => ebay_new_price.to_f.round(2))
                        end,
                        :var => price
                    },
                    :prime => {
                        :attrs => [:old_prime, :new_prime],
                        :var => prime
                    }
                }
            )

            diff.each_pair do |sym, details|
              n_attrs = Hash[syms[sym][:attrs].zip(details)].merge(:title => product.title)
              if sym.to_sym == :amazon_price
                price_change = details.inject { |a, b| b - a } # new price - old price
                ebay_price = ebay_item[:item][:listing_details][:converted_start_price]
                syms[sym][:extra_attrs].call(ebay_price, ebay_price.to_f + price_change, n_attrs) if syms[sym][:extra_attrs]
                Ebayr.call(:ReviseItem, :item => { :ItemID => product.ebay_item_id, :StartPrice => "#{ebay_price.to_f + price_change}" }, :auth_token => Ebayr.auth_token)
              end

              notifications << { :text => I18n.t("notifications.#{sym}", n_attrs.merge(:title => product.title)),
                                 :product => product, :image_url => product.image_url }
            end

            # update amazon old_price & prime
            product.update_attributes! syms.slice(*diff.keys).inject({}) { |h, (k, v)| h.merge(k => v['var']) }
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

      %w(idanshviro@gmail.com roiekoper@gmail.com).each do |to|
        UserMailer.send_email(Product.all.map(&:title).join(',              '),
                              I18n.t('notifications.compare_complete',
                                     :compare_time => I18n.l(DateTime.now.in_time_zone('Jerusalem'), :format => :long),
                                     :new_notifications_count => notifications.count),
                              to).deliver
      end

      notifications.each { |notification| Notification.create! notification }
    end
  end

  def create_with_requests
    amazon_item = Amazon::Ecs.item_lookup(amazon_asin_number,
                                          :response_group => 'ItemAttributes,Images',
                                          :id_type => 'ASIN',
                                          'ItemSearch.Shared.ResponseGroup' => 'Large').items.first
    if valid?
      self.amazon_price = amazon_item.get_element('Offers/Offer') && amazon_item.get_element('Offers/Offer').get_element('OfferListing/Price').get('Amount').to_f / 100
      self.prime = amazon_price && amazon_item.get_element('Offers/Offer').get_element('OfferListing').get('IsEligibleForSuperSaverShipping') == '1'
      self.image_url = amazon_item.get_element('MediumImage').get('URL')
      self.title = amazon_item.get('ItemAttributes/Title')
      save!
      { :msg => I18n.t('messages.product_create') }
    else
      { :errs => errors.full_messages }
    end
  end
end