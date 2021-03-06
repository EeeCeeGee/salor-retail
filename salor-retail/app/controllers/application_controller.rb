# coding: UTF-8

# Salor -- The innovative Point Of Sales Software for your Retail Store
# Copyright (C) 2012-2013  Red (E) Tools LTD
# 
# See license.txt for the license applying to all files within this software.
require "net/http"
require "uri"

class ApplicationController < ActionController::Base
  include SalorBase
  
  helper :all
  helper_method :workstation?, :mobile?
  
  #protect_from_forgery
  
  before_filter :loadup
  after_filter  :loaddown
  before_filter :get_cash_register
  before_filter :set_tailor
  before_filter :set_locale
  
  layout :layout_by_response

  unless SalorRetail::Application.config.consider_all_requests_local
    #rescue_from Exception, :with => :render_error
  end
  

  def is_mac?
     RUBY_PLATFORM.downcase.include?("darwin")
  end

  def is_windows?
     RUBY_PLATFORM.downcase.include?("mswin")
  end

  def is_linux?
     RUBY_PLATFORM.downcase.include?("linux")
  end   

  
  def render_csv(filename = nil,text = nil)
    filename ||= params[:action]
    filename += '.csv'
  
    if request.env['HTTP_USER_AGENT'] =~ /msie/i
      headers['Pragma'] = 'public'
      headers["Content-type"] = "text/plain" 
      headers['Cache-Control'] = 'no-cache, must-revalidate, post-check=0, pre-check=0'
      headers['Content-Disposition'] = "attachment; filename=\"#{filename}\"" 
      headers['Expires'] = "0" 
    else
      headers["Content-Type"] ||= 'text/csv'
      headers["Content-Disposition"] = "attachment; filename=\"#{filename}\"" 
    end  
    if text then
      render :text => text
    else
      render :layout => false
    end
  end

  def workstation?
    request.user_agent.nil? or request.user_agent.include?('Firefox') or request.user_agent.include?('MSIE') or request.user_agent.include?('Macintosh') or request.user_agent.include?('Chrom') or request.user_agent.include?('iPad') or request.user_agent.include?('Qt/4')
  end

  def mobile?
    not workstation?
  end

  private
  
  def set_locale

    if params[:l] and I18n.available_locales.include? params[:l].to_sym
      log_action "params[:l] is set to #{params[:l]}"
      I18n.locale = @locale = session[:locale] = params[:l]
    elsif session[:locale]
      log_action "session[:locale] is set to #{session[:locale]}"
      I18n.locale = @locale = session[:locale]
    elsif @current_user
      log_action "Users Locale is: #{@current_user.language}"
      I18n.locale = @locale = session[:locale] = @current_user.language
    else
      log_action "No locale is set, trying to detect from browser"
      unless request.env['HTTP_ACCEPT_LANGUAGE'].nil?
        browser_language = request.env['HTTP_ACCEPT_LANGUAGE'].scan(/^[a-z]{2}/).first
        browser_language = 'gn' if browser_language == 'de'
      end
      if browser_language.nil? or browser_language.empty? or not I18n.available_locales.include?(browser_language.to_sym)
        I18n.locale = @locale = session[:locale] = 'en'
      else
        I18n.locale = @locale = session[:locale] = browser_language
      end
    end
    log_action "Locale is now set to: #{I18n.locale}"
    @region = @current_vendor.region if @current_vendor
  end
  
  def update_devicenodes
    if @current_register
      @current_register.set_device_paths_from_device_names(CashRegister.get_devicenodes)
    end
  end
  
  def customerscreen_push_notification
    t = SalorRetail.tailor
    if t
      t.puts "CUSTOMERSCREENEVENT|#{@current_vendor.hash_id}|#{ @current_register.name }|/orders/#{ @order.id }/customer_display"
    end
  end
  
  def allowed_klasses
    ['SalorConfiguration','UserLogin','LoyaltyCard','Item','ShipmentItem','Vendor','Category','Location','Shipment','Order','OrderItem']
  end

  def layout_by_response
    if params[:ajax] then
       return false
    end
    return "application"
  end
  
  def loadup
    $USERID = nil
    $PARAMS = nil
    @current_user = User.visible.find_by_id_hash(session[:user_id_hash])

    if @current_user.nil? or session[:user_id_hash].blank?
      redirect_to new_session_path and return 
    end
    $USERID = @current_user.id
    $PARAMS = params

    if defined?(SrSaas) == 'constant'
      # this is necessary due to call to the login method in UsersController#clock{in|out}
      @current_company = SrSaas::Company.visible.find_by_id(@current_user.company_id)
    else
      @current_company = @current_user.company
    end
    @current_vendor = @current_user.vendors.visible.find_by_id(session[:vendor_id])
    Time.zone = @current_vendor.time_zone if @current_vendor
    I18n.locale = @current_user.language
    return @current_user
  end
  
  def loaddown
    # just to make sure we clear out these globals
    $USERID = nil
    $PARAMS = nil
    log_action "End of request \n\n\n\n\n\n"
  end

  def get_cash_register
    @current_register = @current_vendor.cash_registers.visible.find_by_id(session[:cash_register_id])
    redirect_to cash_registers_path and return unless @current_register
  end
  
  def set_tailor
    return unless @current_vendor and SalorRetail::Application::CONFIGURATION[:tailor] and SalorRetail::Application::CONFIGURATION[:tailor] == true
  
    t = SalorRetail.tailor
    if t
      #logger.info "[TAILOR] Checking if socket #{ t.inspect } is healthy"
      begin
        t.puts "PING|#{ @current_vendor.hash_id }|#{ Process.pid }"
      rescue Errno::EPIPE
        logger.info "[TAILOR] Error: Broken pipe for #{ t.inspect } #{ t }"
        SalorRetail.old_tailors << t
        t = nil
      rescue Errno::ECONNRESET
        logger.info "[TAILOR] Error: Connection reset by peer for #{ t.inspect } #{ t }"
        SalorRetail.old_tailors << t
        t = nil
      rescue Exception => e
        logger.info "[TAILOR] Other Error: #{ e.inspect } for #{ t.inspect } #{ t }"
        SalorRetail.old_tailors << t
        t = nil
      end
    end
    
    if t.nil?
      begin
        t = TCPSocket.new 'localhost', 2001
        logger.info "[TAILOR] Info: New TCPSocket #{ t.inspect } #{ t } created"
      rescue Errno::ECONNREFUSED
        t = nil
        logger.info "[TAILOR] Warning: Connection refused. No tailor.rb server running?"
      end
      SalorRetail.tailor = t
    end
  end

  protected

  def render_error(exception)
    #log_error(exception)
    @exception = exception
    if SalorRetail::Application::CONFIGURATION[:exception_notification] == true
      if notifier = Rails.application.config.middleware.detect { |x| x.klass == ExceptionNotifier }
        env['exception_notifier.options'] = notifier.args.first || {}                   
        ExceptionNotifier::Notifier.exception_notification(env, exception).deliver
        env['exception_notifier.delivered'] = true
      end
    end
    render :template => '/errors/error', :layout => 'customer_display'
  end
  
  def check_role
    if not role_check(params) then 
      redirect_to(role_check_failed) and return
    end  
  end
  
  def role_check_failed
      return @current_user.get_root.merge({:notice => I18n.t("system.errors.no_role")})
  end
  
  def role_check(p)
    return @current_user.can(p[:action] + '_' + p[:controller])
  end
  
  def not_my_vendor?(model)
    if @current_user.vendor_id != model.vendor_id then
      return true
    end
    return false
  end
  

  
  def assign_from_to(p)
    begin
      f = Date.civil( p[:from][:year ].to_i,
                      p[:from][:month].to_i,
                      p[:from][:day  ].to_i) if p[:from]
      t = Date.civil( p[:to  ][:year ].to_i,
                      p[:to  ][:month].to_i,
                      p[:to  ][:day  ].to_i) if p[:to]
    rescue
#       f = t = nil
      
    end
    f ||= DateTime.now.beginning_of_day
    t ||= DateTime.now.end_of_day
    return f, t
  end
  def time_from_to(p)
    begin
      f = DateTime.civil( p[:from][:year ].to_i,
                      p[:from][:month].to_i,
                      p[:from][:day  ].to_i,
                      p[:from][:hour  ].to_i,
                      p[:from][:minute  ].to_i,0) if p[:from]
      t = DateTime.civil( p[:to  ][:year ].to_i,
                      p[:to  ][:month].to_i,
                      p[:to  ][:day  ].to_i,
                      p[:to][:hour  ].to_i,
                      p[:to][:minute  ].to_i,0) if p[:to]
    rescue
      f = t = nil
    end

    f ||= 0.day.ago
    t ||= 0.day.ago
    return f, t
  end
  # {END}
end
