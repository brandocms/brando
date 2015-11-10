/* ========================================================================
 * Bootstrap: dropdown.js v3.2.0
 * http://getbootstrap.com/javascript/#dropdowns
 * ========================================================================
 * Copyright 2011-2014 Twitter, Inc.
 * Licensed under MIT (https://github.com/twbs/bootstrap/blob/master/LICENSE)
 * ======================================================================== */


+function ($) {
  'use strict';

  // DROPDOWN CLASS DEFINITION
  // =========================

  var backdrop = '.dropdown-backdrop'
  var toggle   = '[data-toggle="dropdown"]'
  var Dropdown = function (element) {
    $(element).on('click.bs.dropdown', this.toggle)
  }

  Dropdown.VERSION = '3.2.0'

  Dropdown.prototype.mouseenter = function (e) {
    var $icon = $(this).find('input')
    $icon.addClass('hover')
  }

  Dropdown.prototype.mouseleave = function (e) {
    var $icon = $(this).find('input')
    $icon.removeClass('hover')
  }

  Dropdown.prototype.toggle = function (e) {
    var $this = $(this)

    if ($this.is('.disabled, :disabled')) return

    var $parent  = getParent($this)
    var isActive = $parent.hasClass('open')

    clearMenus()

    if (!isActive) {
      if ('ontouchstart' in document.documentElement && !$parent.closest('.navbar-nav').length) {
        // if mobile we use a backdrop because click events don't delegate
        $('<div class="dropdown-backdrop"/>').insertAfter($(this)).on('click', clearMenus)
      }

      var relatedTarget = { relatedTarget: this }
      $parent.trigger(e = $.Event('show.bs.dropdown', relatedTarget))

      if (e.isDefaultPrevented()) return

      $this.trigger('focus')

      $this.find('input')
        .toggleClass('cross')
        .toggleClass('bars')

      $parent
        .toggleClass('open')
        .trigger('shown.bs.dropdown', relatedTarget)
    }

    return false
  }

  Dropdown.prototype.keydown = function (e) {
    if (!/(38|40|27)/.test(e.keyCode)) return

    var $this = $(this)

    e.preventDefault()
    e.stopPropagation()

    if ($this.is('.disabled, :disabled')) return

    var $parent  = getParent($this)
    var isActive = $parent.hasClass('open')

    if (!isActive || (isActive && e.keyCode == 27)) {
      if (e.which == 27) $parent.find(toggle).trigger('focus')
      return $this.trigger('click')
    }

    var desc = ' li:not(.divider):visible a'
    var $items = $parent.find('[role="menu"]' + desc + ', [role="listbox"]' + desc)

    if (!$items.length) return

    var index = $items.index($items.filter(':focus'))

    if (e.keyCode == 38 && index > 0)                 index--                        // up
    if (e.keyCode == 40 && index < $items.length - 1) index++                        // down
    if (!~index)                                      index = 0

    $items.eq(index).trigger('focus')
  }

  function clearMenus(e) {
    if (e && e.which === 3) return
    $(backdrop).remove()
    $(toggle).each(function () {
      var $parent = getParent($(this))
      var relatedTarget = { relatedTarget: this }
      if (!$parent.hasClass('open')) return
      $parent.trigger(e = $.Event('hide.bs.dropdown', relatedTarget))
      if (e.isDefaultPrevented()) return
      $(this).find('input').removeClass('cross')
      $(this).find('input').addClass('bars')
      $parent.removeClass('open').trigger('hidden.bs.dropdown', relatedTarget)
    })
  }

  function getParent($this) {
    var selector = $this.attr('data-target')

    if (!selector) {
      selector = $this.attr('href')
      selector = selector && /#[A-Za-z]/.test(selector) && selector.replace(/.*(?=#[^\s]*$)/, '') // strip for ie7
    }

    var $parent = selector && $(selector)

    return $parent && $parent.length ? $parent : $this.parent()
  }


  // DROPDOWN PLUGIN DEFINITION
  // ==========================

  function Plugin(option) {
    return this.each(function () {
      var $this = $(this)
      var data  = $this.data('bs.dropdown')

      if (!data) $this.data('bs.dropdown', (data = new Dropdown(this)))
      if (typeof option == 'string') data[option].call($this)
    })
  }

  var old = $.fn.dropdown

  $.fn.dropdown             = Plugin
  $.fn.dropdown.Constructor = Dropdown


  // DROPDOWN NO CONFLICT
  // ====================

  $.fn.dropdown.noConflict = function () {
    $.fn.dropdown = old
    return this
  }


  // APPLY TO STANDARD DROPDOWN ELEMENTS
  // ===================================

  $(document)
    .on('click.bs.dropdown.data-api', clearMenus)
    .on('click.bs.dropdown.data-api', '.dropdown form', function (e) { e.stopPropagation() })
    .on('click.bs.dropdown.data-api', toggle, Dropdown.prototype.toggle)
    .on('mouseenter.bs.dropdown.data-api', toggle, Dropdown.prototype.mouseenter)
    .on('mouseleave.bs.dropdown.data-api', toggle, Dropdown.prototype.mouseleave)
    .on('keydown.bs.dropdown.data-api', toggle + ', [role="menu"], [role="listbox"]', Dropdown.prototype.keydown)

}(jQuery);

// dropdown menu
$.fn.dropdown.Constructor.prototype.change = function(e){
  e.preventDefault();
  var $item = $(e.target), $select, $checked = false, $menu, $label;
  !$item.is('a') && ($item = $item.closest('a'));
  $menu = $item.closest('.dropdown-menu');
  $label = $menu.parent().find('.dropdown-label');
  $labelHolder = $label.text();
  $select = $item.find('input');
  $checked = $select.is(':checked');
  if($select.is(':disabled')) return;
  if($select.attr('type') == 'radio' && $checked) return;
  if($select.attr('type') == 'radio') $menu.find('li').removeClass('active');
  $item.parent().removeClass('active');
  !$checked && $item.parent().addClass('active');
  $select.prop("checked", !$select.prop("checked"));

  $items = $menu.find('li > a > input:checked');
  if ($items.length) {
      $text = [];
      $items.each(function () {
          var $str = $(this).parent().text();
          $str && $text.push($.trim($str));
      });

      $text = $text.length < 4 ? $text.join(', ') : $text.length + ' selected';
      $label.html($text);
  }else{
    $label.html($label.data('placeholder'));
  }
}
$(document).on('click.dropdown-menu', '.dropdown-select > li > a', $.fn.dropdown.Constructor.prototype.change);

// collapse nav
$(document).on('click', '.nav-primary a', function (e) {
  var $this = $(e.target), $active;
  $this.is('a') || ($this = $this.closest('a'));
  if( $('.nav-vertical').length ){
    return;
  }

  $active = $this.parent().siblings( ".active" );
  $active && $active.find('> a').toggleClass('active') && $active.toggleClass('active').find('> ul:visible').slideUp(200);

  ($this.hasClass('active') && $this.next().slideUp(200)) || $this.next().slideDown(200);
  $this.toggleClass('active').parent().toggleClass('active');

  $this.next().is('ul') && e.preventDefault();

  setTimeout(function(){ $(document).trigger('updateNav'); }, 300);
});

// dropdown still
$(document).on('click.bs.dropdown.data-api', '.dropdown .on, .dropup .on', function (e) { e.stopPropagation() });