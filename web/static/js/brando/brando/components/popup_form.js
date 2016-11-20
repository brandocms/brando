import $ from 'jquery';
import WS from './ws';
import Autoslug from './autoslug';
import vex from './vex_brando';

class PopupForm {
  constructor(formKey, language, callback, params = [], initialValues = {}) {
    this.key = formKey;
    this.language = language;
    this.params = params;
    this.initialValues = initialValues;
    this.callback = callback;

    WS.systemChannel.on(`popup_form:reply:${this.key}`, (payload) => {
      this.display(payload);
    });

    WS.systemChannel.on(`popup_form:reply_errors:${this.key}`, (payload) => {
      this.updateForm(payload);
    });

    WS.systemChannel.on(`popup_form:error:${this.key}`, (payload) => {
      console.log(`==> PopupForm error: ${payload.message}`);
    });

    WS.systemChannel.on(`popup_form:success:${this.key}`, (payload) => {
      this.callback(payload.fields);
    });
  }

  show() {
    WS.systemChannel.push('popup_form:create', {
      key: this.key,
      language: this.language,
      params: this.params,
      initial_values: this.initialValues,
    });
  }

  pushFormData(data) {
    WS.systemChannel.push('popup_form:push_data', {
      key: this.key,
      data: data,
    });
  }

  display(payload) {
    this.doPopup(payload.rendered_form, payload.url, payload.header);
  }

  updateForm(payload) {
    this.doPopup(payload.rendered_form, payload.url, payload.header);
  }

  doPopup(content, url, header) {
    const self = this;

    vex.dialog.open({
      message: `<h3>${header}</h3>${content}`,
      overlayClosesOnClick: false,
      callback: (data) => {
        const $form = $('.vex-dialog-message form');
        if (data !== false) {
          self.pushFormData($form.serialize());
        }
      },
    });
    Autoslug.scan();
  }
}

export default PopupForm;
