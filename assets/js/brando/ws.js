"use strict";

import {Socket} from '../vendor/phoenix'

class WS {
    static setup() {
        var _this = this
        let socket = new Socket("/ws")
        socket.connect()
        socket.join("admin:stream", {}).receive("ok", chan => {
            console.log("admin:stream hook ready.")
            chan.on("log_msg", payload => {
                _this.log(payload.level, payload.icon, payload.body);
            })
        })
    }
    static log(level, icon, body) {
        $(`<li><i class="fa fa-fw ${icon} m-r-sm"> </i> ${body}</li>`).appendTo("#log-content");
    }
}

export default WS;