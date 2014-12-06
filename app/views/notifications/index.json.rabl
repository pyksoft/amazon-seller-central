collection :@notifications
attributes :id, :text,:image_url,:row_css
node(:product) { |notification| {
 :title => notification.title || notification.product.try(:title),
 :ebay_item_id => notification.ebay_item_id || notification.product.try(:ebay_item_id),
 :amazon_asin_number => notification.amazon_asin_number || notification.product.try(:amazon_asin_number),
 :amazon_url => notification.product.try(:item_url)
 }
}
