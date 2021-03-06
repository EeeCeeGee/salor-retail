# coding: UTF-8

# Salor -- The innovative Point Of Sales Software for your Retail Store
# Copyright (C) 2012-2013  Red (E) Tools LTD
# 
# See license.txt for the license applying to all files within this software.


class ItemsController < ApplicationController
  before_filter :check_role, :except => [:info, :search]
  before_filter :update_devicenodes, :only => [:index]
  

  def index
    orderby = "id DESC"
    orderby ||= params[:order_by]
    @items = @current_vendor.items.by_keywords(params[:keywords]).visible.where("items.sku NOT LIKE 'DMY%'").where(:child_id => nil).page(params[:page]).per(@current_vendor.pagination).order(orderby)
  end

  def show
    if params[:keywords] then
      @item = @current_vendor.items.visible.by_keywords(params[:keywords]).first
    end

    @item ||= @current_vendor.items.visible.find_by_id(params[:id])

    redirect_to items_path if not @item
    
    @from, @to = assign_from_to(params)
    @from = @from ? @from.beginning_of_day : 1.month.ago.beginning_of_day
    @to = @to ? @to.end_of_day : DateTime.now
    @sold_times = @current_vendor.order_items.visible.where(:sku => @item.sku, :is_buyback => nil, :refunded => nil, :created_at => @from..@to).collect do |i| 
      (i.order.paid and not i.order.is_proforma) ? i.quantity : 0 
    end.sum
  end

  def new
    @item = @current_vendor.items.build
  end

  def edit
    @item = @current_vendor.items.visible.where(["id = ? or sku = ?",params[:id],params[:keywords]]).first
    #@item.item_stocks.build if not @item.item_stocks.any?
    #@item.item_shippers.build if not @item.item_shippers.any?
  end


  def create
    @item = Item.new
    @item.vendor = @current_vendor
    @item.company = @current_company
    @item.currency = @current_vendor.currency
    @item.attributes = params[:item]
    if @item.save
      @item.assign_parts(params[:part_skus])
      redirect_to items_path
    else
      render :new
    end
  end
  
  # from shipment form
  def create_ajax
    @item = Item.new
    @item.vendor = @current_vendor
    @item.company = @current_company
    @item.currency = @current_vendor.currency
    @item.item_type = @current_vendor.item_types.find_by_behavior("normal")
    @item.tax_profile_id = params[:item][:tax_profile_id]
    @item.attributes = params[:item]
    @item.save
    render :nothing => true
  end

  def update
    @item = @current_vendor.items.visible.find_by_id(params[:id])
    if @item.update_attributes(params[:item])
      @item.assign_parts(params[:part_skus])
      redirect_to items_path
    else
      render :edit
    end
  end
  
  
  def update_real_quantity
    
    if request.post? then
      @item = @current_vendor.items.find_by_sku(params[:sku])
      @item.update_attribute(:real_quantity, params[:quantity])
      @item.update_attribute(:real_quantity_updated, true)
    end
  end
  def move_real_quantity
    ir = InventoryReport.create(:name => "AutoGenerated #{Time.now}", :created_at => Time.now, :updated_at => Time.now, :vendor_id => @current_user.vendor_id)
    sql = %Q[
        insert into inventory_report_items 
        ( inventory_report_id,
          item_id,
          real_quantity,
          item_quantity,
          created_at,
          updated_at,
          vendor_id
         ) select 
            ir.id,
            i.id,
            i.real_quantity,
            i.quantity,
            NOW(),
            NOW(),
            ir.vendor_id from 
          items as i, 
          inventory_reports as ir where 
            i.real_quantity_updated IS TRUE and 
            ir.id = #{ir.id}
  ]
    Item.connection.execute(sql)
    Item.connection.execute("update items set quantity = real_quantity, real_quantity_updated = FALSE where real_quantity_updated IS TRUE")
    redirect_to items_update_real_quantity_path, :notice => t('views.notice.move_real_quantities_success')
  end

  def destroy
    @item = @current_vendor.items.visible.find_by_id(params[:id])
    @item.hide(@current_user)
    redirect_to items_path
  end
  
  def info
    if params[:sku] then
      @item = Item.find_by_sku(params[:sku])
    else
      @item = Item.find(params[:id]) if Item.exists? params[:id]
    end
  end

  def search
    @items = []
    @customers = []
    @orders = []
    if params[:klass] == 'Item' then
      if params[:keywords].empty? then
        @items = @current_vendor.items.visible.page(params[:page]).per(@current_vendor.pagination)
      else
        # TODO: Add price range search
        @items = @current_vendor.items.visible.where("sku LIKE '%#{params[:keywords]}%' or name LIKE '%#{params[:keywords]}%'").page(params[:page]).per(@current_vendor.pagination)
      end
    elsif params[:klass] == 'Order'
      if params[:keywords].empty? then
        @orders = @current_vendor.orders.order("nr DESC").page(params[:page]).per(@current_vendor.pagination)
      else
        @orders = @current_vendor.orders.where("nr = '#{params[:keywords]}' or tag LIKE '%#{params[:keywords]}%'").page(params[:page]).per(@current_vendor.pagination)
      end
    else
      @customers = @current_company.customers.visible.page(params[:page]).per(@current_vendor.pagination)
    end
  end
  
  def item_json
    @item = @current_vendor.items.visible.find_by_sku(params[:sku], :select => "name,sku,id,purchase_price")
  end
  
  def edit_location
    respond_to do |format|
      format.html 
      format.js { render :content_type => 'text/javascript',:layout => false}
    end
  end

  def database_distiller
    @all_items = Item.where(:hidden => 0).count
    @used_item_ids = OrderItem.connection.execute('select item_id from order_items').to_a.flatten.uniq
    @hidden = Item.where('hidden = 1')
    @hidden_by_distiller = Item.where('hidden_by_distiller = 1')
  end

  def distill_database
    all_item_ids = Item.connection.execute('select id from items').to_a.flatten.uniq
    used_item_ids = OrderItem.connection.execute('select item_id from order_items').to_a.flatten.uniq
    deletion_item_ids = all_item_ids - used_item_ids
    Item.where(:id => deletion_item_ids).update_all(:hidden => 1, :hidden_by_distiller => true, :child_id => nil, :sku => nil)
    redirect_to '/items/database_distiller'
  end
  
  def reorder_recommendation
    text = Item.recommend_reorder(params[:type])
    if not text.nil? and not text.empty? then
      send_data text,:filename => "Reorder" + Time.now.strftime("%Y%m%d%H%I") + ".csv", :type => "application/x-csv"
    else
      redirect_to :action => :index, :notice => I18n.t("system.errors.cannot_reorder")
    end
    
  end

  def upload
    if params[:file]
      @uploader = FileUpload.new("salorretail", @current_vendor, params[:file].read)
      @uploader.crunch
    end
  end
