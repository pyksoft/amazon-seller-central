class ProductsController < ApplicationController
  respond_to :json
  before_filter :init_headers
  skip_before_filter :verify_authenticity_token
  http_basic_authenticate_with :name => 'admin', :password => 'roieroie', :only => [:download_errors,
                                                                                    :download_compare_errors,
                                                                                    :export_products,
                                                                                    :import_products]

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
    product = params[:product][:id].present? ? Product.find_by_id(params[:product][:id]) : Product.new
    response = product.admin_create(params)

    flash[:notice] = response
    redirect_to '/admin'
  end

  def download_errors
    send_file "#{Rails.root}/log/errors.txt", :type => 'text/plain'
  end

  def download_compare_errors
    send_file "#{Rails.root}/log/add_wishlist_errors.txt", :type => 'text/plain'
  end

  def export_products
    respond_to do |format|
      format.xlsx do
        send_data Product.export.to_stream.read,
                  :filename => "products_#{I18n.l(DateTime.now.in_time_zone('Jerusalem'), :format => :regular)}",
                  :type => 'application/vnd.openxmlformates-officedocument.spreadsheetml.sheet'
      end
    end
  end

  def import_products
    respond_to do |format|
      format.html
      format.json do
        flash_message = Product.import params[:file].tempfile.to_path.to_s,
                       File.extname(params[:file].original_filename)
        redirect_to '/import_products', :notice => t(flash_message)
      end
    end
  end
end
