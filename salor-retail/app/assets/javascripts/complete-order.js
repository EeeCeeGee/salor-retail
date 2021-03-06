var sendingOrder = false;
var orderCompleteDisplayed = false;

function complete_order_show() {
  sendingOrder = false;
  $(".payment-amount").remove();
  $(".complete-order-total").html($('#pos_order_total').html());
  $("#complete_order_change").html('');
  $("#recommendation").html('');
  $('#complete_order').show();
  
  set_invoice_button();
  
  bindInplaceEnter(false);
  handleKeyboardEnter = false;
  orderCompleteDisplayed = true;

  setOnEnterKey(function(event) {
    if (event.keyCode == 13 && orderCompleteDisplayed) {
      ajax_log({log_action:'complete_order_show:setOnEnterKey', order_id:Order.id, value:event.keyCode});
      if (Register.no_print == true) {
          complete_order_send(false);
      } else {
          complete_order_send(true);
      }
      event.preventDefault();
    }
  });

  setOnEscKey(function() {
    complete_order_hide();
  });

  $("#add_payment_method_button").show();
  $("#payment_methods").show();
  
  $("#payment_methods").html("");
  add_payment_method();
  $("#payment_amount_0").val( Order.total );
  $("#payment_amount_0").select();
  display_change('function complete_order_show');
  show_denominations();
  $("#keyboard_input").attr("disabled", true);
  $('body').triggerHandler({type: "CompleteOrderShow"});
}

function set_invoice_button() {
  $('.a4-print-button').remove(); 
  var a4print = $("<div class='a4-print-button'><img src='/images/icons/a4print.svg' height='32' /></div>");
  var left = $('#complete_order').position().left;
  var width = $('#complete_order').width();
  var cpos = {x: width + left + 21, y:$('#complete_order').position().top + $('#complete_order').height() - 40 }; //because the first div needs to be on top
  a4print.css({width: '125px',position: 'absolute',top: cpos.y, left: cpos.x});
  relevant_order_id = Order.id;
  a4print.click(function () {
    window.location = '/orders/' + relevant_order_id + '/print';      
  });
  $("body").append(a4print);
}

function complete_order_hide() {
  stop_drawer_observer();
  $("#payment_methods").html("");
  $(".payment-amount").attr("disabled", true);
  $('#complete_order').hide();
  bindInplaceEnter(true);
  handleKeyboardEnter = true;
  orderCompleteDisplayed = false;
  unsetOnEnterKey();
  unsetOnEscKey();
  $('.a4-print-button').remove();
  $('.pieces-button ').remove();
  $("#keyboard_input").attr("disabled", false);
  if (typeof bycard_hide != 'undefined') {
    bycard_hide();
  }
  focuseKeyboardInput = true;
  $('body').triggerHandler({type: "CompleteOrderHide"});
  ajax_log({log_action:'complete_order_hide', order_id:Order.id});
  
  if ( parseInt( Order.id ) % 20 == 0) { 
    window.location = '/orders/new'; 
  }
  
}

function complete_order_send(print) {
  if (sendingOrder) return;
  if (Order.order_items.length == 0) { complete_order_hide(); return;}
  sendingOrder = true;
  allow_complete_order(false);
  if (Register.require_password) {
    // process after password entry
    show_password_dialog(print);
    return
  } else {
    // process immediately
    complete_order_process(print);
  }  
}

// this function handles all the magic regarding printing, drawer opening, drawer observing, pole display update and mimo screen update. detects usage of salor-bin too.
function complete_order_process(print) {
  var drawer_opened = conditionally_open_drawer();
  var order_id = Order.id;
  $.ajax({
    url: "/orders/complete",
    type: 'post',
    data: {
      order_id: Order.id,
      change: toFloat($('#complete_order_change').html()),
      print: print,
      payment_method_items: paymentMethodItems()
    },
    complete: function(data, status) {
      ajax_log({log_action:'get:complete_order_ajax:callback', order_id:Order.id, require_password: false});
      if (print == true) { 
        print_order(order_id, function() {
          // observe after print has finished
          if (drawer_opened == true) observe_drawer();
        });
      } else {
        // observe immediately
        if (drawer_opened == true) observe_drawer();
      }
      sendingOrder = false;
      updateCustomerDisplay(order_id, false, true);
    }
  });
}

// function showCompleteOrderPopup() {
//   var tmpl = getCompleteOrderTemplate();
//   tmpl.dialog({
//     autoOpen: true,
//     height: $(window).height() * 0.8,
//     width: $(window).width() * 0.8,
//     modal: true,
//     buttons: getCompleteOrderButtons(),
//   });
//   $("#payment_method_list").html('');
//   completeOrderShowTotal(tmpl);
//   completeOrderShowChange(tmpl);
//   _set("payment_methods_used",[],getCompleteOrderTemplate());
// }
// 
// function getCompleteOrderTemplate() {
//   return $("#complete_order_popup");
// }

