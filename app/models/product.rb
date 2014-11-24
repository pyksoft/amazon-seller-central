class Product < ActiveRecord::Base
  validates_uniqueness_of :ebay_item_id, :amazon_asin_number
  validates_presence_of :ebay_item_id, :amazon_asin_number
  validate :ebay_item_validation, :amazon_asin_number_validation

  @@test_workspace = Rails.env == 'development'
  @@thread_compare_working = false
  @@working_count = 3

  def self.test_workspace
    @@test_workspace
  end

  def self.test_workspace= status
    @@test_workspace = status
  end

  def self.working_count
    @@working_count
  end

  def self.working_count= n
    @@working_count = n
  end

  def self.create_products_notifications
    p 'start!'
    unless @@thread_compare_working
      Thread.new do
        compare_products
      end
    end
  end

  def self.ebay_product_ending?(ebay_product)
    (ebay_product[:item].present? &&
        ((!ebay_product[:item][:listing_details][:ending_reason].present? &&
            ebay_product[:item][:listing_details][:relisted_item_id].present?) ||
            ebay_product[:item][:listing_details][:ending_reason].present?)) ||
        !ebay_product[:item].present?
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
    reasons = []

    begin
      item_page = agent.get(item_url)
      reasons << :ending unless self.class.in_stock?(self.class.one_get_stock(item_page))
      reasons << :not_prime unless self.class.one_get_prime(item_page)
      reasons << :not_url_page unless validate_url_page
    rescue
      reasons << :unknown
    end

    reasons.each do |reason|
      errors.add :amazon_asin_number, reason
    end
  end

  def validate_url_page
    url_page && url_page.include?("#{amazon_asin_number}") || !url_page
  end

  def self.compare_products
    @@thread_compare_working = true
    notifications = []
    extra_content = nil
    p "*** #{@@working_count} ***"

    seconds = Benchmark.realtime do
      notifications, extra_content = @@working_count % 3 == 0 ? compare_each_product : compare_wish_list
    end

    Notification.where('seen is null OR seen = false').update_all(:seen => true)
    notifications.each { |notification| Notification.create! notification }

    emails_to = ['roiekoper@gmail.com']
    emails_to << 'idanshviro@gmail.com' unless @@test_workspace
    emails_to.each do |to|
      UserMailer.send_email("--- #{extra_content} \n ---   " + Product.all.map(&:title).join(',
'),
                            I18n.t('notifications.compare_complete',
                                   :compare_time => I18n.l(DateTime.now.in_time_zone('Jerusalem'), :format => :long),
                                   :new_notifications_count => notifications.size,
                                   :work_time => "#{Time.at(seconds).gmtime.strftime('%R:%S')}"),
                            to).deliver
    end
    # @@working_count += 1
    @@thread_compare_working = false
  end

  def create_with_requests
    begin
      if valid?
        item_page = self.class.create_agent.get(item_url)
        self.amazon_price = self.class.one_get_price(item_page)
        self.prime = self.class.one_get_prime(item_page).present?
        self.image_url = self.class.one_get_image_url(item_page)
        self.title = self.class.one_get_title(item_page)
        save!
        { :msg => I18n.t('messages.product_create') }
      else
        { :errs => errors.full_messages.join(', ') }
      end
    rescue Exception => e
      { :errs => e.message }
    end
  end

  def admin_create
    begin
      item_page = self.class.create_agent.get(item_url)
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
    File.open("#{Rails.root}/log/errors.txt", 'a') do |f|
      f << "#{text}\n"
    end
  end

  def self.compare_wish_list
    agent = create_agent
    done = false
    page = 1
    notifications = []
    all_assins = []
    product = nil
    wishlist = agent.get 'http://www.amazon.com/gp/registry/wishlist/?page=' + page.to_s
    last_page = YAML.load(wishlist.search('.a-').last.attributes['data-pag-trigger'].value)['page']
    sleep(2)

    begin
      while (!done) do
        wishlist = agent.get 'http://www.amazon.com/gp/registry/wishlist/?page=' + page.to_s
        items = wishlist.search('.g-item-sortable')

        if items.empty?
          if page < last_page
            compare_wish_list
          else
            done = true
            break
          end
        end

        p "item size: #{items.size}"
        p "Page: #{page} / #{last_page}"
        prices_html = items.search('.price-section')
        availability_html = items.search('.itemAvailability')
        products = Product.where(:amazon_asin_number => prices_html.map do |price_html|
                                   YAML.load(price_html.attributes['data-item-prime-info'].value)['asin']
                                 end)

        all_items = prices_html.zip(availability_html)

        all_items.map do |price, stock|
          asin_number = YAML.load(price.attributes['data-item-prime-info'].value)['asin']
          product = products.find { |pro| pro.amazon_asin_number == asin_number }

          done = true if all_assins.include?(asin_number) && page >= last_page
          all_assins << asin_number
          if product
            ebay_item = Ebayr.call(:GetItem, :ItemID => product.ebay_item_id, :auth_token => Ebayr.auth_token)
            product.amazon_stock_change?(get_value(stock), notifications)
            product.ebay_stock_change(ebay_item, notifications)
            product.price_change?(get_value(price)[1..-1].to_f, ebay_item, notifications)
          end
        end
        page += 1
      end

    rescue Exception => e
      UserMailer.send_email("Exception errors:#{e.message}", 'Exception in compare wishlist', 'roiekoper@gmail.com').deliver
      write_errors I18n.t('errors.diff_error',
                          :time => I18n.l(Time.now, :format => :error),
                          :id => product.id,
                          :asin_number => product.amazon_asin_number,
                          :ebay_number => product.ebay_item_id,
                          :errors => "#{product.errors.full_messages.join(' ,')}, \n Exception errors:#{e.message}")
    end

    extra_content = "Over on #{page - 1} pages, out of #{last_page}"
    if page - 1 != last_page
      UserMailer.send_email('', extra_content, 'roiekoper@gmail.com').deliver
    end

    [notifications, extra_content]
  end

  def self.compare_each_product
    notifications = []
    agent = create_agent
    count = 0
    log = []

    Product.all.each do |product|
      p "Over items: #{count}"
      begin
        item_page = agent.get(product.item_url)
        ebay_item = Ebayr.call(:GetItem, :ItemID => product.ebay_item_id, :auth_token => Ebayr.auth_token)
        log << "amazon_asin_number: #{product.amazon_asin_number},ebay_item_id: #{product.ebay_item_id},id: #{product.id}, Amazon stock: #{one_get_stock(item_page)}, Amazon In Stock? #{in_stock?(one_get_stock(item_page))}, Price: #{one_get_price(item_page)}, Prime: #{one_get_prime(item_page)}"

        if ebay_item[:ack] == 'Failure'
          UserMailer.send_email("Exception in ebay call: #{ebay_item}, product: #{product.attributes.slice(:id,:ebay_item_id,:amazon_asin_number)}", 'Exception in compare ebay call', 'roiekoper@gmail.com').deliver
        else
          product.amazon_stock_change?(one_get_stock(item_page), notifications)
          product.ebay_stock_change(ebay_item, notifications)
          product.price_change?(one_get_price(item_page), ebay_item, notifications)
          product.prime_change?(one_get_prime(item_page), notifications)
        end
      rescue
        notifications << {
            :text => I18n.t('notifications.unknown_item', :title => product.title),
            :product => product,
            :image_url => product.image_url,
            :change_title => :unknown_item
        }
        # product.destroy!
      end

      count += 1

    end

    extra_content = "Over on #{count} products / #{Product.count}"
    UserMailer.send_email(extra_content + ' '.center(80) + log.join(' '.center(15)), 'End Compare Each Product', 'roiekoper@gmail.com').deliver

    [notifications, extra_content]
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
                         :change_title => 'amazon_unavailable' }
      # destroy!
    end
  end

  def ebay_stock_change(ebay_item, notifications)
    if self.class.ebay_product_ending?(ebay_item)
      notifications << { :text => I18n.t('notifications.ebay_ending', :title => title),
                         :product => self,
                         :image_url => image_url,
                         :change_title => 'ebay_unavailable' }
      destroy! unless @@test_workspace
    end
  end

  def price_change?(new_price, ebay_item, notifications)
    if new_price != amazon_price && ebay_item[:item].present?
      price_change = new_price.to_f - amazon_price.to_f
      ebay_price = ebay_item[:item] && ebay_item[:item][:listing_details] && ebay_item[:item][:listing_details][:converted_start_price] || 0

      begin
        ebay_item[:item][:listing_details][:converted_start_price]
      rescue Exception => e
        UserMailer.send_email("Exception price change?:#{e.message}, #{ebay_item}, new price: #{new_price}", 'Exception in compare wishlist', 'roiekoper@gmail.com').deliver
      end

      # unless @@test_workspace
      #   Ebayr.call(:ReviseItem,
      #              :item => { :ItemID => ebay_item_id,
      #                         :StartPrice => "#{ebay_price.to_f + price_change}" },
      #              :auth_token => Ebayr.auth_token)
      # end

      notifications << { :text => I18n.t('notifications.amazon_price', :amazon_old_price => self.class.show_price(amazon_price),
                                         :amazon_new_price => self.class.show_price(new_price),
                                         :ebay_old_price => self.class.show_price(ebay_price),
                                         :ebay_new_price => self.class.show_price(ebay_price.to_f + price_change)),
                         :product => self,
                         :image_url => image_url,
                         :change_title => "#{price_change.round(2)}_price"
      }

      update_attribute(:amazon_price, self.class.show_price(new_price)) unless @@test_workspace
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

  def item_url
    url_page || "http://www.amazon.com/dp/#{amazon_asin_number}"
  end

  private

  def self.create_agent
    agent = Mechanize.new do |agent|
      agent.user_agent_alias = 'Mac Safari'
      agent.follow_meta_refresh = true
      agent.redirect_ok = true
    end

    url = 'https://www.amazon.com/ap/signin/192-5085168-5154433?_encoding=UTF8&openid.assoc_handle=usflex&openid.claimed_id=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.identity=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0%2Fidentifier_select&openid.mode=checkid_setup&openid.ns=http%3A%2F%2Fspecs.openid.net%2Fauth%2F2.0&openid.ns.pape=http%3A%2F%2Fspecs.openid.net%2Fextensions%2Fpape%2F1.0&openid.pape.max_auth_age=0&openid.return_to=https%3A%2F%2Fwww.amazon.com%2Fgp%2Fyourstore%2Fhome%3Fie%3DUTF8%26ref_%3Dgno_custrec_signin'
    page = agent.get(url)
    form = page.forms.first
    form['email'] = 'shviro123456@gmail.com'
    form['password'] = 'IDSH987'
    form['ap_signin_existing_radio'] = '1'
    page = form.submit

    if page.uri.to_s.include?('https://www.amazon.com/ap/dcq?ie=UTF8&dcq.arb.value')
      zicode_form = page.forms.first
      zicode_form['dcq_question_subjective_1'] = '11365'
      zipcode_page = zicode_form.submit
    end

    agent
  end

  def self.in_stock?(stock)
    ['In Stock', 'left in stock--order soon', 'left in stock'].any? do |instock_str|
      stock.downcase.match(/^(.*?(\b#{instock_str.downcase}\b)[^$]*)$/)
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
      when item_page.search('#actualPriceRow')
        [item_page.search('#actualPriceRow').search('.priceLarge'), item_page.search('#actualPriceRow')]
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
        item_page.search('#availability_feature_div').search('#availability').present? &&
        item_page.search('#availability_feature_div').search('#availability').first.children[1].children.first.text.strip ||
        item_page.search('.buying') &&
            item_page.search('.buying').search('span').to_s ||
        ''
  end

  def self.one_get_prime(item_page)
    match_page_price = get_match_price(item_page).last
    match_page_price.present? && (match_page_price.search('#ourprice_shippingmessage').
        search('.a-icon-prime').present? || match_page_price.search('.a-icon-prime').present?) ||
        match_page_price.search('#actualPriceExtraMessaging').present? && match_page_price.search('#actualPriceExtraMessaging').search('img').
            first.attributes['src'].value.include?('check-prime')
  end

  def self.one_get_title(item_page)
    title_element = item_page.search('#productTitle').present? && item_page.search('#productTitle') ||
        item_page.search('#btAsinTitle').present? && item_page.search('#btAsinTitle')
    title_element &&title_element.children.first.text.strip || ''
  end

  def self.one_get_image_url(item_page)
    image_page_url = item_page.search('.a-button-toggle').present? &&
        item_page.search('.a-button-toggle')[0].children[0].
            children[1].children[1].attributes['src'].value ||
        item_page.search('#main-image').present? && item_page.search('#main-image').first.attributes['rel'].value
    image_page_url.present? ? image_page_url[0...image_page_url =~ /_/] + '_SL160_.jpg' : '' # remove all _SR38,50_ -> Small image
  end

  def self.upload_wish_list
    products_text = 'B00F8VBJTM, 251645745168
                      B001A5W53E, 261487157757
                      B00267SQVU, 261487161024'.split("\n").select do |details|
      details = details.split(',').map(&:strip)
      details.size == 2 && details.first.length == 10 && details.last.length == 12
    end

    # agent = Product.create_agent
    errors = []

    # over on all current products and update price & prime.
    # Product.all.each_with_index do |product|
    #   begin
    #     item_page = agent.get("http://www.amazon.com/dp/#{product.amazon_asin_number}")
    #     product.amazon_asin_number = product.amazon_asin_number.upcase
    #     product.amazon_price = Product.one_get_price(item_page)
    #     product.prime = Product.one_get_prime(item_page)
    #     product.save(:validate => false)
    #   rescue Exception => e
    #     p "Error #{e.message} in #{product.id} product"
    #   end
    # end


    p 'finished update all current products'
    p "start create new products from file, #{products_text.length} products"
    p 'without over al current products'

    Thread.new do
      products_text.in_groups_of(100).each_with_index do |product_groups, g_i|
        product_groups.each_with_index do |product_details, i|
          begin
            p i
            asin_number, ebay_number = product_details.split(',').map(&:strip)
            error = new(:amazon_asin_number => asin_number,
                        :ebay_item_id => ebay_number).create_with_requests.
                merge(:product => { :ebay_number => ebay_number, :asin_number => asin_number }, :index => i)
            p error if error[:msg]
            errors << error
          rescue Exception => e
            errors << "Error #{e.message} in #{i} -> #{asin_number},#{ebay_number}"
          end
        end


        File.open("#{Rails.root}/log/add_wishlist_errors.txt", 'a') do |f|
          errors.each do |error|
            f << "#{error[:index]}. #{error.except(:index)}\n"
          end
        end

        UserMailer.send_email(errors.join("\n,
"),
                              "Finish #{g_i} group!, errors number: #{errors.length}",
                              'roiekoper@gmail.com').deliver

      end

      p "Finish upload all file, errors size #{errors.size}"
    end
  end
end