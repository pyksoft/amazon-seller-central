class Product < ActiveRecord::Base
  validates_uniqueness_of :ebay_item_id, :amazon_asin_number
  validates_presence_of :ebay_item_id, :amazon_asin_number
  validate :ebay_item_validation, :amazon_asin_number_validation

  @@thread_compare_working = false
  @@working_count = 1

  def self.ebay_product_ending?(ebay_product)
    ebay_product[:item].present? &&
        ((!ebay_product[:item][:listing_details][:ending_reason].present? &&
            ebay_product[:item][:listing_details][:relisted_item_id].present?) ||
            ebay_product[:item][:listing_details][:ending_reason].present?)
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
    rescue
      reasons << :unknown
    end

    reasons.each do |reason|
      errors.add :amazon_asin_number, reason
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
    notifications = []
    extra_content = nil
    p "*** #{@@working_count} ***"

    seconds = Benchmark.realtime do
      notifications, extra_content = @@working_count % 3 == 0 ? compare_each_product : compare_wish_list
    end

    Notification.where('seen is null OR seen = false').update_all(:seen => true)
    notifications.each { |notification| Notification.create! notification }

    emails_to = ['roiekoper@gmail.com']
    emails_to << 'idanshviro@gmail.com' if Rails.env != 'development'
    emails_to.each do |to|
      UserMailer.send_email("--- #{extra_content} \n ---   " + Product.all.map(&:title).join(',
'),
                            I18n.t('notifications.compare_complete',
                                   :compare_time => I18n.l(DateTime.now.in_time_zone('Jerusalem'), :format => :long),
                                   :new_notifications_count => notifications.size,
                                   :work_time => "#{Time.at(seconds).gmtime.strftime('%R:%S')}"),
                            to).deliver
    end
    @@working_count += 1
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
        { :errs => errors.full_messages }
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
      UserMailer.send_email("Exception errors:#{e.message}", 'Exception in compare wishlist', 'roiekoper@gmail.com').deliver
      write_errors I18n.t('errors.diff_error',
                          :time => I18n.l(Time.now, :format => :error),
                          :id => id,
                          :asin_number => product.amazon_asin_number,
                          :ebay_number => product.ebay_item_id,
                          :errors => "#{product.errors.full_messages.join(' ,')}, \n Exception errors:#{e.message}")
    end

    extra_content = "Over on #{page - 1} pages, out of #{last_page}"
    if page != last_page
      UserMailer.send_email('', extra_content, 'roiekoper@gmail.com').deliver
    end

    [notifications, extra_content]
  end

  def self.compare_each_product
    notifications = []
    agent = create_agent
    count = 0
    Product.all.each do |product|
      begin
        item_page = agent.get(product.item_url)
        ebay_item = Ebayr.call(:GetItem, :ItemID => product.ebay_item_id, :auth_token => Ebayr.auth_token)
        case
          when product.amazon_stock_change?(one_get_stock(item_page), notifications)
          when product.ebay_stock_change(ebay_item, notifications)
          else
            product.price_change?(one_get_price(item_page), ebay_item, notifications)
            product.prime_change?(one_get_prime(item_page), notifications)
        end
        count += 1
      rescue
        notifications << {
            :text => I18n.t('notifications.unknown_item', :title => product.title),
            :product => product,
            :image_url => product.image_url,
            :change_title => :unknown_item
        }
        # product.destroy!
      end
    end
    UserMailer.send_email("Over on #{count} products / #{Product.count}", 'End Compare Each Product', 'roiekoper@gmail.com').deliver

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
                         :change_title => "#{price_change.round(2)}_price"
      }
      update_attribute :amazon_price, self.class.show_price(new_price)
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
    ((item_page.search('#availability_feature_div').present? &&
        item_page.search('#availability_feature_div').search('#availability').present? &&
        item_page.search('#availability_feature_div').search('#availability').
            first.children[1] || item_page.search('.buying').search('span')[29]).children.first.text.strip) || ''
  end

  def self.one_get_prime(item_page)
    match_page_price = get_match_price(item_page).last
    match_page_price.present? && (match_page_price.search('#ourprice_shippingmessage').
        search('.a-icon-prime').present? || match_page_price.search('.a-icon-prime').present?) ||
        match_page_price.search('#actualPriceExtraMessaging').search('img').
            first.attributes['src'].value.include?('check-prime')
  end

  def self.one_get_title(item_page)
    item_page.search('#productTitle').children.first.text.strip
  end

  def self.one_get_image_url(item_page)
    image_page_url = item_page.search('.a-button-toggle').present? &&
        item_page.search('.a-button-toggle')[0].children[0].
            children[1].children[1].attributes['src'].value
    image_page_url[0...image_page_url =~ /_/] + '_SL160_.jpg' # remove all _SR38,50_ -> Small image
  end

  def self.upload_wish_list
    products_text = 'B00F8VBJTM, 251645745168
                      B0091A9T9S, 251645772409
                      B000MGD8X8, 261593838017
                      B00BMQFOTI, 261593856848
                      B00CSAWIP0, 251622238503
                      B00BMQFT0C, 261593877817
                      B00BMQFNWQ, 251645832770
                      B006P97RS8, 251645848543
                      B006P97S8C, 251645867198
                      B003PGQ1VI, 261593958483
                      B006P97RVU, 261593966732
                      B00DPE9EQO, 251646378468
                      B00GJX58PE, 251646391150
                      B0049FVB2I, 261594660202
                      B00F8UZJJE, 261594710171
                      B00IM7HX1W, 251646605503
                      B008L9Z5E8, 251646640608
                      B00CN52TRM, 261594756036
                      B000I19D90, 261594758258
                      B008CA7W7E, 261594764275
                      B003TM1BAE, 251646660056
                      B0045122EM, 251646672506
                      B0000AXYLP, 261594798461
                      B00CGVMMPC, 261594802908
                      B00IDWOQ0C, 261594820009
                      B007TGMJ3E, 251646709680
                      B0028AED1W, 261594828724
                      B00KIRR8BY, 251646718093
                      B00HH0G3VQ, 261594835678
                      B002DRLESA, 251646723088
                      B0035HBFWM, 261594846793
                      B003KJ07ME, 251646734647
                      B00591WMAQ, 261594861594
                      B007R5C6CG, 251646758673
                      B000HJ9FZU, 251646762627
                      B00591C0F8, 261594882461
                      B00GK7PUB6, 261594890017
                      B004G6WT4Y, 261594891595
                      B001OVEZ1E, 261594901148
                      B003KGBJ0Q, 261595009901
                      B0002ATD0Q, 261595020690
                      B007TGMJ48, 261595034890
                      B0047XMQBM, 261595046628
                      B0083S5PGK, 251646945258
                      B0035UTVSY, 261595542183
                      B0058RVR6G, 251647401281
                      B00AVPZ1UI, 251647407065
                      B00CWM9BK4, 261595559580
                      B005B1LN40, 261595566801
                      B009SALE9O, 251647446052
                      B00GOFLGX0, 251647451227
                      B00B3BWYXQ, 251647455697
                      B00F0622IC, 261591976910
                      B003E1VZY2, 261591989371
                      B005L4OM22, 251644071336
                      B00CU7KAI8, 251644084585
                      B00EK9VIZI, 261592025326
                      B00F0626NS, 261592034355
                      B00F062JIK, 261592059367
                      B00CUVNT7I, 261592070203
                      B00F062QXI, 261592081924
                      B002YK4YII, 251644154442
                      B00I3L453G, 251644453198
                      B00I3L451S, 251644457240
                      B00I3L4540, 261592418578
                      B00FZJURKE, 251644468363
                      B00FZJUZS8, 261592432583
                      B00851A3VC, 261592439070
                      B007G2MBD4, 261592607566
                      B00DYNRCVA, 261592613305
                      B005QG5314, 251644632379
                      B008INZ466, 261592650626
                      B008XZFOAK, 251644663552
                      B005S4D6TU, 261592661851
                      B00D3RBCJ0, 261592679903
                      B000067QMM, 261592693589
                      B000EXRSI0, 261593431771
                      B000C17T3I, 251645416191
                      B00705Y4M8, 251645419967
                      B000BIA8XK, 261593448565
                      B00705YSJM, 261593451826
                      B00AZI0FLG, 251645429794
                      B00AZI0FMU, 261593460886
                      B00705XO7E, 261593466975
                      B00705Z9LI, 261593469403
                      B000BIBFB4, 261593546232
                      B002WTC37A, 261593732312
                      B00GOBPDAG, 251645724671
                      B00C9K10RG, 251642165053
                      B00DPGJZLG, 261590455806
                      B000P9IRLA, 251539523314
                      B00BC1ZCK4, 261489191184
                      B0055B7Y8U, 261574339835
                      B00450U7V8, 261489225641
                      B002VWJYSE, 261491631104
                      B0052SF0LO, 261578039651
                      B002V9199E, 251547482796
                      B003KRHDNC, 261495859068
                      B00DPK11ZA, 251547581427
                      B002HOFBQU, 251585192857
                      B003FBI9LS, 261496524492
                      B001D0C70C, 261496567508
                      B000H1MRJO, 261496624047
                      B0037UKP9G, 251634161456
                      B0030IMF8E, 251624264346
                      B002AQSWNE, 251632660245
                      B002YD8E5O, 261499043418
                      B0001HKC6E, 251551308130
                      B002PL5KYI, 261500237959
                      B005KC6DY0, 261501809170
                      B00KGEIX9K, 251554334856
                      B006PP8LHS, 261501877743
                      B0016BQFSS, 251554958012
                      B005V2WTSI, 251548427223
                      B00EB8KP4I, 261570739177
                      B00083HKL6, 261507990949
                      B0019IP11A, 261545671547
                      B004Y6V5CI, 261508524970
                      B000BX1H76, 261509255836
                      B004242Z2Q, 261509280342
                      B00B80TJX0, 261509426860
                      B00005MOU9, 261509468949
                      B00007DWBV, 251563294026
                      B00428LJ06, 261509492788
                      B0045UBG90, 261509500596
                      B00AIVNA4E, 251563318727
                      B003BTXSCE, 251638845098
                      B00005RF5G, 251563342467
                      B001I459AS, 261509534279
                      B000RHYPS4, 261509552538
                      B003HS5JTO, 251563386202
                      B000068CKY, 261509573551
                      B00005BRNH, 261509576451
                      B0023NVVAK, 261509961760
                      B00EPE5U52, 251564036823
                      B003LQVYGO, 261510299211
                      B007AIL1A8, 251602039360
                      B008I4XFWU, 261510318103
                      B000R9AAJA, 261510323527
                      B001MYGLJC, 261510327816
                      B00502KFNK, 261510336883
                      B0043494XS, 251564372763
                      B005967L7U, 261510401777
                      B00569CJI6, 251564401609
                      B0009PVV40, 261509390401
                      B000H94F6E, 251564961487
                      B002XT9A7K, 261586986013
                      B000A1FCNY, 251627475544
                      B001U899IK, 251565007007
                      B000Q5VXB4, 261511007687
                      B0002SQVL2, 251611285499
                      B005PR77WM, 261511023539
                      B002OUMVWY, 261511578381
                      B001Q7J18I, 251565764310
                      B004B9V1R2, 251599399287
                      B0000AUSHQ, 261511598489
                      B002IMMDN0, 251565793385
                      B00005IBXJ, 251565799192
                      B003VEG5SS, 261550726815
                      B000DZD3DI, 251565807367
                      B004048VNK, 251565815148
                      B0009V1BDA, 251565834290
                      B000P9GZUA, 251565837124
                      B002NUYTCA, 251565846750
                      B001FDV45G, 251565854918
                      B00251I66C, 251565861780
                      B003UVCY00, 261554952921
                      B004GIO0F8, 261511707365
                      B004NY9UXM, 251565914705
                      B000YAJKL6, 251565941752
                      B000MNN8DG, 261511739908
                      B002EL3YME, 261511776450
                      B003DA48XE, 261511789015
                      B0009E3G8U, 251566025013
                      B00004RA0N, 251629882407
                      B0027AANDA, 251566064757
                      B00004YTQ2, 261511852844
                      B000O15GWC, 251566086431
                      B007RM5CO8, 251566098238
                      B001BFZ3JG, 261511917101
                      B0006A36VY, 261511921333
                      B00264GIFO, 251566172102
                      B000E7NYY8, 261511759321
                      B004477ASK, 261555811760
                      B002CAF3PS, 261512799808
                      B00269II66, 261555818133
                      B004JMZH1C, 251567221029
                      B000RIA95G, 251567253255
                      B000GGVCXW, 261512963334
                      B0097D51HS, 261513334550
                      B001EX2EWE, 261513335520
                      B0034ZUZM6, 251568061941
                      B0019FOUQ0, 251568081219
                      B000FNB1SM, 261513627972
                      B002SUAQBS, 261583688928
                      B0001L0DFA, 251565858167
                      B001NJ0DRM, 251568370155
                      B002KENWZY, 251617389864
                      B005EHILV4, 261552314750
                      B00BOT1WB2, 251639487277
                      B003XU8ABA, 251568441385
                      B004CSZOE8, 251568453113
                      B001FB6TTE, 261513987692
                      B0009OLSY4, 251569284586
                      B0024ECCJW, 261514641244
                      B000GD3N1O, 261514648275
                      B000B6Q6BA, 251569322330
                      B001GXG3DS, 251614119128
                      B004412GTO, 261514861786
                      B007SNQ4FM, 251570290652
                      B001NQJEMA, 261515506110
                      B000R8E7UO, 261515515146
                      B008CMQTZI, 251570428579
                      B0073SYCWY, 251601376499
                      B000KIPT30, 261516612570
                      B0000E2PEI, 261566788815
                      B0072CK57C, 261516648439
                      B000NPSM0C, 261517129713
                      B00EVSF0SO, 261553629857
                      B003P90K58, 251572229570
                      B000QTOQ32, 261517980525
                      B0042HAUJ8, 251573891369
                      B000FJJL42, 251626891928
                      B00GPULY5Y, 251574281368
                      B001MK0G1A, 251600681212
                      B000C3QSPQ, 261519453901
                      B000B58628, 261583317781
                      B0043M4MPK, 251633052461
                      B000PGRXR2, 251593298132
                      B000EMXN4E, 251614436014
                      B0061MU0A6, 261521867550
                      B00FTBP2BW, 251576950784
                      B0091DJM24, 261522814985
                      B0082J9FAC, 261544954863
                      B001UE7D2I, 261507975874
                      B0002YPJRS, 251577956348
                      B004115B8U, 261522848793
                      B000BQRF60, 251577969765
                      B000QD1UUU, 251578012878
                      B000FRQL42, 261522924915
                      B00005KC92, 261522938581
                      B007EI3TW2, 261522945520
                      B001IDZHF6, 251569604852
                      B007SYAMUY, 251613479390
                      B000RMSGXO, 261544992610
                      B004T0AEFS, 261523653210
                      B001MJWN4O, 251600681212
                      B0089W1IGG, 261569509508
                      B0006VK68E, 251618229291
                      B009GCXETW, 251646361185
                      B001PKLWM4, 251597302364
                      B002QFU56G, 251604381612
                      B000F94GPQ, 261524325347
                      B002JAO5YQ, 251621345015
                      B00008IH9X, 251612216638
                      B0056L5NGO ,261524404058
                      B00EP6I6QU, 261524409548
                      B001DNIIOS, 261524412616
                      B007VDN1PA, 251579671126
                      B0032UY9DO, 261525352909
                      B005GYUM0I, 261525402354
                      B002YIACG8, 251580784843
                      B0024E6Z9U, 261525473410
                      B0013I46NU, 261525522472
                      B00004SD7D, 261525527522
                      B00IALPZ3I, 251580871931
                      B003TOBM1K, 251579499011
                      B000F5K9M4, 251599323522
                      B009V5X1CE, 251581674728
                      B002XLHUQG, 261526324636
                      B000BOA0BY, 251581726887
                      B0016KABFC, 251639796348
                      B0002913MI, 251581753477
                      B0002TDUW4, 251621314618
                      B003N6OBI0, 251581826098
                      B0006JO0TC, 261526453731
                      B0031U0P4W, 261526463236,
                       B004RNR9QY, 261559137845
                      B00002N7FP, 261572918382
                      B001F51AM6, 261487223388
                      B000YA9E4Y, 251582516141
                      B00IBDOB5I, 251582551035
                      B002GU6QEG, 251582557578
                      B00C5TEJJC, 261547288428
                      B0063662H0, 251582734075
                      B00EDQK7X2, 261585918991
                      B001PRX7WK, 261442323875
                      B000EM9DG6, 261573896686
                      B005GX3GFW, 261578687206
                      B00FTAKZ10, 261528585265
                      B002AP95H2, 251572270825
                      B0006IX7Y2, 251584135265
                      B00491KE9I, 261528586182
                      B005VRLT6Q, 251645402415
                      B00IM70C7O, 251569577171
                      B002XX5ETO, 251584397054
                      B005KR4LP8, 251600958201
                      B001K7IAMW, 261528936215
                      B007VH5EBK, 261528949596
                      B0007UQ2E6, 251584517011
                      B0018BQ7Do, 251584556303
                      B007X9J85Y, 251585192857
                      B001JF5THE, 251585198333
                      B00AMNCYNQ, 251585203791
                      B000N9FBZW, 251586007383
                      B00003008E, 261530455965
                      B004QYN5IU, 261585500950
                      B0018P7WZ2, 261552313176
                      B00DPGVWDA, 251587114999
                      B0018DQ1RY, 251587247728
                      B008CFT57E, 261531673899
                      B002S0NP7K, 251615729894
                      B002V94KCW, 251605231666
                      B0000BYDEA, 261586388116
                      B00JIJB72E, 261531745213
                      B0007RXD8M, 261559692037
                      B0015TMI28, 261532489574
                      B000Q2Y95O, 251582223453
                      B000FHZNQO, 251642165053
                      B0027Z29TQ, 251629321023
                      B003VYAGLK, 251588434836
                      B004OA2JME, 251588445619
                      B0057ECYS0, 261532902781
                      B0002ASXNY, 261572444384
                      B003XGYDE2, 251588738999
                      B001F51A0S, 251588773787
                      B005QIYSJ0, 261523480962
                      B004RCSS3I, 251589549807
                      B00022P11O, 251589560787
                      B002CLQ1Q2, 261459427316
                      B000ITVSSQ, 261534045280
                      B007OWTTAO, 251577096307
                      B007R6HUDK, 261534388315
                      B000AM2K56, 251537426838
                      B000KPGMUW, 251590455019
                      B0046EC19Y, 261517129713
                      B003F11K0U, 261495227598
                      B00ETP7D8Y, 261487652623
                      B00993F5WC, 261534861292
                      B003QA205O, 251579500412
                      B00BH80LTO, 261549909452
                      B000NM4DVW, 261535425029
                      B000X5QJY8, 251591315864
                      B000P9F0E2, 251591371661
                      B0032UY0BK, 251592398403
                      B002E3KYTS, 261552303068
                      B008DDPLEG, 261536566921
                      B0019UIZUC, 261536747244
                      B0002T48DO, 261579305920
                      B005DKJLLQ, 251618773494
                      B000ETUGTM, 251626884508
                      B0037MMES4, 261536830556
                      B00FZMDCMG, 261536834028
                      B0051XDMRY, 261537044545
                      B000VK0VCQ, 261582499776
                      B000C194F4, 251601858161
                      B007G3VAX0, 251592937600
                      B00CJO90ZG, 251592944056
                      B00GSPFCYU, 251648383995
                      B00B57PHTQ, 261537140710
                      B00310210I, 261555816971
                      B006YBHE6M, 261584685820
                      B002EL3ZBO, 251593030982
                      B004H4X6Z6, 261537193485
                      B0036FTNQ8, 251593066087
                      B000C17L2W, 261514229885
                      B00BGMI3DC, 251593152596
                      B00DW4RRVG, 261537328220
                      B002PQZEHQ, 251615331099
                      B00080LZVA, 251593685020
                      B002Z7FMPO, 261538016574
                      B00CKH9SEK, 261538025822
                      B00CPHGFAU, 251593898735
                      B00CWYONFU, 251595511475
                      B001KBYUYU, 251594008738
                      B001EWEAMW, 251594008738
                      B005GEPO3S, 261538233399
                      B00CSAWINW, 251640715876
                      B0026C780U, 251594134559
                      B00CBVZYUW, 261538333031
                      B007HHQ4VI, 261469368743
                      B0024AKCTS, 261563180543
                      B00AWMP894, 261539047771
                      B00AWMP880, 261539051983
                      B008VQLQQC, 251594845722
                      B002CVTL3M, 261566598039
                      B005XVCR4I, 261539098873
                      B0094J4NLA, 251623821199
                      B00LLH90OI, 251594936838
                      B001M20PLO, 261539195812
                      B00AAPGA2W, 261539206319
                      B008981SDI, 251568434711
                      B00G00BT1S, 251602618427
                      B0000A1O7P, 251552834173
                      B001CATTEA, 261539462481
                      B003LZKRVI, 261576990689
                      B0000DEW8N, 251622238503
                      B002RXHW6S, 251595702192
                      B005QIYUMU, 261540009683
                      B0038B2EKM, 251595741004
                      B00C6PSYK0, 261540060765
                      B00DKCI1P6, 261540069263
                      B00AJSJCC0, 261592448138
                      B006YBG1WA, 261540084983
                      B00CMNX2LM, 251595817601
                      B00F6N0YNE, 251595841425
                      B000LPFUG8, 261539227953
                      B0009Y0188, 251556490097
                      B000BJ1CGQ, 251595924932
                      B00DPGJXJA, 261590458828
                      B00CI4L884, 261590480084
                      B00DT598S8, 251642647183
                      B002S0YKTW, 251642716942
                      B00B4HM8MG, 251642722167
                      B00AQ7UPYI, 261590582885
                      B00AQ7UPZC, 261590591183
                      B00E95KE1M, 261590594710
                      B00KGC63Y4, 261590617803
                      B002TTU2E4, 251642773707
                      B003LMIUEM, 261590648401
                      B002ZFNE92, 251642813066
                      B00D162D82, 251642823455
                      B00D162DAA, 251642828520
                      B009ZQ2OP4, 251642877072
                      B0059KUK4W, 251642883487
                      B00E4G2ZDG, 251643474174
                      B002QAZ8ZY, 251643477476
                      B009WZLOAO, 261591407256
                      B0002DHXUK, 251643523545
                      B0002DHXVE, 261591433754
                      B006OU4GNM, 261591450429
                      B002SDNSF6, 251643563695
                      B00857R9PY, 251643608848
                      B000DZBK6K, 261589928235
                      B0029Z9UNW, 261588496639
                      B00JAJ348C, 251640789296
                      B00L9A90MY, 251640787668
                      B0039NM530, 261588527480
                      B00EZGB4GO, 251640806705
                      B00KXVU2RW, 261588538777
                      B00703BOV4, 261588546108
                      B00CSLT3SY, 251640830262
                      B00MEQZ364, 251640885181
                      B00MEQZ3LE, 261588612685
                      B00K589F8A, 251640880121
                      B00FUV7OP8, 251641157414
                      B00167340E, 261588896000
                      B0017WTYFM, 261589466027
                      B00IEQULT2, 261589476840
                      B00008DFOG, 261586716814
                      B0041HYB7Q, 261587435174
                      B000VLZJLS, 251639825673
                      B003EQ41BG, 251639837641
                      B001A67EI4, 261587457875
                      B00LVOL454, 251639845479
                      B00FPCMXH6, 261587465370
                      B006J23H5S, 261587473215
                      B002FRM9DC, 251639857315
                      B004PT4ISC, 261587490256
                      B00AY6D6Q0, 251639879955
                      B00196P2O8, 251639882730
                      B00AY6D2QY, 261587521148
                      B00AY6D9PI, 251639894703
                      B001CL58BM, 251639899929
                      B00B994L6A, 251639905219
                      B006Z5MY3K, 251639946338
                      B003D6FEYA, 251639964243
                      B00D93AG2C, 261586543502
                      B004NBXUWC, 251638975609
                      B005VEWAN0, 261586561440
                      B000BO3DZ4, 261586566172
                      B0009YF2L4, 261586572426
                      B0002DJX44, 251639010852
                      B001F0RRUA, 261586598416
                      B000WFN0SC, 261586609157
                      B0013QRY22, 261586627629
                      B000A6UF4U, 251639051425
                      B007RBB6UI, 251639058353
                      B0089A62MS, 251639065354
                      B007VL06MI, 261586655880
                      B000CA5VPC, 261586664495
                      B00IDZT294, 251639093240
                      B008J7G1QI, 251639153490
                      B000UUW3VY, 251639164251
                      B000UUSB2Y, 251639171828
                      B0019O178K, 261586765452
                      B0019O82WY, 261586772296
                      B001652VM8, 251639199415
                      B001651BQK, 261586792167
                      B00JRQM88K, 261586815499
                      B0051HEDMI, 251639233958
                      B00ER9SR5K, 251639256905
                      B004ISDGW4, 261586858183
                      B004SPPRR4, 261583509544
                      B00BCSYZG4, 261583516344
                      B004005WWW, 261583522545
                      B00J8VOM3I, 251636123103
                      B003VP29M8, 251636136767
                      B003GEKXRM, 261583552445
                      B007H4GIVW, 251636150678
                      B009NCLM8U, 251636157410
                      B00HLQOKQ6, 261584000035
                      B001AYPKD2, 261584010000
                      B00IFWK9W4, 251636642820
                      B00FC9FRVG, 261584652124
                      B00FC2FENO, 251637225519
                      B00FC2F7P4, 251637227514
                      B0026IBSUA, 261584673551
                      B00AFLH3HM, 251637249275
                      B00HFY6IQ4, 261584691123
                      B009EF6RFO, 261584694849
                      B00BTGQKEY, 251637261980
                      B009ZHU9MI, 261584767343
                      B00E9E9M66, 261584776223
                      B00A10XVAU, 251637341298
                      B00F06TTFG, 251637348835
                      B00EYPHKZ0, 251637355031
                      B002Y3WFUO, 261584800434
                      B00EB8KOYO, 251634689281
                      B00EB8KMP0, 261582073588
                      B00EB8KOVC, 251634706156
                      B005Q91Q30, 251634712683
                      B00CH3A86O, 251634719060
                      B007TIE14M, 261582096321
                      B0098LS03Q, 251634740465
                      B004S0UMYM, 261582123916
                      B00BGTNY8O, 261582144097
                      B004DMUBVE, 261582163821
                      B00132ZG3U, 251634831057
                      B000JE7CMG, 251635884003
                      B005IIR9F8, 261583292876
                      B002LNVMIS, 251635911013
                      B000ANEPYO, 251633844164
                      B000NBIO0Y, 251633851605
                      B00EIDFSBG, 261581172798
                      B0000DG8AR, 261581202860
                      B0000DGG8B, 261581210332
                      B0000DGF5S, 251633902919
                      B009N5OLJY, 261581238417
                      B0030MB4GO, 261581253937
                      B0030MD0BQ, 261581262644
                      B0000DGG1U, 261581278149
                      B005MUWNV2, 251633967332
                      B0020ZY3W4, 261580058134
                      B000LPF018, 251632851445
                      B001722D82, 251632937521
                      B00J0FX6MA, 251631497170
                      B00J4PL7FO, 261578682542
                      B003OEUDMO, 251631511114
                      B00KREJIZ2, 251631515154
                      B00C3YISR8, 261578695526
                      B00CWK2G4Y, 251631524043
                      B007TXI6E8, 261578705275
                      B004QKSWUK, 261578709636
                      B003B1Z0S2, 251631537854
                      B000GRKXWM, 261578717508
                      B004HIZFPQ, 261578722414
                      B007HT5WKA, 251631551416
                      B000VBGS4A, 261578732614
                      B009ZIDWHG, 251631726157
                      B009ZIE0YK, 261578901626
                      B009ZIDRMG, 261578911703
                      B009ZIEFAY, 261578915464
                      B009ZIF6QG, 251631746864
                      B009ZIDNMK, 251631749048
                      B00HRSL02A, 261578926210
                      B009ZIETC8, 261578933401
                      B009ZIEXI8, 261578937123
                      B00CXNXUF4, 251631762656
                      B00HRSLOEO, 261578948373
                      B00HRSLJVW, 251631770183
                      B005F486PC, 261578980606
                      B002YKMPQ6, 261578986229
                      B000FA03KC, 261579026061
                      B004J4HXAS, 261579052591
                      B00ATGHKE4, 251631885814
                      B007MV6I10, 251631892700
                      B006NP9E8K, 251631973892
                      B0053DDNW6, 261577231571
                      B00IXY6DO2, 251630154238
                      B00GGQC6PY, 261577308617
                      B00F57M4MA, 251630240178
                      B002NKX48A, 261577451014
                      B00B0DW9N2, 251630315038
                      B007RQ304I, 251630326035
                      B0055BEAKK, 261577472085
                      B003SIUDV2, 251630350097
                      B00K4UCQCG, 261578003650
                      B00009QMQT, 261578019088
                      B00CJD5GJ6, 251630879385
                      B002LFITQE, 261578031615
                      B005Z7TWZM, 251630892414
                      B00BSJVNOE, 251630902381
                      B000NI6LB6, 251630906287
                      B008XBHITO, 261578064767
                      B0083WH2AS, 261578106689
                      B004NPI3OI, 261578110092
                      B00K89HYOI, 261578115519
                      B007TXJWIW, 261578120406
                      B0006NDB6Q, 261578126413
                      B009TMYBZU, 261578134367
                      B0095EU660, 251630984438
                      B002R27DF4, 261578150104
                      B006YVDY5W, 261578163692
                      B007B525OQ, 261578169382
                      B00IRXWFOG, 261578175862
                      B003ANV102, 251631027876
                      B000KI111Y, 251631035414
                      B00D8YSJTE, 261578201746
                      B001CELJQM, 251631057037
                      B009MM0MZK, 251631067592
                      B0049J4O0K, 261576185181
                      B005JPWNVU, 251629117617
                      B0049J6FWA, 251629168452
                      B00GCFCA00, 251629189847
                      B002PB23SO, 261576277452
                      B00FP19LAE, 251629218022
                      B006L88QJM, 251629237491
                      B0000BW4LU, 261576324665
                      B00AH9HVYW, 261576338931
                      B00064CJMC, 261576366339
                      B0000AXTVF, 251629288626
                      B000VYO7Y0, 251629329885
                      B002KG03AO, 251629353995
                      B000UVV1G6, 261550499228
                      B00EZD3M0S, 261573155404
                      B00DZL7EZU, 261573162052
                      B00EHTX9KI, 261573175755
                      B008PX7HUU, 261573181898
                      B00F3UE8YQ, 261573191315
                      B000LI6S2U, 251626214151
                      B00AEVIG9C, 251626512453
                      B004NBXIQA, 251626512453
                      B0045UBG6S, 261574192178
                      B000NV7N2Y, 251627151934
                      B00CMUN1Z2, 251627160024
                      B00HNAPNE8, 251627176119
                      B0010B8CHG, 251627186587
                      B00M4QLKRU, 251627195644
                      B00F6N0G50, 261574256113
                      B00FZM93C4, 251627301005
                      B00078ZHIU, 261574347848
                      B000IE0YIQ, 261575123293
                      B00889ZYPQ, 251628101163
                      B0081STHQQ, 251628227572
                      B009XFLHZA, 261571271624
                      B005MZE1TO, 251624722395
                      B00CPRU56A, 251624880905
                      B00CBFAE6C, 261571880292
                      B00CA6LAQA, 261571885142
                      B004CEJYCA, 261571893201
                      B00DHLIGE6, 251625135414
                      B00IGFNMEC, 251625138944
                      B00HY6C4KM, 261571925762
                      B00I3YVAFE, 261571931467
                      B00ITYTQVS, 251625155296
                      B009WD9E4E, 251625159250
                      B005O2260G, 261572109204
                      B00BIRB6KM, 261572114909
                      B00EV5C36O, 261572151667
                      B002TAEERE, 251625327266
                      B00B7UR2SA, 251619067149
                      B0094B9BHE, 251622602416
                      B004SL30RC, 261568742623
                      B0079IRIG0, 251622623556
                      B00C625KPA, 251622633129
                      B00BLFLYW6, 261568848316
                      B000UHMITE, 261568860687
                      B00BRMPPUA, 261568869841
                      B0044DEXPW, 251622744443
                      B00J9TOD1A, 261568898634
                      B00CAAKYGS, 261568899947
                      B001GFINJ8, 261568899947
                      B00GBQ5D2M, 261568944343
                      B0078IMV1S, 261568949402
                      B00GBQ5B38, 261568956438
                      B00MHALAVE, 261568966278
                      B00CICT0TU, 261568981152
                      B008OLKVEW, 261569762772
                      B00002N8HZ, 261569773219
                      B00AJG6QCG, 251623462462
                      B00GJWG7UA, 261569790280
                      B008F9UCPG, 261569811358
                      B004XZA0YO, 251623487317
                      B00FDU4WZQ, 261578319964
                      B000FJRSOW, 251623515350
                      B00G055MT8, 251623522620
                      B00BIDKB9I, 251623522620
                      B009067AHG, 251623696554
                      B00BU3YI1S, 261570097577
                      B00ELPIYZI, 251623727360
                      B000ASKN90, 251624365334
                      B0002Z2U6A, 251624372247
                      B000063CK5, 251624394740
                      B0000DHVLE, 261570927688
                      B0002LX8BK, 251624401169
                      B009SJNRMW, 261570940257
                      B00HTB2XOO, 261570951164
                      B00GXUEB38, 251624423279
                      B009FRABOE, 261570961409
                      B00243GXHK, 251624432837
                      B00J4HTYES, 251624432837
                      B00J4HU4S8, 261570988608
                      B00IGITHDE, 261570997994
                      B004WP96OU, 251624465892
                      B00846KOCG, 261571032013
                      B009N7X67U, 261571041364
                      B00757WIRY, 261562218232
                      B00JRDA9JI, 251619027979
                      B00JX89RJ0, 251619035941
                      B00JX8IM6E, 251619048833
                      B005CXOKOC, 261565112529
                      B0057KTMCU, 261565162205
                      B00CRMYLZY, 261565168206
                      B009WLR4BQ, 251619710779
                      B00E8YK7T8, 251619717287
                      B00E8J5KNQ, 261565204705
                      B00E8JLNVO, 261565233369
                      B00HWPAAQA, 251619755615
                      B004D2LHXA, 251619763244
                      B002P2YGHE, 261565297691
                      B0015XGCN0, 261565554578
                      B0041BPFDG, 261565591195
                      B0042TNMMS, 261566345717
                      B000LNY5IE, 251620672992
                      B00DTWB2QW, 251620679526
                      B003FJ8EI8, 261566432512
                      B00F5Y4VU6, 251620754027
                      B004FPYFGQ, 261566730766
                      B008KW8IWW, 261566741203
                      B003F0YY6S, 261566750207
                      B00292BX94, 261567297093
                      B00FLXBCTO, 261567301260
                      B00FLXBEZQ, 261567305285
                      B000A1FV9Y, 251621661777
                      B000YMPBVM, 261561572852
                      B00FFVVOOA, 251616675534
                      B00CQAJG6Q, 251616683834
                      B00FG0J6CW, 251617126340
                      B00BN562T4, 251617173716
                      B00DQYVOI4, 251618008163
                      B00B7UGZ24, 251618013687
                      B00G3ONFSQ, 251618024879
                      B00GKZCX7W, 261563182078
                      B002UG5D2C, 251614610856
                      B0003099EK, 251614620833
                      B004DFSRMG, 261559357098
                      B006SMTCB2, 251614643881
                      B0074P2O6C, 251614653007
                      B002UG8NC4, 251614667427
                      B000NWWS3W, 251614986918
                      B00IAV982W, 261559762211
                      B00FM9QZ4E, 261560381121
                      B004KSN8XY, 261560399984
                      B009L1VV7U, 251615602895
                      B0000E2PO7, 251615610561
                      B005OYE7HE, 261560447119
                      B00005Q5I8, 261560467368
                      B002JKMSZY, 251615659948
                      B0000DJBIR, 251615668265
                      B000OTEZ5I, 251635100088
                      B007JNVAXM, 251610603236
                      B007JQYM52, 251610610226
                      B00JB31BYQ, 251610616375
                      B0056QXNXY, 261554515609
                      B002NKYWO0, 261554531141
                      B000HHS7YC, 251610111164
                      B003QH3HKY, 261554545958
                      B00IF0MJXI, 251610121931
                      B000J3FW10, 261554561033
                      B00CM85KV2, 251610198922
                      B00752QAKU, 261554653538
                      B0080KHF82, 261554658166
                      B004PEIVOY, 261554687500
                      B0043SK7A8, 261554693609
                      B000B7M3SY, 261554702803
                      B003VXG7Y6, 251609090444
                      B00KTH5I6A, 251609095705
                      B000LWRZNM, 261553494360
                      B000GOZZJG, 251609106575
                      B00HS3NI4W, 251609116728
                      B00IKGHRGQ, 261553520122
                      B005QVS3MU, 251609131965
                      B000Z8T7FQ, 251609143330
                      B00FATWGSU, 251644491752
                      B000WTXEIE, 261553550794
                      B005FDIUPE, 261553558574
                      B00BGIXZO8, 261553582048
                      B00IPOP5W6, 251609201684
                      B00BNPBM6M, 261553610855
                      B003ZW8DDG, 251609217947
                      B002ON0AB0, 251609226267
                      B001UFQKJ4, 251608139101
                      B003D0RDC2, 261552518909
                      B00AOPOZIO, 251608154902
                      B00J0GVUTK, 251608166201
                      B009MRDMSY, 251608175970
                      B001IABN4S, 261552570518
                      B00IJC8RCO, 261552588983
                      B00JF83DZW, 261552599144
                      B00K4IA4X6, 261552613039
                      B004ZLXOEY, 261552628290
                      B00858QBM0, 261552636317
                      B00EQ7TDMO, 251608270274
                      B00F9GLM2A, 251608283245
                      B00DMB7ALG, 251608289111
                      B00F5883TW, 251608300742
                      B000T3OO8C, 261550661932
                      B002KYNCRM, 261551895454
                      B000E48ITC, 261551906146
                      B00JJ48X4I, 261551916222
                      B0050P22VK, 261551922682
                      B002448TJE, 261551950343
                      B007WMKPNG, 261551960236
                      B008FQDX78, 261551976577
                      B00BS2W78W, 251607628590
                      B00EUVFXS4, 261552006721
                      B00ILT0GC4, 261572917370
                      B000HMAB00, 251604583899
                      B00BU5LV7K, 261548757210
                      B000Y9TEMM, 261548764897
                      B001600WCY, 251604615841
                      B002V1H13K, 261548800385
                      B00HYLXGDQ, 251604650560
                      B000MPPD9Q, 261548822456
                      B009UQ190A, 261548828412
                      B00F19Q40U, 261548834951
                      B000RTN362, 251604688825
                      B003BMVI96, 261548851888
                      B0032JSPWQ, 261548863515
                      B0001DLLU4, 261548876149
                      B00005LL3N, 251604721576
                      B00005BPHV, 261548886544
                      B00KZ19R1C, 261549686442
                      B000I1Q59G, 261549827939
                      B000I1RLV2, 251605618810
                      B0042ES4MG, 251621690111
                      B008RKCJ2M, 261549854445
                      B00859GIQ8, 251605665670
                      B00JC3MP2M, 261549896377
                      B006O6F932, 251605689874
                      B003OF0PB2, 261549973679
                      B009357J5C, 251605753330
                      B006PHU4F8, 251605761217
                      B00CDL31AU, 251605792477
                      B00GXCO3K2, 261550043913
                      B00B9BFRHU, 261550087117
                      B00BSWSFEC, 251606174922
                      B005HC3QBG, 251606183513
                      B009B7L020, 251606220351
                      B008KYV7KA, 261550499228
                      B004DDQK0O, 251606259349
                      B002QQ48TK, 261550544646
                      B002Q8YRYY, 261550553462
                      B002Q8V8DM, 261550559783
                      B002Q93CGM, 251606290668
                      B003YFADW8, 251606301874
                      B008YQMLUO, 261550606619
                      B002CVTT52, 251606424821
                      B00007J5U7, 251606436008
                      B001KVZZH6, 251606455232
                      B00591GN92, 261550761258
                      B002DML11K, 261550769120
                      B007D9WNC4, 261550778556
                      B0001MQ7A4, 261550803677
                      B002A9KDRY, 261550810592
                      B0015KMQOC, 261551479567
                      B008JSQFA4, 261551531763
                      B004NRP4L6, 261551536251
                      B00DY0SVI6, 251607192608
                      B00KNPAQ9M, 251607197738
                      B00CZ7X6YI, 261551561709
                      B00DUN8BX2, 251607221761
                      B0097CXO4Q, 261551597339
                      B00CSAWJQ8, 261536566921
                      B00HCABYMY, 251607251853
                      B00378K71E, 261551615761
                      B0097CZUUW, 261551633965
                      B00EGFKOZ6, 251607283716
                      B00GMLTAHA, 251607336279
                      B003EV7FCI, 261488292975
                      B004AC65LM, 251603762320
                      B00008URR8, 261547993724
                      B00IMJ5Y52, 251603831898
                      B00IRJ1BYU, 251603838780
                      B008DBRFBK, 251603853407
                      B00AZBIRDQ, 251603861089
                      B000GB0NZA, 261548077025
                      B003OYIAW4, 261548113976
                      B004KGD9W6, 261548120393
                      B003064FXY, 261548130664
                      B00306F51K, 251603989661
                      B000YFD6WU, 261548176566
                      B00178KW8E, 251628427234
                      B00HZARQQ4, 261552981536
                      B002ZK8U28, 261548201590
                      B00AEF0W7W, 261548207454
                      B004NXT3TE, 251604048209
                      B005SI8YZC, 251604063421
                      B004KSQOBM, 251601601083
                      B006P3NVK2, 261545911640
                      B007VAS2K2, 261545924304
                      B005I2GCXY, 251601642416
                      B00AJCNQXC, 251601763982
                      B008N4NJ8U, 261546054706
                      B00F3B4YMQ, 251601785418
                      B003EQ3CRK, 261546074709
                      B000E3BNUE, 261586682744
                      B002CQUDOI, 261546101746
                      B00AWC200Y, 251601834916
                      B000JCGYEK, 251601844410
                      B009HMK1K6, 251601856334
                      B003H4BEKQ, 261546224673
                      B000KGDYQG, 261546675204
                      B0057FOFIQ, 261546777945
                      B00HTPHK5W, 251602606300
                      B003JILWUW, 251602624746
                      B00BHBJPHA, 251602690779
                      B00339912S, 261547049214
                      B0023Y1078, 261544043965
                      B00C6Y4J1E, 251600428521
                      B006J7G82C, 251600475262
                      B002Y2EHVA, 251600487708
                      B004P8GHYQ, 261544798971
                      B004P8AC42, 261544803272
                      B00568CAVI, 251600510014
                      B004DSR7EW, 261544817944
                      B002SG7Q1U, 251600520943
                      B00023RVNO, 251600551586
                      B00G987G9U, 251600568368
                      B005CQ63TE, 261544893295
                      B007IG0VKI, 261544954863
                      B00EPH0CIO, 251600653053
                      B00EPH0AP4, 261545089293
                      B00JJGRXQA, 251600802429
                      B00HQHGUM2, 251600844270
                      B00DJQ9REW, 261545217332
                      B00E1RUYUY, 251600921403
                      B0000AVE5B, 261545244979
                      B006WLS38W, 251600978638
                      B003NRYEQS, 261543104752
                      B00IVLISFO, 251599287241
                      B00G988DK6, 261543637467
                      B00H5X44IO, 251599324979
                      B005L2NVC6, 261543703690
                      B00FVQ5C4W, 251599371606
                      B006ZCI59A, 261543726004
                      B002YVYHV6, 251599386309
                      B007UJ4TJ2, 251599399287
                      B00E448EN8, 251599405157
                      B0018N9HIO, 261543758738
                      B005I0JYUY, 251599437027
                      B00KI3DTVG, 261543796028
                      B0002IO7CM, 261543803420
                      B00CZ1MA2S, 251599468163
                      B00HR1AHUI, 251599481803
                      B00AQMUE30, 251599492148
                      B001J94L4C, 251599505581
                      B009FVDAA2, 261543861776
                      B0002AQLQA, 251599528973
                      B0032JSQSY, 251599533956
                      B00CHYSUJK, 251599543053
                      B004S59R98, 251599553919
                      B007EO8GGK, 251599562559
                      B001RNNBNW, 251599572067
                      B00HGLCEA0, 261543920939
                      B004HY4V00, 251582224678
                      B001L9FTTG, 261541742459
                      B000I84QZ4, 261541840434
                      B000FTE6NI, 251597629681
                      B0019FLH4S, 251597636134
                      B000A42YL4, 251597643441
                      B0035LLZ3W, 261541987744
                      B00LBD9PR4, 261542018603
                      B00LGNUII4, 251597689243
                      B002AR65QE, 261542732932
                      B008MV30M4, 251598396269
                      B0084U48YW, 261542742554
                      B00BMZPS72, 251598413969
                      B000HDHGWU, 261541005705
                      B005DGI6B6, 261541022621
                      B003G4J1PM, 261541073601
                      B00BE04NU8, 251596755593
                      B00AG0D984, 261541132736
                      B008KOBQE2, 261540922368
                      B0002IYILC, 261540964944
                      B0027VS0XY, 261552847658
                      B0042VK7FG, 261585500950
                      B000TYD4H8, 261470622807
                      B00279L0D8, 261469626398
                      B007BISCT0, 261585918991
                      B002L3TTAG, 261468647195
                      B000TM8K7E, 251520059700
                      B003DO5W12, 261591369908
                      B000VYIX8G, 261459243626
                      B000RY46G8, 261459230947
                      B000J3JDIS, 261485847063
                      B001I912SQ, 251536726936
                      B00EI7DPOO, 261486274464
                      B003VPEAO8, 261486348996
                      B000L53D4O, 261486547020
                      B000J1FA32, 261487128869
                      B003XU7VKQ, 251537991891
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