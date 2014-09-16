collection :@notifications
attributes :id, :text,:image_url
node(:product_title) { |notification| notification.product.try(:title) }