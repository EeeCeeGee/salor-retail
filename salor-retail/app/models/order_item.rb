# coding: UTF-8

# Salor -- The innovative Point Of Sales Software for your Retail Store
# Copyright (C) 2012-2013  Red (E) Tools LTD
# 
# See license.txt for the license applying to all files within this software.

class OrderItem < ActiveRecord::Base
  include SalorScope
  include SalorBase
  
  belongs_to :vendor
  belongs_to :company
  belongs_to :order
  belongs_to :user
  belongs_to :item
  belongs_to :tax_profile
  belongs_to :location
  belongs_to :item_type
  belongs_to :category
  belongs_to :drawer
  has_and_belongs_to_many :discounts
  has_many :coupons, :class_name => 'OrderItem', :foreign_key => :coupon_id
  belongs_to :order_item,:foreign_key => :coupon_id
  has_many :histories, :as => :user
  has_one :drawer_transaction # set for refunds only
  has_one :payment_method_item # set for refunds only


  monetize :total_cents, :allow_nil => true
  monetize :price_cents, :allow_nil => true
  monetize :tax_amount_cents, :allow_nil => true
  monetize :coupon_amount_cents, :allow_nil => true
  monetize :gift_card_amount_cents, :allow_nil => true
  monetize :discount_amount_cents, :allow_nil => true
  monetize :rebate_amount_cents, :allow_nil => true

  
  def is_normal?
    return (self.is_buyback != true and self.behavior == 'normal')
  end
  def get_tax_profile_letter
    return self.tax_profile.letter
  end
  
  def get_translated_name(locale)
    return self.item.get_translated_name(locale)
  end
  
  def get_category_name
    if self.category
      return self.category.name
    else
      return ""
    end
  end
  
  def get_location_name
    if self.item.location then
      return self.item.location.name
    else
      return ''
    end
  end
  
  def toggle_buyback=(x)
    self.is_buyback = ! self.is_buyback
    self.modify_price_for_buyback
    self.calculate_totals
  end

  def base_price
    return self.price
  end
  def base_price=(p)
    if p.class == String
      # a string is sent from Vendor.edit_field_on_child
      p = Money.new(self.string_to_float(p) * 100.0, self.currency)
    elsif p.class == Float
      # not sure which parts of the code send a Float, but we leave it here for now
      p = Money.new(p * 100.0, self.currency)
    end
    self.price = p
  end
  
  def tax=(value)
    tax_profile = self.vendor.tax_profiles.visible.find_by_value(value)
    ActiveRecord::Base.logger.info "TaxProfile with value #{ value } has to be created before you can assign this value" and return unless tax_profile
    self.tax_profile = tax_profile
    self.save
    write_attribute :tax, tax_profile.value
  end
  

  def refund(pmid, user)
    return nil if self.refunded
    
    drawer = user.get_drawer
    refund_payment_method = self.vendor.payment_methods.visible.find_by_id(pmid)
    
    pmi = PaymentMethodItem.new
    pmi.vendor = self.vendor
    pmi.company = self.company
    pmi.currency = self.vendor.currency
    pmi.order = self.order
    pmi.user = user
    pmi.drawer = drawer
    pmi.amount = - self.total
    pmi.payment_method = refund_payment_method
    pmi.order_item_id = self.id
    pmi.cash = refund_payment_method.cash
    pmi.refund = true
    pmi.save
    
    if refund_payment_method.cash == true
      dt = DrawerTransaction.new
      dt.vendor = self.vendor
      dt.company = self.company
      dt.currency = self.vendor.currency
      dt.user = user
      dt.refund = true
      dt.tag = 'OrderItemRefund'
      dt.notes = I18n.t("views.notice.order_refund_dt", :id => self.id)
      dt.order = self.order
      dt.order_item_id = self.id
      dt.drawer = drawer
      dt.drawer_amount = drawer.amount
      dt.amount = - self.total
      dt.save
      
      drawer.amount -= self.total
      drawer.save
    end
    
    self.refunded = true
    self.refunded_by = user.id
    self.refunded_at = Time.now
    self.calculate_totals
    
    order = self.order
    order.calculate_totals
  end
  
  def split
    order = self.order
    order.paid = nil
    order.save
    noi = self.dup
    self.quantity -= 1
    self.calculate_totals
    noi.quantity = 1
    noi.calculate_totals
    order.calculate_totals
    order.paid = true
    order.save
  end


  def price=(p)
    if p.class == String
      # a string is sent from Vendor.edit_field_on_child
      p = Money.new(self.string_to_float(p) * 100.0, self.currency)
    elsif p.class == Float
      # not sure which parts of the code send a Float, but we leave it here for now
      p = Money.new(p * 100.0, self.currency)
    end
    
    # this is needed for dynamically created gift cards on the POS screen.
    if self.behavior == 'gift_card'
      i = self.item
      if i.activated.nil?
        i.price = p
        i.gift_card_amount = p
        i.save
      end
    end
    
    # make price negative when it is a buyback OrderItem
    if self.is_buyback
      p = - p.abs
    end
    write_attribute :price_cents, p.fractional
  end
  
  # this method is just for documentation purposes: that total always includes tax. it is the physical money that has to be collected from the customer.
  def gross
    return self.total
  end
  
  def net
    return self.total - self.tax_amount
  end

  
  def set_attrs_from_item(item)
    self.vendor       = item.vendor
    self.company      = item.company
    self.currency     = item.currency # all Items must be validated to have the same currency as the parent Vendor. The system does not support adding Items of different currencies into one order.
    self.item         = item
    self.sku          = item.sku
    self.price        = item.price
    self.tax          = item.tax_profile.value # cache for faster processing
    #self.tax_profile  = item.tax_profile
    self.item_type    = item.item_type
    self.behavior     = item.item_type.behavior # cache for faster processing
    self.is_buyback   = item.default_buyback
    self.category     = item.category
    self.location     = item.location
    self.activated    = item.activated
    self.no_inc       = item.is_gs1
    self.gift_card_amount = item.gift_card_amount
    self.weigh_compulsory = item.weigh_compulsory
    self.quantity     = self.weigh_compulsory ? 0 : 1
    self.calculate_part_price = item.calculate_part_price # cache for faster processing
    self.user         = self.order.user
  end
  
  # This method is only called on add to order
  # otherwise calculate_totals is called
  def modify_price
    log_action "Modifying price"
    self.modify_price_for_actions
    self.modify_price_for_gs1
    if self.is_buyback
      log_action "modify_price_for_buyback"
      self.modify_price_for_buyback 
    end
    self.modify_price_for_parts
    if self.behavior == 'gift_card'
      log_action "modify_price_for_giftcards"
      self.modify_price_for_giftcards 
    end
    self.save
  end
  
  def modify_price_for_actions
    log_action "modify_price_for_actions"
    Action.run(self.vendor, self, :add_to_order)
  end
  
  def modify_price_for_gs1
    if self.item.is_gs1
      m = self.vendor.gs1_regexp.match(self.sku)     
      return unless m and m[2]
      value = m[2]
      m = self.item.gs1_regexp.match(value)
      return unless m and m[2]
      value = "#{m[1]}.#{m[2]}".to_f
      if self.item.price_by_qty
        self.quantity = value
        #self.price = self.item.base_price * self.quantity # this is the case anyway
      else
        self.price = value
      end
    end
  end
  
  def modify_price_for_buyback
    if self.is_buyback
      self.price = - self.item.buyback_price
    else
      self.price = self.item.base_price
    end
  end
  
  def modify_price_for_giftcards
    if self.behavior == 'gift_card' and self.item.activated
      if self.item.gift_card_amount > self.order.total
        self.price = - self.order.total
      else
        self.price = - self.gift_card_amount
      end
    end
  end
  
  def modify_price_for_parts
    if self.calculate_part_price
      self.price = self.item.parts.visible.collect{ |p| p.base_price * p.part_quantity }.sum
    end
  end
  
  def calculate_totals
    if self.refunded or self.behavior == 'coupon'
      # coupons do have a total of 0, because they are not sold. they act on a matching OrderItem instead.
      self.total = 0
    else
      # at this point, total is net for the USA tax system and gross for the Europe tax system.
      self.total = self.price * self.quantity
    end

    # Now, the total can be subject to price reductions. the following apply_ methods handle this and modify self.total
    self.apply_discount
    self.apply_rebate
    self.apply_coupon
    
    # this method calculates taxes and transforms "total" to always include tax
    self.calculate_tax
    self.save
  end
  
  # this method calculates taxes and transforms "total" to always include tax
  def calculate_tax
    if self.vendor.net_prices
      # this is for the US tax system
      self.tax_amount = self.total * self.tax / 100.0
      self.total += tax_amount
    else
      # this is for the Europe tax system. Note that self.total already includes taxes, so we don't have to modify it here.
      self.tax_amount = self.total * ( 1 - 1 / ( 1 + self.tax / 100.0))
    end
  end
  
  # coupons have to be added after the matching product
  # coupons do not have a price by themselves, they just reduce the total of the matching OrderItem. Note that this method does not act on self, but to the matching OrderItem.
  def apply_coupon
    return unless self.behavior == 'coupon'
    
    item = self.item
    
    # coitem is the OrderItem to which the coupon acts upon
    coitem = self.order.order_items.visible.find_by_sku(item.coupon_applies)
    log_action "coitem was not found" and return if coitem.nil?

    unless coitem.coupon_amount.zero? then
      log_action "This item is a coupon, but a coupon_amount has already been set"
      return
    end
    
    ctype = self.item.coupon_type
    if ctype == 1
      # percent rebate
      log_action "Percent rebate coupon"
      coitem.coupon_amount = coitem.total * (self.price.to_f / 100)
    elsif ctype == 2
      # fixed amount
      log_action "Fixed amount coupon"
      coitem.coupon_amount = self.price
    elsif ctype == 3
      # buy x get y free
      log_action "B1G1"
      x = 2
      y = 1
      if coitem.quantity >= x
        coitem.coupon_amount_cents = y * coitem.total_cents / coitem.quantity
      end
    end
    log_action "Total is: #{coitem.total} and coupon_amount is #{coitem.coupon_amount}"
    coitem.total -= coitem.coupon_amount
    coitem.calculate_tax
    coitem.save
  end
  
  def apply_rebate
    if self.rebate
      log_action "Applying rebate"
      self.rebate_amount = (self.total.to_f * (self.rebate / 100.0))
      log_action "rebate_amount is #{self.rebate_amount.to_f} #{self.rebate_amount_cents}"
      self.total -= self.rebate_amount
    end
  end
  
  def apply_discount
    log_action "Applying discount"
    # Vendor
    discount = self.vendor.discounts.visible.where("start_date < '#{ Time.now }' AND end_date > '#{ Time.now }'").where(:applies_to => "Vendor").first
    
    # Category
    discount ||= self.vendor.discounts.visible.where("start_date < '#{ Time.now }' AND end_date > '#{ Time.now }'").where(:applies_to => "Category", :category_id => self.category ).first
    
    # Location
    discount ||= self.vendor.discounts.visible.where("start_date < '#{ Time.now }' AND end_date > '#{ Time.now }'").where(:applies_to => "Location", :location_id => self.location ).first
    
    # Item
    discount ||= self.vendor.discounts.visible.where("start_date < '#{ Time.now }' AND end_date > '#{ Time.now }'").where(:applies_to => "Item", :item_sku => self.sku ).first
    
    if discount
      self.discount = discount.amount
      self.discount_amount = (self.total * discount.amount / 100.0)
      self.total -= self.discount_amount
      self.discounts << discount
    end
  end


  
  
  def quantity=(q)
    q = self.string_to_float(q)
    if ( self.behavior == 'gift_card' or self.behavior == 'coupon' ) and q != 1
      log_action "Cannot have more than 1 coupon or gift card"
      return
    end

    write_attribute :quantity, q
  end
  
  
  def hide(by)
    self.hidden = true
    self.hidden_by = by
    self.hidden_at = Time.now
    if not self.save then
      log_action self.errors.full_messages.to_sentence
      raise "Could Not Hide Item"
    end

    if self.behavior == 'coupon'
      item = self.item
      raise "could not find Item for OrderItem #{ self.id }" if item.nil?
      coitem = self.order.order_items.visible.find_by_sku(item.coupon_applies)
      raise "could not find orderitem #{ item.coupon_applies.inspect }" if coitem.nil?
      coitem.coupon_amount = Money.new(0, self.currency)
      coitem.calculate_totals
    end
    self.order.calculate_totals
  end
  
  
  
  def to_json
    obj = {}
    if self.item then
      obj = {
        :name => self.get_translated_name(I18n.locale)[0..20],
        :sku => self.item.sku,
        :item_id => self.item_id,
        :activated => self.item.activated,
        :gift_card_amount => self.item.gift_card_amount.to_f,
        :coupon_type => self.item.coupon_type,
        :quantity => self.quantity,
        :price => self.price.to_f,
        :coupon_amount => self.coupon_amount_cents.blank? ? 0 : - self.coupon_amount.to_f,
        :total => self.total.to_f,
        :id => self.id,
        :behavior => self.behavior,
        :discount_amount => self.discount_amount.blank? ? 0 : - self.discount_amount.to_f,
        :rebate => self.rebate.nil? ? 0 : self.rebate,
        :is_buyback => self.is_buyback,
        :weigh_compulsory => self.item.weigh_compulsory,
        :must_change_price => self.item.must_change_price,
        :weight_metric => self.item.weight_metric,
        :tax => self.tax,
        :tax_profile_id => self.tax_profile_id,
        :action_applied => self.item.actions.visible.any?
      }
    end
    return obj.to_json
  end

end
