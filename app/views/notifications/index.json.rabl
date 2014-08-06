collection :@notifications
attributes :id, :text
node(:product_title) { |notification| notification.product.try(:title) }
node(:image_url) { |notification| notification.product.try(:image_url) }