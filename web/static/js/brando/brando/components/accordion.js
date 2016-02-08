"use strict";

import $ from "jquery";

class Accordion {
  static setup() {
    var that = this;
    $(document).ready(function () {
      $('.accordion-tabs-minimal').each(function() {
        if (!document.location.hash) {
          $(this).children('li').first().children('a').addClass('is-active').next().addClass('is-open').show();
        }
      });

      $('.accordion-tabs-minimal').on('click', '.tab-link', function(event) {
        event.preventDefault();
        that.activateTab(this);
      });
    });
  }

  static activateTab(obj) {
    if (!$(obj).hasClass('is-active')) {
      // remove `tab-` from obj id
      document.location.hash = $(obj).attr('id').replace('tab-', '');
      var accordionTabs = $(obj).closest('.accordion-tabs-minimal');
      accordionTabs.find('.is-open').removeClass('is-open').hide();

      $(obj).next().toggleClass('is-open').toggle();
      accordionTabs.find('.is-active').removeClass('is-active');
      $(obj).addClass('is-active');
    }
  }
}

export {Accordion};
