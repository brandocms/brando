'use strict';

import $ from 'jquery';

class Brando {
  constructor() {
    this.language = $('html')
      .attr('lang');
    console.log(`==> language = ${this.language}`);
  }
}

let brando = new Brando();

export {
  brando
}
