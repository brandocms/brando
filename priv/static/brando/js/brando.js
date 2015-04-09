'use strict';

(function () {
  'use strict';

  var globals = typeof window !== 'undefined' ? window : global;
  if (typeof globals.require === 'function') return;

  var modules = {};
  var cache = {};

  var has = function has(object, name) {
    return ({}).hasOwnProperty.call(object, name);
  };

  var expand = function expand(root, name) {
    var results = [],
        parts,
        part;
    if (/^\.\.?(\/|$)/.test(name)) {
      parts = [root, name].join('/').split('/');
    } else {
      parts = name.split('/');
    }
    for (var i = 0, length = parts.length; i < length; i++) {
      part = parts[i];
      if (part === '..') {
        results.pop();
      } else if (part !== '.' && part !== '') {
        results.push(part);
      }
    }
    return results.join('/');
  };

  var dirname = function dirname(path) {
    return path.split('/').slice(0, -1).join('/');
  };

  var localRequire = function localRequire(path) {
    return function (name) {
      var dir = dirname(path);
      var absolute = expand(dir, name);
      return globals.require(absolute, path);
    };
  };

  var initModule = function initModule(name, definition) {
    var module = { id: name, exports: {} };
    cache[name] = module;
    definition(module.exports, localRequire(name), module);
    return module.exports;
  };

  var require = function require(name, loaderPath) {
    var path = expand(name, '.');
    if (loaderPath == null) loaderPath = '/';

    if (has(cache, path)) {
      return cache[path].exports;
    }if (has(modules, path)) {
      return initModule(path, modules[path]);
    }var dirIndex = expand(path, './index');
    if (has(cache, dirIndex)) {
      return cache[dirIndex].exports;
    }if (has(modules, dirIndex)) {
      return initModule(dirIndex, modules[dirIndex]);
    }throw new Error('Cannot find module "' + name + '" from ' + '"' + loaderPath + '"');
  };

  var define = function define(bundle, fn) {
    if (typeof bundle === 'object') {
      for (var key in bundle) {
        if (has(bundle, key)) {
          modules[key] = bundle[key];
        }
      }
    } else {
      modules[bundle] = fn;
    }
  };

  var list = function list() {
    var result = [];
    for (var item in modules) {
      if (has(modules, item)) {
        result.push(item);
      }
    }
    return result;
  };

  globals.require = require;
  globals.require.define = define;
  globals.require.register = define;
  globals.require.list = list;
  globals.require.brunch = true;
})();
require.define({ phoenix: function phoenix(exports, require, module) {
    'use strict';

    var _classCallCheck = function _classCallCheck(instance, Constructor) {
      if (!(instance instanceof Constructor)) {
        throw new TypeError('Cannot call a class as a function');
      }
    };

    var SOCKET_STATES = { connecting: 0, open: 1, closing: 2, closed: 3 };
    var CHANNEL_EVENTS = {
      close: 'phx_close',
      error: 'phx_error',
      join: 'phx_join',
      reply: 'phx_reply',
      leave: 'phx_leave'
    };

    var Push = (function () {

      // Initializes the Push
      //
      // chan - The Channel
      // event - The event, ie `"phx_join"`
      // payload - The payload, ie `{user_id: 123}`
      // mergePush - The optional `Push` to merge hooks from

      function Push(chan, event, payload, mergePush) {
        var _this = this;

        _classCallCheck(this, Push);

        this.chan = chan;
        this.event = event;
        this.payload = payload || {};
        this.receivedResp = null;
        this.afterHooks = [];
        this.recHooks = {};
        this.sent = false;
        if (mergePush) {
          mergePush.afterHooks.forEach(function (hook) {
            return _this.after(hook.ms, hook.callback);
          });
          for (var status in mergePush.recHooks) {
            if (mergePush.recHooks.hasOwnProperty(status)) {
              this.receive(status, mergePush.recHooks[status]);
            }
          }
        }
      }

      Push.prototype.send = function send() {
        var _this = this;

        var ref = this.chan.socket.makeRef();
        var refEvent = this.chan.replyEventName(ref);

        this.chan.on(refEvent, function (payload) {
          _this.receivedResp = payload;
          _this.matchReceive(payload);
          _this.chan.off(refEvent);
          _this.cancelAfters();
        });

        this.startAfters();
        this.sent = true;
        this.chan.socket.push({
          topic: this.chan.topic,
          event: this.event,
          payload: this.payload,
          ref: ref
        });
      };

      Push.prototype.receive = function receive(status, callback) {
        if (this.receivedResp && this.receivedResp.status === status) {
          callback(this.receivedResp.response);
        }
        this.recHooks[status] = callback;
        return this;
      };

      Push.prototype.after = function after(ms, callback) {
        var timer = null;
        if (this.sent) {
          timer = setTimeout(callback, ms);
        }
        this.afterHooks.push({ ms: ms, callback: callback, timer: timer });
        return this;
      };

      // private

      Push.prototype.matchReceive = function matchReceive(_ref) {
        var status = _ref.status;
        var response = _ref.response;
        var ref = _ref.ref;

        var callback = this.recHooks[status];
        if (!callback) {
          return;
        }

        if (this.event === CHANNEL_EVENTS.join) {
          callback(this.chan);
        } else {
          callback(response);
        }
      };

      Push.prototype.cancelAfters = function cancelAfters() {
        this.afterHooks.forEach(function (hook) {
          clearTimeout(hook.timer);
          hook.timer = null;
        });
      };

      Push.prototype.startAfters = function startAfters() {
        this.afterHooks.map(function (hook) {
          if (!hook.timer) {
            hook.timer = setTimeout(function () {
              return hook.callback();
            }, hook.ms);
          }
        });
      };

      return Push;
    })();

    var Channel = exports.Channel = (function () {
      function Channel(topic, message, callback, socket) {
        _classCallCheck(this, Channel);

        this.topic = topic;
        this.message = message;
        this.callback = callback;
        this.socket = socket;
        this.bindings = [];
        this.afterHooks = [];
        this.recHooks = {};
        this.joinPush = new Push(this, CHANNEL_EVENTS.join, this.message);

        this.reset();
      }

      Channel.prototype.after = function after(ms, callback) {
        this.joinPush.after(ms, callback);
        return this;
      };

      Channel.prototype.receive = function receive(status, callback) {
        this.joinPush.receive(status, callback);
        return this;
      };

      Channel.prototype.rejoin = function rejoin() {
        this.reset();
        this.joinPush.send();
      };

      Channel.prototype.onClose = function onClose(callback) {
        this.on(CHANNEL_EVENTS.close, callback);
      };

      Channel.prototype.onError = function onError(callback) {
        var _this = this;

        this.on(CHANNEL_EVENTS.error, function (reason) {
          callback(reason);
          _this.trigger(CHANNEL_EVENTS.close, 'error');
        });
      };

      Channel.prototype.reset = function reset() {
        var _this = this;

        this.bindings = [];
        var newJoinPush = new Push(this, CHANNEL_EVENTS.join, this.message, this.joinPush);
        this.joinPush = newJoinPush;
        this.onError(function (reason) {
          setTimeout(function () {
            return _this.rejoin();
          }, _this.socket.reconnectAfterMs);
        });
        this.on(CHANNEL_EVENTS.reply, function (payload) {
          _this.trigger(_this.replyEventName(payload.ref), payload);
        });
      };

      Channel.prototype.on = function on(event, callback) {
        this.bindings.push({ event: event, callback: callback });
      };

      Channel.prototype.isMember = function isMember(topic) {
        return this.topic === topic;
      };

      Channel.prototype.off = function off(event) {
        this.bindings = this.bindings.filter(function (bind) {
          return bind.event !== event;
        });
      };

      Channel.prototype.trigger = function trigger(triggerEvent, msg) {
        this.bindings.filter(function (bind) {
          return bind.event === triggerEvent;
        }).map(function (bind) {
          return bind.callback(msg);
        });
      };

      Channel.prototype.push = function push(event, payload) {
        var pushEvent = new Push(this, event, payload);
        pushEvent.send();

        return pushEvent;
      };

      Channel.prototype.replyEventName = function replyEventName(ref) {
        return 'chan_reply_' + ref;
      };

      Channel.prototype.leave = function leave() {
        var _this = this;

        return this.push(CHANNEL_EVENTS.leave).receive('ok', function () {
          _this.socket.leave(_this);
          chan.reset();
        });
      };

      return Channel;
    })();

    var Socket = exports.Socket = (function () {

      // Initializes the Socket
      //
      // endPoint - The string WebSocket endpoint, ie, "ws://example.com/ws",
      //                                               "wss://example.com"
      //                                               "/ws" (inherited host & protocol)
      // opts - Optional configuration
      //   transport - The Websocket Transport, ie WebSocket, Phoenix.LongPoller.
      //               Defaults to WebSocket with automatic LongPoller fallback.
      //   heartbeatIntervalMs - The millisec interval to send a heartbeat message
      //   reconnectAfterMs - The millisec interval to reconnect after connection loss
      //   logger - The optional function for specialized logging, ie:
      //            `logger: function(msg){ console.log(msg) }`
      //   longpoller_timeout - The maximum timeout of a long poll AJAX request.
      //                        Defaults to 20s (double the server long poll timer).
      //
      // For IE8 support use an ES5-shim (https://github.com/es-shims/es5-shim)
      //

      function Socket(endPoint) {
        var opts = arguments[1] === undefined ? {} : arguments[1];

        _classCallCheck(this, Socket);

        this.states = SOCKET_STATES;
        this.stateChangeCallbacks = { open: [], close: [], error: [], message: [] };
        this.flushEveryMs = 50;
        this.reconnectTimer = null;
        this.channels = [];
        this.sendBuffer = [];
        this.ref = 0;
        this.transport = opts.transport || window.WebSocket || LongPoller;
        this.heartbeatIntervalMs = opts.heartbeatIntervalMs || 30000;
        this.reconnectAfterMs = opts.reconnectAfterMs || 5000;
        this.logger = opts.logger || function () {}; // noop
        this.longpoller_timeout = opts.longpoller_timeout || 20000;
        this.endPoint = this.expandEndpoint(endPoint);

        this.resetBufferTimer();
      }

      Socket.prototype.protocol = function protocol() {
        return location.protocol.match(/^https/) ? 'wss' : 'ws';
      };

      Socket.prototype.expandEndpoint = function expandEndpoint(endPoint) {
        if (endPoint.charAt(0) !== '/') {
          return endPoint;
        }
        if (endPoint.charAt(1) === '/') {
          return '' + this.protocol() + ':' + endPoint;
        }

        return '' + this.protocol() + '://' + location.host + '' + endPoint;
      };

      Socket.prototype.disconnect = function disconnect(callback, code, reason) {
        if (this.conn) {
          this.conn.onclose = function () {}; // noop
          if (code) {
            this.conn.close(code, reason || '');
          } else {
            this.conn.close();
          }
          this.conn = null;
        }
        callback && callback();
      };

      Socket.prototype.connect = function connect() {
        var _this = this;

        this.disconnect(function () {
          _this.conn = new _this.transport(_this.endPoint);
          _this.conn.timeout = _this.longpoller_timeout;
          _this.conn.onopen = function () {
            return _this.onConnOpen();
          };
          _this.conn.onerror = function (error) {
            return _this.onConnError(error);
          };
          _this.conn.onmessage = function (event) {
            return _this.onConnMessage(event);
          };
          _this.conn.onclose = function (event) {
            return _this.onConnClose(event);
          };
        });
      };

      Socket.prototype.resetBufferTimer = function resetBufferTimer() {
        var _this = this;

        clearTimeout(this.sendBufferTimer);
        this.sendBufferTimer = setTimeout(function () {
          return _this.flushSendBuffer();
        }, this.flushEveryMs);
      };

      // Logs the message. Override `this.logger` for specialized logging. noops by default

      Socket.prototype.log = function log(msg) {
        this.logger(msg);
      };

      // Registers callbacks for connection state change events
      //
      // Examples
      //
      //    socket.onError function(error){ alert("An error occurred") }
      //

      Socket.prototype.onOpen = function onOpen(callback) {
        this.stateChangeCallbacks.open.push(callback);
      };

      Socket.prototype.onClose = function onClose(callback) {
        this.stateChangeCallbacks.close.push(callback);
      };

      Socket.prototype.onError = function onError(callback) {
        this.stateChangeCallbacks.error.push(callback);
      };

      Socket.prototype.onMessage = function onMessage(callback) {
        this.stateChangeCallbacks.message.push(callback);
      };

      Socket.prototype.onConnOpen = function onConnOpen() {
        var _this = this;

        clearInterval(this.reconnectTimer);
        if (!this.conn.skipHeartbeat) {
          clearInterval(this.heartbeatTimer);
          this.heartbeatTimer = setInterval(function () {
            return _this.sendHeartbeat();
          }, this.heartbeatIntervalMs);
        }
        this.rejoinAll();
        this.stateChangeCallbacks.open.forEach(function (callback) {
          return callback();
        });
      };

      Socket.prototype.onConnClose = function onConnClose(event) {
        var _this = this;

        this.log('WS close:');
        this.log(event);
        clearInterval(this.reconnectTimer);
        clearInterval(this.heartbeatTimer);
        this.reconnectTimer = setInterval(function () {
          return _this.connect();
        }, this.reconnectAfterMs);
        this.stateChangeCallbacks.close.forEach(function (callback) {
          return callback(event);
        });
      };

      Socket.prototype.onConnError = function onConnError(error) {
        this.log('WS error:');
        this.log(error);
        this.stateChangeCallbacks.error.forEach(function (callback) {
          return callback(error);
        });
      };

      Socket.prototype.connectionState = function connectionState() {
        switch (this.conn && this.conn.readyState) {
          case this.states.connecting:
            return 'connecting';
          case this.states.open:
            return 'open';
          case this.states.closing:
            return 'closing';
          default:
            return 'closed';
        }
      };

      Socket.prototype.isConnected = function isConnected() {
        return this.connectionState() === 'open';
      };

      Socket.prototype.rejoinAll = function rejoinAll() {
        this.channels.forEach(function (chan) {
          return chan.rejoin();
        });
      };

      Socket.prototype.join = function join(topic, message, callback) {
        var chan = new Channel(topic, message, callback, this);
        this.channels.push(chan);
        if (this.isConnected()) {
          chan.rejoin();
        }
        return chan;
      };

      Socket.prototype.leave = function leave(chan) {
        this.channels = this.channels.filter(function (c) {
          return !c.isMember(chan.topic);
        });
      };

      Socket.prototype.push = function push(data) {
        var _this = this;

        var callback = function callback() {
          return _this.conn.send(JSON.stringify(data));
        };
        if (this.isConnected()) {
          callback();
        } else {
          this.sendBuffer.push(callback);
        }
      };

      // Return the next message ref, accounting for overflows

      Socket.prototype.makeRef = function makeRef() {
        var newRef = this.ref + 1;
        if (newRef === this.ref) {
          this.ref = 0;
        } else {
          this.ref = newRef;
        }

        return this.ref.toString();
      };

      Socket.prototype.sendHeartbeat = function sendHeartbeat() {
        this.push({ topic: 'phoenix', event: 'heartbeat', payload: {}, ref: this.makeRef() });
      };

      Socket.prototype.flushSendBuffer = function flushSendBuffer() {
        if (this.isConnected() && this.sendBuffer.length > 0) {
          this.sendBuffer.forEach(function (callback) {
            return callback();
          });
          this.sendBuffer = [];
        }
        this.resetBufferTimer();
      };

      Socket.prototype.onConnMessage = function onConnMessage(rawMessage) {
        this.log('message received:');
        this.log(rawMessage);

        var _JSON$parse = JSON.parse(rawMessage.data);

        var topic = _JSON$parse.topic;
        var event = _JSON$parse.event;
        var payload = _JSON$parse.payload;

        this.channels.filter(function (chan) {
          return chan.isMember(topic);
        }).forEach(function (chan) {
          return chan.trigger(event, payload);
        });
        this.stateChangeCallbacks.message.forEach(function (callback) {
          callback(topic, event, payload);
        });
      };

      return Socket;
    })();

    var LongPoller = exports.LongPoller = (function () {
      function LongPoller(endPoint) {
        _classCallCheck(this, LongPoller);

        this.retryInMs = 5000;
        this.endPoint = null;
        this.token = null;
        this.sig = null;
        this.skipHeartbeat = true;
        this.onopen = function () {}; // noop
        this.onerror = function () {}; // noop
        this.onmessage = function () {}; // noop
        this.onclose = function () {}; // noop
        this.states = SOCKET_STATES;
        this.upgradeEndpoint = this.normalizeEndpoint(endPoint);
        this.pollEndpoint = this.upgradeEndpoint + (/\/$/.test(endPoint) ? 'poll' : '/poll');
        this.readyState = this.states.connecting;

        this.poll();
      }

      LongPoller.prototype.normalizeEndpoint = function normalizeEndpoint(endPoint) {
        return endPoint.replace('ws://', 'http://').replace('wss://', 'https://');
      };

      LongPoller.prototype.endpointURL = function endpointURL() {
        return this.pollEndpoint + ('?token=' + encodeURIComponent(this.token) + '&sig=' + encodeURIComponent(this.sig));
      };

      LongPoller.prototype.closeAndRetry = function closeAndRetry() {
        this.close();
        this.readyState = this.states.connecting;
      };

      LongPoller.prototype.ontimeout = function ontimeout() {
        this.onerror('timeout');
        this.closeAndRetry();
      };

      LongPoller.prototype.poll = function poll() {
        var _this = this;

        if (!(this.readyState === this.states.open || this.readyState === this.states.connecting)) {
          return;
        }

        Ajax.request('GET', this.endpointURL(), 'application/json', null, this.timeout, this.ontimeout.bind(this), function (resp) {
          if (resp) {
            var status = resp.status;
            var token = resp.token;
            var sig = resp.sig;
            var messages = resp.messages;

            _this.token = token;
            _this.sig = sig;
          } else {
            var status = 0;
          }

          switch (status) {
            case 200:
              messages.forEach(function (msg) {
                return _this.onmessage({ data: JSON.stringify(msg) });
              });
              _this.poll();
              break;
            case 204:
              _this.poll();
              break;
            case 410:
              _this.readyState = _this.states.open;
              _this.onopen();
              _this.poll();
              break;
            case 0:
            case 500:
              _this.onerror();
              _this.closeAndRetry();
              break;
            default:
              throw 'unhandled poll status ' + status;
          }
        });
      };

      LongPoller.prototype.send = function send(body) {
        var _this = this;

        Ajax.request('POST', this.endpointURL(), 'application/json', body, this.timeout, this.onerror.bind(this, 'timeout'), function (resp) {
          if (!resp || resp.status !== 200) {
            _this.onerror(status);
            _this.closeAndRetry();
          }
        });
      };

      LongPoller.prototype.close = function close(code, reason) {
        this.readyState = this.states.closed;
        this.onclose();
      };

      return LongPoller;
    })();

    var Ajax = exports.Ajax = (function () {
      function Ajax() {
        _classCallCheck(this, Ajax);
      }

      Ajax.request = function request(method, endPoint, accept, body, timeout, ontimeout, callback) {
        if (window.XDomainRequest) {
          var req = new XDomainRequest(); // IE8, IE9
          this.xdomainRequest(req, method, endPoint, body, timeout, ontimeout, callback);
        } else {
          var req = window.XMLHttpRequest ? new XMLHttpRequest() : // IE7+, Firefox, Chrome, Opera, Safari
          new ActiveXObject('Microsoft.XMLHTTP'); // IE6, IE5
          this.xhrRequest(req, method, endPoint, accept, body, timeout, ontimeout, callback);
        }
      };

      Ajax.xdomainRequest = function xdomainRequest(req, method, endPoint, body, timeout, ontimeout, callback) {
        var _this = this;

        req.timeout = timeout;
        req.open(method, endPoint);
        req.onload = function () {
          var response = _this.parseJSON(req.responseText);
          callback && callback(response);
        };
        if (ontimeout) {
          req.ontimeout = ontimeout;
        }

        // Work around bug in IE9 that requires an attached onprogress handler
        req.onprogress = function () {};

        req.send(body);
      };

      Ajax.xhrRequest = function xhrRequest(req, method, endPoint, accept, body, timeout, ontimeout, callback) {
        var _this = this;

        req.timeout = timeout;
        req.open(method, endPoint, true);
        req.setRequestHeader('Content-Type', accept);
        req.onerror = function () {
          callback && callback(null);
        };
        req.onreadystatechange = function () {
          if (req.readyState === _this.states.complete && callback) {
            var response = _this.parseJSON(req.responseText);
            callback(response);
          }
        };
        if (ontimeout) {
          req.ontimeout = ontimeout;
        }

        req.send(body);
      };

      Ajax.parseJSON = function parseJSON(resp) {
        return resp && resp !== '' ? JSON.parse(resp) : null;
      };

      return Ajax;
    })();

    Ajax.states = { complete: 4 };
    exports.__esModule = true;
  } });
