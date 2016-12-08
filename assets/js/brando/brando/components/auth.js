import $ from 'jquery';
import textFit from 'textfit';

class Auth {
  static setup() {
    /**
     * Setup Textfit
     **/
    textFit(document.getElementById('app-name'), {
      widthOnly: true,
      maxFontSize: 80,
    });

    /**
     * Setup spinner
     **/
    $('input[type=submit]')
      .click(() => {
        $('.spinner')
          .fadeIn();
      });
  }
}

export default Auth;
