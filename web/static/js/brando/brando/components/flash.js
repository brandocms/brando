'use strict';

import $ from 'jquery';

class Flash {
  static setup() {
    // set up dismissal of flash alerts
    $('[data-dismiss]')
      .each((index, elem) => {
        $(elem)
          .click(e => {
            e.preventDefault();
            $(elem)
              .parent()
              .hide();
          });
      });
  }
}

export default Flash;