if (typeof window === 'object' && !window.Phoenix) {
  window.Phoenix = require('phoenix');
};
/*! Brunch !*/
'use strict';

$(document).ready(function () {
  $('.accordion-tabs-minimal').each(function (index) {
    $(this).children('li').first().children('a').addClass('is-active').next().addClass('is-open').show();
  });

  $('.accordion-tabs-minimal').on('click', 'li > a', function (event) {
    event.preventDefault();
    activate_tab(this);
  });
});

function activate_tab(obj) {
  if (!$(obj).hasClass('is-active')) {
    // remove `tab-` from obj id
    document.location.hash = $(obj).attr('id').replace('tab-', '');
    var accordionTabs = $(obj).closest('.accordion-tabs-minimal');
    accordionTabs.find('.is-open').removeClass('is-open').hide();

    $(obj).next().toggleClass('is-open').toggle();
    accordionTabs.find('.is-active').removeClass('is-active');
    $(obj).addClass('is-active');
  }
}
/* ========================================================================
 * Bootstrap: dropdown.js v3.2.0
 * http://getbootstrap.com/javascript/#dropdowns
 * ========================================================================
 * Copyright 2011-2014 Twitter, Inc.
 * Licensed under MIT (https://github.com/twbs/bootstrap/blob/master/LICENSE)
 * ======================================================================== */

