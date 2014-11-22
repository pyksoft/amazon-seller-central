ActiveAdmin.register Product do

  index do
    column :title
    column :amazon_asin_number
    column :ebay_item_id
    column :amazon_price do |product|
      div :class => :price do
        number_to_currency product.amazon_price, locale: :en
      end
    end
    column :prime
    column :url_page
    column :image_url
    actions
  end


  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # permit_params :list, :of, :attributes, :on, :model
  #
  # or
  #
  # permit_params do
  #   permitted = [:permitted, :attributes]
  #   permitted << :other if resource.something?
  #   permitted
  # end


end
