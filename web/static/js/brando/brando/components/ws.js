"use strict";

import $ from "jquery";

import {Socket} from "phoenix"
import {vex} from "./vex_brando";

class WS {
    static setup() {
        var _this = this;
        let user_token = document.querySelector("meta[name=\"channel_token\"]").getAttribute("content");
        let socket = new Socket("/admin/ws", {params: {token: user_token}});
        socket.connect();

        let chan = socket.channel("system:stream", {});
        chan.join().receive("ok", () => {
            console.log("==> System channel ready");
        });

        chan.on("log_msg", payload => {
            _this.log(payload.level, payload.icon, payload.body);
        });

        chan.on("alert", payload => {
            _this.alert(payload.message);
        });

        chan.on("set_progress", payload => {
            _this.set_progress(payload.value);
        });

        chan.on("increase_progress", payload => {
            _this.increase_progress(payload.value, payload.id);
        });
    }

    static log(level, icon, body) {
        let date = new Date();
        $(`<li><i class="fa fa-fw ${icon} m-l-sm m-r-sm"> </i> <span class="time p-r-sm">${date.getHours()}:${date.getMinutes()}</span>${body}</li>`).appendTo("#log-content");
    }

    static alert(message) {
        vex.dialog.alert(message);
    }

    static createProgress() {
        var $overlay = $('<div id="overlay">');
        var $container = $('<div id="progress-container">');

        $overlay.appendTo('body');
        $container.appendTo('#overlay');

        $overlay.css({
            "position": "fixed",
            "top": "0",
            "left": "0",
            "width": "100%",
            "opacity": "0",
            "height": "100%",
            "background-color": "#fff",
            "z-index": "99999",
            "display": "flex",
            "align-items": "center",
            "justify-content": "center"
        });
        $overlay.animate({opacity: 1}, 'slow');
        $('<div id="progressbar">').appendTo('#progress-container');
        WS.progressbar = new ProgressBar.Circle('#progressbar', {
            strokeWidth: 5,
            color: "#c11"
        });
        WS.progressbar.setText('working, please wait!');
    }

    static increase_progress(value) {
        if (WS.progressbar) {
            var newValue = WS.progressbar.value() + value;
        } else {
            WS.createProgress();
        }

        WS.set_progress(newValue)
    }

    static set_progress(value) {
        if (WS.progressbar) {
            WS.progressbar.animate(value);
        } else {
            WS.createProgress();
            WS.progressbar.animate(value);
        }

        if (value == 1) {
            WS.progressbar.setText('done!');
            $('#overlay').remove();
            WS.progressbar = null;
        }
    }
}

WS.progressbar = null;

export default WS;
