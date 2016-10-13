import $ from 'jquery';

class Brando {
  constructor() {
    this.language = $('html')
      .attr('lang');
    console.log(`==> language = ${this.language}`);
  }
}

const brando = new Brando();

export default brando;
