ActiveAdmin.register Product do

  config.per_page = 100
  config.sort_order = 'id_asc'


  permit_params :id,:title, :amazon_asin_number, :ebay_item_id, :amazon_price, :url_page, :image_url, :prime, :prefer_url
  filter :ebay_item_id
  preserve_default_filters!

  index do
    column :id
    column :title
    column :amazon_asin_number do |product|
      link_to product.amazon_asin_number, product.item_url
    end

    column :ebay_item_id do |product|
      link_to product.ebay_item_id, "http://www.ebay.com/itm/#{product.ebay_item_id}"
    end

    column :amazon_price do |product|
      div :class => :price do
        number_to_currency product.amazon_price, locale: :en
      end
    end

    column :prime
    column :prefer_url
    column :url_page do |product|
      link_to product.url_page, product.url_page.present? ? product.url_page : ''
    end

    column :image_url do |product|
      image_tag product.image_url, class: 'active_admin_image_page'
    end

    actions
  end

  show do
    attributes_table do
      row(:title)
      row(:amazon_asin_number)
      row(:ebay_item_id)
      row :amazon_price do |product|
        div :class => :price do
          number_to_currency product.amazon_price, locale: :en
        end
      end
      row(:prime)
      row(:prefer_url)
      row(:url_page)
      row(:image_url)
    end
  end

  form :url => '/products/admin_create',:method => :post do |f|
    f.inputs 'פרטי המוצר' do
      f.input :id,:as => :hidden
      f.input :amazon_asin_number
      f.input :ebay_item_id
      f.input :amazon_price
      f.input :prime
      f.input :prefer_url
      f.input :url_page
    end

    f.semantic_errors *f.object.errors.keys
    f.actions
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
