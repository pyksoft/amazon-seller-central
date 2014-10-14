collection :@notifications
attributes :id, :text,:image_url,:row_css
node(:product_title) { |notification| notification.product.try(:title) }
