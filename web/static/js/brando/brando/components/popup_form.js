'use strict';

import WS from './ws';
import $ from 'jquery';
import {vex} from './vex_brando';

class PopupForm {
  constructor(formName, language, callback) {
    this.name = formName;
    this.callback = callback;

    WS.systemChannel.on('popup_form:reply', payload => {
      this.display(payload);
    });

    WS.systemChannel.on('popup_form:reply_errors', payload => {
      this.updateForm(payload);
    });

    WS.systemChannel.on('popup_form:error', payload => {
      console.log(`==> PopupForm error: ${payload.message}`);
    });

    WS.systemChannel.on('popup_form:success', payload => {
      this.callback(payload.fields);
    });

    WS.systemChannel.push('popup_form:create', {
      name: this.name,
      language: language
    });
  }

  pushFormData(data) {
    WS.systemChannel.push('popup_form:push_data', {
      name: this.name,
      data: data
    });
  }

  display(payload) {
    this.__doPopup(payload.rendered_form, payload.url, payload.header);
  }

  updateForm(payload) {
    this.__doPopup(payload.rendered_form, payload.url, payload.header);
  }

  __doPopup(content, url, header) {
    let _this = this;
    vex.dialog.open({
      message: `<h3>${header}</h3>${content}`,
      callback: function(data) {
        let $form = $('.vex-dialog-message form');
        if (data !== false) {
          _this.pushFormData($form.serialize());
        }
      }
    });
  }
}

export default PopupForm;
