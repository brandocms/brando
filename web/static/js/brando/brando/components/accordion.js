'use strict';

import $ from 'jquery';

class Accordion {
  static setup() {
    var that = this;
    $(document).ready(function () {
      var hash = document.location.hash;
      $('.accordion-tabs-minimal').each(function() {
        if (!hash) {
          let $link = $(this).children('li').first().children('a');
          let $linkSibling = $link.next();
          $link.addClass('is-active');
          $linkSibling.addClass('is-open').show();
        } else {
          let $link = $('#tab-' + hash.replace('#', ''));
          that.activateTab($link);
        }
      });

      $('.accordion-tabs-minimal').on('click', '.tab-link', function(event) {
        event.preventDefault();
        that.activateTab(this);
      });
    });
  }

  static activateTab(obj) {
    let
      $obj = $(obj),
      $accordionTabs = $obj.closest('.accordion-tabs-minimal'),
      $openTabs = $accordionTabs.find('.is-open'),
      $activeTabs = $accordionTabs.find('.is-active'),
      $tabContent = $obj.next();

    if (!$obj.hasClass('is-active')) {
      document.location.hash = $obj.attr('id').replace('tab-', '');
    }

    $openTabs.removeClass('is-open').hide();
    $tabContent.toggleClass('is-open').toggle();
    $activeTabs.removeClass('is-active');
    $obj.addClass('is-active');
  }
}

export {Accordion};
