"use strict";

import {Socket} from '../vendor/phoenix'

class WS {
    static setup() {
        var _this = this
        let socket = new Socket("/admin/ws")
        socket.connect()
        socket.join("system:stream", {}).receive("ok", chan => {
            console.log("admin:stream hook ready.")
            chan.on("log_msg", payload => {
                _this.log(payload.level, payload.icon, payload.body);
            })
        })
    }
    static log(level, icon, body) {
        let date = new Date();
        $(`<li><i class="fa fa-fw ${icon} m-l-sm m-r-sm"> </i> <span class="time p-r-sm">${date.getHours()}:${date.getMinutes()}</span>${body}</li>`).appendTo("#log-content");
    }
}

export default WS;