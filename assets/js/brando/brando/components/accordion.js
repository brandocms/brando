import $ from 'jquery';

class Accordion {
  constructor() {
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
          this.activateTab($link);
        }
      });

      $('.accordion-tabs-minimal').on('click', '.tab-link', (event) => {
        event.preventDefault();
        this.activateTab(event.currentTarget);
      });
    });
  }

  activateTab(obj) {
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
const accordion = new Accordion();
export default accordion;