'use strict';

+(function ($) {
  'use strict';

  // DROPDOWN CLASS DEFINITION
  // =========================

  var backdrop = '.dropdown-backdrop';
  var toggle = '[data-toggle="dropdown"]';
  var Dropdown = function Dropdown(element) {
    $(element).on('click.bs.dropdown', this.toggle);
  };

  Dropdown.VERSION = '3.2.0';

  Dropdown.prototype.toggle = function (e) {
    var $this = $(this);

    if ($this.is('.disabled, :disabled')) return;

    var $parent = getParent($this);
    var isActive = $parent.hasClass('open');

    clearMenus();

    if (!isActive) {
      if ('ontouchstart' in document.documentElement && !$parent.closest('.navbar-nav').length) {
        // if mobile we use a backdrop because click events don't delegate
        $('<div class="dropdown-backdrop"/>').insertAfter($(this)).on('click', clearMenus);
      }

      var relatedTarget = { relatedTarget: this };
      $parent.trigger(e = $.Event('show.bs.dropdown', relatedTarget));

      if (e.isDefaultPrevented()) return;

      $this.trigger('focus');

      $parent.toggleClass('open').trigger('shown.bs.dropdown', relatedTarget);
    }

    return false;
  };

  Dropdown.prototype.keydown = function (e) {
    if (!/(38|40|27)/.test(e.keyCode)) return;

    var $this = $(this);

    e.preventDefault();
    e.stopPropagation();

    if ($this.is('.disabled, :disabled')) return;

    var $parent = getParent($this);
    var isActive = $parent.hasClass('open');

    if (!isActive || isActive && e.keyCode == 27) {
      if (e.which == 27) $parent.find(toggle).trigger('focus');
      return $this.trigger('click');
    }

    var desc = ' li:not(.divider):visible a';
    var $items = $parent.find('[role="menu"]' + desc + ', [role="listbox"]' + desc);

    if (!$items.length) return;

    var index = $items.index($items.filter(':focus'));

    if (e.keyCode == 38 && index > 0) index--; // up
    if (e.keyCode == 40 && index < $items.length - 1) index++; // down
    if (! ~index) index = 0;

    $items.eq(index).trigger('focus');
  };

  function clearMenus(e) {
    if (e && e.which === 3) {
      return;
    }$(backdrop).remove();
    $(toggle).each(function () {
      var $parent = getParent($(this));
      var relatedTarget = { relatedTarget: this };
      if (!$parent.hasClass('open')) return;
      $parent.trigger(e = $.Event('hide.bs.dropdown', relatedTarget));
      if (e.isDefaultPrevented()) return;
      $parent.removeClass('open').trigger('hidden.bs.dropdown', relatedTarget);
    });
  }

  function getParent($this) {
    var selector = $this.attr('data-target');

    if (!selector) {
      selector = $this.attr('href');
      selector = selector && /#[A-Za-z]/.test(selector) && selector.replace(/.*(?=#[^\s]*$)/, '') // strip for ie7
      ;
    }

    var $parent = selector && $(selector);

    return $parent && $parent.length ? $parent : $this.parent();
  }

  // DROPDOWN PLUGIN DEFINITION
  // ==========================

  function Plugin(option) {
    return this.each(function () {
      var $this = $(this);
      var data = $this.data('bs.dropdown');

      if (!data) $this.data('bs.dropdown', data = new Dropdown(this));
      if (typeof option == 'string') data[option].call($this);
    });
  }

  var old = $.fn.dropdown;

  $.fn.dropdown = Plugin;
  $.fn.dropdown.Constructor = Dropdown;

  // DROPDOWN NO CONFLICT
  // ====================

  $.fn.dropdown.noConflict = function () {
    $.fn.dropdown = old;
    return this;
  };

  // APPLY TO STANDARD DROPDOWN ELEMENTS
  // ===================================

  $(document).on('click.bs.dropdown.data-api', clearMenus).on('click.bs.dropdown.data-api', '.dropdown form', function (e) {
    e.stopPropagation();
  }).on('click.bs.dropdown.data-api', toggle, Dropdown.prototype.toggle).on('keydown.bs.dropdown.data-api', toggle + ', [role="menu"], [role="listbox"]', Dropdown.prototype.keydown);
})(jQuery);

// popover
// $("[data-toggle=popover]").popover();
// $(document).on('click', '.popover-title .close', function(e){
//   var $target = $(e.target), $popover = $target.closest('.popover').prev();
//   $popover && $popover.popover('hide');
// });

// // ajax modal
// $(document).on('click', '[data-toggle="ajaxModal"]',
//   function(e) {
//     $('#ajaxModal').remove();
//     e.preventDefault();
//     var $this = $(this)
//       , $remote = $this.data('remote') || $this.attr('href')
//       , $modal = $('<div class="modal" id="ajaxModal"><div class="modal-body"></div></div>');
//     $('body').append($modal);
//     $modal.modal();
//     $modal.load($remote);
//   }
// );

// dropdown menu
$.fn.dropdown.Constructor.prototype.change = function (e) {
  e.preventDefault();
  var $item = $(e.target),
      $select,
      $checked = false,
      $menu,
      $label;
  !$item.is('a') && ($item = $item.closest('a'));
  $menu = $item.closest('.dropdown-menu');
  $label = $menu.parent().find('.dropdown-label');
  $labelHolder = $label.text();
  $select = $item.find('input');
  $checked = $select.is(':checked');
  if ($select.is(':disabled')) return;
  if ($select.attr('type') == 'radio' && $checked) return;
  if ($select.attr('type') == 'radio') $menu.find('li').removeClass('active');
  $item.parent().removeClass('active');
  !$checked && $item.parent().addClass('active');
  $select.prop('checked', !$select.prop('checked'));

  $items = $menu.find('li > a > input:checked');
  if ($items.length) {
    $text = [];
    $items.each(function () {
      var $str = $(this).parent().text();
      $str && $text.push($.trim($str));
    });

    $text = $text.length < 4 ? $text.join(', ') : $text.length + ' selected';
    $label.html($text);
  } else {
    $label.html($label.data('placeholder'));
  }
};
$(document).on('click.dropdown-menu', '.dropdown-select > li > a', $.fn.dropdown.Constructor.prototype.change);

// collapse nav
$(document).on('click', '.nav-primary a', function (e) {
  var $this = $(e.target),
      $active;
  $this.is('a') || ($this = $this.closest('a'));
  if ($('.nav-vertical').length) {
    return;
  }

  $active = $this.parent().siblings('.active');
  $active && $active.find('> a').toggleClass('active') && $active.toggleClass('active').find('> ul:visible').slideUp(200);

  $this.hasClass('active') && $this.next().slideUp(200) || $this.next().slideDown(200);
  $this.toggleClass('active').parent().toggleClass('active');

  $this.next().is('ul') && e.preventDefault();

  setTimeout(function () {
    $(document).trigger('updateNav');
  }, 300);
});

// dropdown still
$(document).on('click.bs.dropdown.data-api', '.dropdown .on, .dropup .on', function (e) {
  e.stopPropagation();
});
/**!
 * Sortable
 * @author	RubaXa   <trash@rubaxa.org>
 * @license MIT
 */

"use strict";

