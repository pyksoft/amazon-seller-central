class ProductsController < ApplicationController
  respond_to :json

  def index
    @products = Product.all
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS'
    headers['Access-Control-Allow-Headers'] = 'X-Requested-With, X-Prototype-Version'
    respond_with(@products)
  end
end