# 
#   def upload_danczek_tobaccoland_plattner
#     if params[:file]
#       lines = params[:file].read.split("\n")
#       i, updated_items, created_items, created_categories, created_tax_profiles = FileUpload.new.type1("tobaccoland", lines)
#       redirect_to(:action => 'index')
#     end
#   end
# 
#   def upload_house_of_smoke
#     if params[:file]
#       lines = params[:file].read.split("\n")
#       i, updated_items, created_items, created_categories, created_tax_profiles = FileUpload.new.type2("dios", lines)
#       redirect_to(:action => 'index')
#     end
#   end
# 
#   def upload_optimalsoft
#     if params[:file]
#       lines = params[:file].read.split("\n")
#       i, updated_items, created_items, created_categories, created_tax_profiles = FileUpload.new.type3("Optimalsoft", lines)
#       redirect_to(:action => 'index')
#     end
#   end
  
  def download
    params[:page] ||= 1
    params[:order_by] = "id DESC" if not params[:order_by] or params[:order_by].blank?
    orderby ||= params[:order_by]
    @items = @current_vendor.items.by_keywords(params[:keywords]).visible.where("items.sku NOT LIKE 'DMY%'").page(params[:page]).per(@current_vendor.pagination).order(orderby)
    data = render_to_string :layout => false
    send_data(data,:filename => 'items.csv', :type => 'text/csv')
  end

  def inventory_report
    @items = @current_vendor.items.where(:real_quantity_updated => true)
    @categories = @current_vendor.categories
  end
  
  def selection
    if params[:order_id]
      order = @current_vendor.orders.visible.find_by_id(params[:order_id])
      @skus = "ORDER#{order.id}"
    else
      @skus = nil
    end
  end
  
  def labels
    output = @current_vendor.print_labels('item', params, @current_register)
    if params[:download] == 'true'
      send_data output, :filename => '1.salor'
      return
    elsif @current_register.salor_printer
      render :text => output
      return
    end
    render :nothing => true
  end
  
  def report
    @items = @current_vendor.items.select("items.quantity,items.name,items.sku,items.base_price,items.category_id,items.location_id,items.id,items.vendor_id").visible.includes(:location,:category).by_keywords(params[:keywords]).page(params[:page]).per(100)
    @view = SalorRetail::Application::CONFIGURATION[:reports][:style]
    @view ||= 'default'
    render "items/reports/#{@view}/page"
  end

  def new_action
    item = @current_vendor.items.visible.find_by_id(params[:item_id])
    action = item.create_action
    redirect_to action_path(action)
  end
end
