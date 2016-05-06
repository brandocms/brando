"use strict";

import WS from "./ws";
import $ from "jquery";
import {vex} from "./vex_brando";
import {brando} from "./brando";

class PopupForm {
    constructor(formName, language, callback) {
        this.name = formName;
        this.callback = callback;

        WS.chan.on("popup_form:reply", payload => {
            this.display(payload);
        });

        WS.chan.on("popup_form:reply_errors", payload => {
            this.updateForm(payload);
        });

        WS.chan.on("popup_form:error", payload => {
            console.log(`==> PopupForm error: ${payload.message}`);
        });

        WS.chan.on("popup_form:success", payload => {
            this.callback(payload.fields);
        });

        WS.chan.push('popup_form:create', {name: this.name, language: language});
    }

    pushFormData(data) {
        WS.chan.push('popup_form:push_data', {name: this.name, data: data});
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
                let $vex = $(".vex-dialog-message");
                let $form = $(".vex-dialog-message form");
                if (data !== false) {
                    _this.pushFormData($form.serialize());
                }
            }
        });
    }
}

$(() => {
    $('.avatar img').click((e) => {
        let userForm = new PopupForm("user", brando.language, myCallback);
    });

    function myCallback(fields) {
        console.log(`myCallback: ${fields.id} --> ${fields.username}`);
    }
});

export default PopupForm;
