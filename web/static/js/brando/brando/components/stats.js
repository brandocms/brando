"use strict";

import $ from "jquery";

import {Socket} from "phoenix"

const MAX_POINTS = 30;
const SPARKLINE_OPTS = {
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
};

class Stats {
    static setup() {
        this.totalMemoryPoints = [];
        this.atomMemoryPoints = [];
        this.binaryMemoryPoints = [];
        this.etsMemoryPoints = [];
        this.systemMemoryPoints = [];
        this.processMemoryPoints = [];
        this.codeMemoryPoints = [];

        let user_token = document.querySelector("meta[name=\"channel_token\"]").getAttribute("content"),
            socket = new Socket("/admin/ws", {params: {token: user_token}}),
            chan = socket.channel("stats", {});

        socket.connect();
        chan.join().receive("ok", ({messages}) => {
            console.log("==> System statistics channel ready");
        });
        chan.on("update", payload => {
            this.update(payload);
        });
    }

    static pushPoint(target, value) {
        target.push(value);
        if (target.length > MAX_POINTS) {
            target.splice(0, 1);
        }
    }

    static updateMemoryGraph(id, statsArray, value) {
        this.pushPoint(statsArray, value);
        $(`${id} .sparkline`).sparkline(statsArray, SPARKLINE_OPTS);
        $(`${id} .text`).html(this.humanFileSize(parseInt(value), false));
    }

    static update(payload) {
        this.updateMemoryGraph('#total-memory', this.totalMemoryPoints, payload.memory.total);
        this.updateMemoryGraph('#system-memory', this.systemMemoryPoints, payload.memory.system);
        this.updateMemoryGraph('#atom-memory', this.atomMemoryPoints, payload.memory.atom);
        this.updateMemoryGraph('#binary-memory', this.binaryMemoryPoints, payload.memory.binary);
        this.updateMemoryGraph('#ets-memory', this.etsMemoryPoints, payload.memory.ets);
        this.updateMemoryGraph('#process-memory', this.processMemoryPoints, payload.memory.process);
        this.updateMemoryGraph('#code-memory', this.codeMemoryPoints, payload.memory.code);

        /* instagram status */
        if (payload.status.instagram) {
            $('#instagram-status').html('<i class="fa fa-check"></i>')
        } else {
            $('#instagram-status').html('<i class="fa fa-times"></i>')
        }

        if (payload.status.registry) {
            $('#registry-status').html('<i class="fa fa-check"></i>')
        } else {
            $('#registry-status').html('<i class="fa fa-times"></i>')
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
