"use strict";

import {Socket} from '../../../deps/phoenix/web/static/js/phoenix.js'

const MAX_POINTS = 30;

class Stats {

    static setup() {
        var _this = this;
        this.totalMemoryPoints = [];
        this.atomMemoryPoints = [];
        this.opts = {
            lineWidth: 2,
            type: 'line',
            width: '110px',
            height: '50px',
            lineColor: '#6cc7d9',
            fillColor: '#e2f4f7',
            spotColor: false,
            minSpotColor: false,
            highlightLineColor: 'rgba(0,0,0,0.1)',
            highlightSpotColor: '#6cc7d9',
            spotRadius: 3,
            chartRangeMin: 0,
            maxSpotColor: false
        }
        let socket = new Socket("/admin/ws");
        let user_token = document.querySelector("meta[name=\"channel_token\"]").getAttribute("content");
        socket.connect({ token: user_token });
        let chan = socket.channel("stats", {});
        chan.join().receive("ok", ({messages}) => {
            console.log(">> System statistics channel ready");
        });
        chan.on("update", payload => {
            this.update(payload);
        });
    }

    static update(payload) {
        // update memory
        this.totalMemoryPoints.push(payload.total_memory);
        if (this.totalMemoryPoints.length > MAX_POINTS) {
            this.totalMemoryPoints.splice(0, 1);
        }
        $('#total-memory .sparkline').sparkline(this.totalMemoryPoints, this.opts);
        $('#total-memory .text').html(this.humanFileSize(parseInt(payload.total_memory), false));

        this.atomMemoryPoints.push(payload.atom_memory);
        if (this.atomMemoryPoints.length > MAX_POINTS) {
            this.atomMemoryPoints.splice(0, 1);
        }
        $('#atom-memory .sparkline').sparkline(this.atomMemoryPoints, this.opts);
        $('#atom-memory .text').html(this.humanFileSize(parseInt(payload.atom_memory), false));

        /* instagram status */
        if (payload.instagram_status) {
            $('#instagram-status .status').html('<i class="fa fa-check fa-4x"></i>')
        } else {
            $('#instagram-status .status').html('<i class="fa fa-times fa-4x"></i>')
        }
    }

    static humanFileSize(bytes, si) {
        var thresh = si ? 1000 : 1024;
        if(Math.abs(bytes) < thresh) {
            return bytes + ' B';
        }
        var units = si
            ? ['kB','MB','GB','TB','PB','EB','ZB','YB']
            : ['KiB','MiB','GiB','TiB','PiB','EiB','ZiB','YiB'];
        var u = -1;
        do {
            bytes /= thresh;
            ++u;
        } while (Math.abs(bytes) >= thresh && u < units.length - 1);
        return bytes.toFixed(1) + ' ' + units[u];
    }

}

export default Stats;