function getCompleteOrderButtons() {
  return {
    "Cancel":           function () { $(this).dialog( "close" ); }, //end Cancel
    "Complete":         function () { compleOrder(false);       }, //end Complete
    "Print":            function () { compleOrder(true);        }, // end Print
  };
}

// function completeOrder(print) {
//   var bValid = true;
// }

function completeOrderShowTotal(tmpl) {
  var el = $('#complete_order_total');
  var w = 300;
  el.css({width: w});
  completeOrderUpdateTotal(Order.total);
}

function completeOrderShowChange(tmpl) {
  var el = $('#complete_order_change');
  var w = 300;
  el.css({width: w});
  completeOrderUpdateChange(0);
}

function completeOrderUpdateTotal(num) {
  var el = $("#complete_order_total");
  var _ttl = toCurrency(num);
  el.html(_ttl);
}

function completeOrderUpdateChange(num) {
  var el = $("#complete_order_change");
  var _ttl = toCurrency(num);
  el.html(_ttl);
}

function completeOrderRightCol() {
  return $("#complete_order_popup .content-table td.right");
}

function completeOrderAddPaymentMethod() {
  var pm = {name: "notset",internal_type: "notset"};
  var pm_options = [];
  var selected = false;
  for (var i = 0; i < PaymentMethodObjects.length; i++) {
    if (_get("payment_methods_used",getCompleteOrderTemplate()).indexOf(PaymentMethodObjects[i].internal_type) == -1 && selected == false) {
      pm = PaymentMethodObjects[i];
      pm_options.push( _.template('<option value="{{=internal_type}}" selected="true">{{= name }}</option>')(PaymentMethodObjects[i]));
      selected = true;
      continue;
    }
    pm_options.push(_.template('<option value="{{=internal_type}}">{{= name }}</option>')(PaymentMethodObjects[i]));
  }
  var tmpl = _.template($("#payment_method_template").html())({pm: pm, i: 0, options: pm_options.join("\n")});
  var row = $(tmpl);
  $("#payment_method_list").append(row);
  var select = row.find("select");
  make_select_widget("",select);
  completeOrderUpdatePaymentMethodsUsed();
  focusInput(row.find("input"));
}

function completeOrderUpdatePaymentMethodsUsed() {
  var pms_used = [];//_get("payment_methods_used",getCompleteOrderTemplate());
  $(".payment-method-select").each(function () {
    pms_used.push($(this).val());
  });
  _set("payment_methods_used",pms_used,getCompleteOrderTemplate());
}

function allow_complete_order(isAllowed) {
  if (isAllowed && $('#pos-table-left-column-items').children().length > 0 || Order.is_proforma) {
    $("#confirm_complete_order_button").removeClass("button-inactive");
    $("#confirm_complete_order_button").off('click');
    $("#confirm_complete_order_button").on('click', function() {complete_order_send(true)});
    $("#confirm_complete_order_noprint_button").removeClass("button-inactive");
    $("#confirm_complete_order_noprint_button").off('click');
    $("#confirm_complete_order_noprint_button").on('click', function() {complete_order_send(false)});
  } else {
    $("#confirm_complete_order_button").addClass("button-inactive");
    $("#confirm_complete_order_button").off('click');
    $("#confirm_complete_order_noprint_button").addClass("button-inactive")
    $("#confirm_complete_order_noprint_button").off('click');
  }
}


function show_password_dialog(print) {
  var el = $("#simple_input_dialog").dialog({
    modal: true,
    buttons: {
      "Cancel": function() {
        $("#simple_input_dialog").dialog( "close" );
      },
      "Complete": function () {
        var bValid = true;
        $('#dialog_input').removeClass("ui-state-error");
        updateTips("");
        bValid = bValid && checkLength($('#dialog_input'),"password",3,255);
        if (bValid) {
          updateTips("Verifying user...");            
          $.post(
              "/users/verify",
              { password: $('#dialog_input').val() }, 
              function (data, status) {
                if (data == "NO") {
                  ajax_log({log_action:'password attempt failed!', order_id:Order.id, require_password: true});
                  updateTips("Wrong Password");
                } else {
                  updateTips("Correct, sending...");
                  complete_order_process(print);
                  $("#simple_input_dialog").dialog( "close" );
                }
              } // end complete
          ); // end post
          
        } // end if bValid
      } // end Complete
    } // end Buttons
  }); // end dialog
  
  setTimeout(function () {
    $('#dialog_input').val("");
    $(".ui-dialog * button > span:contains('Complete')").text(i18n.menu.ok);
    $(".ui-dialog * button > span:contains('Cancel')").text(i18n.menu.cancel);
    $('#dialog_input').keyup(function (event) {
      if (event.which == 13) {
        ajax_log({log_action:'Keyup enter on password dlg', order_id:Order.id});
        $(".ui-dialog * button:contains('"+i18n.menu.ok+"')").trigger("click");
      }
    });
    focusInput($('#dialog_input'));
    var ttl = el.parent().find('.ui-dialog-title');
    ttl.html(i18n.activerecord.attributes.require_password); 
    ttl = el.parent().find('.input_label');
    ttl.html(i18n.activerecord.attributes.password);
  },20);
}