(function (factory) {
	"use strict";

	if (typeof define === "function" && define.amd) {
		define(factory);
	} else if (typeof module != "undefined" && typeof module.exports != "undefined") {
		module.exports = factory();
	} else if (typeof Package !== "undefined") {
		Sortable = factory(); // export for Meteor.js
	} else {
		/* jshint sub:true */
		window.Sortable = factory();
	}
})(function () {
	"use strict";

	var dragEl,
	    ghostEl,
	    cloneEl,
	    rootEl,
	    nextEl,
	    scrollEl,
	    scrollParentEl,
	    lastEl,
	    lastCSS,
	    oldIndex,
	    newIndex,
	    activeGroup,
	    autoScroll = {},
	    tapEvt,
	    touchEvt,
	    expando = "Sortable" + new Date().getTime(),
	    win = window,
	    document = win.document,
	    parseInt = win.parseInt,
	    supportDraggable = !!("draggable" in document.createElement("div")),
	    _silent = false,
	    _dispatchEvent = function _dispatchEvent(rootEl, name, targetEl, fromEl, startIndex, newIndex) {
		var evt = document.createEvent("Event");

		evt.initEvent(name, true, true);

		evt.item = targetEl || rootEl;
		evt.from = fromEl || rootEl;
		evt.clone = cloneEl;

		evt.oldIndex = startIndex;
		evt.newIndex = newIndex;

		rootEl.dispatchEvent(evt);
	},
	    _customEvents = "onAdd onUpdate onRemove onStart onEnd onFilter onSort".split(" "),
	    noop = function noop() {},
	    abs = Math.abs,
	    slice = [].slice,
	    touchDragOverListeners = [],
	    _autoScroll = _throttle(function ( /**Event*/evt, /**Object*/options, /**HTMLElement*/rootEl) {
		// Bug: https://bugzilla.mozilla.org/show_bug.cgi?id=505521
		if (rootEl && options.scroll) {
			var el,
			    rect,
			    sens = options.scrollSensitivity,
			    speed = options.scrollSpeed,
			    x = evt.clientX,
			    y = evt.clientY,
			    winWidth = window.innerWidth,
			    winHeight = window.innerHeight,
			    vx,
			    vy;

			// Delect scrollEl
			if (scrollParentEl !== rootEl) {
				scrollEl = options.scroll;
				scrollParentEl = rootEl;

				if (scrollEl === true) {
					scrollEl = rootEl;

					do {
						if (scrollEl.offsetWidth < scrollEl.scrollWidth || scrollEl.offsetHeight < scrollEl.scrollHeight) {
							break;
						}
						/* jshint boss:true */
					} while (scrollEl = scrollEl.parentNode);
				}
			}

			if (scrollEl) {
				el = scrollEl;
				rect = scrollEl.getBoundingClientRect();
				vx = (abs(rect.right - x) <= sens) - (abs(rect.left - x) <= sens);
				vy = (abs(rect.bottom - y) <= sens) - (abs(rect.top - y) <= sens);
			}

			if (!(vx || vy)) {
				vx = (winWidth - x <= sens) - (x <= sens);
				vy = (winHeight - y <= sens) - (y <= sens);

				/* jshint expr:true */
				(vx || vy) && (el = win);
			}

			if (autoScroll.vx !== vx || autoScroll.vy !== vy || autoScroll.el !== el) {
				autoScroll.el = el;
				autoScroll.vx = vx;
				autoScroll.vy = vy;

				clearInterval(autoScroll.pid);

				if (el) {
					autoScroll.pid = setInterval(function () {
						if (el === win) {
							win.scrollTo(win.scrollX + vx * speed, win.scrollY + vy * speed);
						} else {
							vy && (el.scrollTop += vy * speed);
							vx && (el.scrollLeft += vx * speed);
						}
					}, 24);
				}
			}
		}
	}, 30);

	/**
  * @class  Sortable
  * @param  {HTMLElement}  el
  * @param  {Object}       [options]
  */
	function Sortable(el, options) {
		this.el = el; // root element
		this.options = options = options || {};

		// Default options
		var defaults = {
			group: Math.random(),
			sort: true,
			disabled: false,
			store: null,
			handle: null,
			scroll: true,
			scrollSensitivity: 30,
			scrollSpeed: 10,
			draggable: /[uo]l/i.test(el.nodeName) ? "li" : ">*",
			ghostClass: "sortable-ghost",
			ignore: "a, img",
			filter: null,
			animation: 0,
			setData: function setData(dataTransfer, dragEl) {
				dataTransfer.setData("Text", dragEl.textContent);
			},
			dropBubble: false,
			dragoverBubble: false
		};

		// Set default options
		for (var name in defaults) {
			!(name in options) && (options[name] = defaults[name]);
		}

		var group = options.group;

		if (!group || typeof group != "object") {
			group = options.group = { name: group };
		}

		["pull", "put"].forEach(function (key) {
			if (!(key in group)) {
				group[key] = true;
			}
		});

		// Define events
		_customEvents.forEach(function (name) {
			options[name] = _bind(this, options[name] || noop);
			_on(el, name.substr(2).toLowerCase(), options[name]);
		}, this);

		// Export options
		options.groups = " " + group.name + (group.put.join ? " " + group.put.join(" ") : "") + " ";
		el[expando] = options;

		// Bind all private methods
		for (var fn in this) {
			if (fn.charAt(0) === "_") {
				this[fn] = _bind(this, this[fn]);
			}
		}

		// Bind events
		_on(el, "mousedown", this._onTapStart);
		_on(el, "touchstart", this._onTapStart);

		_on(el, "dragover", this);
		_on(el, "dragenter", this);

		touchDragOverListeners.push(this._onDragOver);

		// Restore sorting
		options.store && this.sort(options.store.get(this));
	}

	Sortable.prototype = /** @lends Sortable.prototype */{
		constructor: Sortable,

		_dragStarted: function _dragStarted() {
			if (rootEl && dragEl) {
				// Apply effect
				_toggleClass(dragEl, this.options.ghostClass, true);

				Sortable.active = this;

				// Drag start event
				_dispatchEvent(rootEl, "start", dragEl, rootEl, oldIndex);
			}
		},

		_onTapStart: function _onTapStart( /**Event|TouchEvent*/evt) {
			var type = evt.type,
			    touch = evt.touches && evt.touches[0],
			    target = (touch || evt).target,
			    originalTarget = target,
			    options = this.options,
			    el = this.el,
			    filter = options.filter;

			if (type === "mousedown" && evt.button !== 0 || options.disabled) {
				return; // only left button or enabled
			}

			target = _closest(target, options.draggable, el);

			if (!target) {
				return;
			}

			// get the index of the dragged element within its parent
			oldIndex = _index(target);

			// Check filter
			if (typeof filter === "function") {
				if (filter.call(this, evt, target, this)) {
					_dispatchEvent(originalTarget, "filter", target, el, oldIndex);
					evt.preventDefault();
					return; // cancel dnd
				}
			} else if (filter) {
				filter = filter.split(",").some(function (criteria) {
					criteria = _closest(originalTarget, criteria.trim(), el);

					if (criteria) {
						_dispatchEvent(criteria, "filter", target, el, oldIndex);
						return true;
					}
				});

				if (filter) {
					evt.preventDefault();
					return; // cancel dnd
				}
			}

			if (options.handle && !_closest(originalTarget, options.handle, el)) {
				return;
			}

			// Prepare `dragstart`
			if (target && !dragEl && target.parentNode === el) {
				tapEvt = evt;

				rootEl = this.el;
				dragEl = target;
				nextEl = dragEl.nextSibling;
				activeGroup = this.options.group;

				dragEl.draggable = true;

				// Disable "draggable"
				options.ignore.split(",").forEach(function (criteria) {
					_find(target, criteria.trim(), _disableDraggable);
				});

				if (touch) {
					// Touch device support
					tapEvt = {
						target: target,
						clientX: touch.clientX,
						clientY: touch.clientY
					};

					this._onDragStart(tapEvt, "touch");
					evt.preventDefault();
				}

				_on(document, "mouseup", this._onDrop);
				_on(document, "touchend", this._onDrop);
				_on(document, "touchcancel", this._onDrop);

				_on(dragEl, "dragend", this);
				_on(rootEl, "dragstart", this._onDragStart);

				if (!supportDraggable) {
					this._onDragStart(tapEvt, true);
				}

				try {
					if (document.selection) {
						document.selection.empty();
					} else {
						window.getSelection().removeAllRanges();
					}
				} catch (err) {}
			}
		},

		_emulateDragOver: function _emulateDragOver() {
			if (touchEvt) {
				_css(ghostEl, "display", "none");

				var target = document.elementFromPoint(touchEvt.clientX, touchEvt.clientY),
				    parent = target,
				    groupName = " " + this.options.group.name + "",
				    i = touchDragOverListeners.length;

				if (parent) {
					do {
						if (parent[expando] && parent[expando].groups.indexOf(groupName) > -1) {
							while (i--) {
								touchDragOverListeners[i]({
									clientX: touchEvt.clientX,
									clientY: touchEvt.clientY,
									target: target,
									rootEl: parent
								});
							}

							break;
						}

						target = parent; // store last element
					}
					/* jshint boss:true */
					while (parent = parent.parentNode);
				}

				_css(ghostEl, "display", "");
			}
		},

		_onTouchMove: function _onTouchMove( /**TouchEvent*/evt) {
			if (tapEvt) {
				var touch = evt.touches ? evt.touches[0] : evt,
				    dx = touch.clientX - tapEvt.clientX,
				    dy = touch.clientY - tapEvt.clientY,
				    translate3d = evt.touches ? "translate3d(" + dx + "px," + dy + "px,0)" : "translate(" + dx + "px," + dy + "px)";

				touchEvt = touch;

				_css(ghostEl, "webkitTransform", translate3d);
				_css(ghostEl, "mozTransform", translate3d);
				_css(ghostEl, "msTransform", translate3d);
				_css(ghostEl, "transform", translate3d);

				evt.preventDefault();
			}
		},

		_onDragStart: function _onDragStart( /**Event*/evt, /**boolean*/useFallback) {
			var dataTransfer = evt.dataTransfer,
			    options = this.options;

			this._offUpEvents();

			if (activeGroup.pull == "clone") {
				cloneEl = dragEl.cloneNode(true);
				_css(cloneEl, "display", "none");
				rootEl.insertBefore(cloneEl, dragEl);
			}

			if (useFallback) {
				var rect = dragEl.getBoundingClientRect(),
				    css = _css(dragEl),
				    ghostRect;

				ghostEl = dragEl.cloneNode(true);

				_css(ghostEl, "top", rect.top - parseInt(css.marginTop, 10));
				_css(ghostEl, "left", rect.left - parseInt(css.marginLeft, 10));
				_css(ghostEl, "width", rect.width);
				_css(ghostEl, "height", rect.height);
				_css(ghostEl, "opacity", "0.8");
				_css(ghostEl, "position", "fixed");
				_css(ghostEl, "zIndex", "100000");

				rootEl.appendChild(ghostEl);

				// Fixing dimensions.
				ghostRect = ghostEl.getBoundingClientRect();
				_css(ghostEl, "width", rect.width * 2 - ghostRect.width);
				_css(ghostEl, "height", rect.height * 2 - ghostRect.height);

				if (useFallback === "touch") {
					// Bind touch events
					_on(document, "touchmove", this._onTouchMove);
					_on(document, "touchend", this._onDrop);
					_on(document, "touchcancel", this._onDrop);
				} else {
					// Old brwoser
					_on(document, "mousemove", this._onTouchMove);
					_on(document, "mouseup", this._onDrop);
				}

				this._loopId = setInterval(this._emulateDragOver, 150);
			} else {
				if (dataTransfer) {
					dataTransfer.effectAllowed = "move";
					options.setData && options.setData.call(this, dataTransfer, dragEl);
				}

				_on(document, "drop", this);
			}

			setTimeout(this._dragStarted, 0);
		},

		_onDragOver: function _onDragOver( /**Event*/evt) {
			var el = this.el,
			    target,
			    dragRect,
			    revert,
			    options = this.options,
			    group = options.group,
			    groupPut = group.put,
			    isOwner = activeGroup === group,
			    canSort = options.sort;

			if (!dragEl) {
				return;
			}

			if (evt.preventDefault !== void 0) {
				evt.preventDefault();
				!options.dragoverBubble && evt.stopPropagation();
			}

			if (activeGroup && !options.disabled && (isOwner ? canSort || (revert = !rootEl.contains(dragEl)) : activeGroup.pull && groupPut && (activeGroup.name === group.name || groupPut.indexOf && ~groupPut.indexOf(activeGroup.name)) // by Array
			) && (evt.rootEl === void 0 || evt.rootEl === this.el)) {
				// Smart auto-scrolling
				_autoScroll(evt, options, this.el);

				if (_silent) {
					return;
				}

				target = _closest(evt.target, options.draggable, el);
				dragRect = dragEl.getBoundingClientRect();

				if (revert) {
					_cloneHide(true);

					if (cloneEl || nextEl) {
						rootEl.insertBefore(dragEl, cloneEl || nextEl);
					} else if (!canSort) {
						rootEl.appendChild(dragEl);
					}

					return;
				}

				if (el.children.length === 0 || el.children[0] === ghostEl || el === evt.target && (target = _ghostInBottom(el, evt))) {
					if (target) {
						if (target.animated) {
							return;
						}
						targetRect = target.getBoundingClientRect();
					}

					_cloneHide(isOwner);

					el.appendChild(dragEl);
					this._animate(dragRect, dragEl);
					target && this._animate(targetRect, target);
				} else if (target && !target.animated && target !== dragEl && target.parentNode[expando] !== void 0) {
					if (lastEl !== target) {
						lastEl = target;
						lastCSS = _css(target);
					}

					var targetRect = target.getBoundingClientRect(),
					    width = targetRect.right - targetRect.left,
					    height = targetRect.bottom - targetRect.top,
					    floating = /left|right|inline/.test(lastCSS.cssFloat + lastCSS.display),
					    isWide = target.offsetWidth > dragEl.offsetWidth,
					    isLong = target.offsetHeight > dragEl.offsetHeight,
					    halfway = (floating ? (evt.clientX - targetRect.left) / width : (evt.clientY - targetRect.top) / height) > 0.5,
					    nextSibling = target.nextElementSibling,
					    after;

					_silent = true;
					setTimeout(_unsilent, 30);

					_cloneHide(isOwner);

					if (floating) {
						after = target.previousElementSibling === dragEl && !isWide || halfway && isWide;
					} else {
						after = nextSibling !== dragEl && !isLong || halfway && isLong;
					}

					if (after && !nextSibling) {
						el.appendChild(dragEl);
					} else {
						target.parentNode.insertBefore(dragEl, after ? nextSibling : target);
					}

					this._animate(dragRect, dragEl);
					this._animate(targetRect, target);
				}
			}
		},

		_animate: function _animate(prevRect, target) {
			var ms = this.options.animation;

			if (ms) {
				var currentRect = target.getBoundingClientRect();

				_css(target, "transition", "none");
				_css(target, "transform", "translate3d(" + (prevRect.left - currentRect.left) + "px," + (prevRect.top - currentRect.top) + "px,0)");

				target.offsetWidth; // repaint

				_css(target, "transition", "all " + ms + "ms");
				_css(target, "transform", "translate3d(0,0,0)");

				clearTimeout(target.animated);
				target.animated = setTimeout(function () {
					_css(target, "transition", "");
					_css(target, "transform", "");
					target.animated = false;
				}, ms);
			}
		},

		_offUpEvents: function _offUpEvents() {
			_off(document, "mouseup", this._onDrop);
			_off(document, "touchmove", this._onTouchMove);
			_off(document, "touchend", this._onDrop);
			_off(document, "touchcancel", this._onDrop);
		},

		_onDrop: function _onDrop( /**Event*/evt) {
			var el = this.el,
			    options = this.options;

			clearInterval(this._loopId);
			clearInterval(autoScroll.pid);

			// Unbind events
			_off(document, "drop", this);
			_off(document, "mousemove", this._onTouchMove);
			_off(el, "dragstart", this._onDragStart);

			this._offUpEvents();

			if (evt) {
				evt.preventDefault();
				!options.dropBubble && evt.stopPropagation();

				ghostEl && ghostEl.parentNode.removeChild(ghostEl);

				if (dragEl) {
					_off(dragEl, "dragend", this);

					_disableDraggable(dragEl);
					_toggleClass(dragEl, this.options.ghostClass, false);

					if (rootEl !== dragEl.parentNode) {
						newIndex = _index(dragEl);

						// drag from one list and drop into another
						_dispatchEvent(dragEl.parentNode, "sort", dragEl, rootEl, oldIndex, newIndex);
						_dispatchEvent(rootEl, "sort", dragEl, rootEl, oldIndex, newIndex);

						// Add event
						_dispatchEvent(dragEl, "add", dragEl, rootEl, oldIndex, newIndex);

						// Remove event
						_dispatchEvent(rootEl, "remove", dragEl, rootEl, oldIndex, newIndex);
					} else {
						// Remove clone
						cloneEl && cloneEl.parentNode.removeChild(cloneEl);

						if (dragEl.nextSibling !== nextEl) {
							// Get the index of the dragged element within its parent
							newIndex = _index(dragEl);

							// drag & drop within the same list
							_dispatchEvent(rootEl, "update", dragEl, rootEl, oldIndex, newIndex);
							_dispatchEvent(rootEl, "sort", dragEl, rootEl, oldIndex, newIndex);
						}
					}

					// Drag end event
					Sortable.active && _dispatchEvent(rootEl, "end", dragEl, rootEl, oldIndex, newIndex);
				}

				// Nulling
				rootEl = dragEl = ghostEl = nextEl = cloneEl = scrollEl = scrollParentEl = tapEvt = touchEvt = lastEl = lastCSS = activeGroup = Sortable.active = null;

				// Save sorting
				this.save();
			}
		},

		handleEvent: function handleEvent( /**Event*/evt) {
			var type = evt.type;

			if (type === "dragover" || type === "dragenter") {
				this._onDragOver(evt);
				_globalDragOver(evt);
			} else if (type === "drop" || type === "dragend") {
				this._onDrop(evt);
			}
		},

		/**
   * Serializes the item into an array of string.
   * @returns {String[]}
   */
		toArray: function toArray() {
			var order = [],
			    el,
			    children = this.el.children,
			    i = 0,
			    n = children.length;

			for (; i < n; i++) {
				el = children[i];
				if (_closest(el, this.options.draggable, this.el)) {
					order.push(el.getAttribute("data-id") || _generateId(el));
				}
			}

			return order;
		},

		/**
   * Sorts the elements according to the array.
   * @param  {String[]}  order  order of the items
   */
		sort: function sort(order) {
			var items = {},
			    rootEl = this.el;

			this.toArray().forEach(function (id, i) {
				var el = rootEl.children[i];

				if (_closest(el, this.options.draggable, rootEl)) {
					items[id] = el;
				}
			}, this);

			order.forEach(function (id) {
				if (items[id]) {
					rootEl.removeChild(items[id]);
					rootEl.appendChild(items[id]);
				}
			});
		},

		/**
   * Save the current sorting
   */
		save: function save() {
			var store = this.options.store;
			store && store.set(this);
		},

		/**
   * For each element in the set, get the first element that matches the selector by testing the element itself and traversing up through its ancestors in the DOM tree.
   * @param   {HTMLElement}  el
   * @param   {String}       [selector]  default: `options.draggable`
   * @returns {HTMLElement|null}
   */
		closest: function closest(el, selector) {
			return _closest(el, selector || this.options.draggable, this.el);
		},

		/**
   * Set/get option
   * @param   {string} name
   * @param   {*}      [value]
   * @returns {*}
   */
		option: function option(name, value) {
			var options = this.options;

			if (value === void 0) {
				return options[name];
			} else {
				options[name] = value;
			}
		},

		/**
   * Destroy
   */
		destroy: function destroy() {
			var el = this.el,
			    options = this.options;

			_customEvents.forEach(function (name) {
				_off(el, name.substr(2).toLowerCase(), options[name]);
			});

			_off(el, "mousedown", this._onTapStart);
			_off(el, "touchstart", this._onTapStart);

			_off(el, "dragover", this);
			_off(el, "dragenter", this);

			//remove draggable attributes
			Array.prototype.forEach.call(el.querySelectorAll("[draggable]"), function (el) {
				el.removeAttribute("draggable");
			});

			touchDragOverListeners.splice(touchDragOverListeners.indexOf(this._onDragOver), 1);

			this._onDrop();

			this.el = null;
		}
	};

	function _cloneHide(state) {
		if (cloneEl && cloneEl.state !== state) {
			_css(cloneEl, "display", state ? "none" : "");
			!state && cloneEl.state && rootEl.insertBefore(cloneEl, dragEl);
			cloneEl.state = state;
		}
	}

	function _bind(ctx, fn) {
		var args = slice.call(arguments, 2);
		return fn.bind ? fn.bind.apply(fn, [ctx].concat(args)) : function () {
			return fn.apply(ctx, args.concat(slice.call(arguments)));
		};
	}

	function _closest( /**HTMLElement*/el, /**String*/selector, /**HTMLElement*/ctx) {
		if (el) {
			ctx = ctx || document;
			selector = selector.split(".");

			var tag = selector.shift().toUpperCase(),
			    re = new RegExp("\\s(" + selector.join("|") + ")\\s", "g");

			do {
				if (tag === ">*" && el.parentNode === ctx || (tag === "" || el.nodeName.toUpperCase() == tag) && (!selector.length || ((" " + el.className + " ").match(re) || []).length == selector.length)) {
					return el;
				}
			} while (el !== ctx && (el = el.parentNode));
		}

		return null;
	}

	function _globalDragOver( /**Event*/evt) {
		evt.dataTransfer.dropEffect = "move";
		evt.preventDefault();
	}

	function _on(el, event, fn) {
		el.addEventListener(event, fn, false);
	}

	function _off(el, event, fn) {
		el.removeEventListener(event, fn, false);
	}

	function _toggleClass(el, name, state) {
		if (el) {
			if (el.classList) {
				el.classList[state ? "add" : "remove"](name);
			} else {
				var className = (" " + el.className + " ").replace(/\s+/g, " ").replace(" " + name + " ", "");
				el.className = className + (state ? " " + name : "");
			}
		}
	}

	function _css(el, prop, val) {
		var style = el && el.style;

		if (style) {
			if (val === void 0) {
				if (document.defaultView && document.defaultView.getComputedStyle) {
					val = document.defaultView.getComputedStyle(el, "");
				} else if (el.currentStyle) {
					val = el.currentStyle;
				}

				return prop === void 0 ? val : val[prop];
			} else {
				if (!(prop in style)) {
					prop = "-webkit-" + prop;
				}

				style[prop] = val + (typeof val === "string" ? "" : "px");
			}
		}
	}

	function _find(ctx, tagName, iterator) {
		if (ctx) {
			var list = ctx.getElementsByTagName(tagName),
			    i = 0,
			    n = list.length;

			if (iterator) {
				for (; i < n; i++) {
					iterator(list[i], i);
				}
			}

			return list;
		}

		return [];
	}

	function _disableDraggable(el) {
		el.draggable = false;
	}

	function _unsilent() {
		_silent = false;
	}

	/** @returns {HTMLElement|false} */
	function _ghostInBottom(el, evt) {
		var lastEl = el.lastElementChild,
		    rect = lastEl.getBoundingClientRect();
		return evt.clientY - (rect.top + rect.height) > 5 && lastEl; // min delta
	}

	/**
  * Generate id
  * @param   {HTMLElement} el
  * @returns {String}
  * @private
  */
	function _generateId(el) {
		var str = el.tagName + el.className + el.src + el.href + el.textContent,
		    i = str.length,
		    sum = 0;

		while (i--) {
			sum += str.charCodeAt(i);
		}

		return sum.toString(36);
	}

	/**
  * Returns the index of an element within its parent
  * @param el
  * @returns {number}
  * @private
  */
	function _index( /**HTMLElement*/el) {
		var index = 0;
		while (el && (el = el.previousElementSibling)) {
			if (el.nodeName.toUpperCase() !== "TEMPLATE") {
				index++;
			}
		}
		return index;
	}

	function _throttle(callback, ms) {
		var args, _this;

		return function () {
			if (args === void 0) {
				args = arguments;
				_this = this;

				setTimeout(function () {
					if (args.length === 1) {
						callback.call(_this, args[0]);
					} else {
						callback.apply(_this, args);
					}

					args = void 0;
				}, ms);
			}
		};
	}

	// Export utils
	Sortable.utils = {
		on: _on,
		off: _off,
		css: _css,
		find: _find,
		bind: _bind,
		is: function is(el, selector) {
			return !!_closest(el, selector, el);
		},
		throttle: _throttle,
		closest: _closest,
		toggleClass: _toggleClass,
		dispatchEvent: _dispatchEvent,
		index: _index
	};

	Sortable.version = "1.1.1";

	/**
  * Create sortable instance
  * @param {HTMLElement}  el
  * @param {Object}      [options]
  */
	Sortable.create = function (el, options) {
		return new Sortable(el, options);
	};

	// Export
	return Sortable;
});
// by Name
"use strict";

