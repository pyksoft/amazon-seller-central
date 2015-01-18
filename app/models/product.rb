class Product < ActiveRecord::Base
  validates_uniqueness_of :ebay_item_id, :amazon_asin_number
  validates_presence_of :ebay_item_id, :amazon_asin_number
  validate :ebay_item_validation, :amazon_asin_number_validation, :on => :create

  @@test_workspace = Rails.env == 'development'
  @@thread_compare_working = false

  require 'compare_products'

  def self.test_workspace
    @@test_workspace
  end

  def self.test_workspace= status
    @@test_workspace = status
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
    url_page.present? && url_page.include?("#{amazon_asin_number}") || !url_page.present?
  end

  def self.compare_products
    @@thread_compare_working = true
    compare_count = List.compare_count
    notifications = []
    extra_content = nil
    Notification.delete_old_notifications
    reset_progress_count
    set_products_count
    p "*** #{compare_count} ***"

    seconds = Benchmark.realtime do
      Product.transaction do
        notifications, extra_content = (compare_count % 2).zero? ? compare_each_product : compare_wish_list
      end

      UserMailer.send_email('',
                            'Finished Transaction',
                            'roiekoper@gmail.com').deliver
    end

    emails_to = ['roiekoper@gmail.com']

    unless @@test_workspace
      emails_to << 'idanshviro@gmail.com'
    end

    emails_to.each do |to|
      UserMailer.send_email("--- #{extra_content} \n ---, Checking no': #{compare_count}",
                            I18n.t('notifications.compare_complete',
                                   :compare_time => I18n.l(DateTime.now.in_time_zone('Jerusalem'), :format => :long),
                                   :new_notifications_count => notifications.size,
                                   :work_time => "#{Time.at(seconds).gmtime.strftime('%R:%S')}"),
                            to).deliver
    end


    reset_progress_count

    UserMailer.send_email('Compare Result',
                          "sec: #{seconds}, Notification size:#{notifications.size},extra: #{extra_content}",
                          'roiekoper@gmail.com').deliver

    List.update_compare_count
    @@thread_compare_working = false

    Notification.where('seen is null OR seen = false').update_all(:seen => true)
    columns = notifications.first.keys
    values = notifications.map(&:values)
    Notification.import columns, values, :validate => false

    UserMailer.send_email('',
                          "Notification unseen size: #{Notification.where(:seen => nil).count}, Notification size: #{Notification.count}",
                          'roiekoper@gmail.com').deliver
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
        { :msg => I18n.t('messages.product_created') }
      else
        { :errs => errors.full_messages.join(', ') }
      end
    rescue Exception => e
      { :errs => e.message }
    end
  end

  def admin_create(params)
    begin
      %i[amazon_asin_number ebay_item_id].each do |main_attr|
        update_attribute main_attr, params[:product][main_attr].strip.upcase
      end

      item_page = self.class.create_agent.get(item_url)

      [
          [:url_page],
          [:prefer_url],
          [:amazon_price, self.class.one_get_price(item_page)],
          [:prime, self.class.one_get_prime(item_page).present?],
          [:image_url, self.class.one_get_image_url(item_page)],
          [:title, self.class.one_get_title(item_page)]
      ].each do |attr, page_value|
        self.send("#{attr}=", params[:product][attr].present? ? params[:product][attr] : page_value)
      end

      self.save(:validate => false)

      I18n.t "messages.#{params[:product][:id].present? ? 'product_updated' : 'product_created'}"
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
    count = 0
    notifications = []
    all_assins = []
    pages = []
    product = nil
    wishlist = agent.get 'http://www.amazon.com/gp/registry/wishlist/?page=' + page.to_s
    last_page = YAML.load((wishlist.search('.a-').last && wishlist.search('.a-').last.attributes['data-pag-trigger'].value).to_s)
    last_page = last_page && last_page['page'] || 1
    set_products_count last_page.to_i * 25
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
            if product.prefer_url
              product.compare_with_url create_agent, [], pages, notifications
            else
              ebay_item = Ebayr.call(:GetItem, :ItemID => product.ebay_item_id, :auth_token => Ebayr.auth_token)
              product.ebay_stock_change(ebay_item, notifications)
              # if amazon in stock check changes in price.
              if product.amazon_stock_change?(get_value(stock), notifications)
                product.price_change?(get_value(price)[1..-1].to_f, ebay_item, notifications)
              end
            end
          end

          count +=1
          set_progress_count count
        end
        page += 1
      end

    rescue Exception => e
      UserMailer.send_email("Exception errors:#{e.message}, product_id: #{product.id}, Page: #{page}", 'Exception in compare wishlist', 'roiekoper@gmail.com').deliver
      write_errors I18n.t('errors.diff_error',
                          :time => I18n.l(DateTime.now.in_time_zone('Jerusalem'), :format => :error),
                          :id => product.id,
                          :asin_number => product.amazon_asin_number,
                          :ebay_number => product.ebay_item_id,
                          :errors => "#{product.errors.full_messages.join(' ,')}, \n Exception errors:#{e.message}")
    end

    extra_content = "Over on #{(page - 1)} pages, out of #{last_page}"
    if page - 1 != last_page
      UserMailer.send_email("Notifications size: #{notifications.count}", extra_content, 'roiekoper@gmail.com').deliver
    end

    [notifications, extra_content]
  end

  def self.compare_each_product
    notifications = []
    agent = create_agent
    count = 0
    log = []
    pages = []

    Product.all.each do |product|
      p "Over items: #{count}"
      begin
        product.compare_with_url agent, log, pages, notifications

        # delay between each product of 3 seconds
        sleep(3)
        # delay between each 100 products of 10 seconds
        sleep(10) if (count % 100).zero?
      rescue
        notifications << {
            :text => I18n.t('notifications.unknown_item', :title => product.title),
            :product_id => product.id,
            :change_title => :unknown_item,
            :row_css => ''
        }.merge(product.attributes.slice(*%w[title image_url ebay_item_id amazon_asin_number]))
        # product.destroy!
      end

      set_progress_count count
      count += 1

    end

    UserMailer.send_html_email(pages.map { |p| p[:page] }.join(','), pages.map { |p| p[:product] }.join(','), 'roiekoper@gmail.com').deliver

    extra_content = "Over on #{count} products / #{Product.count}"
    UserMailer.send_email("[#{notifications.join(',')}]", 'End Compare Each Product', 'roiekoper@gmail.com').deliver

    [notifications, extra_content]
  end

  def self.get_value(item)
    item.children[1].children.present? && item.children[1].children.first.text.strip
  end

  def amazon_stock_change?(stock, notifications)
    is_in_stock = self.class.in_stock?(stock)
    unless is_in_stock
      notifications << { :text => I18n.t('notifications.amazon_ending', :title => title),
                         :product_id => id,
                         :change_title => 'amazon_unavailable',
                         :row_css => ''
      }.merge(attributes.slice(*%w[title image_url ebay_item_id amazon_asin_number]))
    end
    is_in_stock
  end

  def ebay_stock_change(ebay_item, notifications)
    if self.class.ebay_product_ending?(ebay_item)
      notifications << { :text => I18n.t('notifications.ebay_ending', :title => title),
                         :product_id => id,
                         :change_title => 'ebay_unavailable',
                         :row_css => ''
      }.merge(attributes.slice(*%w[title image_url ebay_item_id amazon_asin_number]))
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

      notifications << {
          :text => I18n.t('notifications.amazon_price', :amazon_old_price => self.class.show_price(amazon_price),
                          :amazon_new_price => self.class.show_price(new_price),
                          :ebay_old_price => self.class.show_price(ebay_price),
                          :ebay_new_price => self.class.show_price(ebay_price.to_f + price_change)),
          :product_id => id,
          :change_title => "#{price_change.round(2)}_price",
          :row_css => '',
      }.merge(attributes.slice(*%w[title image_url ebay_item_id amazon_asin_number]))

      update_attribute(:amazon_price, self.class.show_price(new_price)) unless @@test_workspace
    end
  end

  def prime_change?(new_prime, notifications)
    unless new_prime == prime
      notifications << { :text => I18n.t('notifications.prime', # true Bollean to 'true' String
                                         Hash[[:old_prime, :new_prime].zip([prime, new_prime].map do |val|
                                                                             I18n.t(val.to_s, :scope => :app)
                                                                           end)]),
                         :product_id => id,
                         :change_title => "#{new_prime}_prime",
                         :row_css => new_prime ? 'green_prime' : 'red_prime' }.
          merge(attributes.slice(*%w[title image_url ebay_item_id amazon_asin_number]))
    end
  end

  def item_url
    url_page.present? ? url_page : "http://www.amazon.com/dp/#{amazon_asin_number}"
  end

  def amazon_out_of_stock
    unless @@test_workspace
      Ebayr.call(:EndItem, :ItemID => ebay_item_id,
                 :auth_token => Ebayr.auth_token,
                 :EndingReason => 'NotAvailable')
      destroy!
    end
  end

  def ebay_out_of_stock
    destroy! unless @@test_workspace
  end

  def change_prime(new_prime)
    update_attribute(:prime, new_prime) unless @@test_workspace
  end

  def change_price(changed)
    unless @@test_workspace
      ebay_item = Ebayr.call(:GetItem, :ItemID => ebay_item_id,
                             :auth_token => Ebayr.auth_token)
      ebay_price = ebay_item[:item] && ebay_item[:item][:listing_details] &&
          ebay_item[:item][:listing_details][:converted_start_price].to_f || 0
      if ebay_price.nonzero?
        Ebayr.call(:ReviseItem,
                   :item => { :ItemID => ebay_item_id,
                              :StartPrice => "#{ebay_price + changed}" },
                   :auth_token => Ebayr.auth_token)
      end
    end
  end

  def change_accepted(change_title)
    begin
      case change_title
        when /amazon_unavailable/
          amazon_out_of_stock
        when /ebay_unavailable/
          ebay_out_of_stock
        when /prime/
          change_prime(change_title.gsub('_prime', '') == 'true')
        when /price/
          change_price(change_title.gsub('_price', '').to_f)
      end

      { :msg => I18n.t('messages.notification_accepted') }
    rescue Exception => e
      { :errs => e.message }
    end
  end

  # ----------------------
  # ----------------------
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
    # check if remove from amazon web
    stock = stock.to_s.gsub('In stock on', '')
    unless stock.to_s.downcase.match(/^(.*?(\b#{"We don't know when or if this item will be back in stock".downcase}\b)[^$]*)$/)
      ['In Stock', 'left in stock--order soon', 'left in stock'].any? do |instock_str|
        stock.to_s.downcase.match(/^(.*?(\b#{instock_str.downcase}\b)[^$]*)$/)
      end
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
    item_page.search('#merchant-info').first.children.to_s.downcase.include?('amazon')
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

  def self.export
    p = Axlsx::Package.new
    wb = p.workbook

    wb.add_worksheet(:name => "Products to #{I18n.l(DateTime.now.in_time_zone('Jerusalem'), :format => :regular)}") do |sheet|
      sheet.add_row Product.column_names[1..-1]
      Product.all.each do |product|
        sheet.add_row product.values_at(Product.column_names[1..-1]).values
      end
    end
    p
  end
end