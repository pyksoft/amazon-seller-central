Rails.application.routes.draw do
  ActiveAdmin.routes(self)
  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  # You can have the root of your site routed with "root"
  # root 'welcome#index'

  # Example of regular route:
  #   get 'products/:id' => 'catalog#view'

  # Example of named route that can be invoked with purchase_url(id: product.id)
  #   get 'products/:id/purchase' => 'catalog#purchase', as: :purchase

  # Example resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Example resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Example resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Example resource route with more complex sub-resources:
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', on: :collection
  #     end
  #   end

  # Example resource route with concerns:
  #   concern :toggleable do
  #     post 'toggle'
  #   end
  #   resources :posts, concerns: :toggleable
  #   resources :photos, concerns: :toggleable

  # Example resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end

  get 'products/compare' => 'products#compare', :defaults => { :format => 'json' }
  get 'products/download_errors' => 'products#download_errors', :defaults => { :format => 'json' }
  get 'products/download_compare_errors' => 'products#download_compare_errors', :defaults => { :format => 'json' }
  get 'products/upload_wish_list' => 'products#upload_wish_list', :defaults => { :format => 'json' }
  get 'notifications/progress_count' => 'notifications#progress_count', :defaults => { :format => 'json' }

  get 'products_export' => 'products#products_export', :defaults => { :format => 'xlsx' }
  # get 'import_products' => 'products#import_products', :defaults => { :format => 'html' }
  # post 'import_products' => 'products#import_products'

  post 'products/admin_create' => 'products#admin_create'
  post 'products/create_product' => 'products#create_product'
  post 'notifications/change_accepted' => 'notifications#change_accepted'

  resources :products, :only => [:index], :defaults => { :format => 'json' }
  resources :notifications, :only => [:index], :defaults => { :format => 'json' }
end