!(function (e) {
  if ("object" == typeof exports && "undefined" != typeof module) module.exports = e();else if ("function" == typeof define && define.amd) define([], e);else {
    var f;"undefined" != typeof window ? f = window : "undefined" != typeof global ? f = global : "undefined" != typeof self && (f = self), f.Slideout = e();
  }
})(function () {
  var define, module, exports;return (function e(t, n, r) {
    function s(o, u) {
      if (!n[o]) {
        if (!t[o]) {
          var a = typeof require == "function" && require;if (!u && a) {
            return a(o, !0);
          }if (i) {
            return i(o, !0);
          }var f = new Error("Cannot find module '" + o + "'");throw (f.code = "MODULE_NOT_FOUND", f);
        }var l = n[o] = { exports: {} };t[o][0].call(l.exports, function (e) {
          var n = t[o][1][e];return s(n ? n : e);
        }, l, l.exports, e, t, n, r);
      }return n[o].exports;
    }var i = typeof require == "function" && require;for (var o = 0; o < r.length; o++) s(r[o]);return s;
  })({ 1: [function (require, module, exports) {
      "use strict";

      /**
       * Module dependencies
       */
      var decouple = require("decouple");

      /**
       * Privates
       */
      var scrollTimeout;
      var scrolling = false;
      var doc = window.document;
      var html = doc.documentElement;
      var msPointerSupported = window.navigator.msPointerEnabled;
      var touch = {
        start: msPointerSupported ? "MSPointerDown" : "touchstart",
        move: msPointerSupported ? "MSPointerMove" : "touchmove",
        end: msPointerSupported ? "MSPointerUp" : "touchend"
      };
      var prefix = (function prefix() {
        var regex = /^(Webkit|Khtml|Moz|ms|O)(?=[A-Z])/;
        var styleDeclaration = doc.getElementsByTagName("script")[0].style;
        for (var prop in styleDeclaration) {
          if (regex.test(prop)) {
            return "-" + prop.match(regex)[0].toLowerCase() + "-";
          }
        }
        // Nothing found so far? Webkit does not enumerate over the CSS properties of the style object.
        // However (prop in style) returns the correct value, so we'll have to test for
        // the precence of a specific property
        if ("WebkitOpacity" in styleDeclaration) {
          return "-webkit-";
        }
        if ("KhtmlOpacity" in styleDeclaration) {
          return "-khtml-";
        }
        return "";
      })();

      /**
       * Slideout constructor
       */
      function Slideout(options) {
        options = options || {};

        // Sets default values
        this._startOffsetX = 0;
        this._currentOffsetX = 0;
        this._opening = false;
        this._moved = false;
        this._opened = false;
        this._preventOpen = false;

        // Sets panel
        this.panel = options.panel;
        this.menu = options.menu;

        // Sets  classnames
        this.panel.className += " slideout-panel";
        this.menu.className += " slideout-menu";

        // Sets options
        this._fx = options.fx || "ease";
        this._duration = parseInt(options.duration, 10) || 300;
        this._tolerance = parseInt(options.tolerance, 10) || 70;
        this._padding = parseInt(options.padding, 10) || 256;

        // Init touch events
        this._initTouchEvents();
      }

      /**
       * Opens the slideout menu.
       */
      Slideout.prototype.open = function () {
        var self = this;
        if (html.className.search("slideout-open") === -1) {
          html.className += " slideout-open";
        }
        this._setTransition();
        this._translateXTo(this._padding);
        this._opened = true;
        setTimeout(function () {
          self.panel.style.transition = self.panel.style["-webkit-transition"] = "";
        }, this._duration + 50);
        return this;
      };

      /**
       * Closes slideout menu.
       */
      Slideout.prototype.close = function () {
        var self = this;
        if (!this.isOpen() && !this._opening) {
          return this;
        }
        this._setTransition();
        this._translateXTo(0);
        this._opened = false;
        setTimeout(function () {
          html.className = html.className.replace(/ slideout-open/, "");
          self.panel.style.transition = self.panel.style["-webkit-transition"] = "";
        }, this._duration + 50);
        return this;
      };

      /**
       * Toggles (open/close) slideout menu.
       */
      Slideout.prototype.toggle = function () {
        return this.isOpen() ? this.close() : this.open();
      };

      /**
       * Returns true if the slideout is currently open, and false if it is closed.
       */
      Slideout.prototype.isOpen = function () {
        return this._opened;
      };

      /**
       * Translates panel and updates currentOffset with a given X point
       */
      Slideout.prototype._translateXTo = function (translateX) {
        this._currentOffsetX = translateX;
        this.panel.style[prefix + "transform"] = this.panel.style.transform = "translate3d(" + translateX + "px, 0, 0)";
      };

      /**
       * Set transition properties
       */
      Slideout.prototype._setTransition = function () {
        this.panel.style[prefix + "transition"] = this.panel.style.transition = prefix + "transform " + this._duration + "ms " + this._fx;
      };

      /**
       * Initializes touch event
       */
      Slideout.prototype._initTouchEvents = function () {
        var self = this;

        /**
         * Decouple scroll event
         */
        decouple(doc, "scroll", function () {
          if (!self._moved) {
            clearTimeout(scrollTimeout);
            scrolling = true;
            scrollTimeout = setTimeout(function () {
              scrolling = false;
            }, 250);
          }
        });

        /**
         * Prevents touchmove event if slideout is moving
         */
        doc.addEventListener(touch.move, function (eve) {
          if (self._moved) {
            eve.preventDefault();
          }
        });

        /**
         * Resets values on touchstart
         */
        this.panel.addEventListener(touch.start, function (eve) {
          self._moved = false;
          self._opening = false;
          self._startOffsetX = eve.touches[0].pageX;
          self._preventOpen = !self.isOpen() && self.menu.clientWidth !== 0;
        });

        /**
         * Resets values on touchcancel
         */
        this.panel.addEventListener("touchcancel", function () {
          self._moved = false;
          self._opening = false;
        });

        /**
         * Toggles slideout on touchend
         */
        this.panel.addEventListener(touch.end, function () {
          if (self._moved) {
            self._opening && Math.abs(self._currentOffsetX) > self._tolerance ? self.open() : self.close();
          }
          self._moved = false;
        });

        /**
         * Translates panel on touchmove
         */
        this.panel.addEventListener(touch.move, function (eve) {

          if (scrolling || self._preventOpen) {
            return;
          }

          var dif_x = eve.touches[0].clientX - self._startOffsetX;
          var translateX = self._currentOffsetX = dif_x;

          if (Math.abs(translateX) > self._padding) {
            return;
          }

          if (Math.abs(dif_x) > 20) {
            self._opening = true;

            if (self._opened && dif_x > 0 || !self._opened && dif_x < 0) {
              return;
            }

            if (!self._moved && html.className.search("slideout-open") === -1) {
              html.className += " slideout-open";
            }

            if (dif_x <= 0) {
              translateX = dif_x + self._padding;
              self._opening = false;
            }

            self.panel.style[prefix + "transform"] = self.panel.style.transform = "translate3d(" + translateX + "px, 0, 0)";

            self._moved = true;
          }
        });
      };

      /**
       * Expose Slideout
       */
      module.exports = Slideout;
    }, { decouple: 2 }], 2: [function (require, module, exports) {
      "use strict";

      var requestAnimFrame = (function () {
        return window.requestAnimationFrame || window.webkitRequestAnimationFrame || function (callback) {
          window.setTimeout(callback, 1000 / 60);
        };
      })();

      function decouple(node, event, fn) {
        var eve,
            tracking = false;

        function captureEvent(e) {
          eve = e;
          track();
        }

        function track() {
          if (!tracking) {
            requestAnimFrame(update);
            tracking = true;
          }
        }

        function update() {
          fn.call(node, eve);
          tracking = false;
        }

        node.addEventListener(event, captureEvent, false);
      }

      /**
       * Expose decouple
       */
      module.exports = decouple;
    }, {}] }, {}, [1])(1);
});
//
//  Grid Forms
//  Copyright (c) 2013 Kumail Hunaid
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

