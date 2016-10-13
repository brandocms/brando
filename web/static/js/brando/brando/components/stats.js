'use strict';

import $ from 'jquery';
import {Socket} from 'phoenix';
import Chart from 'chart.js';

const MAX_POINTS = 30;

function range(start, count) {
  if (arguments.length == 1) {
    count = start;
    start = 0;
  }

  var foo = [];
  for (var i = 0; i < count; i++) {
    foo.push(start + i);
  }
  return foo;
}

class Stats {
  static setup() {
    let defaultOptions = {
      animation: {
        duration: 100,
        easing: 'easeInQuart'
      },
      elements: {
        line: {
          backgroundColor: 'rgba(99, 166, 177, 0.19)',
          borderColor: '#84D1DE'
        },
        point: {
          backgroundColor: '#84D1DE',
          borderColor: '#84D1DE',
          radius: 1
        }
      },
      legend: {
        display: false
      },
      scales: {
        xAxes: [{
          display: true,
          ticks: {
            display: false
          },
          gridLines: {
            color: 'rgba(0, 0, 0, 0.05)'
          }
        }],
        yAxes: [{
          display: true,
          ticks: {
            beginAtZero: true,
            maxTicksLimit: 5,
            suggestedMax: 100000000,
            callback: function(value) {
              return Stats.humanFileSize(value, true);
            },
            fontFamily: 'a-mono',
            fontSize: 10
          },
          gridLines: {
            color: 'rgba(0, 0, 0, 0.05)'
          }
        }]
      },
      tooltips: {
        callbacks: {
          label: function(tooltipItem) {
            return Stats.humanFileSize(tooltipItem.yLabel, true);
          },
          title: function() {

          }
        }
      }
    };

    // create charts
    let canvas = document.getElementById('total-memory-chart')
    let ctx = canvas.getContext('2d');

    let totalMemoryChart = new Chart(ctx, {
      type: 'line',
      options: defaultOptions,
      data: {
        labels: range(1, MAX_POINTS),
        datasets: [{
          label: '',
          data: []
        }]
      }
    });

    canvas = document.getElementById('system-memory-chart')
    ctx = canvas.getContext('2d');

    let systemMemoryChart = new Chart(ctx, {
      type: 'line',
      options: defaultOptions,
      data: {
        labels: range(1, MAX_POINTS),
        datasets: [{
          label: '',
          data: []
        }]
      }
    });

    canvas = document.getElementById('atom-memory-chart')
    ctx = canvas.getContext('2d');

    let atomMemoryChart = new Chart(ctx, {
      type: 'line',
      options: defaultOptions,
      data: {
        labels: range(1, MAX_POINTS),
        datasets: [{
          label: '',
          data: []
        }]
      }
    });

    canvas = document.getElementById('binary-memory-chart')
    ctx = canvas.getContext('2d');

    let binaryMemoryChart = new Chart(ctx, {
      type: 'line',
      options: defaultOptions,
      data: {
        labels: range(1, MAX_POINTS),
        datasets: [{
          label: '',
          data: []
        }]
      }
    });

    canvas = document.getElementById('ets-memory-chart')
    ctx = canvas.getContext('2d');

    let etsMemoryChart = new Chart(ctx, {
      type: 'line',
      options: defaultOptions,
      data: {
        labels: range(1, MAX_POINTS),
        datasets: [{
          label: '',
          data: []
        }]
      }
    });

    canvas = document.getElementById('process-memory-chart')
    ctx = canvas.getContext('2d');

    let processMemoryChart = new Chart(ctx, {
      type: 'line',
      options: defaultOptions,
      data: {
        labels: range(1, MAX_POINTS),
        datasets: [{
          label: '',
          data: []
        }]
      }
    });

    canvas = document.getElementById('code-memory-chart')
    ctx = canvas.getContext('2d');

    let codeMemoryChart = new Chart(ctx, {
      type: 'line',
      options: defaultOptions,
      data: {
        labels: range(1, 30),
        datasets: [{
          label: '',
          data: []
        }]
      }
    });

    this.metrics = [{
      key: 'total',
      chart: totalMemoryChart,
      values: []
    }, {
      key: 'system',
      chart: systemMemoryChart,
      values: []
    }, {
      key: 'atom',
      chart: atomMemoryChart,
      values: []
    }, {
      key: 'binary',
      chart: binaryMemoryChart,
      values: []
    }, {
      key: 'ets',
      chart: etsMemoryChart,
      values: []
    }, {
      key: 'process',
      chart: processMemoryChart,
      values: []
    }, {
      key: 'code',
      chart: codeMemoryChart,
      values: []
    }];

    let user_token = document.querySelector('meta[name="channel_token"]')
      .getAttribute('content'),
      socket = new Socket('/admin/ws', {
        params: {
          token: user_token
        }
      }),
      chan = socket.channel('stats', {});

    socket.connect();
    chan.join()
      .receive('ok', () => {
        console.log('==> System statistics channel ready');
      });
    chan.on('update', payload => {
      this.update(payload);
    });
  }

  static updateCharts(payload) {
    for (let x = 0; x < this.metrics.length; x++) {
      let metric = this.metrics[x];
      let payloadValue = payload.memory[metric.key];
      metric.values.push(payloadValue);
      if (metric.values.length > MAX_POINTS) {
        metric.values.splice(0, 1);
      }
      $(`#${metric.key}-memory .text`)
        .html(this.humanFileSize(parseInt(payloadValue), false));
      metric.chart.data.datasets[0].data = metric.values;
      metric.chart.update();
    }

  }

  static updateUptime(payload) {
    if (payload.status.uptime) {
      $('#system-uptime .display')
        .html(payload.status.uptime);
    }
  }

  static update(payload) {
    this.updateCharts(payload);
    this.updateUptime(payload);

    /* instagram status */
    if (payload.status.instagram) {
      $('#instagram-status')
        .html('<i class="fa fa-check"></i>')
    } else {
      $('#instagram-status')
        .html('<i class="fa fa-times"></i>')
    }

    if (payload.status.registry) {
      $('#registry-status')
        .html('<i class="fa fa-check"></i>')
    } else {
      $('#registry-status')
        .html('<i class="fa fa-times"></i>')
    }
  }

  static humanFileSize(bytes, si) {
    var thresh = si ? 1000 : 1024;
    if (Math.abs(bytes) < thresh) {
      return bytes + ' B';
    }
    var units = si ?
      ['kB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'] :
      ['KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'EiB', 'ZiB', 'YiB'];
    var u = -1;
    do {
      bytes /= thresh;
      ++u;
    } while (Math.abs(bytes) >= thresh && u < units.length - 1);
    return bytes.toFixed(1) + ' ' + units[u];
  }
}

export default Stats;
