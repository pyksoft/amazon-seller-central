# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20141011093416) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "lists", force: true do |t|
    t.string "kind"
    t.string "title"
  end

  create_table "notifications", force: true do |t|
    t.text     "text"
    t.integer  "product_id"
    t.datetime "created_at"
    t.boolean  "seen"
    t.string   "icon"
    t.string   "image_url"
    t.string   "title"
    t.string   "change_title"
    t.string   "row_css"
  end

  add_index "notifications", ["seen"], name: "index_notifications_on_seen", using: :btree

  create_table "products", force: true do |t|
    t.string   "ebay_item_id"
    t.string   "amazon_asin_number"
    t.text     "title"
    t.text     "image_url"
    t.float    "amazon_price"
    t.boolean  "prime"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "products", ["amazon_asin_number"], name: "index_products_on_amazon_asin_number", using: :btree

end
