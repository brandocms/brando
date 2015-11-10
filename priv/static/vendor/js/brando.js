(function() {
  'use strict';

  var globals = typeof window === 'undefined' ? global : window;
  if (typeof globals.require === 'function') return;

  var modules = {};
  var cache = {};
  var aliases = {};
  var has = ({}).hasOwnProperty;

  var endsWith = function(str, suffix) {
    return str.indexOf(suffix, str.length - suffix.length) !== -1;
  };

  var _cmp = 'components/';
  var unalias = function(alias, loaderPath) {
    var start = 0;
    if (loaderPath) {
      if (loaderPath.indexOf(_cmp) === 0) {
        start = _cmp.length;
      }
      if (loaderPath.indexOf('/', start) > 0) {
        loaderPath = loaderPath.substring(start, loaderPath.indexOf('/', start));
      }
    }
    var result = aliases[alias + '/index.js'] || aliases[loaderPath + '/deps/' + alias + '/index.js'];
    if (result) {
      return _cmp + result.substring(0, result.length - '.js'.length);
    }
    return alias;
  };

  var _reg = /^\.\.?(\/|$)/;
  var expand = function(root, name) {
    var results = [], part;
    var parts = (_reg.test(name) ? root + '/' + name : name).split('/');
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

  var dirname = function(path) {
    return path.split('/').slice(0, -1).join('/');
  };

  var localRequire = function(path) {
    return function expanded(name) {
      var absolute = expand(dirname(path), name);
      return globals.require(absolute, path);
    };
  };

  var initModule = function(name, definition) {
    var module = {id: name, exports: {}};
    cache[name] = module;
    definition(module.exports, localRequire(name), module);
    return module.exports;
  };

  var require = function(name, loaderPath) {
    var path = expand(name, '.');
    if (loaderPath == null) loaderPath = '/';
    path = unalias(name, loaderPath);

    if (has.call(cache, path)) return cache[path].exports;
    if (has.call(modules, path)) return initModule(path, modules[path]);

    var dirIndex = expand(path, './index');
    if (has.call(cache, dirIndex)) return cache[dirIndex].exports;
    if (has.call(modules, dirIndex)) return initModule(dirIndex, modules[dirIndex]);

    throw new Error('Cannot find module "' + name + '" from '+ '"' + loaderPath + '"');
  };

  require.alias = function(from, to) {
    aliases[to] = from;
  };

  require.register = require.define = function(bundle, fn) {
    if (typeof bundle === 'object') {
      for (var key in bundle) {
        if (has.call(bundle, key)) {
          modules[key] = bundle[key];
        }
      }
    } else {
      modules[bundle] = fn;
    }
  };

  require.list = function() {
    var result = [];
    for (var item in modules) {
      if (has.call(modules, item)) {
        result.push(item);
      }
    }
    return result;
  };

  require.brunch = true;
  require._cache = cache;
  globals.require = require;
})();
require.register("deps/phoenix/web/static/js/phoenix", function(exports, require, module) {
// Phoenix Channels JavaScript client
//
// ## Socket Connection
//
// A single connection is established to the server and
// channels are mulitplexed over the connection.
// Connect to the server using the `Socket` class:
//
//     let socket = new Socket("/ws", {params: {userToken: "123"}})
//     socket.connect()
//
// The `Socket` constructor takes the mount point of the socket,
// the authentication params, as well as options that can be found in
// the Socket docs, such as configuring the `LongPoll` transport, and
// heartbeat.
//
// ## Channels
//
// Channels are isolated, concurrent processes on the server that
// subscribe to topics and broker events between the client and server.
// To join a channel, you must provide the topic, and channel params for
// authorization. Here's an example chat room example where `"new_msg"`
// events are listened for, messages are pushed to the server, and
// the channel is joined with ok/error matches, and `after` hook:
//
//     let channel = socket.channel("rooms:123", {token: roomToken})
//     channel.on("new_msg", msg => console.log("Got message", msg) )
//     $input.onEnter( e => {
//       channel.push("new_msg", {body: e.target.val})
//        .receive("ok", (msg) => console.log("created message", msg) )
//        .receive("error", (reasons) => console.log("create failed", reasons) )
//        .after(10000, () => console.log("Networking issue. Still waiting...") )
//     })
//     channel.join()
//       .receive("ok", ({messages}) => console.log("catching up", messages) )
//       .receive("error", ({reason}) => console.log("failed join", reason) )
//       .after(10000, () => console.log("Networking issue. Still waiting...") )
//
//
// ## Joining
//
// Joining a channel with `channel.join(topic, params)`, binds the params to
// `channel.params`. Subsequent rejoins will send up the modified params for
// updating authorization params, or passing up last_message_id information.
// Successful joins receive an "ok" status, while unsuccessful joins
// receive "error".
//
//
// ## Pushing Messages
//
// From the previous example, we can see that pushing messages to the server
// can be done with `channel.push(eventName, payload)` and we can optionally
// receive responses from the push. Additionally, we can use
// `after(millsec, callback)` to abort waiting for our `receive` hooks and
// take action after some period of waiting.
//
//
// ## Socket Hooks
//
// Lifecycle events of the multiplexed connection can be hooked into via
// `socket.onError()` and `socket.onClose()` events, ie:
//
//     socket.onError( () => console.log("there was an error with the connection!") )
//     socket.onClose( () => console.log("the connection dropped") )
//
//
// ## Channel Hooks
//
// For each joined channel, you can bind to `onError` and `onClose` events
// to monitor the channel lifecycle, ie:
//
//     channel.onError( () => console.log("there was an error!") )
//     channel.onClose( () => console.log("the channel has gone away gracefully") )
//
// ### onError hooks
//
// `onError` hooks are invoked if the socket connection drops, or the channel
// crashes on the server. In either case, a channel rejoin is attemtped
// automatically in an exponential backoff manner.
//
// ### onClose hooks
//
// `onClose` hooks are invoked only in two cases. 1) the channel explicitly
// closed on the server, or 2). The client explicitly closed, by calling
// `channel.leave()`
//

"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } }

var VSN = "1.0.0";
var SOCKET_STATES = { connecting: 0, open: 1, closing: 2, closed: 3 };
var CHANNEL_STATES = {
  closed: "closed",
  errored: "errored",
  joined: "joined",
  joining: "joining"
};
var CHANNEL_EVENTS = {
  close: "phx_close",
  error: "phx_error",
  join: "phx_join",
  reply: "phx_reply",
  leave: "phx_leave"
};
var TRANSPORTS = {
  longpoll: "longpoll",
  websocket: "websocket"
};

var Push = (function () {

  // Initializes the Push
  //
  // channel - The Channel
  // event - The event, for example `"phx_join"`
  // payload - The payload, for example `{user_id: 123}`
  //

  function Push(channel, event, payload) {
    _classCallCheck(this, Push);

    this.channel = channel;
    this.event = event;
    this.payload = payload || {};
    this.receivedResp = null;
    this.afterHook = null;
    this.recHooks = [];
    this.sent = false;
  }

  _createClass(Push, [{
    key: "send",
    value: function send() {
      var _this = this;

      var ref = this.channel.socket.makeRef();
      this.refEvent = this.channel.replyEventName(ref);
      this.receivedResp = null;
      this.sent = false;

      this.channel.on(this.refEvent, function (payload) {
        _this.receivedResp = payload;
        _this.matchReceive(payload);
        _this.cancelRefEvent();
        _this.cancelAfter();
      });

      this.startAfter();
      this.sent = true;
      this.channel.socket.push({
        topic: this.channel.topic,
        event: this.event,
        payload: this.payload,
        ref: ref
      });
    }
  }, {
    key: "receive",
    value: function receive(status, callback) {
      if (this.receivedResp && this.receivedResp.status === status) {
        callback(this.receivedResp.response);
      }

      this.recHooks.push({ status: status, callback: callback });
      return this;
    }
  }, {
    key: "after",
    value: function after(ms, callback) {
      if (this.afterHook) {
        throw "only a single after hook can be applied to a push";
      }
      var timer = null;
      if (this.sent) {
        timer = setTimeout(callback, ms);
      }
      this.afterHook = { ms: ms, callback: callback, timer: timer };
      return this;
    }

    // private

  }, {
    key: "matchReceive",
    value: function matchReceive(_ref) {
      var status = _ref.status;
      var response = _ref.response;
      var ref = _ref.ref;

      this.recHooks.filter(function (h) {
        return h.status === status;
      }).forEach(function (h) {
        return h.callback(response);
      });
    }
  }, {
    key: "cancelRefEvent",
    value: function cancelRefEvent() {
      this.channel.off(this.refEvent);
    }
  }, {
    key: "cancelAfter",
    value: function cancelAfter() {
      if (!this.afterHook) {
        return;
      }
      clearTimeout(this.afterHook.timer);
      this.afterHook.timer = null;
    }
  }, {
    key: "startAfter",
    value: function startAfter() {
      var _this2 = this;

      if (!this.afterHook) {
        return;
      }
      var callback = function callback() {
        _this2.cancelRefEvent();
        _this2.afterHook.callback();
      };
      this.afterHook.timer = setTimeout(callback, this.afterHook.ms);
    }
  }]);

  return Push;
})();

var Channel = (function () {
  function Channel(topic, params, socket) {
    var _this3 = this;

    _classCallCheck(this, Channel);

    this.state = CHANNEL_STATES.closed;
    this.topic = topic;
    this.params = params || {};
    this.socket = socket;
    this.bindings = [];
    this.joinedOnce = false;
    this.joinPush = new Push(this, CHANNEL_EVENTS.join, this.params);
    this.pushBuffer = [];
    this.rejoinTimer = new Timer(function () {
      return _this3.rejoinUntilConnected();
    }, this.socket.reconnectAfterMs);
    this.joinPush.receive("ok", function () {
      _this3.state = CHANNEL_STATES.joined;
      _this3.rejoinTimer.reset();
    });
    this.onClose(function () {
      _this3.socket.log("channel", "close " + _this3.topic);
      _this3.state = CHANNEL_STATES.closed;
      _this3.socket.remove(_this3);
    });
    this.onError(function (reason) {
      _this3.socket.log("channel", "error " + _this3.topic, reason);
      _this3.state = CHANNEL_STATES.errored;
      _this3.rejoinTimer.setTimeout();
    });
    this.on(CHANNEL_EVENTS.reply, function (payload, ref) {
      _this3.trigger(_this3.replyEventName(ref), payload);
    });
  }

  _createClass(Channel, [{
    key: "rejoinUntilConnected",
    value: function rejoinUntilConnected() {
      this.rejoinTimer.setTimeout();
      if (this.socket.isConnected()) {
        this.rejoin();
      }
    }
  }, {
    key: "join",
    value: function join() {
      if (this.joinedOnce) {
        throw "tried to join multiple times. 'join' can only be called a single time per channel instance";
      } else {
        this.joinedOnce = true;
      }
      this.sendJoin();
      return this.joinPush;
    }
  }, {
    key: "onClose",
    value: function onClose(callback) {
      this.on(CHANNEL_EVENTS.close, callback);
    }
  }, {
    key: "onError",
    value: function onError(callback) {
      this.on(CHANNEL_EVENTS.error, function (reason) {
        return callback(reason);
      });
    }
  }, {
    key: "on",
    value: function on(event, callback) {
      this.bindings.push({ event: event, callback: callback });
    }
  }, {
    key: "off",
    value: function off(event) {
      this.bindings = this.bindings.filter(function (bind) {
        return bind.event !== event;
      });
    }
  }, {
    key: "canPush",
    value: function canPush() {
      return this.socket.isConnected() && this.state === CHANNEL_STATES.joined;
    }
  }, {
    key: "push",
    value: function push(event, payload) {
      if (!this.joinedOnce) {
        throw "tried to push '" + event + "' to '" + this.topic + "' before joining. Use channel.join() before pushing events";
      }
      var pushEvent = new Push(this, event, payload);
      if (this.canPush()) {
        pushEvent.send();
      } else {
        this.pushBuffer.push(pushEvent);
      }

      return pushEvent;
    }

    // Leaves the channel
    //
    // Unsubscribes from server events, and
    // instructs channel to terminate on server
    //
    // Triggers onClose() hooks
    //
    // To receive leave acknowledgements, use the a `receive`
    // hook to bind to the server ack, ie:
    //
    //     channel.leave().receive("ok", () => alert("left!") )
    //
  }, {
    key: "leave",
    value: function leave() {
      var _this4 = this;

      return this.push(CHANNEL_EVENTS.leave).receive("ok", function () {
        _this4.socket.log("channel", "leave " + _this4.topic);
        _this4.trigger(CHANNEL_EVENTS.close, "leave");
      });
    }

    // Overridable message hook
    //
    // Receives all events for specialized message handling
  }, {
    key: "onMessage",
    value: function onMessage(event, payload, ref) {}

    // private

  }, {
    key: "isMember",
    value: function isMember(topic) {
      return this.topic === topic;
    }
  }, {
    key: "sendJoin",
    value: function sendJoin() {
      this.state = CHANNEL_STATES.joining;
      this.joinPush.send();
    }
  }, {
    key: "rejoin",
    value: function rejoin() {
      this.sendJoin();
      this.pushBuffer.forEach(function (pushEvent) {
        return pushEvent.send();
      });
      this.pushBuffer = [];
    }
  }, {
    key: "trigger",
    value: function trigger(triggerEvent, payload, ref) {
      this.onMessage(triggerEvent, payload, ref);
      this.bindings.filter(function (bind) {
        return bind.event === triggerEvent;
      }).map(function (bind) {
        return bind.callback(payload, ref);
      });
    }
  }, {
    key: "replyEventName",
    value: function replyEventName(ref) {
      return "chan_reply_" + ref;
    }
  }]);

  return Channel;
})();

exports.Channel = Channel;

var Socket = (function () {

  // Initializes the Socket
  //
  // endPoint - The string WebSocket endpoint, ie, "ws://example.com/ws",
  //                                               "wss://example.com"
  //                                               "/ws" (inherited host & protocol)
  // opts - Optional configuration
  //   transport - The Websocket Transport, for example WebSocket or Phoenix.LongPoll.
  //               Defaults to WebSocket with automatic LongPoll fallback.
  //   heartbeatIntervalMs - The millisec interval to send a heartbeat message
  //   reconnectAfterMs - The optional function that returns the millsec
  //                      reconnect interval. Defaults to stepped backoff of:
  //
  //     function(tries){
  //       return [1000, 5000, 10000][tries - 1] || 10000
  //     }
  //
  //   logger - The optional function for specialized logging, ie:
  //     `logger: (kind, msg, data) => { console.log(`${kind}: ${msg}`, data) }
  //
  //   longpollerTimeout - The maximum timeout of a long poll AJAX request.
  //                        Defaults to 20s (double the server long poll timer).
  //
  //   params - The optional params to pass when connecting
  //
  // For IE8 support use an ES5-shim (https://github.com/es-shims/es5-shim)
  //

  function Socket(endPoint) {
    var _this5 = this;

    var opts = arguments.length <= 1 || arguments[1] === undefined ? {} : arguments[1];

    _classCallCheck(this, Socket);

    this.stateChangeCallbacks = { open: [], close: [], error: [], message: [] };
    this.channels = [];
    this.sendBuffer = [];
    this.ref = 0;
    this.transport = opts.transport || window.WebSocket || LongPoll;
    this.heartbeatIntervalMs = opts.heartbeatIntervalMs || 30000;
    this.reconnectAfterMs = opts.reconnectAfterMs || function (tries) {
      return [1000, 5000, 10000][tries - 1] || 10000;
    };
    this.logger = opts.logger || function () {}; // noop
    this.longpollerTimeout = opts.longpollerTimeout || 20000;
    this.params = opts.params || {};
    this.endPoint = endPoint + "/" + TRANSPORTS.websocket;
    this.reconnectTimer = new Timer(function () {
      _this5.disconnect(function () {
        return _this5.connect();
      });
    }, this.reconnectAfterMs);
  }

  _createClass(Socket, [{
    key: "protocol",
    value: function protocol() {
      return location.protocol.match(/^https/) ? "wss" : "ws";
    }
  }, {
    key: "endPointURL",
    value: function endPointURL() {
      var uri = Ajax.appendParams(Ajax.appendParams(this.endPoint, this.params), { vsn: VSN });
      if (uri.charAt(0) !== "/") {
        return uri;
      }
      if (uri.charAt(1) === "/") {
        return this.protocol() + ":" + uri;
      }

      return this.protocol() + "://" + location.host + uri;
    }
  }, {
    key: "disconnect",
    value: function disconnect(callback, code, reason) {
      if (this.conn) {
        this.conn.onclose = function () {}; // noop
        if (code) {
          this.conn.close(code, reason || "");
        } else {
          this.conn.close();
        }
        this.conn = null;
      }
      callback && callback();
    }

    // params - The params to send when connecting, for example `{user_id: userToken}`
  }, {
    key: "connect",
    value: function connect(params) {
      var _this6 = this;

      if (params) {
        console && console.log("passing params to connect is deprecated. Instead pass :params to the Socket constructor");
        this.params = params;
      }
      if (this.conn) {
        return;
      }

      this.conn = new this.transport(this.endPointURL());
      this.conn.timeout = this.longpollerTimeout;
      this.conn.onopen = function () {
        return _this6.onConnOpen();
      };
      this.conn.onerror = function (error) {
        return _this6.onConnError(error);
      };
      this.conn.onmessage = function (event) {
        return _this6.onConnMessage(event);
      };
      this.conn.onclose = function (event) {
        return _this6.onConnClose(event);
      };
    }

    // Logs the message. Override `this.logger` for specialized logging. noops by default
  }, {
    key: "log",
    value: function log(kind, msg, data) {
      this.logger(kind, msg, data);
    }

    // Registers callbacks for connection state change events
    //
    // Examples
    //
    //    socket.onError(function(error){ alert("An error occurred") })
    //
  }, {
    key: "onOpen",
    value: function onOpen(callback) {
      this.stateChangeCallbacks.open.push(callback);
    }
  }, {
    key: "onClose",
    value: function onClose(callback) {
      this.stateChangeCallbacks.close.push(callback);
    }
  }, {
    key: "onError",
    value: function onError(callback) {
      this.stateChangeCallbacks.error.push(callback);
    }
  }, {
    key: "onMessage",
    value: function onMessage(callback) {
      this.stateChangeCallbacks.message.push(callback);
    }
  }, {
    key: "onConnOpen",
    value: function onConnOpen() {
      var _this7 = this;

      this.log("transport", "connected to " + this.endPointURL(), this.transport.prototype);
      this.flushSendBuffer();
      this.reconnectTimer.reset();
      if (!this.conn.skipHeartbeat) {
        clearInterval(this.heartbeatTimer);
        this.heartbeatTimer = setInterval(function () {
          return _this7.sendHeartbeat();
        }, this.heartbeatIntervalMs);
      }
      this.stateChangeCallbacks.open.forEach(function (callback) {
        return callback();
      });
    }
  }, {
    key: "onConnClose",
    value: function onConnClose(event) {
      this.log("transport", "close", event);
      this.triggerChanError();
      clearInterval(this.heartbeatTimer);
      this.reconnectTimer.setTimeout();
      this.stateChangeCallbacks.close.forEach(function (callback) {
        return callback(event);
      });
    }
  }, {
    key: "onConnError",
    value: function onConnError(error) {
      this.log("transport", error);
      this.triggerChanError();
      this.stateChangeCallbacks.error.forEach(function (callback) {
        return callback(error);
      });
    }
  }, {
    key: "triggerChanError",
    value: function triggerChanError() {
      this.channels.forEach(function (channel) {
        return channel.trigger(CHANNEL_EVENTS.error);
      });
    }
  }, {
    key: "connectionState",
    value: function connectionState() {
      switch (this.conn && this.conn.readyState) {
        case SOCKET_STATES.connecting:
          return "connecting";
        case SOCKET_STATES.open:
          return "open";
        case SOCKET_STATES.closing:
          return "closing";
        default:
          return "closed";
      }
    }
  }, {
    key: "isConnected",
    value: function isConnected() {
      return this.connectionState() === "open";
    }
  }, {
    key: "remove",
    value: function remove(channel) {
      this.channels = this.channels.filter(function (c) {
        return !c.isMember(channel.topic);
      });
    }
  }, {
    key: "channel",
    value: function channel(topic) {
      var chanParams = arguments.length <= 1 || arguments[1] === undefined ? {} : arguments[1];

      var channel = new Channel(topic, chanParams, this);
      this.channels.push(channel);
      return channel;
    }
  }, {
    key: "push",
    value: function push(data) {
      var _this8 = this;

      var topic = data.topic;
      var event = data.event;
      var payload = data.payload;
      var ref = data.ref;

      var callback = function callback() {
        return _this8.conn.send(JSON.stringify(data));
      };
      this.log("push", topic + " " + event + " (" + ref + ")", payload);
      if (this.isConnected()) {
        callback();
      } else {
        this.sendBuffer.push(callback);
      }
    }

    // Return the next message ref, accounting for overflows
  }, {
    key: "makeRef",
    value: function makeRef() {
      var newRef = this.ref + 1;
      if (newRef === this.ref) {
        this.ref = 0;
      } else {
        this.ref = newRef;
      }

      return this.ref.toString();
    }
  }, {
    key: "sendHeartbeat",
    value: function sendHeartbeat() {
      this.push({ topic: "phoenix", event: "heartbeat", payload: {}, ref: this.makeRef() });
    }
  }, {
    key: "flushSendBuffer",
    value: function flushSendBuffer() {
      if (this.isConnected() && this.sendBuffer.length > 0) {
        this.sendBuffer.forEach(function (callback) {
          return callback();
        });
        this.sendBuffer = [];
      }
    }
  }, {
    key: "onConnMessage",
    value: function onConnMessage(rawMessage) {
      var msg = JSON.parse(rawMessage.data);
      var topic = msg.topic;
      var event = msg.event;
      var payload = msg.payload;
      var ref = msg.ref;

      this.log("receive", (payload.status || "") + " " + topic + " " + event + " " + (ref && "(" + ref + ")" || ""), payload);
      this.channels.filter(function (channel) {
        return channel.isMember(topic);
      }).forEach(function (channel) {
        return channel.trigger(event, payload, ref);
      });
      this.stateChangeCallbacks.message.forEach(function (callback) {
        return callback(msg);
      });
    }
  }]);

  return Socket;
})();

exports.Socket = Socket;

var LongPoll = (function () {
  function LongPoll(endPoint) {
    _classCallCheck(this, LongPoll);

    this.endPoint = null;
    this.token = null;
    this.skipHeartbeat = true;
    this.onopen = function () {}; // noop
    this.onerror = function () {}; // noop
    this.onmessage = function () {}; // noop
    this.onclose = function () {}; // noop
    this.pollEndpoint = this.normalizeEndpoint(endPoint);
    this.readyState = SOCKET_STATES.connecting;

    this.poll();
  }

  _createClass(LongPoll, [{
    key: "normalizeEndpoint",
    value: function normalizeEndpoint(endPoint) {
      return endPoint.replace("ws://", "http://").replace("wss://", "https://").replace(new RegExp("(.*)\/" + TRANSPORTS.websocket), "$1/" + TRANSPORTS.longpoll);
    }
  }, {
    key: "endpointURL",
    value: function endpointURL() {
      return Ajax.appendParams(this.pollEndpoint, { token: this.token });
    }
  }, {
    key: "closeAndRetry",
    value: function closeAndRetry() {
      this.close();
      this.readyState = SOCKET_STATES.connecting;
    }
  }, {
    key: "ontimeout",
    value: function ontimeout() {
      this.onerror("timeout");
      this.closeAndRetry();
    }
  }, {
    key: "poll",
    value: function poll() {
      var _this9 = this;

      if (!(this.readyState === SOCKET_STATES.open || this.readyState === SOCKET_STATES.connecting)) {
        return;
      }

      Ajax.request("GET", this.endpointURL(), "application/json", null, this.timeout, this.ontimeout.bind(this), function (resp) {
        if (resp) {
          var status = resp.status;
          var token = resp.token;
          var messages = resp.messages;

          _this9.token = token;
        } else {
          var status = 0;
        }

        switch (status) {
          case 200:
            messages.forEach(function (msg) {
              return _this9.onmessage({ data: JSON.stringify(msg) });
            });
            _this9.poll();
            break;
          case 204:
            _this9.poll();
            break;
          case 410:
            _this9.readyState = SOCKET_STATES.open;
            _this9.onopen();
            _this9.poll();
            break;
          case 0:
          case 500:
            _this9.onerror();
            _this9.closeAndRetry();
            break;
          default:
            throw "unhandled poll status " + status;
        }
      });
    }
  }, {
    key: "send",
    value: function send(body) {
      var _this10 = this;

      Ajax.request("POST", this.endpointURL(), "application/json", body, this.timeout, this.onerror.bind(this, "timeout"), function (resp) {
        if (!resp || resp.status !== 200) {
          _this10.onerror(status);
          _this10.closeAndRetry();
        }
      });
    }
  }, {
    key: "close",
    value: function close(code, reason) {
      this.readyState = SOCKET_STATES.closed;
      this.onclose();
    }
  }]);

  return LongPoll;
})();

exports.LongPoll = LongPoll;

var Ajax = (function () {
  function Ajax() {
    _classCallCheck(this, Ajax);
  }

  _createClass(Ajax, null, [{
    key: "request",
    value: function request(method, endPoint, accept, body, timeout, ontimeout, callback) {
      if (window.XDomainRequest) {
        var req = new XDomainRequest(); // IE8, IE9
        this.xdomainRequest(req, method, endPoint, body, timeout, ontimeout, callback);
      } else {
        var req = window.XMLHttpRequest ? new XMLHttpRequest() : // IE7+, Firefox, Chrome, Opera, Safari
        new ActiveXObject("Microsoft.XMLHTTP"); // IE6, IE5
        this.xhrRequest(req, method, endPoint, accept, body, timeout, ontimeout, callback);
      }
    }
  }, {
    key: "xdomainRequest",
    value: function xdomainRequest(req, method, endPoint, body, timeout, ontimeout, callback) {
      var _this11 = this;

      req.timeout = timeout;
      req.open(method, endPoint);
      req.onload = function () {
        var response = _this11.parseJSON(req.responseText);
        callback && callback(response);
      };
      if (ontimeout) {
        req.ontimeout = ontimeout;
      }

      // Work around bug in IE9 that requires an attached onprogress handler
      req.onprogress = function () {};

      req.send(body);
    }
  }, {
    key: "xhrRequest",
    value: function xhrRequest(req, method, endPoint, accept, body, timeout, ontimeout, callback) {
      var _this12 = this;

      req.timeout = timeout;
      req.open(method, endPoint, true);
      req.setRequestHeader("Content-Type", accept);
      req.onerror = function () {
        callback && callback(null);
      };
      req.onreadystatechange = function () {
        if (req.readyState === _this12.states.complete && callback) {
          var response = _this12.parseJSON(req.responseText);
          callback(response);
        }
      };
      if (ontimeout) {
        req.ontimeout = ontimeout;
      }

      req.send(body);
    }
  }, {
    key: "parseJSON",
    value: function parseJSON(resp) {
      return resp && resp !== "" ? JSON.parse(resp) : null;
    }
  }, {
    key: "serialize",
    value: function serialize(obj, parentKey) {
      var queryStr = [];
      for (var key in obj) {
        if (!obj.hasOwnProperty(key)) {
          continue;
        }
        var paramKey = parentKey ? parentKey + "[" + key + "]" : key;
        var paramVal = obj[key];
        if (typeof paramVal === "object") {
          queryStr.push(this.serialize(paramVal, paramKey));
        } else {
          queryStr.push(encodeURIComponent(paramKey) + "=" + encodeURIComponent(paramVal));
        }
      }
      return queryStr.join("&");
    }
  }, {
    key: "appendParams",
    value: function appendParams(url, params) {
      if (Object.keys(params).length === 0) {
        return url;
      }

      var prefix = url.match(/\?/) ? "&" : "?";
      return "" + url + prefix + this.serialize(params);
    }
  }]);

  return Ajax;
})();

exports.Ajax = Ajax;

Ajax.states = { complete: 4 };

// Creates a timer that accepts a `timerCalc` function to perform
// calculated timeout retries, such as exponential backoff.
//
// ## Examples
//
//    let reconnectTimer = new Timer(() => this.connect(), function(tries){
//      return [1000, 5000, 10000][tries - 1] || 10000
//    })
//    reconnectTimer.setTimeout() // fires after 1000
//    reconnectTimer.setTimeout() // fires after 5000
//    reconnectTimer.reset()
//    reconnectTimer.setTimeout() // fires after 1000
//

var Timer = (function () {
  function Timer(callback, timerCalc) {
    _classCallCheck(this, Timer);

    this.callback = callback;
    this.timerCalc = timerCalc;
    this.timer = null;
    this.tries = 0;
  }

  _createClass(Timer, [{
    key: "reset",
    value: function reset() {
      this.tries = 0;
      clearTimeout(this.timer);
    }

    // Cancels any previous setTimeout and schedules callback
  }, {
    key: "setTimeout",
    value: (function (_setTimeout) {
      function setTimeout() {
        return _setTimeout.apply(this, arguments);
      }

      setTimeout.toString = function () {
        return _setTimeout.toString();
      };

      return setTimeout;
    })(function () {
      var _this13 = this;

      clearTimeout(this.timer);

      this.timer = setTimeout(function () {
        _this13.tries = _this13.tries + 1;
        _this13.callback();
      }, this.timerCalc(this.tries + 1));
    })
  }]);

  return Timer;
})();
});

;require.register("web/static/js/brando/brando", function(exports, require, module) {
"use strict";

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { "default": obj }; }

var _componentsAutoslug = require("./components/autoslug");

var _componentsAutoslug2 = _interopRequireDefault(_componentsAutoslug);

var _componentsFlash = require("./components/flash");

var _componentsFlash2 = _interopRequireDefault(_componentsFlash);

var _componentsFilter_table = require("./components/filter_table");

var _componentsFilter_table2 = _interopRequireDefault(_componentsFilter_table);

var _componentsMobile = require("./components/mobile");

var _componentsMobile2 = _interopRequireDefault(_componentsMobile);

var _componentsUtils = require("./components/utils");

var _componentsUtils2 = _interopRequireDefault(_componentsUtils);

var _componentsVex = require("./components/vex");

var _componentsVex2 = _interopRequireDefault(_componentsVex);

var _componentsImages = require("./components/images");

var _componentsImages2 = _interopRequireDefault(_componentsImages);

var _componentsInstagram = require("./components/instagram");

var _componentsInstagram2 = _interopRequireDefault(_componentsInstagram);

var _componentsPages = require("./components/pages");

var _componentsPages2 = _interopRequireDefault(_componentsPages);

var _componentsSequence = require("./components/sequence");

var _componentsSequence2 = _interopRequireDefault(_componentsSequence);

var _componentsStats = require("./components/stats");

var _componentsStats2 = _interopRequireDefault(_componentsStats);

var _componentsTags = require("./components/tags");

var _componentsTags2 = _interopRequireDefault(_componentsTags);

var _componentsToolbar = require("./components/toolbar");

var _componentsToolbar2 = _interopRequireDefault(_componentsToolbar);

var _componentsWs = require("./components/ws");

var _componentsWs2 = _interopRequireDefault(_componentsWs);

$(function () {
    /* set up automated vendored js stuff */
    _componentsVex2["default"].setup();
    _componentsAutoslug2["default"].setup();
    _componentsFilter_table2["default"].setup();
    _componentsFlash2["default"].setup();
    _componentsMobile2["default"].setup();
    _componentsSequence2["default"].setup();
    _componentsToolbar2["default"].setup();
    _componentsTags2["default"].setup();

    switch ($('body').attr('data-script')) {
        case "images-index":
            _componentsImages2["default"].setup();
            break;
        case "dashboard-system_info":
            _componentsStats2["default"].setup();
            break;
        case "instagram-index":
            _componentsInstagram2["default"].setup();
            break;
        case "pages-index":
            _componentsPages2["default"].setup();
            break;
    }
    /* set up ws */
    _componentsWs2["default"].setup();
});
});

