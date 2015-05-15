"use strict";

import {Socket} from '../vendor/phoenix'

const MAX_POINTS = 30;

class Stats {

    static setup() {
        var _this = this;
        this.memoryPoints = [];
        this.opts = {
            lineWidth: 2,
            type: 'line',
            width: '80px',
            height: '35px',
            lineColor: '#6cc7d9',
            fillColor: '#e2f4f7',
            spotColor: false,
            minSpotColor: false,
            highlightLineColor: 'rgba(0,0,0,0.1)',
            highlightSpotColor: '#6cc7d9',
            spotRadius: 3,
            maxSpotColor: false
        }
        let socket = new Socket("/admin/ws");
        socket.connect();
        let chan = socket.chan("stats", {});
        chan.join().receive("ok", ({messages}) => {
            console.log(">> System statistics channel ready");
        });
        chan.on("update", payload => {
            this.update(payload);
        });
    }

    static update(payload) {
        // update memory
        this.memoryPoints.push(payload.memory);
        if (this.memoryPoints.length > MAX_POINTS) {
            this.memoryPoints.splice(0, 1);
        }
        $('#memory .sparkline')
            .sparkline(this.memoryPoints, this.opts);
        $('#memory .text')
            .html(payload.memory + " mb");
    }
}

export default Stats;