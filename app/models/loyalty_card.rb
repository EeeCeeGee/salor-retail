# coding: UTF-8

# Salor -- The innovative Point Of Sales Software for your Retail Store
# Copyright (C) 2012-2013  Red (E) Tools LTD
# 
# See license.txt for the license applying to all files within this software.

class LoyaltyCard < ActiveRecord::Base
	include SalorScope
	include SalorBase
  include SalorModel
  belongs_to :customer
  has_many :orders, :through => :customer
  before_save :clean_model
  before_update :clean_model
  validate :validify
  def validify
    clean_model
    lc = LoyaltyCard.scopied.find_by_sku(self.sku)
    if not lc.id.nil? and lc.id != self.id then
      errors.add(:sku, I18n.t('system.errors.sku_must_be_unique'))
      GlobalErrors.append_fatal('system.errors.sku_must_be_unique');
    end
  end
  def clean_model
    self.sku = self.sku.gsub(' ','')
  end
end
