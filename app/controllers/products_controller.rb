class ProductsController < ApplicationController
  respond_to :json
  before_filter :init_headers
  skip_before_filter :verify_authenticity_token

  def init_headers
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS'
    headers['Access-Control-Allow-Headers'] = 'X-Requested-With, X-Prototype-Version , accept, content-type'
  end

  def index
    @products = Product.all.order(:prime)
    respond_with(@products)
  end

  def compare
    Product.create_products_notifications
    redirect_to '/notifications'
  end

  def create_product
    response = Product.new(params.slice(:amazon_asin_number, :ebay_item_id)).create_with_requests
    response[:errs] ? render({:json => (response[:errs])}) : redirect_to('/notifications')
  end
end