require.register("web/static/js/brando/components/autoslug", function(exports, require, module) {
"use strict";

Object.defineProperty(exports, '__esModule', {
    value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ('value' in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError('Cannot call a class as a function'); } }

var Autoslug = (function () {
    function Autoslug() {
        _classCallCheck(this, Autoslug);
    }

    _createClass(Autoslug, null, [{
        key: 'setup',
        value: function setup() {
            // set up auto slug
            $('[data-slug-from]').each(function (index, elem) {
                var slugFrom = $(elem).attr('data-slug-from');
                $('[name="' + slugFrom + '"]').slugIt({
                    output: $(elem)
                });
            });
        }
    }]);

    return Autoslug;
})();

exports['default'] = Autoslug;
module.exports = exports['default'];
});

require.register("web/static/js/brando/components/filter_table", function(exports, require, module) {
"use strict";

Object.defineProperty(exports, "__esModule", {
    value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } }

var FilterTable = (function () {
    function FilterTable() {
        _classCallCheck(this, FilterTable);
    }

    _createClass(FilterTable, null, [{
        key: "setup",
        value: function setup() {
            // set up table filtering
            $('[data-filter-table]').each(function (index, elem) {
                $(elem).searcher({ inputSelector: "#filter-input" });
            });
        }
    }]);

    return FilterTable;
})();

exports["default"] = FilterTable;
module.exports = exports["default"];
});

require.register("web/static/js/brando/components/flash", function(exports, require, module) {
"use strict";

Object.defineProperty(exports, "__esModule", {
    value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } }

var Flash = (function () {
    function Flash() {
        _classCallCheck(this, Flash);
    }

    _createClass(Flash, null, [{
        key: "setup",
        value: function setup() {
            // set up dismissal of flash alerts
            $('[data-dismiss]').each(function (index, elem) {
                $(elem).click(function (e) {
                    e.preventDefault();
                    $(elem).parent().hide();
                });
            });
        }
    }]);

    return Flash;
})();

exports["default"] = Flash;
module.exports = exports["default"];
});

require.register("web/static/js/brando/components/images", function(exports, require, module) {
"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { "default": obj }; }

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } }

var _utils = require("./utils");

var _utils2 = _interopRequireDefault(_utils);

var imagePool = [];

var Images = (function () {
    function Images() {
        _classCallCheck(this, Images);
    }

    _createClass(Images, null, [{
        key: "setup",
        value: function setup() {
            this.getHash();
            this.deleteListener();
            this.imageSelectionListener();
            this.imagePropertiesListener();
        }
    }, {
        key: "getHash",
        value: function getHash() {
            var hash = document.location.hash;
            if (hash) {
                // show the tab
                activate_tab("#tab-" + hash.slice(1));
            }
        }
    }, {
        key: "imageSelectionListener",
        value: function imageSelectionListener() {
            var that = this;
            $('.image-selection-pool img').click(function (e) {
                if ($(this).hasClass('selected')) {
                    // remove from selected pool
                    var pos;
                    for (var i = 0; i < imagePool.length; i++) {
                        if (imagePool[i] == $(this).attr('data-id')) {
                            pos = i;
                            break;
                        }
                    }
                    imagePool.splice(pos, 1);
                } else {
                    // add to selected pool
                    if (!imagePool) {
                        imagePool = new Array();
                    }
                    imagePool.push($(this).attr('data-id'));
                }
                $(this).toggleClass('selected');
                that.checkButtonEnable();
            });
        }
    }, {
        key: "imagePropertiesListener",
        value: function imagePropertiesListener() {
            var that = this;

            $(document).on({
                mouseenter: function mouseenter() {
                    $(this).find('.overlay').css('visibility', 'visible');
                },
                mouseleave: function mouseleave() {
                    $(this).find('.overlay').css('visibility', 'hidden');
                }
            }, '.image-wrapper');

            $(document).on('click', '.edit-properties', function (e) {
                e.preventDefault();

                var attrs;
                var $content = $('<div>');
                var $form;
                var $img = $(this).parent().parent().find('img').clone();

                vex.dialog.open({
                    message: '',
                    input: function input() {
                        attrs = that._buildAttrs($img.data());
                        $content.append($img).append(attrs);
                        return $content;
                    },
                    callback: function callback(form) {
                        if (form === false) {
                            return console.log('Cancelled');
                        }
                        var id = form.id;
                        delete form.id;
                        var data = {
                            form: form,
                            id: id
                        };
                        that._submitProperties(data);
                    }
                });
            });
        }
    }, {
        key: "_submitProperties",
        value: function _submitProperties(data) {
            $.ajax({
                headers: { Accept: "application/json; charset=utf-8" },
                type: "POST",
                data: data,
                url: _utils2["default"].addToPathName('set-properties')
            }).done($.proxy(function (data) {
                /**
                 * Callback after confirming.
                 */
                if (data.status == '200') {
                    // success
                    var $img = $('.image-serie img[data-id=' + data.id + ']');
                    $.each(data.attrs, function (attr, val) {
                        $img.attr('data-' + attr, val);
                    });
                }
            }));
        }
    }, {
        key: "_buildAttrs",
        value: function _buildAttrs(data) {
            var that = this;
            var ret = '';
            $.each(data, function (attr, val) {
                if (attr == 'id') {
                    ret += '<input name="id" type="hidden" value="' + val + '" />';
                } else {
                    ret += '<div><label>' + that._capitalize(attr) + '</label>' + '<input name="' + attr + '" type="text" value="' + val + '" /></div>';
                }
            });
            return ret;
        }
    }, {
        key: "_capitalize",
        value: function _capitalize(word) {
            return $.camelCase("-" + word);
        }
    }, {
        key: "checkButtonEnable",
        value: function checkButtonEnable() {
            var $btn = $('.delete-selected-images');
            if (imagePool.length > 0) {
                $btn.removeAttr('disabled');
            } else {
                $btn.attr('disabled', 'disabled');
            }
        }
    }, {
        key: "deleteListener",
        value: function deleteListener() {
            var that = this;
            $('.delete-selected-images').click(function (e) {
                e.preventDefault();
                vex.dialog.confirm({
                    message: 'Er du sikker på at du vil slette disse bildene?',
                    callback: function callback(value) {
                        if (value) {
                            $(this).removeClass("btn-danger").addClass("btn-warning").html("Lagrer ...");
                            $.ajax({
                                headers: { Accept: "application/json; charset=utf-8" },
                                type: "POST",
                                url: _utils2["default"].addToPathName('delete-selected-images'),
                                data: { ids: imagePool },
                                success: that.deleteSuccess
                            });
                        }
                    }
                });
            });
        }
    }, {
        key: "deleteSuccess",
        value: function deleteSuccess(data) {
            if (data.status == 200) {
                $(".delete-selected-images").removeClass("btn-warning").addClass("btn-danger").html("Slett valgte bilder");
                for (var i = 0; i < data.ids.length; i++) {
                    $('.image-selection-pool img[data-id=' + data.ids[i] + ']').fadeOut();
                }
                imagePool = [];
            }
        }
    }]);

    return Images;
})();

exports["default"] = Images;
module.exports = exports["default"];
});