'use strict';

$(function () {
    var GridForms = {
        el: {
            fieldsRows: $('[data-row-span]'),
            fieldsContainers: $('[data-field-span]:not(.no-height)'),
            focusableFields: $('input, textarea, select', '[data-field-span]'),
            window: $(window)
        },
        init: function init() {
            this.focusField(this.el.focusableFields.filter(':focus'));
            this.equalizeFieldHeights();
            this.events();
        },
        focusField: function focusField(currentField) {
            currentField.closest('[data-field-span]').addClass('focus');
        },
        removeFieldFocus: function removeFieldFocus() {
            this.el.fieldsContainers.removeClass('focus');
        },
        events: function events() {
            var that = this;
            // that.el.fieldsContainers.click(function() {
            //     $(this).find('input[type="text"], textarea, select').focus();
            // });
            // that.el.focusableFields.focus(function() {
            //     that.focusField($(this));
            // });
            // that.el.focusableFields.blur(function() {
            //     that.removeFieldFocus();
            // });
            that.el.window.resize(function () {
                that.equalizeFieldHeights();
            });
        },
        equalizeFieldHeights: function equalizeFieldHeights() {
            this.el.fieldsContainers.css('height', 'auto');

            var fieldsRows = this.el.fieldsRows;
            var fieldsContainers = this.el.fieldsContainers;

            // Make sure that the fields aren't stacked
            if (!this.areFieldsStacked()) {
                fieldsRows.each(function () {
                    // Get the height of the row (thus the tallest element's height)
                    var fieldRow = $(this);
                    var rowHeight = fieldRow.css('height');

                    // Set the height for each field in the row...
                    fieldRow.find(fieldsContainers).css('height', rowHeight);
                });
            }
        },
        areFieldsStacked: function areFieldsStacked() {
            // Get the first row
            // which does not only contain one field
            var firstRow = this.el.fieldsRows.not('[data-row-span="1"]').first();

            // Get to the total width
            // of each field witin the row
            var totalWidth = 0;
            firstRow.children().each(function () {
                totalWidth += $(this).width();
            });

            // Determine whether fields are stacked or not
            return firstRow.width() <= totalWidth;
        }
    };
    GridForms.init();
    window.GridForms = GridForms;
});
/*
 * jQuery slugIt plug-in 1.0
 *
 * Copyright (c) 2010 Diego Kuperman
 *
 * Inspired by perl module Text::Unidecode and Django urlfy.js
 *
 * Licensed under the BSD license:
 *      http://www.opensource.org/licenses/bsd-license.php
 */

