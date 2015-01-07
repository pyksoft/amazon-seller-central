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

ActiveRecord::Schema.define(version: 20141230061145) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_admin_comments", force: true do |t|
    t.string   "namespace"
    t.text     "body"
    t.string   "resource_id",   null: false
    t.string   "resource_type", null: false
    t.integer  "author_id"
    t.string   "author_type"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "active_admin_comments", ["author_type", "author_id"], name: "index_active_admin_comments_on_author_type_and_author_id", using: :btree
  add_index "active_admin_comments", ["namespace"], name: "index_active_admin_comments_on_namespace", using: :btree
  add_index "active_admin_comments", ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource_type_and_resource_id", using: :btree

  create_table "delayed_jobs", force: true do |t|
    t.integer  "priority",   default: 0, null: false
    t.integer  "attempts",   default: 0, null: false
    t.text     "handler",                null: false
    t.text     "last_error"
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string   "locked_by"
    t.string   "queue"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "delayed_jobs", ["priority", "run_at"], name: "delayed_jobs_priority", using: :btree

  create_table "lists", force: true do |t|
    t.string "kind"
    t.string "title"
  end

  add_index "lists", ["kind"], name: "index_lists_on_kind", using: :btree

  create_table "notifications", force: true do |t|
    t.text     "text"
    t.integer  "product_id"
    t.datetime "created_at"
    t.boolean  "seen"
    t.text     "icon"
    t.text     "image_url"
    t.text     "title"
    t.text     "change_title"
    t.text     "row_css"
    t.text     "amazon_asin_number"
    t.text     "ebay_item_id"
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
    t.text     "url_page"
    t.boolean  "prefer_url",         default: false
  end

  add_index "products", ["amazon_asin_number"], name: "index_products_on_amazon_asin_number", using: :btree

end
