class Product < ActiveRecord::Base
  validates_uniqueness_of :ebay_item_id, :amazon_asin_number
  validates_presence_of :ebay_item_id, :amazon_asin_number
  validate :ebay_item_validation, :amazon_asin_number_validation
  # validate :prime_validation, :on => :create

  @@thread_compare_working = false
  @@working_count = 1

  def self.ebay_product_ending?(ebay_product)
    !ebay_product[:item] ||
        (!ebay_product[:item][:listing_details][:ending_reason] &&
            ebay_product[:item][:listing_details][:relisted_item_id])
  end

  def self.amazon_product_ending?(amazon_product)
    !amazon_product.get_hash['Offers'].match('AvailabilityType') ||
        %w[now futureDate].exclude?(amazon_product.get_hash['Offers'].
                                        string_between_markers('AvailabilityType', 'AvailabilityType').delete('></'))
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
    agent = self.class.create_agent
    reason = nil

    begin
      item_page = agent.get("http://www.amazon.com/dp/#{amazon_asin_number}")
      reason = :ending unless self.class.in_stock?(self.class.one_get_stock(item_page))
    rescue
      reason = :unknown
    end

    errors.add(:amazon_asin_number, reason) if reason
  end

  def prime_validation
    begin
      item_page = self.class.create_agent.
          get("http://www.amazon.com/dp/#{amazon_asin_number}")
      errors.add(:amazon_asin_number, :not_prime) unless self.class.one_get_prime(item_page).present?
    rescue
    end
  end

  def self.create_products_notifications
    unless @@thread_compare_working
      Thread.new do
        compare_products
      end
    end
  end

  def self.compare_products
    @@thread_compare_working = true
    # Notification.where('seen is null OR seen = false').update_all(:seen => true)
    notifications = @@working_count % 3 == 0 ? compare_each_product : compare_wish_list
    notifications.each { |notification| Notification.create! notification }

    %w(roiekoper@gmail.com).each do |to|
      UserMailer.send_email(Product.all.map(&:title).join(',
'),
                            I18n.t('notifications.compare_complete',
                                   :compare_time => I18n.l(DateTime.now.in_time_zone('Jerusalem'), :format => :long),
                                   :new_notifications_count => notifications.size),
                            to).deliver
      @@working_count += 1
      @@thread_compare_working = false
    end
  end

  def create_with_requests
    begin
      if valid?
        item_page = self.class.create_agent.get("http://www.amazon.com/dp/#{amazon_asin_number}")
        self.amazon_price = self.class.one_get_price(item_page)
        self.prime = self.class.one_get_prime(item_page).present?
        self.image_url = self.class.one_get_image_url(item_page)
        self.title = self.class.one_get_title(item_page)
        save!
        { :msg => I18n.t('messages.product_create') }
      else
        { :errs => errors.full_messages }
      end
    rescue Exception => e
      { :errs => e.message }
    end
  end

  def admin_create
    begin
      item_page = self.class.create_agent.get("http://www.amazon.com/dp/#{amazon_asin_number}")
      self.amazon_price = self.class.one_get_price(item_page)
      self.prime = self.class.one_get_prime(item_page).present?
      self.image_url = self.class.one_get_image_url(item_page)
      self.title = self.class.one_get_title(item_page)
      save(:validate => false)
      I18n.t 'messages.product_create'
    rescue Exception => e
      e.message
    end
  end

  def self.write_errors(text)
    File.open("#{Rails.root}/log/errors.txt", 'a') { |f|
      f << "#{text}\n" }
  end

  def self.compare_wish_list
    agent = create_agent
    done = false
    page = 1
    notifications = []
    all_assins = []
    product = nil

    begin
      while (!done) do
        wishlist = agent.get 'http://www.amazon.com/gp/registry/wishlist/?page=' + page.to_s
        items = wishlist.search('.g-item-sortable')
        prices_html = items.search('.price-section')
        availability_html = items.search('.itemAvailability')
        all_items = prices_html.zip(availability_html)
        done = true if all_items.empty?
        all_items.map do |price, stock|
          asin_number = YAML.load(price.attributes['data-item-prime-info'].value)['asin']
          product = asin_number && find_by_amazon_asin_number(asin_number)
          done = true if all_assins.include?(asin_number)
          all_assins << asin_number
          if product
            ebay_item = Ebayr.call(:GetItem, :ItemID => product.ebay_item_id, :auth_token => Ebayr.auth_token)
            case
              when product.amazon_stock_change?(get_value(stock), notifications)
              when product.ebay_stock_change(ebay_item, notifications)
              when product.price_change?(get_value(price)[1..-1].to_f, ebay_item, notifications)
            end
          end
        end
        page += 1
      end
    rescue Exception => e
      write_errors I18n.t('errors.diff_error',
                          :time => I18n.l(Time.now, :format => :error),
                          :id => id,
                          :asin_number => product.amazon_asin_number,
                          :ebay_number => product.ebay_item_id,
                          :errors => "#{product.errors.full_messages.join(' ,')}, \n Exception errors:#{e.message}")
    end
    notifications
  end

  def self.compare_each_product
    notifications = []

    Product.all.each do |product|
      begin
        item_page = create_agent.get("http://www.amazon.com/dp/#{product.amazon_asin_number}")
        if item_page
          ebay_item = Ebayr.call(:GetItem, :ItemID => product.ebay_item_id, :auth_token => Ebayr.auth_token)
          case
            when product.amazon_stock_change?(one_get_stock(item_page), notifications)
            when product.ebay_stock_change(ebay_item, notifications)
            else
              product.price_change?(one_get_price(item_page), ebay_item, notifications)
              product.prime_change?(one_get_prime(item_page), notifications)
          end
        end
      rescue Exception => e
        write_errors I18n.t('errors.diff_error',
                            :time => I18n.l(Time.now, :format => :error),
                            :id => id,
                            :asin_number => product.amazon_asin_number,
                            :ebay_number => product.ebay_item_id,
                            :errors => "#{product.errors.full_messages.join(' ,')}, \n Exception errors:#{e.message}")
      end
    end
    notifications
  end

  def self.get_value(item)
    item.children[1].children.present? && item.children[1].children.first.text.strip
  end

  def amazon_stock_change?(stock, notifications)
    unless self.class.in_stock?(stock)
      # Ebayr.call(:EndItem, :ItemID => ebay_item_id,
      #            :auth_token => Ebayr.auth_token,
      #            :EndingReason => 'NotAvailable')
      notifications << { :text => I18n.t('notifications.amazon_ending', :title => title),
                         :product => self,
                         :image_url => image_url,
                         :change_title => 'amazon_unavailable'}
      # destroy!
    end
  end

  def ebay_stock_change(ebay_item, notifications)
    if self.class.ebay_product_ending?(ebay_item)
      notifications << { :text => I18n.t('notifications.ebay_ending', :title => title),
                         :product => self,
                         :image_url => image_url,
                         :change_title => 'ebay_unavailable'}
    end
    # destroy!
  end

  def price_change?(new_price, ebay_item, notifications)
    unless new_price == amazon_price
      price_change = new_price.to_f - amazon_price.to_f
      ebay_price = ebay_item[:item][:listing_details][:converted_start_price]
      # Ebayr.call(:ReviseItem,
      #            :item => { :ItemID => ebay_item_id,
      #                       :StartPrice => "#{ebay_price.to_f + price_change}" },
      #            :auth_token => Ebayr.auth_token)

      notifications << { :text => I18n.t('notifications.amazon_price', :amazon_old_price => self.class.show_price(amazon_price),
                                         :amazon_new_price => self.class.show_price(new_price),
                                         :ebay_old_price => self.class.show_price(ebay_price),
                                         :ebay_new_price => self.class.show_price(ebay_price.to_f + price_change)),
                         :product => self,
                         :image_url => image_url,
                         :change_title => "#{ebay_price.to_f + price_change}_price"
      }
      # update_attribute :amazon_price, self.class.show_price(new_price)
    end
  end

  def prime_change?(new_prime, notifications)
    unless new_prime == prime
      notifications << { :text => I18n.t('notifications.prime', # true Bollean to 'true' String
                                         Hash[[:old_prime, :new_prime].zip([prime, new_prime].map do |val|
                                           I18n.t(val.to_s, :scope => :app)
                                         end)]),
                         :product => self,
                         :image_url => image_url,
                         :row_css => new_prime ? 'green_prime' : 'red_prime',
                         :change_title => "#{new_prime}_prime" }
      # update_attribute :prime, new_prime
    end
  end

  private
  def self.create_agent
    agent = Mechanize.new do |agent|
      agent.user_agent_alias = 'Mac Safari'
      agent.follow_meta_refresh = true
      agent.redirect_ok = true
    end

    url = 'https://www.amazon.com/ap/signin/192-5085168-5154433?_encoding=UTF8&openid.assoc_handle=usflex&openid.claimed_id=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.identity=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.mode=checkid_setup&openid.ns=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0&openid.ns.pape=http%3A%2F%2Fspecs.openid.net%2Fextensions%2Fpape%2F1.0&openid.pape.max_auth_age=0&openid.return_to=https%3A%2F%2Fwww.amazon.com%2Fgp%2Fyourstore%2Fhome%3Fie%3DUTF8%26ref_%3Dgno_custrec_signin'
    agent.get(url) do |page|
      search_form = page.form_with(:name => 'signIn')
      search_form.field_with(name: 'email').value = 'shviro123456@gmail.com'
      search_form.field_with(name: 'password').value = 'IDSH987'
      search_form['ap_signin_existing_radio'] = '1'
      search_form.submit
    end

    agent
  end

  def self.in_stock?(stock)
    ['In Stock', 'left in stock--order soon', 'left in stock'].any? do |instock_str|
      stock.match(/^(.*?(\b#{instock_str}\b)[^$]*)$/)
    end
  end

  def self.show_price(price)
    price.to_f.round(2)
  end

  # get many options to get price from html product page. first attr is for price, second for prime.
  def self.get_match_price(item_page)
    case
      when item_page.search('#price').present? &&
          item_page.search('#price').search('#priceblock_ourprice').present?
        [item_page.search('#price').search('#priceblock_ourprice'), item_page.search('#price')]
      when item_page.search('#price').present? &&
          item_page.search('#price').search('#priceblock_saleprice').present?
        [item_page.search('#price').search('#priceblock_saleprice'), item_page.search('#price')]
      when item_page.search('#price').present? &&
          item_page.search('#price').search('#priceblock_dealprice')
        [item_page.search('#price').search('#priceblock_dealprice').first.children[1], item_page.search('#price').search('#priceblock_dealprice')]
      else
        []
    end
  end

  def self.one_get_price(item_page)
    match_page_price = get_match_price(item_page).first
    match_page_price.present? && match_page_price.children.first.text[1..-1].to_f || 0
  end

  def self.one_get_stock(item_page)
    item_page.search('#availability_feature_div').present? &&
        item_page.search('#availability_feature_div').search('#availability').
            first.children[1].children.first.text.strip
  end

  def self.one_get_prime(item_page)
    match_page_price = get_match_price(item_page).last
    match_page_price.present? && (match_page_price.search('#ourprice_shippingmessage').
        search('.a-icon-prime').present? || match_page_price.search('.a-icon-prime').present?)
  end

  def self.one_get_title(item_page)
    item_page.search('#productTitle').children.first.text.strip
  end

  def self.one_get_image_url(item_page)
    item_page.search('.a-button-toggle').present? &&
        item_page.search('.a-button-toggle')[0].children[0].
            children[1].children[1].attributes['src'].value.gsub('SS40', 'SL160')
  end
end