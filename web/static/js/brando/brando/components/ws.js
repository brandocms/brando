"use strict";

import $ from "jquery";

import {Socket} from "phoenix";
import ProgressBar from "progressbar.js";
import {vex} from "./vex_brando";

class WS {
    static setup() {
        var _this = this;
        let user_token = document.querySelector("meta[name=\"channel_token\"]").getAttribute("content");
        let socket = new Socket("/admin/ws", {params: {token: user_token}});

        socket.connect();

        let chan = socket.channel("system:stream", {});

        chan.join().receive("ok", ({messages}) => {
            console.log(">> System channel ready");
        });

        chan.on("log_msg", payload => {
            _this.log(payload.level, payload.icon, payload.body);
        });

        chan.on("alert", payload => {
            _this.alert(payload.message);
        });

        chan.on("progress", payload => {
            _this.progress(payload.value);
        });

    }

    static log(level, icon, body) {
        let date = new Date();
        $(`<li><i class="fa fa-fw ${icon} m-l-sm m-r-sm"> </i> <span class="time p-r-sm">${date.getHours()}:${date.getMinutes()}</span>${body}</li>`).appendTo("#log-content");
    }

    static alert(message) {
        vex.dialog.alert(message);
    }

    static progress(value) {
        console.log(value);
        var line = new ProgressBar.Line('#container');
        console.log(line);
    }
}

export default WS;
