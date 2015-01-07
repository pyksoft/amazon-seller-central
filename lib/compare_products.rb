class Product
  def compare_with_url(agent,log,pages,notifications)
    item_page = agent.get(item_url)
    ebay_item = Ebayr.call(:GetItem, :ItemID => ebay_item_id, :auth_token => Ebayr.auth_token)
    log << "amazon_asin_number: #{amazon_asin_number},ebay_item_id: #{ebay_item_id},id: #{id}, Amazon stock: #{Product.one_get_stock(item_page)}, Amazon In Stock? #{Product.in_stock?(Product.one_get_stock(item_page))}, Price: #{Product.one_get_price(item_page)}, Prime: #{Product.one_get_prime(item_page)}"

    if item_page.body.include?('dcq_question_subjective_1')
      UserMailer.send_email("Exception in item page: #{item_page}, product: #{attributes.slice(*%w[id ebay_item_id amazon_asin_number])}", 'Exception in compare ebay call', 'roiekoper@gmail.com').deliver
    end

    if !Product.in_stock?(Product.one_get_stock(item_page)) && !Product.one_get_stock(item_page).present?
      pages << {
          :page => "#{item_page.body.to_s.force_encoding('UTF-8')} \n\n\n ================================= \n \n \n",
          :product => amazon_asin_number
      }
    end

    if ebay_item[:ack] == 'Failure'
      UserMailer.send_email("Exception in ebay call: #{ebay_item}, product: #{attributes.slice(*%w[id ebay_item_id amazon_asin_number])}", 'Exception in compare ebay call', 'roiekoper@gmail.com').deliver
    else
      ebay_stock_change(ebay_item, notifications)
      if amazon_stock_change?(Product.one_get_stock(item_page), notifications)
        price_change?(Product.one_get_price(item_page), ebay_item, notifications)
        prime_change?(Product.one_get_prime(item_page), notifications)
      end
    end
  end
end