'use strict';

jQuery.fn.slugIt = function (options) {
    var defaults = {
        events: 'keypress keyup',
        output: '#slug',
        separator: '-',
        map: false,
        before: false,
        after: false
    };

    var opts = jQuery.extend(defaults, options);

    var chars = latin_map();
    chars = jQuery.extend(chars, greek_map());
    chars = jQuery.extend(chars, turkish_map());
    chars = jQuery.extend(chars, russian_map());
    chars = jQuery.extend(chars, ukranian_map());
    chars = jQuery.extend(chars, czech_map());
    chars = jQuery.extend(chars, latvian_map());
    chars = jQuery.extend(chars, polish_map());
    chars = jQuery.extend(chars, symbols_map());
    chars = jQuery.extend(chars, currency_map());

    if (opts.map) {
        chars = jQuery.extend(chars, opts.map);
    }

    jQuery(this).bind(defaults.events, function () {
        var text = jQuery(this).val();

        if (opts.before) text = opts.before(text);
        text = jQuery.trim(text.toString());

        var slug = new String();
        for (var i = 0; i < text.length; i++) {
            if (chars[text.charAt(i)]) {
                slug += chars[text.charAt(i)];
            } else {
                slug += text.charAt(i);
            }
        }

        // Ensure separator is composable into regexes
        var sep_esc = opts.separator.replace(/([.*+?^=!:${}()|\[\]\/\\])/g, '\\$1');
        var re_trail = new RegExp('^' + sep_esc + '+|' + sep_esc + '+$', 'g');
        var re_multi = new RegExp(sep_esc + '+', 'g');

        slug = slug.replace(/[^-\w\d\$\*\(\)\'\!\_]/g, opts.separator); // swap spaces and unwanted chars
        slug = slug.replace(re_trail, ''); // trim leading/trailing separators
        slug = slug.replace(re_multi, opts.separator); // eliminate repeated separatos
        slug = slug.toLowerCase(); // convert sting to lower case

        if (opts.after) slug = opts.after(slug);

        if (typeof opts.output == 'function') {
            opts.output(slug);
        } else {
            jQuery(opts.output).val(slug); // input or textarea
            jQuery(opts.output).html(slug); // other dom elements
        }

        return this;
    });

    function latin_map() {
        return {
            À: 'A', Á: 'A', Â: 'A', Ã: 'A', Ä: 'A', Å: 'A', Æ: 'AE', Ç: 'C', È: 'E', É: 'E', Ê: 'E', Ë: 'E', Ì: 'I', Í: 'I', Î: 'I',
            Ï: 'I', Ð: 'D', Ñ: 'N', Ò: 'O', Ó: 'O', Ô: 'O', Õ: 'O', Ö: 'O', Ő: 'O', Ø: 'O', Ù: 'U', Ú: 'U', Û: 'U', Ü: 'U', Ű: 'U',
            Ý: 'Y', Þ: 'TH', ß: 'ss', à: 'a', á: 'a', â: 'a', ã: 'a', ä: 'a', å: 'a', æ: 'ae', ç: 'c', è: 'e', é: 'e', ê: 'e', ë: 'e',
            ì: 'i', í: 'i', î: 'i', ï: 'i', ð: 'd', ñ: 'n', ò: 'o', ó: 'o', ô: 'o', õ: 'o', ö: 'o', ő: 'o', ø: 'o', ù: 'u', ú: 'u',
            û: 'u', ü: 'u', ű: 'u', ý: 'y', þ: 'th', ÿ: 'y'
        };
    }

    function greek_map() {
        return {
            α: 'a', β: 'b', γ: 'g', δ: 'd', ε: 'e', ζ: 'z', η: 'h', θ: '8',
            ι: 'i', κ: 'k', λ: 'l', μ: 'm', ν: 'n', ξ: '3', ο: 'o', π: 'p',
            ρ: 'r', σ: 's', τ: 't', υ: 'y', φ: 'f', χ: 'x', ψ: 'ps', ω: 'w',
            ά: 'a', έ: 'e', ί: 'i', ό: 'o', ύ: 'y', ή: 'h', ώ: 'w', ς: 's',
            ϊ: 'i', ΰ: 'y', ϋ: 'y', ΐ: 'i',
            Α: 'A', Β: 'B', Γ: 'G', Δ: 'D', Ε: 'E', Ζ: 'Z', Η: 'H', Θ: '8',
            Ι: 'I', Κ: 'K', Λ: 'L', Μ: 'M', Ν: 'N', Ξ: '3', Ο: 'O', Π: 'P',
            Ρ: 'R', Σ: 'S', Τ: 'T', Υ: 'Y', Φ: 'F', Χ: 'X', Ψ: 'PS', Ω: 'W',
            Ά: 'A', Έ: 'E', Ί: 'I', Ό: 'O', Ύ: 'Y', Ή: 'H', Ώ: 'W', Ϊ: 'I',
            Ϋ: 'Y'
        };
    }

    function turkish_map() {
        return {
            ş: 's', Ş: 'S', ı: 'i', İ: 'I', ç: 'c', Ç: 'C', ü: 'u', Ü: 'U',
            ö: 'o', Ö: 'O', ğ: 'g', Ğ: 'G'
        };
    }

    function russian_map() {
        return {
            а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'yo', ж: 'zh',
            з: 'z', и: 'i', й: 'j', к: 'k', л: 'l', м: 'm', н: 'n', о: 'o',
            п: 'p', р: 'r', с: 's', т: 't', у: 'u', ф: 'f', х: 'h', ц: 'c',
            ч: 'ch', ш: 'sh', щ: 'sh', ъ: '', ы: 'y', ь: '', э: 'e', ю: 'yu',
            я: 'ya',
            А: 'A', Б: 'B', В: 'V', Г: 'G', Д: 'D', Е: 'E', Ё: 'Yo', Ж: 'Zh',
            З: 'Z', И: 'I', Й: 'J', К: 'K', Л: 'L', М: 'M', Н: 'N', О: 'O',
            П: 'P', Р: 'R', С: 'S', Т: 'T', У: 'U', Ф: 'F', Х: 'H', Ц: 'C',
            Ч: 'Ch', Ш: 'Sh', Щ: 'Sh', Ъ: '', Ы: 'Y', Ь: '', Э: 'E', Ю: 'Yu',
            Я: 'Ya'
        };
    }

    function ukranian_map() {
        return {
            Є: 'Ye', І: 'I', Ї: 'Yi', Ґ: 'G', є: 'ye', і: 'i', ї: 'yi', ґ: 'g'
        };
    }

    function czech_map() {
        return {
            č: 'c', ď: 'd', ě: 'e', ň: 'n', ř: 'r', š: 's', ť: 't', ů: 'u',
            ž: 'z', Č: 'C', Ď: 'D', Ě: 'E', Ň: 'N', Ř: 'R', Š: 'S', Ť: 'T',
            Ů: 'U', Ž: 'Z'
        };
    }

    function polish_map() {
        return {
            ą: 'a', ć: 'c', ę: 'e', ł: 'l', ń: 'n', ó: 'o', ś: 's', ź: 'z',
            ż: 'z', Ą: 'A', Ć: 'C', Ę: 'e', Ł: 'L', Ń: 'N', Ó: 'o', Ś: 'S',
            Ź: 'Z', Ż: 'Z'
        };
    }

    function latvian_map() {
        return {
            ā: 'a', č: 'c', ē: 'e', ģ: 'g', ī: 'i', ķ: 'k', ļ: 'l', ņ: 'n',
            š: 's', ū: 'u', ž: 'z', Ā: 'A', Č: 'C', Ē: 'E', Ģ: 'G', Ī: 'i',
            Ķ: 'k', Ļ: 'L', Ņ: 'N', Š: 'S', Ū: 'u', Ž: 'Z'
        };
    }

    function currency_map() {
        return {
            '€': 'euro', $: 'dollar'
        };
    }

    function symbols_map() {
        return {
            '©': '(c)', œ: 'oe', Œ: 'OE', '∑': 'sum', '®': '(r)', '†': '+',
            '“': '"', '”': '"', '‘': '\'', '’': '\'', '∂': 'd', ƒ: 'f', '™': 'tm',
            '℠': 'sm', '…': '...', '˚': 'o', º: 'o', ª: 'a', '•': '*',
            '∆': 'delta', '∞': 'infinity', '♥': 'love', '&': 'and'
        };
    }

    return this;
};
'use strict';

(function () {
  var vexFactory;

  vexFactory = function ($) {
    var animationEndSupport, vex;
    animationEndSupport = false;
    $(function () {
      var s;
      s = (document.body || document.documentElement).style;
      animationEndSupport = s.animation !== void 0 || s.WebkitAnimation !== void 0 || s.MozAnimation !== void 0 || s.MsAnimation !== void 0 || s.OAnimation !== void 0;
      return $(window).bind('keyup.vex', function (event) {
        if (event.keyCode === 27) {
          return vex.closeByEscape();
        }
      });
    });
    return vex = {
      globalID: 1,
      animationEndEvent: 'animationend webkitAnimationEnd mozAnimationEnd MSAnimationEnd oanimationend',
      baseClassNames: {
        vex: 'vex',
        content: 'vex-content',
        overlay: 'vex-overlay',
        close: 'vex-close',
        closing: 'vex-closing',
        open: 'vex-open'
      },
      defaultOptions: {
        content: '',
        showCloseButton: true,
        escapeButtonCloses: true,
        overlayClosesOnClick: true,
        appendLocation: 'body',
        className: '',
        css: {},
        overlayClassName: '',
        overlayCSS: {},
        contentClassName: '',
        contentCSS: {},
        closeClassName: '',
        closeCSS: {}
      },
      open: function open(options) {
        options = $.extend({}, vex.defaultOptions, options);
        options.id = vex.globalID;
        vex.globalID += 1;
        options.$vex = $('<div>').addClass(vex.baseClassNames.vex).addClass(options.className).css(options.css).data({
          vex: options
        });
        options.$vexOverlay = $('<div>').addClass(vex.baseClassNames.overlay).addClass(options.overlayClassName).css(options.overlayCSS).data({
          vex: options
        });
        if (options.overlayClosesOnClick) {
          options.$vexOverlay.bind('click.vex', function (e) {
            if (e.target !== this) {
              return;
            }
            return vex.close($(this).data().vex.id);
          });
        }
        options.$vex.append(options.$vexOverlay);
        options.$vexContent = $('<div>').addClass(vex.baseClassNames.content).addClass(options.contentClassName).css(options.contentCSS).append(options.content).data({
          vex: options
        });
        options.$vex.append(options.$vexContent);
        if (options.showCloseButton) {
          options.$closeButton = $('<div>').addClass(vex.baseClassNames.close).addClass(options.closeClassName).css(options.closeCSS).data({
            vex: options
          }).bind('click.vex', function () {
            return vex.close($(this).data().vex.id);
          });
          options.$vexContent.append(options.$closeButton);
        }
        $(options.appendLocation).append(options.$vex);
        vex.setupBodyClassName(options.$vex);
        if (options.afterOpen) {
          options.afterOpen(options.$vexContent, options);
        }
        setTimeout(function () {
          return options.$vexContent.trigger('vexOpen', options);
        }, 0);
        return options.$vexContent;
      },
      getSelectorFromBaseClass: function getSelectorFromBaseClass(baseClass) {
        return '.' + baseClass.split(' ').join('.');
      },
      getAllVexes: function getAllVexes() {
        return $('.' + vex.baseClassNames.vex + ':not(".' + vex.baseClassNames.closing + '") ' + vex.getSelectorFromBaseClass(vex.baseClassNames.content));
      },
      getVexByID: function getVexByID(id) {
        return vex.getAllVexes().filter(function () {
          return $(this).data().vex.id === id;
        });
      },
      close: function close(id) {
        var $lastVex;
        if (!id) {
          $lastVex = vex.getAllVexes().last();
          if (!$lastVex.length) {
            return false;
          }
          id = $lastVex.data().vex.id;
        }
        return vex.closeByID(id);
      },
      closeAll: function closeAll() {
        var ids;
        ids = vex.getAllVexes().map(function () {
          return $(this).data().vex.id;
        }).toArray();
        if (!(ids != null ? ids.length : void 0)) {
          return false;
        }
        $.each(ids.reverse(), function (index, id) {
          return vex.closeByID(id);
        });
        return true;
      },
      closeByID: function closeByID(id) {
        var $vex, $vexContent, beforeClose, close, options;
        $vexContent = vex.getVexByID(id);
        if (!$vexContent.length) {
          return;
        }
        $vex = $vexContent.data().vex.$vex;
        options = $.extend({}, $vexContent.data().vex);
        beforeClose = function () {
          if (options.beforeClose) {
            return options.beforeClose($vexContent, options);
          }
        };
        close = function () {
          $vexContent.trigger('vexClose', options);
          $vex.remove();
          $('body').trigger('vexAfterClose', options);
          if (options.afterClose) {
            return options.afterClose($vexContent, options);
          }
        };
        if (animationEndSupport) {
          beforeClose();
          $vex.unbind(vex.animationEndEvent).bind(vex.animationEndEvent, function () {
            return close();
          }).addClass(vex.baseClassNames.closing);
        } else {
          beforeClose();
          close();
        }
        return true;
      },
      closeByEscape: function closeByEscape() {
        var $lastVex, id, ids;
        ids = vex.getAllVexes().map(function () {
          return $(this).data().vex.id;
        }).toArray();
        if (!(ids != null ? ids.length : void 0)) {
          return false;
        }
        id = Math.max.apply(Math, ids);
        $lastVex = vex.getVexByID(id);
        if ($lastVex.data().vex.escapeButtonCloses !== true) {
          return false;
        }
        return vex.closeByID(id);
      },
      setupBodyClassName: function setupBodyClassName($vex) {
        return $('body').bind('vexOpen.vex', function () {
          return $('body').addClass(vex.baseClassNames.open);
        }).bind('vexAfterClose.vex', function () {
          if (!vex.getAllVexes().length) {
            return $('body').removeClass(vex.baseClassNames.open);
          }
        });
      },
      hideLoading: function hideLoading() {
        return $('.vex-loading-spinner').remove();
      },
      showLoading: function showLoading() {
        vex.hideLoading();
        return $('body').append('<div class="vex-loading-spinner ' + vex.defaultOptions.className + '"></div>');
      }
    };
  };

  if (typeof define === 'function' && define.amd) {
    define(['jquery'], vexFactory);
  } else if (typeof exports === 'object') {
    module.exports = vexFactory(require('jquery'));
  } else {
    window.vex = vexFactory(jQuery);
  }
}).call(undefined);
'use strict';

(function () {
  var vexDialogFactory;

  vexDialogFactory = function ($, vex) {
    var $formToObject, dialog;
    if (vex == null) {
      return $.error('Vex is required to use vex.dialog');
    }
    $formToObject = function ($form) {
      var object;
      object = {};
      $.each($form.serializeArray(), function () {
        if (object[this.name]) {
          if (!object[this.name].push) {
            object[this.name] = [object[this.name]];
          }
          return object[this.name].push(this.value || '');
        } else {
          return object[this.name] = this.value || '';
        }
      });
      return object;
    };
    dialog = {};
    dialog.buttons = {
      YES: {
        text: 'OK',
        type: 'submit',
        className: 'vex-dialog-button-primary'
      },
      NO: {
        text: 'Cancel',
        type: 'button',
        className: 'vex-dialog-button-secondary',
        click: function click($vexContent, event) {
          $vexContent.data().vex.value = false;
          return vex.close($vexContent.data().vex.id);
        }
      }
    };
    dialog.defaultOptions = {
      callback: function callback(value) {},
      afterOpen: function afterOpen() {},
      message: 'Message',
      input: '<input name="vex" type="hidden" value="_vex-empty-value" />',
      value: false,
      buttons: [dialog.buttons.YES, dialog.buttons.NO],
      showCloseButton: false,
      onSubmit: function onSubmit(event) {
        var $form, $vexContent;
        $form = $(this);
        $vexContent = $form.parent();
        event.preventDefault();
        event.stopPropagation();
        $vexContent.data().vex.value = dialog.getFormValueOnSubmit($formToObject($form));
        return vex.close($vexContent.data().vex.id);
      },
      focusFirstInput: true
    };
    dialog.defaultAlertOptions = {
      message: 'Alert',
      buttons: [dialog.buttons.YES]
    };
    dialog.defaultConfirmOptions = {
      message: 'Confirm'
    };
    dialog.open = function (options) {
      var $vexContent;
      options = $.extend({}, vex.defaultOptions, dialog.defaultOptions, options);
      options.content = dialog.buildDialogForm(options);
      options.beforeClose = function ($vexContent) {
        return options.callback($vexContent.data().vex.value);
      };
      $vexContent = vex.open(options);
      if (options.focusFirstInput) {
        $vexContent.find('button[type="submit"], button[type="button"], input[type="submit"], input[type="button"], textarea, input[type="date"], input[type="datetime"], input[type="datetime-local"], input[type="email"], input[type="month"], input[type="number"], input[type="password"], input[type="search"], input[type="tel"], input[type="text"], input[type="time"], input[type="url"], input[type="week"]').first().focus();
      }
      return $vexContent;
    };
    dialog.alert = function (options) {
      if (typeof options === 'string') {
        options = {
          message: options
        };
      }
      options = $.extend({}, dialog.defaultAlertOptions, options);
      return dialog.open(options);
    };
    dialog.confirm = function (options) {
      if (typeof options === 'string') {
        return $.error('dialog.confirm(options) requires options.callback.');
      }
      options = $.extend({}, dialog.defaultConfirmOptions, options);
      return dialog.open(options);
    };
    dialog.prompt = function (options) {
      var defaultPromptOptions;
      if (typeof options === 'string') {
        return $.error('dialog.prompt(options) requires options.callback.');
      }
      defaultPromptOptions = {
        message: '<label for="vex">' + (options.label || 'Prompt:') + '</label>',
        input: '<input name="vex" type="text" class="vex-dialog-prompt-input" placeholder="' + (options.placeholder || '') + '"  value="' + (options.value || '') + '" />'
      };
      options = $.extend({}, defaultPromptOptions, options);
      return dialog.open(options);
    };
    dialog.buildDialogForm = function (options) {
      var $form, $input, $message;
      $form = $('<form class="vex-dialog-form" />');
      $message = $('<div class="vex-dialog-message" />');
      $input = $('<div class="vex-dialog-input" />');
      $form.append($message.append(options.message)).append($input.append(options.input)).append(dialog.buttonsToDOM(options.buttons)).bind('submit.vex', options.onSubmit);
      return $form;
    };
    dialog.getFormValueOnSubmit = function (formData) {
      if (formData.vex || formData.vex === '') {
        if (formData.vex === '_vex-empty-value') {
          return true;
        }
        return formData.vex;
      } else {
        return formData;
      }
    };
    dialog.buttonsToDOM = function (buttons) {
      var $buttons;
      $buttons = $('<div class="vex-dialog-buttons" />');
      $.each(buttons, function (index, button) {
        var $button;
        $button = $('<button type="' + button.type + '"></button>').text(button.text).addClass(button.className + ' vex-dialog-button ' + (index === 0 ? 'vex-first ' : '') + (index === buttons.length - 1 ? 'vex-last ' : '')).bind('click.vex', function (e) {
          if (button.click) {
            return button.click($(this).parents(vex.getSelectorFromBaseClass(vex.baseClassNames.content)), e);
          }
        });
        return $button.appendTo($buttons);
      });
      return $buttons;
    };
    return dialog;
  };

  if (typeof define === 'function' && define.amd) {
    define(['jquery', 'vex'], vexDialogFactory);
  } else if (typeof exports === 'object') {
    module.exports = vexDialogFactory(require('jquery'), require('./vex.js'));
  } else {
    window.vex.dialog = vexDialogFactory(window.jQuery, window.vex);
  }
}).call(undefined);
"use strict";

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

var Utils = (function () {
  function Utils() {
    _classCallCheck(this, Utils);
  }

  _createClass(Utils, null, [{
    key: "addToPathName",
    value: function addToPathName(relativeUrl) {
      divider = window.location.pathname.slice(-1) == "/" ? "" : "/";
      return window.location.pathname + divider + relativeUrl;
    }
  }]);

  return Utils;
})();
'use strict';

$(function () {
    // set default theme for vex dialogs
    vex.defaultOptions.className = 'vex-theme-plain';
    vex.dialog.buttons.YES.text = 'OK';
    vex.dialog.buttons.NO.text = 'Angre';

    // set up phoenix back channel

    // set up auto slug

    $('[data-slug-from]').each(function (index, elem) {
        var slugFrom = $(elem).attr('data-slug-from');
        $('[name="' + slugFrom + '"]').slugIt({
            output: $(elem) });
    });
});