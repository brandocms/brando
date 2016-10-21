import $ from 'jquery';

import { Socket } from 'phoenix';
import bI18n from './i18n';
import { vex } from './vex_brando';

class WS {
  static setup() {
    const that = this;
    const userToken = document.querySelector('meta[name="channel_token"]')
      .getAttribute('content');
    const socket = new Socket('/admin/ws', {
      params: {
        token: userToken,
      },
    });

    socket.connect();

    WS.lobbyChannel = socket.channel('user:lobby', {});
    WS.lobbyChannel.join()
      .receive('ok', (joinPayload) => {
        console.log('==> Lobby channel ready');
        WS.userChannel = socket.channel(`user:${joinPayload.user_id}`, {});
        WS.userChannel.join()
          .receive('ok', () => {
            console.log('==> User channel ready');
          });

        WS.userChannel.on('alert', (payload) => {
          that.alert(payload.message);
        });

        WS.userChannel.on('set_progress', (payload) => {
          that.setProgress(payload.value);
        });

        WS.userChannel.on('increase_progress', (payload) => {
          that.increaseProgress(payload.value, payload.id);
        });
      });

    WS.systemChannel = socket.channel('system:stream', {});
    WS.systemChannel.join()
      .receive('ok', () => {
        console.log('==> System channel ready');
      });

    WS.systemChannel.on('alert', (payload) => {
      that.alert(payload.message);
    });

    WS.systemChannel.on('set_progress', (payload) => {
      that.setProgress(payload.value);
    });

    WS.systemChannel.on('increase_progress', (payload) => {
      that.increaseProgress(payload.value, payload.id);
    });
  }

  static alert(message) {
    vex.dialog.alert(message);
  }

  static createProgress() {
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

    WS.progressbar = new ProgressBar.Circle('#progressbar', {
      strokeWidth: 5,
      color: '#c11',
    });
    WS.progressbar.setText(bI18n.t('ws:working'));
  }

  static increaseProgress(value) {
    let newValue = 0;
    if (WS.progressbar) {
      newValue = WS.progressbar.value() + value;
    } else {
      WS.createProgress();
    }

    WS.setProgress(newValue);
  }

  static setProgress(value) {
    if (WS.progressbar) {
      WS.progressbar.animate(value);
    } else {
      WS.createProgress();
      WS.progressbar.animate(value);
    }

    if (value === 1) {
      WS.progressbar.setText('done!');
      $('#overlay')
        .remove();
      WS.progressbar = null;
    }
  }
}

WS.progressbar = null;
WS.systemChannel = null;
WS.lobbyChannel = null;
WS.userChannel = null;

export default WS;
