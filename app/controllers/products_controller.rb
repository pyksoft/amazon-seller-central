class ProductsController < ApplicationController
  respond_to :json
  before_filter :init_headers
  skip_before_filter :verify_authenticity_token
  http_basic_authenticate_with :name => 'admin', :password => 'roieroie', :only => :download_errors
  http_basic_authenticate_with :name => 'admin', :password => 'roieroie', :only => :download_compare_errors

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
    response = Product.new(params.permit(:amazon_asin_number, :ebay_item_id, :url_page).
                               slice(:amazon_asin_number, :ebay_item_id).
                               inject({}) { |h, (k, v)| h.merge(k => v.strip.upcase) }.
                               merge(params.slice(:url_page))).create_with_requests
    render({ :json => (response) })
  end

  def admin_create
    response = Product.new(params[:product].
                               slice(:amazon_asin_number, :ebay_item_id).
                               inject({}) { |h, (k, v)| h.merge(k => v.strip.upcase) }.
                               merge(params[:product].slice(:url_page,:prefer_url))).admin_create
    render({ :json => (response) })
  end

  def download_errors
    send_file "#{Rails.root}/log/errors.txt", :type => 'text/plain'
  end

  def download_compare_errors
    send_file "#{Rails.root}/log/add_wishlist_errors.txt", :type => 'text/plain'
  end

  def upload_wish_list
    Product.upload_wish_list
  end
end
