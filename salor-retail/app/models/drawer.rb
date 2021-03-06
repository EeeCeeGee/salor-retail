# coding: UTF-8

# Salor -- The innovative Point Of Sales Software for your Retail Store
# Copyright (C) 2012-2013  Red (E) Tools LTD
# 
# See license.txt for the license applying to all files within this software.

class Drawer < ActiveRecord::Base
  include SalorBase

  has_one :user
  belongs_to :company
  
  has_many :orders
  has_many :drawer_transactions

  monetize :amount_cents, :allow_nil => true
  
  def to_json
    { :amount => self.amount.to_f }.to_json
  end
end
