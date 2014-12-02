collection :@notifications
attributes :id, :text,:image_url,:row_css
node(:product) { |notification| {
 :title => notification.product.try(:title),
 :ebay_item_id => notification.product.try(:ebay_item_id),
 :amazon_asin_number => notification.product.try(:amazon_asin_number)
 }
}
