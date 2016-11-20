import $ from 'jquery';

import { Socket } from 'phoenix';
import i18n from './i18n';
import vex from './vex_brando';

class WS {
  constructor() {
    const that = this;
    const userToken = document.querySelector('meta[name="channel_token"]')
      .getAttribute('content');
    const socket = new Socket('/admin/ws', {
      params: {
        token: userToken,
      },
    });

    socket.connect();

    this.lobbyChannel = socket.channel('user:lobby', {});
    this.lobbyChannel.join()
      .receive('ok', (joinPayload) => {
        console.log('==> Lobby channel ready');
        this.userChannel = socket.channel(`user:${joinPayload.user_id}`, {});
        this.userChannel.join()
          .receive('ok', () => {
            console.log('==> User channel ready');
          });

        this.userChannel.on('alert', (payload) => {
          that.alert(payload.message);
        });

        this.userChannel.on('set_progress', (payload) => {
          that.setProgress(payload.value);
        });

        this.userChannel.on('increase_progress', (payload) => {
          that.increaseProgress(payload.value, payload.id);
        });
      });

    this.systemChannel = socket.channel('system:stream', {});
    this.systemChannel.join()
      .receive('ok', () => {
        console.log('==> System channel ready');
      });

    this.systemChannel.on('alert', (payload) => {
      that.alert(payload.message);
    });

    this.systemChannel.on('set_progress', (payload) => {
      that.setProgress(payload.value);
    });

    this.systemChannel.on('increase_progress', (payload) => {
      that.increaseProgress(payload.value, payload.id);
    });
  }

  alert(message) {
    vex.dialog.alert(message);
  }

  createProgress() {
    const $overlay = $('<div id="overlay">');
    const $container = $('<div id="progress-container">');

    $overlay.appendTo('body');
    $container.appendTo('#overlay');

    $overlay.css({
      'position': 'fixed',
      'top': '0',
      'left': '0',
      'width': '100%',
      'opacity': '0',
      'height': '100%',
      'background-color': '#fff',
      'z-index': '99999',
      'display': 'flex',
      'align-items': 'center',
      'justify-content': 'center',
    });
    $overlay.animate({ opacity: 1 }, 'slow');
    $('<div id="progressbar">').appendTo('#progress-container');

    this.progressbar = new ProgressBar.Circle('#progressbar', {
      strokeWidth: 5,
      color: '#c11',
    });
    this.progressbar.setText(i18n.t('ws:working'));
  }

  increaseProgress(value) {
    let newValue = 0;
    if (this.progressbar) {
      newValue = this.progressbar.value() + value;
    } else {
      this.createProgress();
    }

    this.setProgress(newValue);
  }

  setProgress(value) {
    if (this.progressbar) {
      this.progressbar.animate(value);
    } else {
      this.createProgress();
      this.progressbar.animate(value);
    }

    if (value === 1) {
      this.progressbar.setText('done!');
      $('#overlay')
        .remove();
      this.progressbar = null;
    }
  }
}

const ws = new WS();

export default ws;
