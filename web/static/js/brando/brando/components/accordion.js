import $ from 'jquery';

class Accordion {
  static setup() {
    const that = this;
    $(document).ready(() => {
      const hash = document.location.hash;
      $('.accordion-tabs-minimal').each(() => {
        if (!hash) {
          const $link = $(this).children('li').first().children('a');
          const $linkSibling = $link.next();
          $link.addClass('is-active');
          $linkSibling.addClass('is-open').show();
        } else {
          const $link = $(`#tab-${hash.replace('#', '')}`);
          that.activateTab($link);
        }
      });

      $('.accordion-tabs-minimal').on('click', '.tab-link', (event) => {
        event.preventDefault();
        that.activateTab(event.currentTarget);
      });
    });
  }

  static activateTab(obj) {
    const $obj = $(obj);
    const $accordionTabs = $obj.closest('.accordion-tabs-minimal');
    const $openTabs = $accordionTabs.find('.is-open');
    const $activeTabs = $accordionTabs.find('.is-active');
    const $tabContent = $obj.next();

    if (!$obj.hasClass('is-active')) {
      document.location.hash = $obj.attr('id').replace('tab-', '');
    }

    $openTabs.removeClass('is-open').hide();
    $tabContent.toggleClass('is-open').toggle();
    $activeTabs.removeClass('is-active');
    $obj.addClass('is-active');
  }
}

export default Accordion;
