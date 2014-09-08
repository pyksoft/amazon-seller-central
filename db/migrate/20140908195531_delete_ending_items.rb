class DeleteEndingItems < ActiveRecord::Migration
  def change
    products_deleted = []
    Product.all.each do |product|
      unless product.valid?
        products_deleted << product.as_json.slice(*%w[title amazon_asin_number ebay_item_id]).values.join(', ')
        product.destroy!
      end
    end

    %w(idanshviro@gmail.com roiekoper@gmail.com).each do |to|
      UserMailer.send_email(products_deleted.join('\n'),
                            "Deleted Products(#{products_deleted.size})",to).deliver
    end
  end
end
