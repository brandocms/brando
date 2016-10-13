import $ from 'jquery';

class Mobile {
  static setup() {
    // set up mobile menu
    $(document)
      .on('click', '#mobile-nav', () => {
        $('#menu').toggle();
      });
  }
}

export default Mobile;
