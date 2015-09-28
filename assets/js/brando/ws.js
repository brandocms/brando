"use strict";

import {Socket} from '../../../deps/phoenix/web/static/js/phoenix.js'

class WS {
    static setup() {
        var _this = this;
        let socket = new Socket("/admin/ws");
        let user_token = document.querySelector("meta[name=\"channel_token\"]").getAttribute("content");
        socket.connect({token: user_token});
        let chan = socket.channel("system:stream", {});
        chan.join().receive("ok", ({messages}) => {
            console.log(">> System channel ready");
        });
        chan.on("log_msg", payload => {
            _this.log(payload.level, payload.icon, payload.body);
        });
    }
    static log(level, icon, body) {
        let date = new Date();
        $(`<li><i class="fa fa-fw ${icon} m-l-sm m-r-sm"> </i> <span class="time p-r-sm">${date.getHours()}:${date.getMinutes()}</span>${body}</li>`).appendTo("#log-content");
    }
}

export default WS;