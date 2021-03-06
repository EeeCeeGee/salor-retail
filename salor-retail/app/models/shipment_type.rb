# coding: UTF-8

# Salor -- The innovative Point Of Sales Software for your Retail Store
# Copyright (C) 2012-2013  Red (E) Tools LTD
# 
# See license.txt for the license applying to all files within this software.

class ShipmentType < ActiveRecord::Base
  include SalorBase
  include SalorScope

  has_many :shipments
  belongs_to :vendor
  belongs_to :company
  
  validates_presence_of :name
end