require.register("web/static/js/brando/components/instagram", function(exports, require, module) {
"use strict";
Object.defineProperty(exports, "__esModule", {
    value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _interopRequireDefault(obj) { return obj && obj.__esModule ? obj : { "default": obj }; }

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } }

var _utils = require("./utils");

var _utils2 = _interopRequireDefault(_utils);

var imagePool = [];

var Instagram = (function () {
    function Instagram() {
        _classCallCheck(this, Instagram);
    }

    _createClass(Instagram, null, [{
        key: "setup",
        value: function setup() {
            this.checkButtonEnable();
            this.changeStatusListener();
            this.imageSelectionListener();
        }
    }, {
        key: "imageSelectionListener",
        value: function imageSelectionListener() {
            var that = this;
            $('.image-selection-pool img').click(function (e) {
                if ($(this).hasClass('selected')) {
                    // remove from selected pool
                    var pos;
                    for (var i = 0; i < imagePool.length; i++) {
                        if (imagePool[i] == $(this).attr('data-id')) {
                            pos = i;
                            break;
                        }
                    }
                    imagePool.splice(pos, 1);
                } else {
                    // add to selected pool
                    if (!imagePool) {
                        imagePool = new Array();
                    }
                    imagePool.push($(this).attr('data-id'));
                }
                $(this).toggleClass('selected');
                that.checkButtonEnable();
            });
        }
    }, {
        key: "checkButtonEnable",
        value: function checkButtonEnable() {
            var $btn = $('.delete-selected-images, .approve-selected-images, .reject-selected-images');
            if (imagePool.length > 0) {
                $btn.removeAttr('disabled');
            } else {
                $btn.attr('disabled', 'disabled');
            }
        }
    }, {
        key: "changeStatusListener",
        value: function changeStatusListener() {
            var that = this;
            $('.delete-selected-images').click(function (e) {
                e.preventDefault();
                that.changeStatus(0, imagePool);
            });
            $('.reject-selected-images').click(function (e) {
                e.preventDefault();
                that.changeStatus(1, imagePool);
            });
            $('.approve-selected-images').click(function (e) {
                e.preventDefault();
                that.changeStatus(2, imagePool);
            });
        }
    }, {
        key: "changeStatus",
        value: function changeStatus(status, images) {
            var that = this;
            $.ajax({
                headers: { Accept: "application/json; charset=utf-8" },
                type: "POST",
                url: _utils2["default"].addToPathName('change-status'),
                data: { ids: images, status: status },
                success: that.changeStatusSuccess
            });
        }
    }, {
        key: "changeStatusSuccess",
        value: function changeStatusSuccess(data) {
            var new_status = "";
            if (data.status == 200) {
                switch (data.new_status) {
                    case "0":
                        new_status = "deleted";break;
                    case "1":
                        new_status = "rejected";break;
                    case "2":
                        new_status = "approved";break;
                }
                for (var i = 0; i < data.ids.length; i++) {
                    $('.image-selection-pool img[data-id=' + data.ids[i] + ']').fadeOut(500, function () {
                        $(this).detach().appendTo('.' + new_status).fadeIn().attr('data-status', new_status);
                    });
                }
                imagePool = [];
                $('.image-selection-pool img').removeClass('selected');
                vex.dialog.alert("Status successfully changed.");
            }
        }
    }]);

    return Instagram;
})();

exports["default"] = Instagram;
module.exports = exports["default"];
});

