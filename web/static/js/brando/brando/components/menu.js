import $ from 'jquery';

class Menu {
  static setup() {
    $('.menuitem.active')
      .parent()
      .parent()
      .addClass('active');
  }
}

export default Menu;
