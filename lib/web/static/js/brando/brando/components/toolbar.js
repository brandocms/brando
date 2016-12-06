import $ from 'jquery';

class Toolbar {
  static setup() {
    const that = this;
    $('.toolbar .logbutton')
      .click(function onClick(e) {
        that.onClickLogButton(e, this);
      });
  }

  static onClickLogButton(e, elem) {
    $(elem)
      .toggleClass('active');
    $('#log-wrapper')
      .toggle();
  }
}

export default Toolbar;