require.register("web/static/js/brando/components/mobile", function(exports, require, module) {
"use strict";

Object.defineProperty(exports, '__esModule', {
    value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ('value' in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError('Cannot call a class as a function'); } }

var Mobile = (function () {
    function Mobile() {
        _classCallCheck(this, Mobile);
    }

    _createClass(Mobile, null, [{
        key: 'setup',
        value: function setup() {
            // set up mobile menu
            $(document).on('click', '#mobile-nav', function (e) {
                $('#menu').toggle();
            });
        }
    }]);

    return Mobile;
})();

exports['default'] = Mobile;
module.exports = exports['default'];
});

require.register("web/static/js/brando/components/pages", function(exports, require, module) {
"use strict";

Object.defineProperty(exports, '__esModule', {
    value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ('value' in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError('Cannot call a class as a function'); } }

var Pages = (function () {
    function Pages() {
        _classCallCheck(this, Pages);
    }

    _createClass(Pages, null, [{
        key: 'setup',
        value: function setup() {
            var _this = this;
            $('.expand-page-children').click(function (e) {
                _this.onClickExpandButton(e, this);
            });
        }
    }, {
        key: 'onClickExpandButton',
        value: function onClickExpandButton(e, elem) {
            e.preventDefault();
            $(elem).toggleClass('active');
            $(elem).find('i').toggleClass('fa-plus').toggleClass('fa-times');
            $('tr.child[data-parent-id=' + $(elem).attr('data-id') + ']').toggleClass('hidden');
        }
    }]);

    return Pages;
})();

exports['default'] = Pages;
module.exports = exports['default'];
});

require.register("web/static/js/brando/components/sequence", function(exports, require, module) {
"use strict";

Object.defineProperty(exports, '__esModule', {
    value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ('value' in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError('Cannot call a class as a function'); } }

var Sequence = (function () {
    function Sequence() {
        _classCallCheck(this, Sequence);
    }

    _createClass(Sequence, null, [{
        key: 'setup',
        value: function setup() {
            if ($('#sequence').length != 0) {
                var el = document.getElementById('sequence');
                this.sortable = new Sortable(el, {
                    animation: 150,
                    ghostClass: "sequence-ghost",
                    onUpdate: function onUpdate(e) {
                        $('#sort-post').removeClass("btn-default", "btn-success").addClass("btn-warning").html("Lagre ny rekkefølge");
                    }
                });
                this.sortListener();
            }
        }
    }, {
        key: 'sortSuccess',
        value: function sortSuccess(data) {
            if (data.status == 200) {
                $("#sort-post").removeClass("btn-warning").addClass("btn-success").html("OK!");
            }
        }
    }, {
        key: 'sortListener',
        value: function sortListener() {
            var _this = this;
            $('#sort-post').on('click', function (e) {
                e.preventDefault();
                $(this).removeClass("btn-default").addClass("btn-warning").html("Lagrer ...");
                $.ajax({
                    headers: { Accept: "application/json; charset=utf-8" },
                    type: "POST",
                    url: "",
                    data: { order: _this.sortable.toArray() },
                    success: _this.sortSuccess
                });
            });
        }
    }]);

    return Sequence;
})();

exports['default'] = Sequence;
module.exports = exports['default'];
});

require.register("web/static/js/brando/components/stats", function(exports, require, module) {
"use strict";

Object.defineProperty(exports, "__esModule", {
    value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } }

var _depsPhoenixWebStaticJsPhoenix = require("deps/phoenix/web/static/js/phoenix");

var MAX_POINTS = 30;

var Stats = (function () {
    function Stats() {
        _classCallCheck(this, Stats);
    }

    _createClass(Stats, null, [{
        key: "setup",
        value: function setup() {
            var _this2 = this;

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
            };

            var user_token = document.querySelector("meta[name=\"channel_token\"]").getAttribute("content");
            var socket = new _depsPhoenixWebStaticJsPhoenix.Socket("/admin/ws", { params: { token: user_token } });
            socket.connect();
            var chan = socket.channel("stats", {});
            chan.join().receive("ok", function (_ref) {
                var messages = _ref.messages;

                console.log(">> System statistics channel ready");
            });
            chan.on("update", function (payload) {
                _this2.update(payload);
            });
        }
    }, {
        key: "update",
        value: function update(payload) {
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
                $('#instagram-status .status').html('<i class="fa fa-check fa-4x"></i>');
            } else {
                $('#instagram-status .status').html('<i class="fa fa-times fa-4x"></i>');
            }
        }
    }, {
        key: "humanFileSize",
        value: function humanFileSize(bytes, si) {
            var thresh = si ? 1000 : 1024;
            if (Math.abs(bytes) < thresh) {
                return bytes + ' B';
            }
            var units = si ? ['kB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'] : ['KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'EiB', 'ZiB', 'YiB'];
            var u = -1;
            do {
                bytes /= thresh;
                ++u;
            } while (Math.abs(bytes) >= thresh && u < units.length - 1);
            return bytes.toFixed(1) + ' ' + units[u];
        }
    }]);

    return Stats;
})();

exports["default"] = Stats;
module.exports = exports["default"];
});

require.register("web/static/js/brando/components/tags", function(exports, require, module) {
"use strict";

Object.defineProperty(exports, "__esModule", {
    value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } }

var Tags = (function () {
    function Tags() {
        _classCallCheck(this, Tags);
    }

    _createClass(Tags, null, [{
        key: "setup",
        value: function setup() {
            // set up tags
            $('[data-tags-input]').each(function (index, elem) {
                $(elem).tagsInput({ width: "100%", height: "35px", defaultText: "+" });
            });
        }
    }]);

    return Tags;
})();

exports["default"] = Tags;
module.exports = exports["default"];
});

require.register("web/static/js/brando/components/toolbar", function(exports, require, module) {
"use strict";

Object.defineProperty(exports, '__esModule', {
    value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ('value' in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError('Cannot call a class as a function'); } }

var Toolbar = (function () {
    function Toolbar() {
        _classCallCheck(this, Toolbar);
    }

    _createClass(Toolbar, null, [{
        key: 'setup',
        value: function setup() {
            var _this = this;
            $('.toolbar .logbutton').click(function (e) {
                _this.onClickLogButton(e, this);
            });
        }
    }, {
        key: 'onClickLogButton',
        value: function onClickLogButton(e, elem) {
            $(elem).toggleClass('active');
            $('#log-wrapper').toggle();
        }
    }]);

    return Toolbar;
})();

exports['default'] = Toolbar;
module.exports = exports['default'];
});

require.register("web/static/js/brando/components/utils", function(exports, require, module) {
"use strict";

Object.defineProperty(exports, "__esModule", {
    value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } }

var Utils = (function () {
    function Utils() {
        _classCallCheck(this, Utils);
    }

    _createClass(Utils, null, [{
        key: "addToPathName",
        value: function addToPathName(relativeUrl) {
            var divider = window.location.pathname.slice(-1) == "/" ? "" : "/";
            return window.location.pathname + divider + relativeUrl;
        }
    }, {
        key: "test",
        value: function test() {
            console.log("testing");
        }
    }]);

    return Utils;
})();

exports["default"] = Utils;
module.exports = exports["default"];
});

require.register("web/static/js/brando/components/vex", function(exports, require, module) {
"use strict";

Object.defineProperty(exports, '__esModule', {
    value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ('value' in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError('Cannot call a class as a function'); } }

var Vex = (function () {
    function Vex() {
        _classCallCheck(this, Vex);
    }

    _createClass(Vex, null, [{
        key: 'setup',
        value: function setup() {
            // set default theme for vex dialogs
            vex.defaultOptions.className = 'vex-theme-plain';
            vex.dialog.buttons.YES.text = 'OK';
            vex.dialog.buttons.NO.text = 'Angre';
        }
    }]);

    return Vex;
})();

exports['default'] = Vex;
module.exports = exports['default'];
});

require.register("web/static/js/brando/components/ws", function(exports, require, module) {
"use strict";

Object.defineProperty(exports, "__esModule", {
    value: true
});

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

function _classCallCheck(instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } }

var _depsPhoenixWebStaticJsPhoenix = require("deps/phoenix/web/static/js/phoenix");

var WS = (function () {
    function WS() {
        _classCallCheck(this, WS);
    }

    _createClass(WS, null, [{
        key: "setup",
        value: function setup() {
            var _this = this;
            var user_token = document.querySelector("meta[name=\"channel_token\"]").getAttribute("content");
            var socket = new _depsPhoenixWebStaticJsPhoenix.Socket("/admin/ws", { params: { token: user_token } });
            socket.connect();
            var chan = socket.channel("system:stream", {});
            chan.join().receive("ok", function (_ref) {
                var messages = _ref.messages;

                console.log(">> System channel ready");
            });
            chan.on("log_msg", function (payload) {
                _this.log(payload.level, payload.icon, payload.body);
            });
        }
    }, {
        key: "log",
        value: function log(level, icon, body) {
            var date = new Date();
            $("<li><i class=\"fa fa-fw " + icon + " m-l-sm m-r-sm\"> </i> <span class=\"time p-r-sm\">" + date.getHours() + ":" + date.getMinutes() + "</span>" + body + "</li>").appendTo("#log-content");
        }
    }]);

    return WS;
})();

exports["default"] = WS;
module.exports = exports["default"];
});

require('web/static/js/brando/brando');
//# sourceMappingURL=brando.js.map