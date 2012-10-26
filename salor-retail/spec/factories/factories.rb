FactoryGirl.define do
  factory :user do
    username 'admin'
    sequence(:email){|n| "#{Faker::Name::first_name}#{n}@factory.com" }
    password "31202053297"
    after_create do |u|
      u.meta = Factory :meta, :ownable_id => u.id
      u.save
    end
  end
  factory :user2, :class => User do
    username 'admin2'
    sequence(:email){|n| "#{Faker::Name::first_name}#{n}@factory.com" }
    password "31202053297"
    after_create do |u|
      u.meta = Factory :meta, :ownable_id => u.id
      u.save
    end
  end
  factory :customer do
    first_name Faker::Name::first_name
    last_name Faker::Name::last_name
    association :vendor
    after_create do |c|
      lc = LoyaltyCard.new
      lc.points = 300
      lc.sku = Faker::Name::first_name.gsub(/[^a-zA-Z]/,'')
      lc.customer_id = c.id
      lc.save
    end
  end
  factory :employee do
    username 'employee'
    sequence(:email){|n| "#{Faker::Name::first_name}#{n}@factory.com" }
    password "31202023287"
    after_create do |u|
      u.meta = Factory :meta, :ownable_id => u.id
      u.save
    end
  end
  factory :cashier, :class => Employee do
    username 'cashier'
    sequence(:email){|n| "#{Faker::Name::first_name}#{n}@factory.com" }
    password "31202003285"
    association :vendor
    association :user
    after_create do |u|
      u.meta = Factory :meta, :ownable_id => u.id
      u.save
      r = Role.find_or_create_by_name :cashier
      u.roles << r
      u.save
      u.drawer = Drawer.new(:amount => 0)
    end
  end
  factory :manager, :class => Employee do
    username 'manager'
    sequence(:email){|n| "#{Faker::Name::first_name}#{n}@factory.com" }
    password "31202053295"
    association :vendor
    association :user
    after_create do |u|
      u.meta = Factory :meta, :ownable_id => u.id
      u.save
      r = Role.find_or_create_by_name :manager
      u.roles << r
      u.save
      u.drawer = Drawer.new(:amount => 0)
    end
  end



  factory :discount do
    name "test discount"
    start_date (Time.now - 2.days)
    end_date (Time.now + 2.days)
    amount 50
    amount_type 'percent'
    association :vendor
    association :category
  end
  factory :salor_configuration do
    association :vendor
    address "None"
    calculate_tax false
    license_accepted true
    pagination 10
  end
  factory :order do
    association :vendor
    association :user
    association :cash_register
  end
  factory :meta do
    vendor_id 0
    ownable_id 0
    ownable_type 'User'
    order_id 0
    cash_register_id 0
    last_order_id 0
    color "#ffffff"
  end
  factory :category do
    name "Test Category"
    association :vendor
  end
  factory :vendor do
    name "TestVendor"
    association :user, :factory => :user
    
    multi_currency false
    after_create do |v|
      v.salor_configuration = Factory(:salor_configuration, :vendor => v)
      v.save
    end
  end
  factory :cash_register do
    name "Cash Register"
    association :vendor
    thermal_printer "/tmp/thermal_printer"
    sticker_printer "/tmp/sticker_printer"
    salor_printer false
  end
  factory :tax_profile do
    name "Test Tax Profile"
    value 20
    sku "TP1234"
    association :user
  end
  factory :item_type do
    name "Normal Item"
    behavior "normal"
  end
  factory :item do
    name "Test Item"
    sequence(:sku){|n| "#{Faker::Name::first_name.gsub(/[^a-zA-Z]/,'')}#{n}factory.com" }
    base_price 5.95
    quantity 100
    quantity_sold 0
    association :vendor
    association :tax_profile
    association :item_type, :factory => :item_type
    association :category
    coupon_type 0
    coupon_applies ""
  end
  factory :shipper do
    name "The Shipper"
    association :user
  end
  factory :stock_location do
    name "StockLocation"
    association :vendor
  end
  factory :shipment do
    name "Shipment"
    association :user
    association :vendor
  end
  factory :shipment_item do
    association :shipment
    name "ShipmentItem"
    sku "STEST"
    quantity 1
  end
end