class ProductsController < ApplicationController
  respond_to :json

  def show
    @products = Product.all
    respond_with(@products)
  end
end
