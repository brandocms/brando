import $ from 'jquery';

import './brando/extensions/datepicker';
import './brando/extensions/searcher';
import './brando/extensions/slugit';
import './brando/extensions/tablesaw';
import './brando/extensions/tags_input';

import Dropdown from './brando/extensions/dropdown';

import accordion from './brando/components/accordion';
import vex from './brando/components/vex_brando';

import Auth from './brando/components/auth';
import Autoslug from './brando/components/autoslug';
import DatePicker from './brando/components/datepicker';
import Flash from './brando/components/flash';
import FilterTable from './brando/components/filter_table';
import ImagePreview from './brando/components/image_preview';
import Mobile from './brando/components/mobile';
import i18n from './brando/components/i18n';
import Images from './brando/components/images';
import ImageConfig from './brando/components/image_config';
import Menu from './brando/components/menu';
import Pages from './brando/components/pages';
import PopupForm from './brando/components/popup_form';
import Sequence from './brando/components/sequence';
import Sortable from './brando/components/sortable';
import Stats from './brando/components/stats';
import Tags from './brando/components/tags';
import Toolbar from './brando/components/toolbar';
import Utils from './brando/components/utils';
import ws from './brando/components/ws';


class Brando {
  constructor() {
    this.setLanguage();
    this.i18n = i18n;
    this.accordion = accordion;
    this.vex = vex;
    this.ws = ws;
    this.Utils = Utils;
    this.PopupForm = PopupForm;
  }

  setLanguage() {
    this.language = $('html').attr('lang');
    console.log(`==> language = ${this.language}`);
  }
}

const brando = new Brando();

$(() => {
  /**
   * Setup vendored modules.
   */

  Autoslug.setup(brando);
  FilterTable.setup(brando);
  Flash.setup(brando);
  Mobile.setup(brando);
  Sequence.setup(brando);
  Toolbar.setup(brando);
  Tags.setup(brando);
  DatePicker.setup(brando);
  ImagePreview.setup(brando);

  /**
   * Section-specific setup
   */

  switch ($('body').attr('data-script')) {
    case 'images-index':
      Images.setup(brando);
      break;
    case 'images-upload':
      Images.setupUpload(brando);
      break;
    case 'images-configure':
      ImageConfig.setup(brando);
      break;
    case 'portfolio-configure':
      ImageConfig.setup(brando);
      break;
    case 'dashboard-system_info':
      Stats.setup(brando);
      break;
    case 'pages-index':
      Pages.setup(brando);
      break;
    case 'auth':
      Auth.setup(brando);
      break;
  }

  /**
   * Global setup
   */

  Menu.setup();

  $(document).trigger('enhance.tablesaw');

  $('.expander-trigger')
    .click(function onClick() {
      $(this).toggleClass('expander-hidden');
    });
});

module.exports = brando;
