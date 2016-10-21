import $ from 'jquery';

class Pages {
  static setup() {
    const that = this;
    $('.expand-page-children')
      .click(function onClick(e) {
        that.onClickExpandButton(e, this);
      });
  }

  static onClickExpandButton(e, elem) {
    e.preventDefault();

    $(elem)
      .toggleClass('active');

    $(elem)
      .find('i')
      .toggleClass('fa-plus')
      .toggleClass('fa-times');

    $(`tr.child[data-parent-id=${$(elem).attr('data-id')}]`).toggleClass('hidden');
  }
}

export default Pages;
