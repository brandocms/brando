(function e(t,n,r){function s(o,u){if(!n[o]){if(!t[o]){var a=typeof require=="function"&&require;if(!u&&a)return a(o,!0);if(i)return i(o,!0);var f=new Error("Cannot find module '"+o+"'");throw f.code="MODULE_NOT_FOUND",f}var l=n[o]={exports:{}};t[o][0].call(l.exports,function(e){var n=t[o][1][e];return s(n?n:e)},l,l.exports,e,t,n,r)}return n[o].exports}var i=typeof require=="function"&&require;for(var o=0;o<r.length;o++)s(r[o]);return s})({1:[function(require,module,exports){
"use strict";

var _interopRequireWildcard = function (obj) { return obj && obj.__esModule ? obj : { "default": obj }; };

var _Autoslug = require("./autoslug.js");

var _Autoslug2 = _interopRequireWildcard(_Autoslug);

var _Flash = require("./flash.js");

var _Flash2 = _interopRequireWildcard(_Flash);

var _FilterTable = require("./filter_table.js");

var _FilterTable2 = _interopRequireWildcard(_FilterTable);

var _Mobile = require("./mobile.js");

var _Mobile2 = _interopRequireWildcard(_Mobile);

var _Utils = require("./utils.js");

var _Utils2 = _interopRequireWildcard(_Utils);

var _Vex = require("./vex.js");

var _Vex2 = _interopRequireWildcard(_Vex);

var _Images = require("./images.js");

var _Images2 = _interopRequireWildcard(_Images);

var _Instagram = require("./instagram.js");

var _Instagram2 = _interopRequireWildcard(_Instagram);

var _Pages = require("./pages.js");

var _Pages2 = _interopRequireWildcard(_Pages);

var _Sequence = require("./sequence.js");

var _Sequence2 = _interopRequireWildcard(_Sequence);

var _Stats = require("./stats.js");

var _Stats2 = _interopRequireWildcard(_Stats);

var _Tags = require("./tags.js");

var _Tags2 = _interopRequireWildcard(_Tags);

var _Toolbar = require("./toolbar.js");

var _Toolbar2 = _interopRequireWildcard(_Toolbar);

var _WS = require("./ws.js");

var _WS2 = _interopRequireWildcard(_WS);

$(function () {
    /* set up automated vendored js stuff */
    _Vex2["default"].setup();
    _Autoslug2["default"].setup();
    _FilterTable2["default"].setup();
    _Flash2["default"].setup();
    _Mobile2["default"].setup();
    _Sequence2["default"].setup();
    _Toolbar2["default"].setup();
    _Tags2["default"].setup();

    switch ($("body").attr("data-script")) {
        case "images-index":
            _Images2["default"].setup();
            break;
        case "dashboard-system_info":
            _Stats2["default"].setup();
            break;
        case "instagram-index":
            _Instagram2["default"].setup();
            break;
        case "pages-index":
            _Pages2["default"].setup();
            break;
    }
    /* set up ws */
    _WS2["default"].setup();
});

},{"./autoslug.js":2,"./filter_table.js":3,"./flash.js":4,"./images.js":5,"./instagram.js":6,"./mobile.js":7,"./pages.js":8,"./sequence.js":9,"./stats.js":10,"./tags.js":11,"./toolbar.js":12,"./utils.js":13,"./vex.js":14,"./ws.js":15}],2:[function(require,module,exports){
'use strict';

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError('Cannot call a class as a function'); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ('value' in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, '__esModule', {
    value: true
});
'use strict';

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
                    output: $(elem) });
            });
        }
    }]);

    return Autoslug;
})();

exports['default'] = Autoslug;
module.exports = exports['default'];

},{}],3:[function(require,module,exports){
"use strict";

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, "__esModule", {
    value: true
});
"use strict";

var FilterTable = (function () {
    function FilterTable() {
        _classCallCheck(this, FilterTable);
    }

    _createClass(FilterTable, null, [{
        key: "setup",
        value: function setup() {
            // set up table filtering
            $("[data-filter-table]").each(function (index, elem) {
                $(elem).searcher({ inputSelector: "#filter-input" });
            });
        }
    }]);

    return FilterTable;
})();

exports["default"] = FilterTable;
module.exports = exports["default"];

},{}],4:[function(require,module,exports){
"use strict";

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, "__esModule", {
    value: true
});
"use strict";

var Flash = (function () {
    function Flash() {
        _classCallCheck(this, Flash);
    }

    _createClass(Flash, null, [{
        key: "setup",
        value: function setup() {
            // set up dismissal of flash alerts
            $("[data-dismiss]").each(function (index, elem) {
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

},{}],5:[function(require,module,exports){
"use strict";

var _interopRequireWildcard = function (obj) { return obj && obj.__esModule ? obj : { "default": obj }; };

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, "__esModule", {
    value: true
});

var _Utils = require("./utils.js");

var _Utils2 = _interopRequireWildcard(_Utils);

"use strict";

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
            $(".image-selection-pool img").click(function (e) {
                if ($(this).hasClass("selected")) {
                    // remove from selected pool
                    var pos;
                    for (var i = 0; i < imagePool.length; i++) {
                        if (imagePool[i] == $(this).attr("data-id")) {
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
                    imagePool.push($(this).attr("data-id"));
                }
                $(this).toggleClass("selected");
                that.checkButtonEnable();
            });
        }
    }, {
        key: "imagePropertiesListener",
        value: function imagePropertiesListener() {
            var that = this;

            $(document).on({
                mouseenter: function mouseenter() {
                    $(this).find(".overlay").css("visibility", "visible");
                },
                mouseleave: function mouseleave() {
                    $(this).find(".overlay").css("visibility", "hidden");
                }
            }, ".image-wrapper");

            $(document).on("click", ".edit-properties", function (e) {
                e.preventDefault();

                var attrs;
                var $content = $("<div>");
                var $form;
                var $img = $(this).parent().parent().find("img").clone();

                vex.dialog.open({
                    message: "",
                    input: function input() {
                        attrs = that._buildAttrs($img.data());
                        $content.append($img).append(attrs);
                        return $content;
                    },
                    callback: function callback(form) {
                        if (form === false) {
                            return console.log("Cancelled");
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
                url: _Utils2["default"].addToPathName("set-properties") }).done($.proxy(function (data) {
                /**
                 * Callback after confirming.
                 */
                if (data.status == "200") {
                    // success
                    var $img = $(".image-serie img[data-id=" + data.id + "]");
                    $.each(data.attrs, function (attr, val) {
                        $img.attr("data-" + attr, val);
                    });
                }
            }));
        }
    }, {
        key: "_buildAttrs",
        value: function _buildAttrs(data) {
            var that = this;
            var ret = "";
            $.each(data, function (attr, val) {
                if (attr == "id") {
                    ret += "<input name=\"id\" type=\"hidden\" value=\"" + val + "\" />";
                } else {
                    ret += "<div><label>" + that._capitalize(attr) + "</label>" + "<input name=\"" + attr + "\" type=\"text\" value=\"" + val + "\" /></div>";
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
            var $btn = $(".delete-selected-images");
            if (imagePool.length > 0) {
                $btn.removeAttr("disabled");
            } else {
                $btn.attr("disabled", "disabled");
            }
        }
    }, {
        key: "deleteListener",
        value: function deleteListener() {
            var that = this;
            $(".delete-selected-images").click(function (e) {
                e.preventDefault();
                vex.dialog.confirm({
                    message: "Er du sikker på at du vil slette disse bildene?",
                    callback: function callback(value) {
                        if (value) {
                            $(this).removeClass("btn-danger").addClass("btn-warning").html("Lagrer ...");
                            $.ajax({
                                headers: { Accept: "application/json; charset=utf-8" },
                                type: "POST",
                                url: _Utils2["default"].addToPathName("delete-selected-images"),
                                data: { ids: imagePool },
                                success: that.deleteSuccess });
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
                    $(".image-selection-pool img[data-id=" + data.ids[i] + "]").fadeOut();
                }
                imagePool = [];
            }
        }
    }]);

    return Images;
})();

exports["default"] = Images;
module.exports = exports["default"];

},{"./utils.js":13}],6:[function(require,module,exports){
"use strict";

var _interopRequireWildcard = function (obj) { return obj && obj.__esModule ? obj : { "default": obj }; };

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, "__esModule", {
    value: true
});

var _Utils = require("./utils.js");

var _Utils2 = _interopRequireWildcard(_Utils);

"use strict";

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
            $(".image-selection-pool img").click(function (e) {
                if ($(this).hasClass("selected")) {
                    // remove from selected pool
                    var pos;
                    for (var i = 0; i < imagePool.length; i++) {
                        if (imagePool[i] == $(this).attr("data-id")) {
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
                    imagePool.push($(this).attr("data-id"));
                }
                $(this).toggleClass("selected");
                that.checkButtonEnable();
            });
        }
    }, {
        key: "checkButtonEnable",
        value: function checkButtonEnable() {
            var $btn = $(".delete-selected-images, .approve-selected-images, .reject-selected-images");
            if (imagePool.length > 0) {
                $btn.removeAttr("disabled");
            } else {
                $btn.attr("disabled", "disabled");
            }
        }
    }, {
        key: "changeStatusListener",
        value: function changeStatusListener() {
            var that = this;
            $(".delete-selected-images").click(function (e) {
                e.preventDefault();
                that.changeStatus(0, imagePool);
            });
            $(".reject-selected-images").click(function (e) {
                e.preventDefault();
                that.changeStatus(1, imagePool);
            });
            $(".approve-selected-images").click(function (e) {
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
                url: _Utils2["default"].addToPathName("change-status"),
                data: { ids: images, status: status },
                success: that.changeStatusSuccess });
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
                    $(".image-selection-pool img[data-id=" + data.ids[i] + "]").fadeOut(500, function () {
                        $(this).detach().appendTo("." + new_status).fadeIn().attr("data-status", new_status);
                    });
                }
                imagePool = [];
                $(".image-selection-pool img").removeClass("selected");
            }
        }
    }]);

    return Instagram;
})();

exports["default"] = Instagram;
module.exports = exports["default"];

},{"./utils.js":13}],7:[function(require,module,exports){
'use strict';

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError('Cannot call a class as a function'); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ('value' in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, '__esModule', {
    value: true
});
'use strict';

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

},{}],8:[function(require,module,exports){
'use strict';

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError('Cannot call a class as a function'); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ('value' in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, '__esModule', {
    value: true
});
'use strict';

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
            $('tr.child[data-parent-id=' + $(elem).attr('data-id') + ']').toggleClass('hidden');
        }
    }]);

    return Pages;
})();

exports['default'] = Pages;
module.exports = exports['default'];

},{}],9:[function(require,module,exports){
'use strict';

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError('Cannot call a class as a function'); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ('value' in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, '__esModule', {
    value: true
});
'use strict';

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
                    ghostClass: 'sequence-ghost',
                    onUpdate: function onUpdate(e) {
                        $('#sort-post').removeClass('btn-default', 'btn-success').addClass('btn-warning').html('Lagre ny rekkefølge');
                    } });
                this.sortListener();
            }
        }
    }, {
        key: 'sortSuccess',
        value: function sortSuccess(data) {
            if (data.status == 200) {
                $('#sort-post').removeClass('btn-warning').addClass('btn-success').html('OK!');
            }
        }
    }, {
        key: 'sortListener',
        value: function sortListener() {
            var _this = this;
            $('#sort-post').on('click', function (e) {
                e.preventDefault();
                $(this).removeClass('btn-default').addClass('btn-warning').html('Lagrer ...');
                $.ajax({
                    headers: { Accept: 'application/json; charset=utf-8' },
                    type: 'POST',
                    url: '',
                    data: { order: _this.sortable.toArray() },
                    success: _this.sortSuccess });
            });
        }
    }]);

    return Sequence;
})();

exports['default'] = Sequence;
module.exports = exports['default'];

},{}],10:[function(require,module,exports){
'use strict';

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError('Cannot call a class as a function'); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ('value' in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, '__esModule', {
    value: true
});

var _Socket = require('../../../deps/phoenix/web/static/js/phoenix.js');

'use strict';

var MAX_POINTS = 30;

var Stats = (function () {
    function Stats() {
        _classCallCheck(this, Stats);
    }

    _createClass(Stats, null, [{
        key: 'setup',
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
            var socket = new _Socket.Socket('/admin/ws');
            var user_token = document.querySelector('meta[name="channel_token"]').getAttribute('content');
            socket.connect({ token: user_token });
            var chan = socket.channel('stats', {});
            chan.join().receive('ok', function (_ref) {
                var messages = _ref.messages;

                console.log('>> System statistics channel ready');
            });
            chan.on('update', function (payload) {
                _this2.update(payload);
            });
        }
    }, {
        key: 'update',
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
        key: 'humanFileSize',
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

exports['default'] = Stats;
module.exports = exports['default'];

},{"../../../deps/phoenix/web/static/js/phoenix.js":16}],11:[function(require,module,exports){
"use strict";

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, "__esModule", {
    value: true
});
"use strict";

var Tags = (function () {
    function Tags() {
        _classCallCheck(this, Tags);
    }

    _createClass(Tags, null, [{
        key: "setup",
        value: function setup() {
            // set up tags
            $("[data-tags-input]").each(function (index, elem) {
                $(elem).tagsInput({ width: "100%", height: "35px", defaultText: "+" });
            });
        }
    }]);

    return Tags;
})();

exports["default"] = Tags;
module.exports = exports["default"];

},{}],12:[function(require,module,exports){
'use strict';

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError('Cannot call a class as a function'); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ('value' in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, '__esModule', {
    value: true
});
'use strict';

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

},{}],13:[function(require,module,exports){
"use strict";

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, "__esModule", {
    value: true
});
"use strict";

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

},{}],14:[function(require,module,exports){
'use strict';

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError('Cannot call a class as a function'); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ('value' in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, '__esModule', {
    value: true
});
'use strict';

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

},{}],15:[function(require,module,exports){
"use strict";

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, "__esModule", {
    value: true
});

var _Socket = require("../../../deps/phoenix/web/static/js/phoenix.js");

"use strict";

var WS = (function () {
    function WS() {
        _classCallCheck(this, WS);
    }

    _createClass(WS, null, [{
        key: "setup",
        value: function setup() {
            var _this = this;
            var socket = new _Socket.Socket("/admin/ws");
            var user_token = document.querySelector("meta[name=\"channel_token\"]").getAttribute("content");
            socket.connect({ token: user_token });
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

},{"../../../deps/phoenix/web/static/js/phoenix.js":16}],16:[function(require,module,exports){
"use strict";

var _classCallCheck = function (instance, Constructor) { if (!(instance instanceof Constructor)) { throw new TypeError("Cannot call a class as a function"); } };

var _createClass = (function () { function defineProperties(target, props) { for (var i = 0; i < props.length; i++) { var descriptor = props[i]; descriptor.enumerable = descriptor.enumerable || false; descriptor.configurable = true; if ("value" in descriptor) descriptor.writable = true; Object.defineProperty(target, descriptor.key, descriptor); } } return function (Constructor, protoProps, staticProps) { if (protoProps) defineProperties(Constructor.prototype, protoProps); if (staticProps) defineProperties(Constructor, staticProps); return Constructor; }; })();

Object.defineProperty(exports, "__esModule", {
  value: true
});
// Phoenix Channels JavaScript client
//
// ## Socket Connection
//
// A single connection is established to the server and
// channels are mulitplexed over the connection.
// Connect to the server using the `Socket` class:
//
//     let socket = new Socket("/ws")
//     socket.connect({userToken: "123"})
//
// The `Socket` constructor takes the mount point of the socket
// as well as options that can be found in the Socket docs,
// such as configuring the `LongPoll` transport, and heartbeat.
// Socket params can also be passed as an object literal to `connect`.
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

var VSN = "1.0.0";
var SOCKET_STATES = { connecting: 0, open: 1, closing: 2, closed: 3 };
var CHANNEL_STATES = {
  closed: "closed",
  errored: "errored",
  joined: "joined",
  joining: "joining" };
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
  // channel - The Channelnel
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
  }, {
    key: "matchReceive",

    // private

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
  }, {
    key: "leave",

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
    value: function leave() {
      var _this4 = this;

      return this.push(CHANNEL_EVENTS.leave).receive("ok", function () {
        _this4.socket.log("channel", "leave " + _this4.topic);
        _this4.trigger(CHANNEL_EVENTS.close, "leave");
      });
    }
  }, {
    key: "onMessage",

    // Overridable message hook
    //
    // Receives all events for specialized message handling
    value: function onMessage(event, payload, ref) {}
  }, {
    key: "isMember",

    // private

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
  // For IE8 support use an ES5-shim (https://github.com/es-shims/es5-shim)
  //

  function Socket(endPoint) {
    var _this5 = this;

    var opts = arguments[1] === undefined ? {} : arguments[1];

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
    this.params = {};
    this.reconnectTimer = new Timer(function () {
      return _this5.connect(_this5.params);
    }, this.reconnectAfterMs);
    this.endPoint = "" + endPoint + "/" + TRANSPORTS.websocket;
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
        return "" + this.protocol() + ":" + uri;
      }

      return "" + this.protocol() + "://" + location.host + "" + uri;
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
  }, {
    key: "connect",

    // params - The params to send when connecting, for example `{user_id: userToken}`
    value: function connect() {
      var _this6 = this;

      var params = arguments[0] === undefined ? {} : arguments[0];
      this.params = params;
      this.disconnect(function () {
        _this6.conn = new _this6.transport(_this6.endPointURL());
        _this6.conn.timeout = _this6.longpollerTimeout;
        _this6.conn.onopen = function () {
          return _this6.onConnOpen();
        };
        _this6.conn.onerror = function (error) {
          return _this6.onConnError(error);
        };
        _this6.conn.onmessage = function (event) {
          return _this6.onConnMessage(event);
        };
        _this6.conn.onclose = function (event) {
          return _this6.onConnClose(event);
        };
      });
    }
  }, {
    key: "log",

    // Logs the message. Override `this.logger` for specialized logging. noops by default
    value: function log(kind, msg, data) {
      this.logger(kind, msg, data);
    }
  }, {
    key: "onOpen",

    // Registers callbacks for connection state change events
    //
    // Examples
    //
    //    socket.onError(function(error){ alert("An error occurred") })
    //
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
    value: (function (_channel) {
      function channel(_x) {
        return _channel.apply(this, arguments);
      }

      channel.toString = function () {
        return _channel.toString();
      };

      return channel;
    })(function (topic) {
      var chanParams = arguments[1] === undefined ? {} : arguments[1];

      var channel = new Channel(topic, chanParams, this);
      this.channels.push(channel);
      return channel;
    })
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
      this.log("push", "" + topic + " " + event + " (" + ref + ")", payload);
      if (this.isConnected()) {
        callback();
      } else {
        this.sendBuffer.push(callback);
      }
    }
  }, {
    key: "makeRef",

    // Return the next message ref, accounting for overflows
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

      this.log("receive", "" + (payload.status || "") + " " + topic + " " + event + " " + (ref && "(" + ref + ")" || ""), payload);
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
      return endPoint.replace("ws://", "http://").replace("wss://", "https://").replace(new RegExp("(.*)/" + TRANSPORTS.websocket), "$1/" + TRANSPORTS.longpoll);
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
        var paramKey = parentKey ? "" + parentKey + "[" + key + "]" : key;
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
      return "" + url + "" + prefix + "" + this.serialize(params);
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
  }, {
    key: "setTimeout",

    // Cancels any previous setTimeout and schedules callback
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

},{}],17:[function(require,module,exports){
(function (global){
"use strict";

if (global._babelPolyfill) {
  throw new Error("only one instance of babel/polyfill is allowed");
}
global._babelPolyfill = true;

require("core-js/shim");

require("regenerator-babel/runtime");
}).call(this,typeof global !== "undefined" ? global : typeof self !== "undefined" ? self : typeof window !== "undefined" ? window : {})
//# sourceMappingURL=data:application/json;charset:utf-8;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9saWIvYmFiZWwvcG9seWZpbGwuanMiXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IjtBQUFBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBIiwiZmlsZSI6ImdlbmVyYXRlZC5qcyIsInNvdXJjZVJvb3QiOiIiLCJzb3VyY2VzQ29udGVudCI6WyJcInVzZSBzdHJpY3RcIjtcblxuaWYgKGdsb2JhbC5fYmFiZWxQb2x5ZmlsbCkge1xuICB0aHJvdyBuZXcgRXJyb3IoXCJvbmx5IG9uZSBpbnN0YW5jZSBvZiBiYWJlbC9wb2x5ZmlsbCBpcyBhbGxvd2VkXCIpO1xufVxuZ2xvYmFsLl9iYWJlbFBvbHlmaWxsID0gdHJ1ZTtcblxucmVxdWlyZShcImNvcmUtanMvc2hpbVwiKTtcblxucmVxdWlyZShcInJlZ2VuZXJhdG9yLWJhYmVsL3J1bnRpbWVcIik7Il19
},{"core-js/shim":86,"regenerator-babel/runtime":87}],18:[function(require,module,exports){
'use strict';
// false -> Array#indexOf
// true  -> Array#includes
var $ = require('./$');
module.exports = function(IS_INCLUDES){
  return function(el /*, fromIndex = 0 */){
    var O      = $.toObject(this)
      , length = $.toLength(O.length)
      , index  = $.toIndex(arguments[1], length)
      , value;
    if(IS_INCLUDES && el != el)while(length > index){
      value = O[index++];
      if(value != value)return true;
    } else for(;length > index; index++)if(IS_INCLUDES || index in O){
      if(O[index] === el)return IS_INCLUDES || index;
    } return !IS_INCLUDES && -1;
  };
};
},{"./$":31}],19:[function(require,module,exports){
'use strict';
// 0 -> Array#forEach
// 1 -> Array#map
// 2 -> Array#filter
// 3 -> Array#some
// 4 -> Array#every
// 5 -> Array#find
// 6 -> Array#findIndex
var $   = require('./$')
  , ctx = require('./$.ctx');
module.exports = function(TYPE){
  var IS_MAP        = TYPE == 1
    , IS_FILTER     = TYPE == 2
    , IS_SOME       = TYPE == 3
    , IS_EVERY      = TYPE == 4
    , IS_FIND_INDEX = TYPE == 6
    , NO_HOLES      = TYPE == 5 || IS_FIND_INDEX;
  return function(callbackfn/*, that = undefined */){
    var O      = Object($.assertDefined(this))
      , self   = $.ES5Object(O)
      , f      = ctx(callbackfn, arguments[1], 3)
      , length = $.toLength(self.length)
      , index  = 0
      , result = IS_MAP ? Array(length) : IS_FILTER ? [] : undefined
      , val, res;
    for(;length > index; index++)if(NO_HOLES || index in self){
      val = self[index];
      res = f(val, index, O);
      if(TYPE){
        if(IS_MAP)result[index] = res;            // map
        else if(res)switch(TYPE){
          case 3: return true;                    // some
          case 5: return val;                     // find
          case 6: return index;                   // findIndex
          case 2: result.push(val);               // filter
        } else if(IS_EVERY)return false;          // every
      }
    }
    return IS_FIND_INDEX ? -1 : IS_SOME || IS_EVERY ? IS_EVERY : result;
  };
};
},{"./$":31,"./$.ctx":26}],20:[function(require,module,exports){
var $ = require('./$');
function assert(condition, msg1, msg2){
  if(!condition)throw TypeError(msg2 ? msg1 + msg2 : msg1);
}
assert.def = $.assertDefined;
assert.fn = function(it){
  if(!$.isFunction(it))throw TypeError(it + ' is not a function!');
  return it;
};
assert.obj = function(it){
  if(!$.isObject(it))throw TypeError(it + ' is not an object!');
  return it;
};
assert.inst = function(it, Constructor, name){
  if(!(it instanceof Constructor))throw TypeError(name + ": use the 'new' operator!");
  return it;
};
module.exports = assert;
},{"./$":31}],21:[function(require,module,exports){
var $ = require('./$');
// 19.1.2.1 Object.assign(target, source, ...)
module.exports = Object.assign || function(target, source){ // eslint-disable-line no-unused-vars
  var T = Object($.assertDefined(target))
    , l = arguments.length
    , i = 1;
  while(l > i){
    var S      = $.ES5Object(arguments[i++])
      , keys   = $.getKeys(S)
      , length = keys.length
      , j      = 0
      , key;
    while(length > j)T[key = keys[j++]] = S[key];
  }
  return T;
};
},{"./$":31}],22:[function(require,module,exports){
var $        = require('./$')
  , TAG      = require('./$.wks')('toStringTag')
  , toString = {}.toString;
function cof(it){
  return toString.call(it).slice(8, -1);
}
cof.classof = function(it){
  var O, T;
  return it == undefined ? it === undefined ? 'Undefined' : 'Null'
    : typeof (T = (O = Object(it))[TAG]) == 'string' ? T : cof(O);
};
cof.set = function(it, tag, stat){
  if(it && !$.has(it = stat ? it : it.prototype, TAG))$.hide(it, TAG, tag);
};
module.exports = cof;
},{"./$":31,"./$.wks":42}],23:[function(require,module,exports){
'use strict';
var $        = require('./$')
  , ctx      = require('./$.ctx')
  , safe     = require('./$.uid').safe
  , assert   = require('./$.assert')
  , $iter    = require('./$.iter')
  , has      = $.has
  , set      = $.set
  , isObject = $.isObject
  , hide     = $.hide
  , step     = $iter.step
  , isFrozen = Object.isFrozen || $.core.Object.isFrozen
  , ID       = safe('id')
  , O1       = safe('O1')
  , LAST     = safe('last')
  , FIRST    = safe('first')
  , ITER     = safe('iter')
  , SIZE     = $.DESC ? safe('size') : 'size'
  , id       = 0;

function fastKey(it, create){
  // return primitive with prefix
  if(!isObject(it))return (typeof it == 'string' ? 'S' : 'P') + it;
  // can't set id to frozen object
  if(isFrozen(it))return 'F';
  if(!has(it, ID)){
    // not necessary to add id
    if(!create)return 'E';
    // add missing object id
    hide(it, ID, ++id);
  // return object id with prefix
  } return 'O' + it[ID];
}

function getEntry(that, key){
  // fast case
  var index = fastKey(key), entry;
  if(index != 'F')return that[O1][index];
  // frozen object case
  for(entry = that[FIRST]; entry; entry = entry.n){
    if(entry.k == key)return entry;
  }
}

module.exports = {
  getConstructor: function(NAME, IS_MAP, ADDER){
    function C(iterable){
      var that = assert.inst(this, C, NAME);
      set(that, O1, $.create(null));
      set(that, SIZE, 0);
      set(that, LAST, undefined);
      set(that, FIRST, undefined);
      if(iterable != undefined)$iter.forOf(iterable, IS_MAP, that[ADDER], that);
    }
    $.mix(C.prototype, {
      // 23.1.3.1 Map.prototype.clear()
      // 23.2.3.2 Set.prototype.clear()
      clear: function(){
        for(var that = this, data = that[O1], entry = that[FIRST]; entry; entry = entry.n){
          entry.r = true;
          if(entry.p)entry.p = entry.p.n = undefined;
          delete data[entry.i];
        }
        that[FIRST] = that[LAST] = undefined;
        that[SIZE] = 0;
      },
      // 23.1.3.3 Map.prototype.delete(key)
      // 23.2.3.4 Set.prototype.delete(value)
      'delete': function(key){
        var that  = this
          , entry = getEntry(that, key);
        if(entry){
          var next = entry.n
            , prev = entry.p;
          delete that[O1][entry.i];
          entry.r = true;
          if(prev)prev.n = next;
          if(next)next.p = prev;
          if(that[FIRST] == entry)that[FIRST] = next;
          if(that[LAST] == entry)that[LAST] = prev;
          that[SIZE]--;
        } return !!entry;
      },
      // 23.2.3.6 Set.prototype.forEach(callbackfn, thisArg = undefined)
      // 23.1.3.5 Map.prototype.forEach(callbackfn, thisArg = undefined)
      forEach: function(callbackfn /*, that = undefined */){
        var f = ctx(callbackfn, arguments[1], 3)
          , entry;
        while(entry = entry ? entry.n : this[FIRST]){
          f(entry.v, entry.k, this);
          // revert to the last existing entry
          while(entry && entry.r)entry = entry.p;
        }
      },
      // 23.1.3.7 Map.prototype.has(key)
      // 23.2.3.7 Set.prototype.has(value)
      has: function(key){
        return !!getEntry(this, key);
      }
    });
    if($.DESC)$.setDesc(C.prototype, 'size', {
      get: function(){
        return assert.def(this[SIZE]);
      }
    });
    return C;
  },
  def: function(that, key, value){
    var entry = getEntry(that, key)
      , prev, index;
    // change existing entry
    if(entry){
      entry.v = value;
    // create new entry
    } else {
      that[LAST] = entry = {
        i: index = fastKey(key, true), // <- index
        k: key,                        // <- key
        v: value,                      // <- value
        p: prev = that[LAST],          // <- previous entry
        n: undefined,                  // <- next entry
        r: false                       // <- removed
      };
      if(!that[FIRST])that[FIRST] = entry;
      if(prev)prev.n = entry;
      that[SIZE]++;
      // add to index
      if(index != 'F')that[O1][index] = entry;
    } return that;
  },
  getEntry: getEntry,
  getIterConstructor: function(){
    return function(iterated, kind){
      set(this, ITER, {o: iterated, k: kind});
    };
  },
  next: function(){
    var iter  = this[ITER]
      , kind  = iter.k
      , entry = iter.l;
    // revert to the last existing entry
    while(entry && entry.r)entry = entry.p;
    // get next entry
    if(!iter.o || !(iter.l = entry = entry ? entry.n : iter.o[FIRST])){
      // or finish the iteration
      iter.o = undefined;
      return step(1);
    }
    // return step by kind
    if(kind == 'key'  )return step(0, entry.k);
    if(kind == 'value')return step(0, entry.v);
    return step(0, [entry.k, entry.v]);
  }
};
},{"./$":31,"./$.assert":20,"./$.ctx":26,"./$.iter":30,"./$.uid":40}],24:[function(require,module,exports){
'use strict';
var $         = require('./$')
  , safe      = require('./$.uid').safe
  , assert    = require('./$.assert')
  , forOf     = require('./$.iter').forOf
  , has       = $.has
  , isObject  = $.isObject
  , hide      = $.hide
  , isFrozen  = Object.isFrozen || $.core.Object.isFrozen
  , id        = 0
  , ID        = safe('id')
  , WEAK      = safe('weak')
  , LEAK      = safe('leak')
  , method    = require('./$.array-methods')
  , find      = method(5)
  , findIndex = method(6);
function findFrozen(store, key){
  return find.call(store.array, function(it){
    return it[0] === key;
  });
}
// fallback for frozen keys
function leakStore(that){
  return that[LEAK] || hide(that, LEAK, {
    array: [],
    get: function(key){
      var entry = findFrozen(this, key);
      if(entry)return entry[1];
    },
    has: function(key){
      return !!findFrozen(this, key);
    },
    set: function(key, value){
      var entry = findFrozen(this, key);
      if(entry)entry[1] = value;
      else this.array.push([key, value]);
    },
    'delete': function(key){
      var index = findIndex.call(this.array, function(it){
        return it[0] === key;
      });
      if(~index)this.array.splice(index, 1);
      return !!~index;
    }
  })[LEAK];
}

module.exports = {
  getConstructor: function(NAME, IS_MAP, ADDER){
    function C(iterable){
      $.set(assert.inst(this, C, NAME), ID, id++);
      if(iterable != undefined)forOf(iterable, IS_MAP, this[ADDER], this);
    }
    $.mix(C.prototype, {
      // 23.3.3.2 WeakMap.prototype.delete(key)
      // 23.4.3.3 WeakSet.prototype.delete(value)
      'delete': function(key){
        if(!isObject(key))return false;
        if(isFrozen(key))return leakStore(this)['delete'](key);
        return has(key, WEAK) && has(key[WEAK], this[ID]) && delete key[WEAK][this[ID]];
      },
      // 23.3.3.4 WeakMap.prototype.has(key)
      // 23.4.3.4 WeakSet.prototype.has(value)
      has: function(key){
        if(!isObject(key))return false;
        if(isFrozen(key))return leakStore(this).has(key);
        return has(key, WEAK) && has(key[WEAK], this[ID]);
      }
    });
    return C;
  },
  def: function(that, key, value){
    if(isFrozen(assert.obj(key))){
      leakStore(that).set(key, value);
    } else {
      has(key, WEAK) || hide(key, WEAK, {});
      key[WEAK][that[ID]] = value;
    } return that;
  },
  leakStore: leakStore,
  WEAK: WEAK,
  ID: ID
};
},{"./$":31,"./$.array-methods":19,"./$.assert":20,"./$.iter":30,"./$.uid":40}],25:[function(require,module,exports){
'use strict';
var $     = require('./$')
  , $def  = require('./$.def')
  , $iter = require('./$.iter')
  , assertInstance = require('./$.assert').inst;

module.exports = function(NAME, methods, common, IS_MAP, isWeak){
  var Base  = $.g[NAME]
    , C     = Base
    , ADDER = IS_MAP ? 'set' : 'add'
    , proto = C && C.prototype
    , O     = {};
  function fixMethod(KEY, CHAIN){
    var method = proto[KEY];
    if($.FW)proto[KEY] = function(a, b){
      var result = method.call(this, a === 0 ? 0 : a, b);
      return CHAIN ? this : result;
    };
  }
  if(!$.isFunction(C) || !(isWeak || !$iter.BUGGY && proto.forEach && proto.entries)){
    // create collection constructor
    C = common.getConstructor(NAME, IS_MAP, ADDER);
    $.mix(C.prototype, methods);
  } else {
    var inst  = new C
      , chain = inst[ADDER](isWeak ? {} : -0, 1)
      , buggyZero;
    // wrap for init collections from iterable
    if($iter.fail(function(iter){
      new C(iter); // eslint-disable-line no-new
    }) || $iter.DANGER_CLOSING){
      C = function(iterable){
        assertInstance(this, C, NAME);
        var that = new Base;
        if(iterable != undefined)$iter.forOf(iterable, IS_MAP, that[ADDER], that);
        return that;
      };
      C.prototype = proto;
      if($.FW)proto.constructor = C;
    }
    isWeak || inst.forEach(function(val, key){
      buggyZero = 1 / key === -Infinity;
    });
    // fix converting -0 key to +0
    if(buggyZero){
      fixMethod('delete');
      fixMethod('has');
      IS_MAP && fixMethod('get');
    }
    // + fix .add & .set for chaining
    if(buggyZero || chain !== inst)fixMethod(ADDER, true);
  }

  require('./$.cof').set(C, NAME);
  require('./$.species')(C);

  O[NAME] = C;
  $def($def.G + $def.W + $def.F * (C != Base), O);

  // add .keys, .values, .entries, [@@iterator]
  // 23.1.3.4, 23.1.3.8, 23.1.3.11, 23.1.3.12, 23.2.3.5, 23.2.3.8, 23.2.3.10, 23.2.3.11
  if(!isWeak)$iter.std(
    C, NAME,
    common.getIterConstructor(), common.next,
    IS_MAP ? 'key+value' : 'value' , !IS_MAP, true
  );

  return C;
};
},{"./$":31,"./$.assert":20,"./$.cof":22,"./$.def":27,"./$.iter":30,"./$.species":37}],26:[function(require,module,exports){
// Optional / simple context binding
var assertFunction = require('./$.assert').fn;
module.exports = function(fn, that, length){
  assertFunction(fn);
  if(~length && that === undefined)return fn;
  switch(length){
    case 1: return function(a){
      return fn.call(that, a);
    };
    case 2: return function(a, b){
      return fn.call(that, a, b);
    };
    case 3: return function(a, b, c){
      return fn.call(that, a, b, c);
    };
  } return function(/* ...args */){
      return fn.apply(that, arguments);
    };
};
},{"./$.assert":20}],27:[function(require,module,exports){
var $          = require('./$')
  , global     = $.g
  , core       = $.core
  , isFunction = $.isFunction;
function ctx(fn, that){
  return function(){
    return fn.apply(that, arguments);
  };
}
global.core = core;
// type bitmap
$def.F = 1;  // forced
$def.G = 2;  // global
$def.S = 4;  // static
$def.P = 8;  // proto
$def.B = 16; // bind
$def.W = 32; // wrap
function $def(type, name, source){
  var key, own, out, exp
    , isGlobal = type & $def.G
    , target   = isGlobal ? global : type & $def.S
        ? global[name] : (global[name] || {}).prototype
    , exports  = isGlobal ? core : core[name] || (core[name] = {});
  if(isGlobal)source = name;
  for(key in source){
    // contains in native
    own = !(type & $def.F) && target && key in target;
    // export native or passed
    out = (own ? target : source)[key];
    // bind timers to global for call from export context
    if(type & $def.B && own)exp = ctx(out, global);
    else exp = type & $def.P && isFunction(out) ? ctx(Function.call, out) : out;
    // extend global
    if(target && !own){
      if(isGlobal)target[key] = out;
      else delete target[key] && $.hide(target, key, out);
    }
    // export
    if(exports[key] != out)$.hide(exports, key, exp);
  }
}
module.exports = $def;
},{"./$":31}],28:[function(require,module,exports){
module.exports = function($){
  $.FW   = true;
  $.path = $.g;
  return $;
};
},{}],29:[function(require,module,exports){
// Fast apply
// http://jsperf.lnkit.com/fast-apply/5
module.exports = function(fn, args, that){
  var un = that === undefined;
  switch(args.length){
    case 0: return un ? fn()
                      : fn.call(that);
    case 1: return un ? fn(args[0])
                      : fn.call(that, args[0]);
    case 2: return un ? fn(args[0], args[1])
                      : fn.call(that, args[0], args[1]);
    case 3: return un ? fn(args[0], args[1], args[2])
                      : fn.call(that, args[0], args[1], args[2]);
    case 4: return un ? fn(args[0], args[1], args[2], args[3])
                      : fn.call(that, args[0], args[1], args[2], args[3]);
    case 5: return un ? fn(args[0], args[1], args[2], args[3], args[4])
                      : fn.call(that, args[0], args[1], args[2], args[3], args[4]);
  } return              fn.apply(that, args);
};
},{}],30:[function(require,module,exports){
'use strict';
var $                 = require('./$')
  , ctx               = require('./$.ctx')
  , cof               = require('./$.cof')
  , $def              = require('./$.def')
  , assertObject      = require('./$.assert').obj
  , SYMBOL_ITERATOR   = require('./$.wks')('iterator')
  , FF_ITERATOR       = '@@iterator'
  , Iterators         = {}
  , IteratorPrototype = {};
// Safari has byggy iterators w/o `next`
var BUGGY = 'keys' in [] && !('next' in [].keys());
// 25.1.2.1.1 %IteratorPrototype%[@@iterator]()
setIterator(IteratorPrototype, $.that);
function setIterator(O, value){
  $.hide(O, SYMBOL_ITERATOR, value);
  // Add iterator for FF iterator protocol
  if(FF_ITERATOR in [])$.hide(O, FF_ITERATOR, value);
}
function defineIterator(Constructor, NAME, value, DEFAULT){
  var proto = Constructor.prototype
    , iter  = proto[SYMBOL_ITERATOR] || proto[FF_ITERATOR] || DEFAULT && proto[DEFAULT] || value;
  // Define iterator
  if($.FW)setIterator(proto, iter);
  if(iter !== value){
    var iterProto = $.getProto(iter.call(new Constructor));
    // Set @@toStringTag to native iterators
    cof.set(iterProto, NAME + ' Iterator', true);
    // FF fix
    if($.FW)$.has(proto, FF_ITERATOR) && setIterator(iterProto, $.that);
  }
  // Plug for library
  Iterators[NAME] = iter;
  // FF & v8 fix
  Iterators[NAME + ' Iterator'] = $.that;
  return iter;
}
function getIterator(it){
  var Symbol  = $.g.Symbol
    , ext     = it[Symbol && Symbol.iterator || FF_ITERATOR]
    , getIter = ext || it[SYMBOL_ITERATOR] || Iterators[cof.classof(it)];
  return assertObject(getIter.call(it));
}
function closeIterator(iterator){
  var ret = iterator['return'];
  if(ret !== undefined)assertObject(ret.call(iterator));
}
function stepCall(iterator, fn, value, entries){
  try {
    return entries ? fn(assertObject(value)[0], value[1]) : fn(value);
  } catch(e){
    closeIterator(iterator);
    throw e;
  }
}
var DANGER_CLOSING = true;
!function(){
  try {
    var iter = [1].keys();
    iter['return'] = function(){ DANGER_CLOSING = false; };
    Array.from(iter, function(){ throw 2; });
  } catch(e){ /* empty */ }
}();
var $iter = module.exports = {
  BUGGY: BUGGY,
  DANGER_CLOSING: DANGER_CLOSING,
  fail: function(exec){
    var fail = true;
    try {
      var arr  = [[{}, 1]]
        , iter = arr[SYMBOL_ITERATOR]()
        , next = iter.next;
      iter.next = function(){
        fail = false;
        return next.call(this);
      };
      arr[SYMBOL_ITERATOR] = function(){
        return iter;
      };
      exec(arr);
    } catch(e){ /* empty */ }
    return fail;
  },
  Iterators: Iterators,
  prototype: IteratorPrototype,
  step: function(done, value){
    return {value: value, done: !!done};
  },
  stepCall: stepCall,
  close: closeIterator,
  is: function(it){
    var O      = Object(it)
      , Symbol = $.g.Symbol
      , SYM    = Symbol && Symbol.iterator || FF_ITERATOR;
    return SYM in O || SYMBOL_ITERATOR in O || $.has(Iterators, cof.classof(O));
  },
  get: getIterator,
  set: setIterator,
  create: function(Constructor, NAME, next, proto){
    Constructor.prototype = $.create(proto || $iter.prototype, {next: $.desc(1, next)});
    cof.set(Constructor, NAME + ' Iterator');
  },
  define: defineIterator,
  std: function(Base, NAME, Constructor, next, DEFAULT, IS_SET, FORCE){
    function createIter(kind){
      return function(){
        return new Constructor(this, kind);
      };
    }
    $iter.create(Constructor, NAME, next);
    var entries = createIter('key+value')
      , values  = createIter('value')
      , proto   = Base.prototype
      , methods, key;
    if(DEFAULT == 'value')values = defineIterator(Base, NAME, values, 'values');
    else entries = defineIterator(Base, NAME, entries, 'entries');
    if(DEFAULT){
      methods = {
        entries: entries,
        keys:    IS_SET ? values : createIter('key'),
        values:  values
      };
      $def($def.P + $def.F * BUGGY, NAME, methods);
      if(FORCE)for(key in methods){
        if(!(key in proto))$.hide(proto, key, methods[key]);
      }
    }
  },
  forOf: function(iterable, entries, fn, that){
    var iterator = getIterator(iterable)
      , f = ctx(fn, that, entries ? 2 : 1)
      , step;
    while(!(step = iterator.next()).done){
      if(stepCall(iterator, f, step.value, entries) === false){
        return closeIterator(iterator);
      }
    }
  }
};
},{"./$":31,"./$.assert":20,"./$.cof":22,"./$.ctx":26,"./$.def":27,"./$.wks":42}],31:[function(require,module,exports){
'use strict';
var global = typeof self != 'undefined' ? self : Function('return this')()
  , core   = {}
  , defineProperty = Object.defineProperty
  , hasOwnProperty = {}.hasOwnProperty
  , ceil  = Math.ceil
  , floor = Math.floor
  , max   = Math.max
  , min   = Math.min;
// The engine works fine with descriptors? Thank's IE8 for his funny defineProperty.
var DESC = !!function(){
  try {
    return defineProperty({}, 'a', {get: function(){ return 2; }}).a == 2;
  } catch(e){ /* empty */ }
}();
var hide = createDefiner(1);
// 7.1.4 ToInteger
function toInteger(it){
  return isNaN(it = +it) ? 0 : (it > 0 ? floor : ceil)(it);
}
function desc(bitmap, value){
  return {
    enumerable  : !(bitmap & 1),
    configurable: !(bitmap & 2),
    writable    : !(bitmap & 4),
    value       : value
  };
}
function simpleSet(object, key, value){
  object[key] = value;
  return object;
}
function createDefiner(bitmap){
  return DESC ? function(object, key, value){
    return $.setDesc(object, key, desc(bitmap, value)); // eslint-disable-line no-use-before-define
  } : simpleSet;
}

function isObject(it){
  return it !== null && (typeof it == 'object' || typeof it == 'function');
}
function isFunction(it){
  return typeof it == 'function';
}
function assertDefined(it){
  if(it == undefined)throw TypeError("Can't call method on  " + it);
  return it;
}

var $ = module.exports = require('./$.fw')({
  g: global,
  core: core,
  html: global.document && document.documentElement,
  // http://jsperf.com/core-js-isobject
  isObject:   isObject,
  isFunction: isFunction,
  it: function(it){
    return it;
  },
  that: function(){
    return this;
  },
  // 7.1.4 ToInteger
  toInteger: toInteger,
  // 7.1.15 ToLength
  toLength: function(it){
    return it > 0 ? min(toInteger(it), 0x1fffffffffffff) : 0; // pow(2, 53) - 1 == 9007199254740991
  },
  toIndex: function(index, length){
    index = toInteger(index);
    return index < 0 ? max(index + length, 0) : min(index, length);
  },
  has: function(it, key){
    return hasOwnProperty.call(it, key);
  },
  create:     Object.create,
  getProto:   Object.getPrototypeOf,
  DESC:       DESC,
  desc:       desc,
  getDesc:    Object.getOwnPropertyDescriptor,
  setDesc:    defineProperty,
  getKeys:    Object.keys,
  getNames:   Object.getOwnPropertyNames,
  getSymbols: Object.getOwnPropertySymbols,
  // Dummy, fix for not array-like ES3 string in es5 module
  assertDefined: assertDefined,
  ES5Object: Object,
  toObject: function(it){
    return $.ES5Object(assertDefined(it));
  },
  hide: hide,
  def: createDefiner(0),
  set: global.Symbol ? simpleSet : hide,
  mix: function(target, src){
    for(var key in src)hide(target, key, src[key]);
    return target;
  },
  each: [].forEach
});
if(typeof __e != 'undefined')__e = core;
if(typeof __g != 'undefined')__g = global;
},{"./$.fw":28}],32:[function(require,module,exports){
var $ = require('./$');
module.exports = function(object, el){
  var O      = $.toObject(object)
    , keys   = $.getKeys(O)
    , length = keys.length
    , index  = 0
    , key;
  while(length > index)if(O[key = keys[index++]] === el)return key;
};
},{"./$":31}],33:[function(require,module,exports){
var $            = require('./$')
  , assertObject = require('./$.assert').obj;
module.exports = function(it){
  assertObject(it);
  return $.getSymbols ? $.getNames(it).concat($.getSymbols(it)) : $.getNames(it);
};
},{"./$":31,"./$.assert":20}],34:[function(require,module,exports){
'use strict';
var $      = require('./$')
  , invoke = require('./$.invoke')
  , assertFunction = require('./$.assert').fn;
module.exports = function(/* ...pargs */){
  var fn     = assertFunction(this)
    , length = arguments.length
    , pargs  = Array(length)
    , i      = 0
    , _      = $.path._
    , holder = false;
  while(length > i)if((pargs[i] = arguments[i++]) === _)holder = true;
  return function(/* ...args */){
    var that    = this
      , _length = arguments.length
      , j = 0, k = 0, args;
    if(!holder && !_length)return invoke(fn, pargs, that);
    args = pargs.slice();
    if(holder)for(;length > j; j++)if(args[j] === _)args[j] = arguments[k++];
    while(_length > k)args.push(arguments[k++]);
    return invoke(fn, args, that);
  };
};
},{"./$":31,"./$.assert":20,"./$.invoke":29}],35:[function(require,module,exports){
'use strict';
module.exports = function(regExp, replace, isStatic){
  var replacer = replace === Object(replace) ? function(part){
    return replace[part];
  } : replace;
  return function(it){
    return String(isStatic ? it : this).replace(regExp, replacer);
  };
};
},{}],36:[function(require,module,exports){
// Works with __proto__ only. Old v8 can't works with null proto objects.
/*eslint-disable no-proto */
var $      = require('./$')
  , assert = require('./$.assert');
module.exports = Object.setPrototypeOf || ('__proto__' in {} // eslint-disable-line
  ? function(buggy, set){
      try {
        set = require('./$.ctx')(Function.call, $.getDesc(Object.prototype, '__proto__').set, 2);
        set({}, []);
      } catch(e){ buggy = true; }
      return function(O, proto){
        assert.obj(O);
        assert(proto === null || $.isObject(proto), proto, ": can't set as prototype!");
        if(buggy)O.__proto__ = proto;
        else set(O, proto);
        return O;
      };
    }()
  : undefined);
},{"./$":31,"./$.assert":20,"./$.ctx":26}],37:[function(require,module,exports){
var $ = require('./$');
module.exports = function(C){
  if($.DESC && $.FW)$.setDesc(C, require('./$.wks')('species'), {
    configurable: true,
    get: $.that
  });
};
},{"./$":31,"./$.wks":42}],38:[function(require,module,exports){
'use strict';
// true  -> String#at
// false -> String#codePointAt
var $ = require('./$');
module.exports = function(TO_STRING){
  return function(pos){
    var s = String($.assertDefined(this))
      , i = $.toInteger(pos)
      , l = s.length
      , a, b;
    if(i < 0 || i >= l)return TO_STRING ? '' : undefined;
    a = s.charCodeAt(i);
    return a < 0xd800 || a > 0xdbff || i + 1 === l
      || (b = s.charCodeAt(i + 1)) < 0xdc00 || b > 0xdfff
        ? TO_STRING ? s.charAt(i) : a
        : TO_STRING ? s.slice(i, i + 2) : (a - 0xd800 << 10) + (b - 0xdc00) + 0x10000;
  };
};
},{"./$":31}],39:[function(require,module,exports){
'use strict';
var $      = require('./$')
  , ctx    = require('./$.ctx')
  , cof    = require('./$.cof')
  , invoke = require('./$.invoke')
  , global             = $.g
  , isFunction         = $.isFunction
  , setTask            = global.setImmediate
  , clearTask          = global.clearImmediate
  , postMessage        = global.postMessage
  , addEventListener   = global.addEventListener
  , MessageChannel     = global.MessageChannel
  , counter            = 0
  , queue              = {}
  , ONREADYSTATECHANGE = 'onreadystatechange'
  , defer, channel, port;
function run(){
  var id = +this;
  if($.has(queue, id)){
    var fn = queue[id];
    delete queue[id];
    fn();
  }
}
function listner(event){
  run.call(event.data);
}
// Node.js 0.9+ & IE10+ has setImmediate, otherwise:
if(!isFunction(setTask) || !isFunction(clearTask)){
  setTask = function(fn){
    var args = [], i = 1;
    while(arguments.length > i)args.push(arguments[i++]);
    queue[++counter] = function(){
      invoke(isFunction(fn) ? fn : Function(fn), args);
    };
    defer(counter);
    return counter;
  };
  clearTask = function(id){
    delete queue[id];
  };
  // Node.js 0.8-
  if(cof(global.process) == 'process'){
    defer = function(id){
      global.process.nextTick(ctx(run, id, 1));
    };
  // Modern browsers, skip implementation for WebWorkers
  // IE8 has postMessage, but it's sync & typeof its postMessage is object
  } else if(addEventListener && isFunction(postMessage) && !$.g.importScripts){
    defer = function(id){
      postMessage(id, '*');
    };
    addEventListener('message', listner, false);
  // WebWorkers
  } else if(isFunction(MessageChannel)){
    channel = new MessageChannel;
    port    = channel.port2;
    channel.port1.onmessage = listner;
    defer = ctx(port.postMessage, port, 1);
  // IE8-
  } else if($.g.document && ONREADYSTATECHANGE in document.createElement('script')){
    defer = function(id){
      $.html.appendChild(document.createElement('script'))[ONREADYSTATECHANGE] = function(){
        $.html.removeChild(this);
        run.call(id);
      };
    };
  // Rest old browsers
  } else {
    defer = function(id){
      setTimeout(ctx(run, id, 1), 0);
    };
  }
}
module.exports = {
  set:   setTask,
  clear: clearTask
};
},{"./$":31,"./$.cof":22,"./$.ctx":26,"./$.invoke":29}],40:[function(require,module,exports){
var sid = 0;
function uid(key){
  return 'Symbol(' + key + ')_' + (++sid + Math.random()).toString(36);
}
uid.safe = require('./$').g.Symbol || uid;
module.exports = uid;
},{"./$":31}],41:[function(require,module,exports){
// 22.1.3.31 Array.prototype[@@unscopables]
var $           = require('./$')
  , UNSCOPABLES = require('./$.wks')('unscopables');
if($.FW && !(UNSCOPABLES in []))$.hide(Array.prototype, UNSCOPABLES, {});
module.exports = function(key){
  if($.FW)[][UNSCOPABLES][key] = true;
};
},{"./$":31,"./$.wks":42}],42:[function(require,module,exports){
var global = require('./$').g
  , store  = {};
module.exports = function(name){
  return store[name] || (store[name] =
    global.Symbol && global.Symbol[name] || require('./$.uid').safe('Symbol.' + name));
};
},{"./$":31,"./$.uid":40}],43:[function(require,module,exports){
var $                = require('./$')
  , cof              = require('./$.cof')
  , $def             = require('./$.def')
  , invoke           = require('./$.invoke')
  , arrayMethod      = require('./$.array-methods')
  , IE_PROTO         = require('./$.uid').safe('__proto__')
  , assert           = require('./$.assert')
  , assertObject     = assert.obj
  , ObjectProto      = Object.prototype
  , A                = []
  , slice            = A.slice
  , indexOf          = A.indexOf
  , classof          = cof.classof
  , defineProperties = Object.defineProperties
  , has              = $.has
  , defineProperty   = $.setDesc
  , getOwnDescriptor = $.getDesc
  , isFunction       = $.isFunction
  , toObject         = $.toObject
  , toLength         = $.toLength
  , IE8_DOM_DEFINE   = false;

if(!$.DESC){
  try {
    IE8_DOM_DEFINE = defineProperty(document.createElement('div'), 'x',
      {get: function(){ return 8; }}
    ).x == 8;
  } catch(e){ /* empty */ }
  $.setDesc = function(O, P, Attributes){
    if(IE8_DOM_DEFINE)try {
      return defineProperty(O, P, Attributes);
    } catch(e){ /* empty */ }
    if('get' in Attributes || 'set' in Attributes)throw TypeError('Accessors not supported!');
    if('value' in Attributes)assertObject(O)[P] = Attributes.value;
    return O;
  };
  $.getDesc = function(O, P){
    if(IE8_DOM_DEFINE)try {
      return getOwnDescriptor(O, P);
    } catch(e){ /* empty */ }
    if(has(O, P))return $.desc(!ObjectProto.propertyIsEnumerable.call(O, P), O[P]);
  };
  defineProperties = function(O, Properties){
    assertObject(O);
    var keys   = $.getKeys(Properties)
      , length = keys.length
      , i = 0
      , P;
    while(length > i)$.setDesc(O, P = keys[i++], Properties[P]);
    return O;
  };
}
$def($def.S + $def.F * !$.DESC, 'Object', {
  // 19.1.2.6 / 15.2.3.3 Object.getOwnPropertyDescriptor(O, P)
  getOwnPropertyDescriptor: $.getDesc,
  // 19.1.2.4 / 15.2.3.6 Object.defineProperty(O, P, Attributes)
  defineProperty: $.setDesc,
  // 19.1.2.3 / 15.2.3.7 Object.defineProperties(O, Properties)
  defineProperties: defineProperties
});

  // IE 8- don't enum bug keys
var keys1 = ('constructor,hasOwnProperty,isPrototypeOf,propertyIsEnumerable,' +
            'toLocaleString,toString,valueOf').split(',')
  // Additional keys for getOwnPropertyNames
  , keys2 = keys1.concat('length', 'prototype')
  , keysLen1 = keys1.length;

// Create object with `null` prototype: use iframe Object with cleared prototype
var createDict = function(){
  // Thrash, waste and sodomy: IE GC bug
  var iframe = document.createElement('iframe')
    , i      = keysLen1
    , iframeDocument;
  iframe.style.display = 'none';
  $.html.appendChild(iframe);
  iframe.src = 'javascript:'; // eslint-disable-line no-script-url
  // createDict = iframe.contentWindow.Object;
  // html.removeChild(iframe);
  iframeDocument = iframe.contentWindow.document;
  iframeDocument.open();
  iframeDocument.write('<script>document.F=Object</script>');
  iframeDocument.close();
  createDict = iframeDocument.F;
  while(i--)delete createDict.prototype[keys1[i]];
  return createDict();
};
function createGetKeys(names, length){
  return function(object){
    var O      = toObject(object)
      , i      = 0
      , result = []
      , key;
    for(key in O)if(key != IE_PROTO)has(O, key) && result.push(key);
    // Don't enum bug & hidden keys
    while(length > i)if(has(O, key = names[i++])){
      ~indexOf.call(result, key) || result.push(key);
    }
    return result;
  };
}
function isPrimitive(it){ return !$.isObject(it); }
function Empty(){}
$def($def.S, 'Object', {
  // 19.1.2.9 / 15.2.3.2 Object.getPrototypeOf(O)
  getPrototypeOf: $.getProto = $.getProto || function(O){
    O = Object(assert.def(O));
    if(has(O, IE_PROTO))return O[IE_PROTO];
    if(isFunction(O.constructor) && O instanceof O.constructor){
      return O.constructor.prototype;
    } return O instanceof Object ? ObjectProto : null;
  },
  // 19.1.2.7 / 15.2.3.4 Object.getOwnPropertyNames(O)
  getOwnPropertyNames: $.getNames = $.getNames || createGetKeys(keys2, keys2.length, true),
  // 19.1.2.2 / 15.2.3.5 Object.create(O [, Properties])
  create: $.create = $.create || function(O, /*?*/Properties){
    var result;
    if(O !== null){
      Empty.prototype = assertObject(O);
      result = new Empty();
      Empty.prototype = null;
      // add "__proto__" for Object.getPrototypeOf shim
      result[IE_PROTO] = O;
    } else result = createDict();
    return Properties === undefined ? result : defineProperties(result, Properties);
  },
  // 19.1.2.14 / 15.2.3.14 Object.keys(O)
  keys: $.getKeys = $.getKeys || createGetKeys(keys1, keysLen1, false),
  // 19.1.2.17 / 15.2.3.8 Object.seal(O)
  seal: $.it, // <- cap
  // 19.1.2.5 / 15.2.3.9 Object.freeze(O)
  freeze: $.it, // <- cap
  // 19.1.2.15 / 15.2.3.10 Object.preventExtensions(O)
  preventExtensions: $.it, // <- cap
  // 19.1.2.13 / 15.2.3.11 Object.isSealed(O)
  isSealed: isPrimitive, // <- cap
  // 19.1.2.12 / 15.2.3.12 Object.isFrozen(O)
  isFrozen: isPrimitive, // <- cap
  // 19.1.2.11 / 15.2.3.13 Object.isExtensible(O)
  isExtensible: $.isObject // <- cap
});

// 19.2.3.2 / 15.3.4.5 Function.prototype.bind(thisArg, args...)
$def($def.P, 'Function', {
  bind: function(that /*, args... */){
    var fn       = assert.fn(this)
      , partArgs = slice.call(arguments, 1);
    function bound(/* args... */){
      var args = partArgs.concat(slice.call(arguments));
      return invoke(fn, args, this instanceof bound ? $.create(fn.prototype) : that);
    }
    if(fn.prototype)bound.prototype = fn.prototype;
    return bound;
  }
});

// Fix for not array-like ES3 string
function arrayMethodFix(fn){
  return function(){
    return fn.apply($.ES5Object(this), arguments);
  };
}
if(!(0 in Object('z') && 'z'[0] == 'z')){
  $.ES5Object = function(it){
    return cof(it) == 'String' ? it.split('') : Object(it);
  };
}
$def($def.P + $def.F * ($.ES5Object != Object), 'Array', {
  slice: arrayMethodFix(slice),
  join: arrayMethodFix(A.join)
});

// 22.1.2.2 / 15.4.3.2 Array.isArray(arg)
$def($def.S, 'Array', {
  isArray: function(arg){
    return cof(arg) == 'Array';
  }
});
function createArrayReduce(isRight){
  return function(callbackfn, memo){
    assert.fn(callbackfn);
    var O      = toObject(this)
      , length = toLength(O.length)
      , index  = isRight ? length - 1 : 0
      , i      = isRight ? -1 : 1;
    if(arguments.length < 2)for(;;){
      if(index in O){
        memo = O[index];
        index += i;
        break;
      }
      index += i;
      assert(isRight ? index >= 0 : length > index, 'Reduce of empty array with no initial value');
    }
    for(;isRight ? index >= 0 : length > index; index += i)if(index in O){
      memo = callbackfn(memo, O[index], index, this);
    }
    return memo;
  };
}
$def($def.P, 'Array', {
  // 22.1.3.10 / 15.4.4.18 Array.prototype.forEach(callbackfn [, thisArg])
  forEach: $.each = $.each || arrayMethod(0),
  // 22.1.3.15 / 15.4.4.19 Array.prototype.map(callbackfn [, thisArg])
  map: arrayMethod(1),
  // 22.1.3.7 / 15.4.4.20 Array.prototype.filter(callbackfn [, thisArg])
  filter: arrayMethod(2),
  // 22.1.3.23 / 15.4.4.17 Array.prototype.some(callbackfn [, thisArg])
  some: arrayMethod(3),
  // 22.1.3.5 / 15.4.4.16 Array.prototype.every(callbackfn [, thisArg])
  every: arrayMethod(4),
  // 22.1.3.18 / 15.4.4.21 Array.prototype.reduce(callbackfn [, initialValue])
  reduce: createArrayReduce(false),
  // 22.1.3.19 / 15.4.4.22 Array.prototype.reduceRight(callbackfn [, initialValue])
  reduceRight: createArrayReduce(true),
  // 22.1.3.11 / 15.4.4.14 Array.prototype.indexOf(searchElement [, fromIndex])
  indexOf: indexOf = indexOf || require('./$.array-includes')(false),
  // 22.1.3.14 / 15.4.4.15 Array.prototype.lastIndexOf(searchElement [, fromIndex])
  lastIndexOf: function(el, fromIndex /* = @[*-1] */){
    var O      = toObject(this)
      , length = toLength(O.length)
      , index  = length - 1;
    if(arguments.length > 1)index = Math.min(index, $.toInteger(fromIndex));
    if(index < 0)index = toLength(length + index);
    for(;index >= 0; index--)if(index in O)if(O[index] === el)return index;
    return -1;
  }
});

// 21.1.3.25 / 15.5.4.20 String.prototype.trim()
$def($def.P, 'String', {trim: require('./$.replacer')(/^\s*([\s\S]*\S)?\s*$/, '$1')});

// 20.3.3.1 / 15.9.4.4 Date.now()
$def($def.S, 'Date', {now: function(){
  return +new Date;
}});

function lz(num){
  return num > 9 ? num : '0' + num;
}
// 20.3.4.36 / 15.9.5.43 Date.prototype.toISOString()
$def($def.P, 'Date', {toISOString: function(){
  if(!isFinite(this))throw RangeError('Invalid time value');
  var d = this
    , y = d.getUTCFullYear()
    , m = d.getUTCMilliseconds()
    , s = y < 0 ? '-' : y > 9999 ? '+' : '';
  return s + ('00000' + Math.abs(y)).slice(s ? -6 : -4) +
    '-' + lz(d.getUTCMonth() + 1) + '-' + lz(d.getUTCDate()) +
    'T' + lz(d.getUTCHours()) + ':' + lz(d.getUTCMinutes()) +
    ':' + lz(d.getUTCSeconds()) + '.' + (m > 99 ? m : '0' + lz(m)) + 'Z';
}});

if(classof(function(){ return arguments; }()) == 'Object')cof.classof = function(it){
  var tag = classof(it);
  return tag == 'Object' && isFunction(it.callee) ? 'Arguments' : tag;
};
},{"./$":31,"./$.array-includes":18,"./$.array-methods":19,"./$.assert":20,"./$.cof":22,"./$.def":27,"./$.invoke":29,"./$.replacer":35,"./$.uid":40}],44:[function(require,module,exports){
'use strict';
var $       = require('./$')
  , $def    = require('./$.def')
  , toIndex = $.toIndex;
$def($def.P, 'Array', {
  // 22.1.3.3 Array.prototype.copyWithin(target, start, end = this.length)
  copyWithin: function(target/* = 0 */, start /* = 0, end = @length */){
    var O     = Object($.assertDefined(this))
      , len   = $.toLength(O.length)
      , to    = toIndex(target, len)
      , from  = toIndex(start, len)
      , end   = arguments[2]
      , fin   = end === undefined ? len : toIndex(end, len)
      , count = Math.min(fin - from, len - to)
      , inc   = 1;
    if(from < to && to < from + count){
      inc  = -1;
      from = from + count - 1;
      to   = to   + count - 1;
    }
    while(count-- > 0){
      if(from in O)O[to] = O[from];
      else delete O[to];
      to   += inc;
      from += inc;
    } return O;
  }
});
require('./$.unscope')('copyWithin');
},{"./$":31,"./$.def":27,"./$.unscope":41}],45:[function(require,module,exports){
'use strict';
var $       = require('./$')
  , $def    = require('./$.def')
  , toIndex = $.toIndex;
$def($def.P, 'Array', {
  // 22.1.3.6 Array.prototype.fill(value, start = 0, end = this.length)
  fill: function(value /*, start = 0, end = @length */){
    var O      = Object($.assertDefined(this))
      , length = $.toLength(O.length)
      , index  = toIndex(arguments[1], length)
      , end    = arguments[2]
      , endPos = end === undefined ? length : toIndex(end, length);
    while(endPos > index)O[index++] = value;
    return O;
  }
});
require('./$.unscope')('fill');
},{"./$":31,"./$.def":27,"./$.unscope":41}],46:[function(require,module,exports){
var $def = require('./$.def');
$def($def.P, 'Array', {
  // 22.1.3.9 Array.prototype.findIndex(predicate, thisArg = undefined)
  findIndex: require('./$.array-methods')(6)
});
require('./$.unscope')('findIndex');
},{"./$.array-methods":19,"./$.def":27,"./$.unscope":41}],47:[function(require,module,exports){
var $def = require('./$.def');
$def($def.P, 'Array', {
  // 22.1.3.8 Array.prototype.find(predicate, thisArg = undefined)
  find: require('./$.array-methods')(5)
});
require('./$.unscope')('find');
},{"./$.array-methods":19,"./$.def":27,"./$.unscope":41}],48:[function(require,module,exports){
var $     = require('./$')
  , ctx   = require('./$.ctx')
  , $def  = require('./$.def')
  , $iter = require('./$.iter')
  , stepCall = $iter.stepCall;
$def($def.S + $def.F * $iter.DANGER_CLOSING, 'Array', {
  // 22.1.2.1 Array.from(arrayLike, mapfn = undefined, thisArg = undefined)
  from: function(arrayLike/*, mapfn = undefined, thisArg = undefined*/){
    var O       = Object($.assertDefined(arrayLike))
      , mapfn   = arguments[1]
      , mapping = mapfn !== undefined
      , f       = mapping ? ctx(mapfn, arguments[2], 2) : undefined
      , index   = 0
      , length, result, step, iterator;
    if($iter.is(O)){
      iterator = $iter.get(O);
      // strange IE quirks mode bug -> use typeof instead of isFunction
      result   = new (typeof this == 'function' ? this : Array);
      for(; !(step = iterator.next()).done; index++){
        result[index] = mapping ? stepCall(iterator, f, [step.value, index], true) : step.value;
      }
    } else {
      // strange IE quirks mode bug -> use typeof instead of isFunction
      result = new (typeof this == 'function' ? this : Array)(length = $.toLength(O.length));
      for(; length > index; index++){
        result[index] = mapping ? f(O[index], index) : O[index];
      }
    }
    result.length = index;
    return result;
  }
});
},{"./$":31,"./$.ctx":26,"./$.def":27,"./$.iter":30}],49:[function(require,module,exports){
var $          = require('./$')
  , setUnscope = require('./$.unscope')
  , ITER       = require('./$.uid').safe('iter')
  , $iter      = require('./$.iter')
  , step       = $iter.step
  , Iterators  = $iter.Iterators;

// 22.1.3.4 Array.prototype.entries()
// 22.1.3.13 Array.prototype.keys()
// 22.1.3.29 Array.prototype.values()
// 22.1.3.30 Array.prototype[@@iterator]()
$iter.std(Array, 'Array', function(iterated, kind){
  $.set(this, ITER, {o: $.toObject(iterated), i: 0, k: kind});
// 22.1.5.2.1 %ArrayIteratorPrototype%.next()
}, function(){
  var iter  = this[ITER]
    , O     = iter.o
    , kind  = iter.k
    , index = iter.i++;
  if(!O || index >= O.length){
    iter.o = undefined;
    return step(1);
  }
  if(kind == 'key'  )return step(0, index);
  if(kind == 'value')return step(0, O[index]);
  return step(0, [index, O[index]]);
}, 'value');

// argumentsList[@@iterator] is %ArrayProto_values% (9.4.4.6, 9.4.4.7)
Iterators.Arguments = Iterators.Array;

setUnscope('keys');
setUnscope('values');
setUnscope('entries');
},{"./$":31,"./$.iter":30,"./$.uid":40,"./$.unscope":41}],50:[function(require,module,exports){
var $def = require('./$.def');
$def($def.S, 'Array', {
  // 22.1.2.3 Array.of( ...items)
  of: function(/* ...args */){
    var index  = 0
      , length = arguments.length
      // strange IE quirks mode bug -> use typeof instead of isFunction
      , result = new (typeof this == 'function' ? this : Array)(length);
    while(length > index)result[index] = arguments[index++];
    result.length = length;
    return result;
  }
});
},{"./$.def":27}],51:[function(require,module,exports){
require('./$.species')(Array);
},{"./$.species":37}],52:[function(require,module,exports){
'use strict';
var $    = require('./$')
  , NAME = 'name'
  , setDesc = $.setDesc
  , FunctionProto = Function.prototype;
// 19.2.4.2 name
NAME in FunctionProto || $.FW && $.DESC && setDesc(FunctionProto, NAME, {
  configurable: true,
  get: function(){
    var match = String(this).match(/^\s*function ([^ (]*)/)
      , name  = match ? match[1] : '';
    $.has(this, NAME) || setDesc(this, NAME, $.desc(5, name));
    return name;
  },
  set: function(value){
    $.has(this, NAME) || setDesc(this, NAME, $.desc(0, value));
  }
});
},{"./$":31}],53:[function(require,module,exports){
'use strict';
var strong = require('./$.collection-strong');

// 23.1 Map Objects
require('./$.collection')('Map', {
  // 23.1.3.6 Map.prototype.get(key)
  get: function(key){
    var entry = strong.getEntry(this, key);
    return entry && entry.v;
  },
  // 23.1.3.9 Map.prototype.set(key, value)
  set: function(key, value){
    return strong.def(this, key === 0 ? 0 : key, value);
  }
}, strong, true);
},{"./$.collection":25,"./$.collection-strong":23}],54:[function(require,module,exports){
var Infinity = 1 / 0
  , $def  = require('./$.def')
  , E     = Math.E
  , pow   = Math.pow
  , abs   = Math.abs
  , exp   = Math.exp
  , log   = Math.log
  , sqrt  = Math.sqrt
  , ceil  = Math.ceil
  , floor = Math.floor
  , sign  = Math.sign || function(x){
      return (x = +x) == 0 || x != x ? x : x < 0 ? -1 : 1;
    };

// 20.2.2.5 Math.asinh(x)
function asinh(x){
  return !isFinite(x = +x) || x == 0 ? x : x < 0 ? -asinh(-x) : log(x + sqrt(x * x + 1));
}
// 20.2.2.14 Math.expm1(x)
function expm1(x){
  return (x = +x) == 0 ? x : x > -1e-6 && x < 1e-6 ? x + x * x / 2 : exp(x) - 1;
}

$def($def.S, 'Math', {
  // 20.2.2.3 Math.acosh(x)
  acosh: function(x){
    return (x = +x) < 1 ? NaN : isFinite(x) ? log(x / E + sqrt(x + 1) * sqrt(x - 1) / E) + 1 : x;
  },
  // 20.2.2.5 Math.asinh(x)
  asinh: asinh,
  // 20.2.2.7 Math.atanh(x)
  atanh: function(x){
    return (x = +x) == 0 ? x : log((1 + x) / (1 - x)) / 2;
  },
  // 20.2.2.9 Math.cbrt(x)
  cbrt: function(x){
    return sign(x = +x) * pow(abs(x), 1 / 3);
  },
  // 20.2.2.11 Math.clz32(x)
  clz32: function(x){
    return (x >>>= 0) ? 32 - x.toString(2).length : 32;
  },
  // 20.2.2.12 Math.cosh(x)
  cosh: function(x){
    return (exp(x = +x) + exp(-x)) / 2;
  },
  // 20.2.2.14 Math.expm1(x)
  expm1: expm1,
  // 20.2.2.16 Math.fround(x)
  // TODO: fallback for IE9-
  fround: function(x){
    return new Float32Array([x])[0];
  },
  // 20.2.2.17 Math.hypot([value1[, value2[, … ]]])
  hypot: function(value1, value2){ // eslint-disable-line no-unused-vars
    var sum  = 0
      , len1 = arguments.length
      , len2 = len1
      , args = Array(len1)
      , larg = -Infinity
      , arg;
    while(len1--){
      arg = args[len1] = +arguments[len1];
      if(arg == Infinity || arg == -Infinity)return Infinity;
      if(arg > larg)larg = arg;
    }
    larg = arg || 1;
    while(len2--)sum += pow(args[len2] / larg, 2);
    return larg * sqrt(sum);
  },
  // 20.2.2.18 Math.imul(x, y)
  imul: function(x, y){
    var UInt16 = 0xffff
      , xn = +x
      , yn = +y
      , xl = UInt16 & xn
      , yl = UInt16 & yn;
    return 0 | xl * yl + ((UInt16 & xn >>> 16) * yl + xl * (UInt16 & yn >>> 16) << 16 >>> 0);
  },
  // 20.2.2.20 Math.log1p(x)
  log1p: function(x){
    return (x = +x) > -1e-8 && x < 1e-8 ? x - x * x / 2 : log(1 + x);
  },
  // 20.2.2.21 Math.log10(x)
  log10: function(x){
    return log(x) / Math.LN10;
  },
  // 20.2.2.22 Math.log2(x)
  log2: function(x){
    return log(x) / Math.LN2;
  },
  // 20.2.2.28 Math.sign(x)
  sign: sign,
  // 20.2.2.30 Math.sinh(x)
  sinh: function(x){
    return abs(x = +x) < 1 ? (expm1(x) - expm1(-x)) / 2 : (exp(x - 1) - exp(-x - 1)) * (E / 2);
  },
  // 20.2.2.33 Math.tanh(x)
  tanh: function(x){
    var a = expm1(x = +x)
      , b = expm1(-x);
    return a == Infinity ? 1 : b == Infinity ? -1 : (a - b) / (exp(x) + exp(-x));
  },
  // 20.2.2.34 Math.trunc(x)
  trunc: function(it){
    return (it > 0 ? floor : ceil)(it);
  }
});
},{"./$.def":27}],55:[function(require,module,exports){
'use strict';
var $          = require('./$')
  , isObject   = $.isObject
  , isFunction = $.isFunction
  , NUMBER     = 'Number'
  , Number     = $.g[NUMBER]
  , Base       = Number
  , proto      = Number.prototype;
function toPrimitive(it){
  var fn, val;
  if(isFunction(fn = it.valueOf) && !isObject(val = fn.call(it)))return val;
  if(isFunction(fn = it.toString) && !isObject(val = fn.call(it)))return val;
  throw TypeError("Can't convert object to number");
}
function toNumber(it){
  if(isObject(it))it = toPrimitive(it);
  if(typeof it == 'string' && it.length > 2 && it.charCodeAt(0) == 48){
    var binary = false;
    switch(it.charCodeAt(1)){
      case 66 : case 98  : binary = true;
      case 79 : case 111 : return parseInt(it.slice(2), binary ? 2 : 8);
    }
  } return +it;
}
if($.FW && !(Number('0o1') && Number('0b1'))){
  Number = function Number(it){
    return this instanceof Number ? new Base(toNumber(it)) : toNumber(it);
  };
  $.each.call($.DESC ? $.getNames(Base) : (
      // ES3:
      'MAX_VALUE,MIN_VALUE,NaN,NEGATIVE_INFINITY,POSITIVE_INFINITY,' +
      // ES6 (in case, if modules with ES6 Number statics required before):
      'EPSILON,isFinite,isInteger,isNaN,isSafeInteger,MAX_SAFE_INTEGER,' +
      'MIN_SAFE_INTEGER,parseFloat,parseInt,isInteger'
    ).split(','), function(key){
      if($.has(Base, key) && !$.has(Number, key)){
        $.setDesc(Number, key, $.getDesc(Base, key));
      }
    }
  );
  Number.prototype = proto;
  proto.constructor = Number;
  $.hide($.g, NUMBER, Number);
}
},{"./$":31}],56:[function(require,module,exports){
var $     = require('./$')
  , $def  = require('./$.def')
  , abs   = Math.abs
  , floor = Math.floor
  , MAX_SAFE_INTEGER = 0x1fffffffffffff; // pow(2, 53) - 1 == 9007199254740991;
function isInteger(it){
  return !$.isObject(it) && isFinite(it) && floor(it) === it;
}
$def($def.S, 'Number', {
  // 20.1.2.1 Number.EPSILON
  EPSILON: Math.pow(2, -52),
  // 20.1.2.2 Number.isFinite(number)
  isFinite: function(it){
    return typeof it == 'number' && isFinite(it);
  },
  // 20.1.2.3 Number.isInteger(number)
  isInteger: isInteger,
  // 20.1.2.4 Number.isNaN(number)
  isNaN: function(number){
    return number != number;
  },
  // 20.1.2.5 Number.isSafeInteger(number)
  isSafeInteger: function(number){
    return isInteger(number) && abs(number) <= MAX_SAFE_INTEGER;
  },
  // 20.1.2.6 Number.MAX_SAFE_INTEGER
  MAX_SAFE_INTEGER: MAX_SAFE_INTEGER,
  // 20.1.2.10 Number.MIN_SAFE_INTEGER
  MIN_SAFE_INTEGER: -MAX_SAFE_INTEGER,
  // 20.1.2.12 Number.parseFloat(string)
  parseFloat: parseFloat,
  // 20.1.2.13 Number.parseInt(string, radix)
  parseInt: parseInt
});
},{"./$":31,"./$.def":27}],57:[function(require,module,exports){
// 19.1.3.1 Object.assign(target, source)
var $def = require('./$.def');
$def($def.S, 'Object', {assign: require('./$.assign')});
},{"./$.assign":21,"./$.def":27}],58:[function(require,module,exports){
// 19.1.3.10 Object.is(value1, value2)
var $def = require('./$.def');
$def($def.S, 'Object', {
  is: function(x, y){
    return x === y ? x !== 0 || 1 / x === 1 / y : x != x && y != y;
  }
});
},{"./$.def":27}],59:[function(require,module,exports){
// 19.1.3.19 Object.setPrototypeOf(O, proto)
var $def = require('./$.def');
$def($def.S, 'Object', {setPrototypeOf: require('./$.set-proto')});
},{"./$.def":27,"./$.set-proto":36}],60:[function(require,module,exports){
var $        = require('./$')
  , $def     = require('./$.def')
  , isObject = $.isObject
  , toObject = $.toObject;
function wrapObjectMethod(METHOD, MODE){
  var fn  = ($.core.Object || {})[METHOD] || Object[METHOD]
    , f   = 0
    , o   = {};
  o[METHOD] = MODE == 1 ? function(it){
    return isObject(it) ? fn(it) : it;
  } : MODE == 2 ? function(it){
    return isObject(it) ? fn(it) : true;
  } : MODE == 3 ? function(it){
    return isObject(it) ? fn(it) : false;
  } : MODE == 4 ? function(it, key){
    return fn(toObject(it), key);
  } : MODE == 5 ? function(it){
    return fn(Object($.assertDefined(it)));
  } : function(it){
    return fn(toObject(it));
  };
  try {
    fn('z');
  } catch(e){
    f = 1;
  }
  $def($def.S + $def.F * f, 'Object', o);
}
wrapObjectMethod('freeze', 1);
wrapObjectMethod('seal', 1);
wrapObjectMethod('preventExtensions', 1);
wrapObjectMethod('isFrozen', 2);
wrapObjectMethod('isSealed', 2);
wrapObjectMethod('isExtensible', 3);
wrapObjectMethod('getOwnPropertyDescriptor', 4);
wrapObjectMethod('getPrototypeOf', 5);
wrapObjectMethod('keys');
wrapObjectMethod('getOwnPropertyNames');
},{"./$":31,"./$.def":27}],61:[function(require,module,exports){
'use strict';
// 19.1.3.6 Object.prototype.toString()
var $   = require('./$')
  , cof = require('./$.cof')
  , tmp = {};
tmp[require('./$.wks')('toStringTag')] = 'z';
if($.FW && cof(tmp) != 'z')$.hide(Object.prototype, 'toString', function(){
  return '[object ' + cof.classof(this) + ']';
});
},{"./$":31,"./$.cof":22,"./$.wks":42}],62:[function(require,module,exports){
'use strict';
var $       = require('./$')
  , ctx     = require('./$.ctx')
  , cof     = require('./$.cof')
  , $def    = require('./$.def')
  , assert  = require('./$.assert')
  , $iter   = require('./$.iter')
  , SPECIES = require('./$.wks')('species')
  , RECORD  = require('./$.uid').safe('record')
  , forOf   = $iter.forOf
  , PROMISE = 'Promise'
  , global  = $.g
  , process = global.process
  , asap    = process && process.nextTick || require('./$.task').set
  , Promise = global[PROMISE]
  , Base    = Promise
  , isFunction     = $.isFunction
  , isObject       = $.isObject
  , assertFunction = assert.fn
  , assertObject   = assert.obj
  , test;
function getConstructor(C){
  var S = assertObject(C)[SPECIES];
  return S != undefined ? S : C;
}
isFunction(Promise) && isFunction(Promise.resolve)
&& Promise.resolve(test = new Promise(function(){})) == test
|| function(){
  function isThenable(it){
    var then;
    if(isObject(it))then = it.then;
    return isFunction(then) ? then : false;
  }
  function handledRejectionOrHasOnRejected(promise){
    var record = promise[RECORD]
      , chain  = record.c
      , i      = 0
      , react;
    if(record.h)return true;
    while(chain.length > i){
      react = chain[i++];
      if(react.fail || handledRejectionOrHasOnRejected(react.P))return true;
    }
  }
  function notify(record, isReject){
    var chain = record.c;
    if(isReject || chain.length)asap(function(){
      var promise = record.p
        , value   = record.v
        , ok      = record.s == 1
        , i       = 0;
      if(isReject && !handledRejectionOrHasOnRejected(promise)){
        setTimeout(function(){
          if(!handledRejectionOrHasOnRejected(promise)){
            if(cof(process) == 'process'){
              process.emit('unhandledRejection', value, promise);
            } else if(global.console && isFunction(console.error)){
              console.error('Unhandled promise rejection', value);
            }
          }
        }, 1e3);
      } else while(chain.length > i)!function(react){
        var cb = ok ? react.ok : react.fail
          , ret, then;
        try {
          if(cb){
            if(!ok)record.h = true;
            ret = cb === true ? value : cb(value);
            if(ret === react.P){
              react.rej(TypeError(PROMISE + '-chain cycle'));
            } else if(then = isThenable(ret)){
              then.call(ret, react.res, react.rej);
            } else react.res(ret);
          } else react.rej(value);
        } catch(err){
          react.rej(err);
        }
      }(chain[i++]);
      chain.length = 0;
    });
  }
  function reject(value){
    var record = this;
    if(record.d)return;
    record.d = true;
    record = record.r || record; // unwrap
    record.v = value;
    record.s = 2;
    notify(record, true);
  }
  function resolve(value){
    var record = this
      , then, wrapper;
    if(record.d)return;
    record.d = true;
    record = record.r || record; // unwrap
    try {
      if(then = isThenable(value)){
        wrapper = {r: record, d: false}; // wrap
        then.call(value, ctx(resolve, wrapper, 1), ctx(reject, wrapper, 1));
      } else {
        record.v = value;
        record.s = 1;
        notify(record);
      }
    } catch(err){
      reject.call(wrapper || {r: record, d: false}, err); // wrap
    }
  }
  // 25.4.3.1 Promise(executor)
  Promise = function(executor){
    assertFunction(executor);
    var record = {
      p: assert.inst(this, Promise, PROMISE), // <- promise
      c: [],                                  // <- chain
      s: 0,                                   // <- state
      d: false,                               // <- done
      v: undefined,                           // <- value
      h: false                                // <- handled rejection
    };
    $.hide(this, RECORD, record);
    try {
      executor(ctx(resolve, record, 1), ctx(reject, record, 1));
    } catch(err){
      reject.call(record, err);
    }
  };
  $.mix(Promise.prototype, {
    // 25.4.5.3 Promise.prototype.then(onFulfilled, onRejected)
    then: function(onFulfilled, onRejected){
      var S = assertObject(assertObject(this).constructor)[SPECIES];
      var react = {
        ok:   isFunction(onFulfilled) ? onFulfilled : true,
        fail: isFunction(onRejected)  ? onRejected  : false
      };
      var P = react.P = new (S != undefined ? S : Promise)(function(res, rej){
        react.res = assertFunction(res);
        react.rej = assertFunction(rej);
      });
      var record = this[RECORD];
      record.c.push(react);
      record.s && notify(record);
      return P;
    },
    // 25.4.5.1 Promise.prototype.catch(onRejected)
    'catch': function(onRejected){
      return this.then(undefined, onRejected);
    }
  });
}();
$def($def.G + $def.W + $def.F * (Promise != Base), {Promise: Promise});
$def($def.S, PROMISE, {
  // 25.4.4.5 Promise.reject(r)
  reject: function(r){
    return new (getConstructor(this))(function(res, rej){
      rej(r);
    });
  },
  // 25.4.4.6 Promise.resolve(x)
  resolve: function(x){
    return isObject(x) && RECORD in x && $.getProto(x) === this.prototype
      ? x : new (getConstructor(this))(function(res){
        res(x);
      });
  }
});
$def($def.S + $def.F * ($iter.fail(function(iter){
  Promise.all(iter)['catch'](function(){});
}) || $iter.DANGER_CLOSING), PROMISE, {
  // 25.4.4.1 Promise.all(iterable)
  all: function(iterable){
    var C      = getConstructor(this)
      , values = [];
    return new C(function(resolve, reject){
      forOf(iterable, false, values.push, values);
      var remaining = values.length
        , results   = Array(remaining);
      if(remaining)$.each.call(values, function(promise, index){
        C.resolve(promise).then(function(value){
          results[index] = value;
          --remaining || resolve(results);
        }, reject);
      });
      else resolve(results);
    });
  },
  // 25.4.4.4 Promise.race(iterable)
  race: function(iterable){
    var C = getConstructor(this);
    return new C(function(resolve, reject){
      forOf(iterable, false, function(promise){
        C.resolve(promise).then(resolve, reject);
      });
    });
  }
});
cof.set(Promise, PROMISE);
require('./$.species')(Promise);
},{"./$":31,"./$.assert":20,"./$.cof":22,"./$.ctx":26,"./$.def":27,"./$.iter":30,"./$.species":37,"./$.task":39,"./$.uid":40,"./$.wks":42}],63:[function(require,module,exports){
var $         = require('./$')
  , $def      = require('./$.def')
  , setProto  = require('./$.set-proto')
  , $iter     = require('./$.iter')
  , ITER      = require('./$.uid').safe('iter')
  , step      = $iter.step
  , assert    = require('./$.assert')
  , isObject  = $.isObject
  , getDesc   = $.getDesc
  , setDesc   = $.setDesc
  , getProto  = $.getProto
  , apply     = Function.apply
  , assertObject = assert.obj
  , isExtensible = Object.isExtensible || $.it;
function Enumerate(iterated){
  var keys = [], key;
  for(key in iterated)keys.push(key);
  $.set(this, ITER, {o: iterated, a: keys, i: 0});
}
$iter.create(Enumerate, 'Object', function(){
  var iter = this[ITER]
    , keys = iter.a
    , key;
  do {
    if(iter.i >= keys.length)return step(1);
  } while(!((key = keys[iter.i++]) in iter.o));
  return step(0, key);
});

function wrap(fn){
  return function(it){
    assertObject(it);
    try {
      fn.apply(undefined, arguments);
      return true;
    } catch(e){
      return false;
    }
  };
}

function reflectGet(target, propertyKey/*, receiver*/){
  var receiver = arguments.length < 3 ? target : arguments[2]
    , desc = getDesc(assertObject(target), propertyKey), proto;
  if(desc)return $.has(desc, 'value')
    ? desc.value
    : desc.get === undefined
      ? undefined
      : desc.get.call(receiver);
  return isObject(proto = getProto(target))
    ? reflectGet(proto, propertyKey, receiver)
    : undefined;
}
function reflectSet(target, propertyKey, V/*, receiver*/){
  var receiver = arguments.length < 4 ? target : arguments[3]
    , ownDesc  = getDesc(assertObject(target), propertyKey)
    , existingDescriptor, proto;
  if(!ownDesc){
    if(isObject(proto = getProto(target))){
      return reflectSet(proto, propertyKey, V, receiver);
    }
    ownDesc = $.desc(0);
  }
  if($.has(ownDesc, 'value')){
    if(ownDesc.writable === false || !isObject(receiver))return false;
    existingDescriptor = getDesc(receiver, propertyKey) || $.desc(0);
    existingDescriptor.value = V;
    setDesc(receiver, propertyKey, existingDescriptor);
    return true;
  }
  return ownDesc.set === undefined ? false : (ownDesc.set.call(receiver, V), true);
}

var reflect = {
  // 26.1.1 Reflect.apply(target, thisArgument, argumentsList)
  apply: require('./$.ctx')(Function.call, apply, 3),
  // 26.1.2 Reflect.construct(target, argumentsList [, newTarget])
  construct: function(target, argumentsList /*, newTarget*/){
    var proto    = assert.fn(arguments.length < 3 ? target : arguments[2]).prototype
      , instance = $.create(isObject(proto) ? proto : Object.prototype)
      , result   = apply.call(target, instance, argumentsList);
    return isObject(result) ? result : instance;
  },
  // 26.1.3 Reflect.defineProperty(target, propertyKey, attributes)
  defineProperty: wrap(setDesc),
  // 26.1.4 Reflect.deleteProperty(target, propertyKey)
  deleteProperty: function(target, propertyKey){
    var desc = getDesc(assertObject(target), propertyKey);
    return desc && !desc.configurable ? false : delete target[propertyKey];
  },
  // 26.1.5 Reflect.enumerate(target)
  enumerate: function(target){
    return new Enumerate(assertObject(target));
  },
  // 26.1.6 Reflect.get(target, propertyKey [, receiver])
  get: reflectGet,
  // 26.1.7 Reflect.getOwnPropertyDescriptor(target, propertyKey)
  getOwnPropertyDescriptor: function(target, propertyKey){
    return getDesc(assertObject(target), propertyKey);
  },
  // 26.1.8 Reflect.getPrototypeOf(target)
  getPrototypeOf: function(target){
    return getProto(assertObject(target));
  },
  // 26.1.9 Reflect.has(target, propertyKey)
  has: function(target, propertyKey){
    return propertyKey in target;
  },
  // 26.1.10 Reflect.isExtensible(target)
  isExtensible: function(target){
    return !!isExtensible(assertObject(target));
  },
  // 26.1.11 Reflect.ownKeys(target)
  ownKeys: require('./$.own-keys'),
  // 26.1.12 Reflect.preventExtensions(target)
  preventExtensions: wrap(Object.preventExtensions || $.it),
  // 26.1.13 Reflect.set(target, propertyKey, V [, receiver])
  set: reflectSet
};
// 26.1.14 Reflect.setPrototypeOf(target, proto)
if(setProto)reflect.setPrototypeOf = function(target, proto){
  setProto(assertObject(target), proto);
  return true;
};

$def($def.G, {Reflect: {}});
$def($def.S, 'Reflect', reflect);
},{"./$":31,"./$.assert":20,"./$.ctx":26,"./$.def":27,"./$.iter":30,"./$.own-keys":33,"./$.set-proto":36,"./$.uid":40}],64:[function(require,module,exports){
var $      = require('./$')
  , cof    = require('./$.cof')
  , RegExp = $.g.RegExp
  , Base   = RegExp
  , proto  = RegExp.prototype;
if($.FW && $.DESC){
  // RegExp allows a regex with flags as the pattern
  if(!function(){try{ return RegExp(/a/g, 'i') == '/a/i'; }catch(e){ /* empty */ }}()){
    RegExp = function RegExp(pattern, flags){
      return new Base(cof(pattern) == 'RegExp' && flags !== undefined
        ? pattern.source : pattern, flags);
    };
    $.each.call($.getNames(Base), function(key){
      key in RegExp || $.setDesc(RegExp, key, {
        configurable: true,
        get: function(){ return Base[key]; },
        set: function(it){ Base[key] = it; }
      });
    });
    proto.constructor = RegExp;
    RegExp.prototype = proto;
    $.hide($.g, 'RegExp', RegExp);
  }
  // 21.2.5.3 get RegExp.prototype.flags()
  if(/./g.flags != 'g')$.setDesc(proto, 'flags', {
    configurable: true,
    get: require('./$.replacer')(/^.*\/(\w*)$/, '$1')
  });
}
require('./$.species')(RegExp);
},{"./$":31,"./$.cof":22,"./$.replacer":35,"./$.species":37}],65:[function(require,module,exports){
'use strict';
var strong = require('./$.collection-strong');

// 23.2 Set Objects
require('./$.collection')('Set', {
  // 23.2.3.1 Set.prototype.add(value)
  add: function(value){
    return strong.def(this, value = value === 0 ? 0 : value, value);
  }
}, strong);
},{"./$.collection":25,"./$.collection-strong":23}],66:[function(require,module,exports){
var $def = require('./$.def');
$def($def.P, 'String', {
  // 21.1.3.3 String.prototype.codePointAt(pos)
  codePointAt: require('./$.string-at')(false)
});
},{"./$.def":27,"./$.string-at":38}],67:[function(require,module,exports){
'use strict';
var $    = require('./$')
  , cof  = require('./$.cof')
  , $def = require('./$.def')
  , toLength = $.toLength;

$def($def.P, 'String', {
  // 21.1.3.6 String.prototype.endsWith(searchString [, endPosition])
  endsWith: function(searchString /*, endPosition = @length */){
    if(cof(searchString) == 'RegExp')throw TypeError();
    var that = String($.assertDefined(this))
      , endPosition = arguments[1]
      , len = toLength(that.length)
      , end = endPosition === undefined ? len : Math.min(toLength(endPosition), len);
    searchString += '';
    return that.slice(end - searchString.length, end) === searchString;
  }
});
},{"./$":31,"./$.cof":22,"./$.def":27}],68:[function(require,module,exports){
var $def    = require('./$.def')
  , toIndex = require('./$').toIndex
  , fromCharCode = String.fromCharCode;

$def($def.S, 'String', {
  // 21.1.2.2 String.fromCodePoint(...codePoints)
  fromCodePoint: function(x){ // eslint-disable-line no-unused-vars
    var res = []
      , len = arguments.length
      , i   = 0
      , code;
    while(len > i){
      code = +arguments[i++];
      if(toIndex(code, 0x10ffff) !== code)throw RangeError(code + ' is not a valid code point');
      res.push(code < 0x10000
        ? fromCharCode(code)
        : fromCharCode(((code -= 0x10000) >> 10) + 0xd800, code % 0x400 + 0xdc00)
      );
    } return res.join('');
  }
});
},{"./$":31,"./$.def":27}],69:[function(require,module,exports){
'use strict';
var $    = require('./$')
  , cof  = require('./$.cof')
  , $def = require('./$.def');

$def($def.P, 'String', {
  // 21.1.3.7 String.prototype.includes(searchString, position = 0)
  includes: function(searchString /*, position = 0 */){
    if(cof(searchString) == 'RegExp')throw TypeError();
    return !!~String($.assertDefined(this)).indexOf(searchString, arguments[1]);
  }
});
},{"./$":31,"./$.cof":22,"./$.def":27}],70:[function(require,module,exports){
var set   = require('./$').set
  , at    = require('./$.string-at')(true)
  , ITER  = require('./$.uid').safe('iter')
  , $iter = require('./$.iter')
  , step  = $iter.step;

// 21.1.3.27 String.prototype[@@iterator]()
$iter.std(String, 'String', function(iterated){
  set(this, ITER, {o: String(iterated), i: 0});
// 21.1.5.2.1 %StringIteratorPrototype%.next()
}, function(){
  var iter  = this[ITER]
    , O     = iter.o
    , index = iter.i
    , point;
  if(index >= O.length)return step(1);
  point = at.call(O, index);
  iter.i += point.length;
  return step(0, point);
});
},{"./$":31,"./$.iter":30,"./$.string-at":38,"./$.uid":40}],71:[function(require,module,exports){
var $    = require('./$')
  , $def = require('./$.def');

$def($def.S, 'String', {
  // 21.1.2.4 String.raw(callSite, ...substitutions)
  raw: function(callSite){
    var raw = $.toObject(callSite.raw)
      , len = $.toLength(raw.length)
      , sln = arguments.length
      , res = []
      , i   = 0;
    while(len > i){
      res.push(String(raw[i++]));
      if(i < sln)res.push(String(arguments[i]));
    } return res.join('');
  }
});
},{"./$":31,"./$.def":27}],72:[function(require,module,exports){
'use strict';
var $    = require('./$')
  , $def = require('./$.def');

$def($def.P, 'String', {
  // 21.1.3.13 String.prototype.repeat(count)
  repeat: function(count){
    var str = String($.assertDefined(this))
      , res = ''
      , n   = $.toInteger(count);
    if(n < 0 || n == Infinity)throw RangeError("Count can't be negative");
    for(;n > 0; (n >>>= 1) && (str += str))if(n & 1)res += str;
    return res;
  }
});
},{"./$":31,"./$.def":27}],73:[function(require,module,exports){
'use strict';
var $    = require('./$')
  , cof  = require('./$.cof')
  , $def = require('./$.def');

$def($def.P, 'String', {
  // 21.1.3.18 String.prototype.startsWith(searchString [, position ])
  startsWith: function(searchString /*, position = 0 */){
    if(cof(searchString) == 'RegExp')throw TypeError();
    var that  = String($.assertDefined(this))
      , index = $.toLength(Math.min(arguments[1], that.length));
    searchString += '';
    return that.slice(index, index + searchString.length) === searchString;
  }
});
},{"./$":31,"./$.cof":22,"./$.def":27}],74:[function(require,module,exports){
'use strict';
// ECMAScript 6 symbols shim
var $        = require('./$')
  , setTag   = require('./$.cof').set
  , uid      = require('./$.uid')
  , $def     = require('./$.def')
  , keyOf    = require('./$.keyof')
  , has      = $.has
  , hide     = $.hide
  , getNames = $.getNames
  , toObject = $.toObject
  , Symbol   = $.g.Symbol
  , Base     = Symbol
  , setter   = false
  , TAG      = uid.safe('tag')
  , SymbolRegistry = {}
  , AllSymbols     = {};

function wrap(tag){
  var sym = AllSymbols[tag] = $.set($.create(Symbol.prototype), TAG, tag);
  $.DESC && setter && $.setDesc(Object.prototype, tag, {
    configurable: true,
    set: function(value){
      hide(this, tag, value);
    }
  });
  return sym;
}

// 19.4.1.1 Symbol([description])
if(!$.isFunction(Symbol)){
  Symbol = function(description){
    if(this instanceof Symbol)throw TypeError('Symbol is not a constructor');
    return wrap(uid(description));
  };
  hide(Symbol.prototype, 'toString', function(){
    return this[TAG];
  });
}
$def($def.G + $def.W, {Symbol: Symbol});

var symbolStatics = {
  // 19.4.2.1 Symbol.for(key)
  'for': function(key){
    return has(SymbolRegistry, key += '')
      ? SymbolRegistry[key]
      : SymbolRegistry[key] = Symbol(key);
  },
  // 19.4.2.5 Symbol.keyFor(sym)
  keyFor: function(key){
    return keyOf(SymbolRegistry, key);
  },
  pure: uid.safe,
  set: $.set,
  useSetter: function(){ setter = true; },
  useSimple: function(){ setter = false; }
};
// 19.4.2.2 Symbol.hasInstance
// 19.4.2.3 Symbol.isConcatSpreadable
// 19.4.2.4 Symbol.iterator
// 19.4.2.6 Symbol.match
// 19.4.2.8 Symbol.replace
// 19.4.2.9 Symbol.search
// 19.4.2.10 Symbol.species
// 19.4.2.11 Symbol.split
// 19.4.2.12 Symbol.toPrimitive
// 19.4.2.13 Symbol.toStringTag
// 19.4.2.14 Symbol.unscopables
$.each.call((
    'hasInstance,isConcatSpreadable,iterator,match,replace,search,' +
    'species,split,toPrimitive,toStringTag,unscopables'
  ).split(','), function(it){
    var sym = require('./$.wks')(it);
    symbolStatics[it] = Symbol === Base ? sym : wrap(sym);
  }
);

setter = true;

$def($def.S, 'Symbol', symbolStatics);

$def($def.S + $def.F * (Symbol != Base), 'Object', {
  // 19.1.2.7 Object.getOwnPropertyNames(O)
  getOwnPropertyNames: function(it){
    var names = getNames(toObject(it)), result = [], key, i = 0;
    while(names.length > i)has(AllSymbols, key = names[i++]) || result.push(key);
    return result;
  },
  // 19.1.2.8 Object.getOwnPropertySymbols(O)
  getOwnPropertySymbols: function(it){
    var names = getNames(toObject(it)), result = [], key, i = 0;
    while(names.length > i)has(AllSymbols, key = names[i++]) && result.push(AllSymbols[key]);
    return result;
  }
});

setTag(Symbol, 'Symbol');
// 20.2.1.9 Math[@@toStringTag]
setTag(Math, 'Math', true);
// 24.3.3 JSON[@@toStringTag]
setTag($.g.JSON, 'JSON', true);
},{"./$":31,"./$.cof":22,"./$.def":27,"./$.keyof":32,"./$.uid":40,"./$.wks":42}],75:[function(require,module,exports){
'use strict';
var $         = require('./$')
  , weak      = require('./$.collection-weak')
  , leakStore = weak.leakStore
  , ID        = weak.ID
  , WEAK      = weak.WEAK
  , has       = $.has
  , isObject  = $.isObject
  , isFrozen  = Object.isFrozen || $.core.Object.isFrozen
  , tmp       = {};

// 23.3 WeakMap Objects
var WeakMap = require('./$.collection')('WeakMap', {
  // 23.3.3.3 WeakMap.prototype.get(key)
  get: function(key){
    if(isObject(key)){
      if(isFrozen(key))return leakStore(this).get(key);
      if(has(key, WEAK))return key[WEAK][this[ID]];
    }
  },
  // 23.3.3.5 WeakMap.prototype.set(key, value)
  set: function(key, value){
    return weak.def(this, key, value);
  }
}, weak, true, true);

// IE11 WeakMap frozen keys fix
if($.FW && new WeakMap().set((Object.freeze || Object)(tmp), 7).get(tmp) != 7){
  $.each.call(['delete', 'has', 'get', 'set'], function(key){
    var method = WeakMap.prototype[key];
    WeakMap.prototype[key] = function(a, b){
      // store frozen objects on leaky map
      if(isObject(a) && isFrozen(a)){
        var result = leakStore(this)[key](a, b);
        return key == 'set' ? this : result;
      // store all the rest on native weakmap
      } return method.call(this, a, b);
    };
  });
}
},{"./$":31,"./$.collection":25,"./$.collection-weak":24}],76:[function(require,module,exports){
'use strict';
var weak = require('./$.collection-weak');

// 23.4 WeakSet Objects
require('./$.collection')('WeakSet', {
  // 23.4.3.1 WeakSet.prototype.add(value)
  add: function(value){
    return weak.def(this, value, true);
  }
}, weak, false, true);
},{"./$.collection":25,"./$.collection-weak":24}],77:[function(require,module,exports){
// https://github.com/domenic/Array.prototype.includes
var $def = require('./$.def');
$def($def.P, 'Array', {
  includes: require('./$.array-includes')(true)
});
require('./$.unscope')('includes');
},{"./$.array-includes":18,"./$.def":27,"./$.unscope":41}],78:[function(require,module,exports){
// https://gist.github.com/WebReflection/9353781
var $       = require('./$')
  , $def    = require('./$.def')
  , ownKeys = require('./$.own-keys');

$def($def.S, 'Object', {
  getOwnPropertyDescriptors: function(object){
    var O      = $.toObject(object)
      , result = {};
    $.each.call(ownKeys(O), function(key){
      $.setDesc(result, key, $.desc(0, $.getDesc(O, key)));
    });
    return result;
  }
});
},{"./$":31,"./$.def":27,"./$.own-keys":33}],79:[function(require,module,exports){
// http://goo.gl/XkBrjD
var $    = require('./$')
  , $def = require('./$.def');
function createObjectToArray(isEntries){
  return function(object){
    var O      = $.toObject(object)
      , keys   = $.getKeys(object)
      , length = keys.length
      , i      = 0
      , result = Array(length)
      , key;
    if(isEntries)while(length > i)result[i] = [key = keys[i++], O[key]];
    else while(length > i)result[i] = O[keys[i++]];
    return result;
  };
}
$def($def.S, 'Object', {
  values:  createObjectToArray(false),
  entries: createObjectToArray(true)
});
},{"./$":31,"./$.def":27}],80:[function(require,module,exports){
// https://gist.github.com/kangax/9698100
var $def = require('./$.def');
$def($def.S, 'RegExp', {
  escape: require('./$.replacer')(/([\\\-[\]{}()*+?.,^$|])/g, '\\$1', true)
});
},{"./$.def":27,"./$.replacer":35}],81:[function(require,module,exports){
// https://github.com/mathiasbynens/String.prototype.at
var $def = require('./$.def');
$def($def.P, 'String', {
  at: require('./$.string-at')(true)
});
},{"./$.def":27,"./$.string-at":38}],82:[function(require,module,exports){
// JavaScript 1.6 / Strawman array statics shim
var $       = require('./$')
  , $def    = require('./$.def')
  , core    = $.core
  , statics = {};
function setStatics(keys, length){
  $.each.call(keys.split(','), function(key){
    if(length == undefined && key in core.Array)statics[key] = core.Array[key];
    else if(key in [])statics[key] = require('./$.ctx')(Function.call, [][key], length);
  });
}
setStatics('pop,reverse,shift,keys,values,entries', 1);
setStatics('indexOf,every,some,forEach,map,filter,find,findIndex,includes', 3);
setStatics('join,slice,concat,push,splice,unshift,sort,lastIndexOf,' +
           'reduce,reduceRight,copyWithin,fill,turn');
$def($def.S, 'Array', statics);
},{"./$":31,"./$.ctx":26,"./$.def":27}],83:[function(require,module,exports){
require('./es6.array.iterator');
var $         = require('./$')
  , Iterators = require('./$.iter').Iterators
  , ITERATOR  = require('./$.wks')('iterator')
  , NodeList  = $.g.NodeList;
if($.FW && NodeList && !(ITERATOR in NodeList.prototype)){
  $.hide(NodeList.prototype, ITERATOR, Iterators.Array);
}
Iterators.NodeList = Iterators.Array;
},{"./$":31,"./$.iter":30,"./$.wks":42,"./es6.array.iterator":49}],84:[function(require,module,exports){
var $def  = require('./$.def')
  , $task = require('./$.task');
$def($def.G + $def.B, {
  setImmediate:   $task.set,
  clearImmediate: $task.clear
});
},{"./$.def":27,"./$.task":39}],85:[function(require,module,exports){
// ie9- setTimeout & setInterval additional parameters fix
var $       = require('./$')
  , $def    = require('./$.def')
  , invoke  = require('./$.invoke')
  , partial = require('./$.partial')
  , MSIE    = !!$.g.navigator && /MSIE .\./.test(navigator.userAgent); // <- dirty ie9- check
function wrap(set){
  return MSIE ? function(fn, time /*, ...args */){
    return set(invoke(
      partial,
      [].slice.call(arguments, 2),
      $.isFunction(fn) ? fn : Function(fn)
    ), time);
  } : set;
}
$def($def.G + $def.B + $def.F * MSIE, {
  setTimeout:  wrap($.g.setTimeout),
  setInterval: wrap($.g.setInterval)
});
},{"./$":31,"./$.def":27,"./$.invoke":29,"./$.partial":34}],86:[function(require,module,exports){
require('./modules/es5');
require('./modules/es6.symbol');
require('./modules/es6.object.assign');
require('./modules/es6.object.is');
require('./modules/es6.object.set-prototype-of');
require('./modules/es6.object.to-string');
require('./modules/es6.object.statics-accept-primitives');
require('./modules/es6.function.name');
require('./modules/es6.number.constructor');
require('./modules/es6.number.statics');
require('./modules/es6.math');
require('./modules/es6.string.from-code-point');
require('./modules/es6.string.raw');
require('./modules/es6.string.iterator');
require('./modules/es6.string.code-point-at');
require('./modules/es6.string.ends-with');
require('./modules/es6.string.includes');
require('./modules/es6.string.repeat');
require('./modules/es6.string.starts-with');
require('./modules/es6.array.from');
require('./modules/es6.array.of');
require('./modules/es6.array.iterator');
require('./modules/es6.array.species');
require('./modules/es6.array.copy-within');
require('./modules/es6.array.fill');
require('./modules/es6.array.find');
require('./modules/es6.array.find-index');
require('./modules/es6.regexp');
require('./modules/es6.promise');
require('./modules/es6.map');
require('./modules/es6.set');
require('./modules/es6.weak-map');
require('./modules/es6.weak-set');
require('./modules/es6.reflect');
require('./modules/es7.array.includes');
require('./modules/es7.string.at');
require('./modules/es7.regexp.escape');
require('./modules/es7.object.get-own-property-descriptors');
require('./modules/es7.object.to-array');
require('./modules/js.array.statics');
require('./modules/web.timers');
require('./modules/web.immediate');
require('./modules/web.dom.iterable');
module.exports = require('./modules/$').core;
},{"./modules/$":31,"./modules/es5":43,"./modules/es6.array.copy-within":44,"./modules/es6.array.fill":45,"./modules/es6.array.find":47,"./modules/es6.array.find-index":46,"./modules/es6.array.from":48,"./modules/es6.array.iterator":49,"./modules/es6.array.of":50,"./modules/es6.array.species":51,"./modules/es6.function.name":52,"./modules/es6.map":53,"./modules/es6.math":54,"./modules/es6.number.constructor":55,"./modules/es6.number.statics":56,"./modules/es6.object.assign":57,"./modules/es6.object.is":58,"./modules/es6.object.set-prototype-of":59,"./modules/es6.object.statics-accept-primitives":60,"./modules/es6.object.to-string":61,"./modules/es6.promise":62,"./modules/es6.reflect":63,"./modules/es6.regexp":64,"./modules/es6.set":65,"./modules/es6.string.code-point-at":66,"./modules/es6.string.ends-with":67,"./modules/es6.string.from-code-point":68,"./modules/es6.string.includes":69,"./modules/es6.string.iterator":70,"./modules/es6.string.raw":71,"./modules/es6.string.repeat":72,"./modules/es6.string.starts-with":73,"./modules/es6.symbol":74,"./modules/es6.weak-map":75,"./modules/es6.weak-set":76,"./modules/es7.array.includes":77,"./modules/es7.object.get-own-property-descriptors":78,"./modules/es7.object.to-array":79,"./modules/es7.regexp.escape":80,"./modules/es7.string.at":81,"./modules/js.array.statics":82,"./modules/web.dom.iterable":83,"./modules/web.immediate":84,"./modules/web.timers":85}],87:[function(require,module,exports){
(function (global){
/**
 * Copyright (c) 2014, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * https://raw.github.com/facebook/regenerator/master/LICENSE file. An
 * additional grant of patent rights can be found in the PATENTS file in
 * the same directory.
 */

!(function(global) {
  "use strict";

  var hasOwn = Object.prototype.hasOwnProperty;
  var undefined; // More compressible than void 0.
  var iteratorSymbol =
    typeof Symbol === "function" && Symbol.iterator || "@@iterator";

  var inModule = typeof module === "object";
  var runtime = global.regeneratorRuntime;
  if (runtime) {
    if (inModule) {
      // If regeneratorRuntime is defined globally and we're in a module,
      // make the exports object identical to regeneratorRuntime.
      module.exports = runtime;
    }
    // Don't bother evaluating the rest of this file if the runtime was
    // already defined globally.
    return;
  }

  // Define the runtime globally (as expected by generated code) as either
  // module.exports (if we're in a module) or a new, empty object.
  runtime = global.regeneratorRuntime = inModule ? module.exports : {};

  function wrap(innerFn, outerFn, self, tryLocsList) {
    return new Generator(innerFn, outerFn, self || null, tryLocsList || []);
  }
  runtime.wrap = wrap;

  // Try/catch helper to minimize deoptimizations. Returns a completion
  // record like context.tryEntries[i].completion. This interface could
  // have been (and was previously) designed to take a closure to be
  // invoked without arguments, but in all the cases we care about we
  // already have an existing method we want to call, so there's no need
  // to create a new function object. We can even get away with assuming
  // the method takes exactly one argument, since that happens to be true
  // in every case, so we don't have to touch the arguments object. The
  // only additional allocation required is the completion record, which
  // has a stable shape and so hopefully should be cheap to allocate.
  function tryCatch(fn, obj, arg) {
    try {
      return { type: "normal", arg: fn.call(obj, arg) };
    } catch (err) {
      return { type: "throw", arg: err };
    }
  }

  var GenStateSuspendedStart = "suspendedStart";
  var GenStateSuspendedYield = "suspendedYield";
  var GenStateExecuting = "executing";
  var GenStateCompleted = "completed";

  // Returning this object from the innerFn has the same effect as
  // breaking out of the dispatch switch statement.
  var ContinueSentinel = {};

  // Dummy constructor functions that we use as the .constructor and
  // .constructor.prototype properties for functions that return Generator
  // objects. For full spec compliance, you may wish to configure your
  // minifier not to mangle the names of these two functions.
  function GeneratorFunction() {}
  function GeneratorFunctionPrototype() {}

  var Gp = GeneratorFunctionPrototype.prototype = Generator.prototype;
  GeneratorFunction.prototype = Gp.constructor = GeneratorFunctionPrototype;
  GeneratorFunctionPrototype.constructor = GeneratorFunction;
  GeneratorFunction.displayName = "GeneratorFunction";

  runtime.isGeneratorFunction = function(genFun) {
    var ctor = typeof genFun === "function" && genFun.constructor;
    return ctor
      ? ctor === GeneratorFunction ||
        // For the native GeneratorFunction constructor, the best we can
        // do is to check its .name property.
        (ctor.displayName || ctor.name) === "GeneratorFunction"
      : false;
  };

  runtime.mark = function(genFun) {
    genFun.__proto__ = GeneratorFunctionPrototype;
    genFun.prototype = Object.create(Gp);
    return genFun;
  };

  runtime.async = function(innerFn, outerFn, self, tryLocsList) {
    return new Promise(function(resolve, reject) {
      var generator = wrap(innerFn, outerFn, self, tryLocsList);
      var callNext = step.bind(generator.next);
      var callThrow = step.bind(generator["throw"]);

      function step(arg) {
        var record = tryCatch(this, null, arg);
        if (record.type === "throw") {
          reject(record.arg);
          return;
        }

        var info = record.arg;
        if (info.done) {
          resolve(info.value);
        } else {
          Promise.resolve(info.value).then(callNext, callThrow);
        }
      }

      callNext();
    });
  };

  function Generator(innerFn, outerFn, self, tryLocsList) {
    var generator = outerFn ? Object.create(outerFn.prototype) : this;
    var context = new Context(tryLocsList);
    var state = GenStateSuspendedStart;

    function invoke(method, arg) {
      if (state === GenStateExecuting) {
        throw new Error("Generator is already running");
      }

      if (state === GenStateCompleted) {
        // Be forgiving, per 25.3.3.3.3 of the spec:
        // https://people.mozilla.org/~jorendorff/es6-draft.html#sec-generatorresume
        return doneResult();
      }

      while (true) {
        var delegate = context.delegate;
        if (delegate) {
          var record = tryCatch(
            delegate.iterator[method],
            delegate.iterator,
            arg
          );

          if (record.type === "throw") {
            context.delegate = null;

            // Like returning generator.throw(uncaught), but without the
            // overhead of an extra function call.
            method = "throw";
            arg = record.arg;

            continue;
          }

          // Delegate generator ran and handled its own exceptions so
          // regardless of what the method was, we continue as if it is
          // "next" with an undefined arg.
          method = "next";
          arg = undefined;

          var info = record.arg;
          if (info.done) {
            context[delegate.resultName] = info.value;
            context.next = delegate.nextLoc;
          } else {
            state = GenStateSuspendedYield;
            return info;
          }

          context.delegate = null;
        }

        if (method === "next") {
          if (state === GenStateSuspendedStart &&
              typeof arg !== "undefined") {
            // https://people.mozilla.org/~jorendorff/es6-draft.html#sec-generatorresume
            throw new TypeError(
              "attempt to send " + JSON.stringify(arg) + " to newborn generator"
            );
          }

          if (state === GenStateSuspendedYield) {
            context.sent = arg;
          } else {
            delete context.sent;
          }

        } else if (method === "throw") {
          if (state === GenStateSuspendedStart) {
            state = GenStateCompleted;
            throw arg;
          }

          if (context.dispatchException(arg)) {
            // If the dispatched exception was caught by a catch block,
            // then let that catch block handle the exception normally.
            method = "next";
            arg = undefined;
          }

        } else if (method === "return") {
          context.abrupt("return", arg);
        }

        state = GenStateExecuting;

        var record = tryCatch(innerFn, self, context);
        if (record.type === "normal") {
          // If an exception is thrown from innerFn, we leave state ===
          // GenStateExecuting and loop back for another invocation.
          state = context.done
            ? GenStateCompleted
            : GenStateSuspendedYield;

          var info = {
            value: record.arg,
            done: context.done
          };

          if (record.arg === ContinueSentinel) {
            if (context.delegate && method === "next") {
              // Deliberately forget the last sent value so that we don't
              // accidentally pass it on to the delegate.
              arg = undefined;
            }
          } else {
            return info;
          }

        } else if (record.type === "throw") {
          state = GenStateCompleted;

          if (method === "next") {
            context.dispatchException(record.arg);
          } else {
            arg = record.arg;
          }
        }
      }
    }

    generator.next = invoke.bind(generator, "next");
    generator["throw"] = invoke.bind(generator, "throw");
    generator["return"] = invoke.bind(generator, "return");

    return generator;
  }

  Gp[iteratorSymbol] = function() {
    return this;
  };

  Gp.toString = function() {
    return "[object Generator]";
  };

  function pushTryEntry(locs) {
    var entry = { tryLoc: locs[0] };

    if (1 in locs) {
      entry.catchLoc = locs[1];
    }

    if (2 in locs) {
      entry.finallyLoc = locs[2];
      entry.afterLoc = locs[3];
    }

    this.tryEntries.push(entry);
  }

  function resetTryEntry(entry) {
    var record = entry.completion || {};
    record.type = "normal";
    delete record.arg;
    entry.completion = record;
  }

  function Context(tryLocsList) {
    // The root entry object (effectively a try statement without a catch
    // or a finally block) gives us a place to store values thrown from
    // locations where there is no enclosing try statement.
    this.tryEntries = [{ tryLoc: "root" }];
    tryLocsList.forEach(pushTryEntry, this);
    this.reset();
  }

  runtime.keys = function(object) {
    var keys = [];
    for (var key in object) {
      keys.push(key);
    }
    keys.reverse();

    // Rather than returning an object with a next method, we keep
    // things simple and return the next function itself.
    return function next() {
      while (keys.length) {
        var key = keys.pop();
        if (key in object) {
          next.value = key;
          next.done = false;
          return next;
        }
      }

      // To avoid creating an additional object, we just hang the .value
      // and .done properties off the next function object itself. This
      // also ensures that the minifier will not anonymize the function.
      next.done = true;
      return next;
    };
  };

  function values(iterable) {
    if (iterable) {
      var iteratorMethod = iterable[iteratorSymbol];
      if (iteratorMethod) {
        return iteratorMethod.call(iterable);
      }

      if (typeof iterable.next === "function") {
        return iterable;
      }

      if (!isNaN(iterable.length)) {
        var i = -1, next = function next() {
          while (++i < iterable.length) {
            if (hasOwn.call(iterable, i)) {
              next.value = iterable[i];
              next.done = false;
              return next;
            }
          }

          next.value = undefined;
          next.done = true;

          return next;
        };

        return next.next = next;
      }
    }

    // Return an iterator with no values.
    return { next: doneResult };
  }
  runtime.values = values;

  function doneResult() {
    return { value: undefined, done: true };
  }

  Context.prototype = {
    constructor: Context,

    reset: function() {
      this.prev = 0;
      this.next = 0;
      this.sent = undefined;
      this.done = false;
      this.delegate = null;

      this.tryEntries.forEach(resetTryEntry);

      // Pre-initialize at least 20 temporary variables to enable hidden
      // class optimizations for simple generators.
      for (var tempIndex = 0, tempName;
           hasOwn.call(this, tempName = "t" + tempIndex) || tempIndex < 20;
           ++tempIndex) {
        this[tempName] = null;
      }
    },

    stop: function() {
      this.done = true;

      var rootEntry = this.tryEntries[0];
      var rootRecord = rootEntry.completion;
      if (rootRecord.type === "throw") {
        throw rootRecord.arg;
      }

      return this.rval;
    },

    dispatchException: function(exception) {
      if (this.done) {
        throw exception;
      }

      var context = this;
      function handle(loc, caught) {
        record.type = "throw";
        record.arg = exception;
        context.next = loc;
        return !!caught;
      }

      for (var i = this.tryEntries.length - 1; i >= 0; --i) {
        var entry = this.tryEntries[i];
        var record = entry.completion;

        if (entry.tryLoc === "root") {
          // Exception thrown outside of any try block that could handle
          // it, so set the completion value of the entire function to
          // throw the exception.
          return handle("end");
        }

        if (entry.tryLoc <= this.prev) {
          var hasCatch = hasOwn.call(entry, "catchLoc");
          var hasFinally = hasOwn.call(entry, "finallyLoc");

          if (hasCatch && hasFinally) {
            if (this.prev < entry.catchLoc) {
              return handle(entry.catchLoc, true);
            } else if (this.prev < entry.finallyLoc) {
              return handle(entry.finallyLoc);
            }

          } else if (hasCatch) {
            if (this.prev < entry.catchLoc) {
              return handle(entry.catchLoc, true);
            }

          } else if (hasFinally) {
            if (this.prev < entry.finallyLoc) {
              return handle(entry.finallyLoc);
            }

          } else {
            throw new Error("try statement without catch or finally");
          }
        }
      }
    },

    abrupt: function(type, arg) {
      for (var i = this.tryEntries.length - 1; i >= 0; --i) {
        var entry = this.tryEntries[i];
        if (entry.tryLoc <= this.prev &&
            hasOwn.call(entry, "finallyLoc") &&
            this.prev < entry.finallyLoc) {
          var finallyEntry = entry;
          break;
        }
      }

      if (finallyEntry &&
          (type === "break" ||
           type === "continue") &&
          finallyEntry.tryLoc <= arg &&
          arg < finallyEntry.finallyLoc) {
        // Ignore the finally entry if control is not jumping to a
        // location outside the try/catch block.
        finallyEntry = null;
      }

      var record = finallyEntry ? finallyEntry.completion : {};
      record.type = type;
      record.arg = arg;

      if (finallyEntry) {
        this.next = finallyEntry.finallyLoc;
      } else {
        this.complete(record);
      }

      return ContinueSentinel;
    },

    complete: function(record, afterLoc) {
      if (record.type === "throw") {
        throw record.arg;
      }

      if (record.type === "break" ||
          record.type === "continue") {
        this.next = record.arg;
      } else if (record.type === "return") {
        this.rval = record.arg;
        this.next = "end";
      } else if (record.type === "normal" && afterLoc) {
        this.next = afterLoc;
      }

      return ContinueSentinel;
    },

    finish: function(finallyLoc) {
      for (var i = this.tryEntries.length - 1; i >= 0; --i) {
        var entry = this.tryEntries[i];
        if (entry.finallyLoc === finallyLoc) {
          return this.complete(entry.completion, entry.afterLoc);
        }
      }
    },

    "catch": function(tryLoc) {
      for (var i = this.tryEntries.length - 1; i >= 0; --i) {
        var entry = this.tryEntries[i];
        if (entry.tryLoc === tryLoc) {
          var record = entry.completion;
          if (record.type === "throw") {
            var thrown = record.arg;
            resetTryEntry(entry);
          }
          return thrown;
        }
      }

      // The context.catch method must only be called with a location
      // argument that corresponds to a known catch block.
      throw new Error("illegal catch attempt");
    },

    delegateYield: function(iterable, resultName, nextLoc) {
      this.delegate = {
        iterator: values(iterable),
        resultName: resultName,
        nextLoc: nextLoc
      };

      return ContinueSentinel;
    }
  };
})(
  // Among the various tricks for obtaining a reference to the global
  // object, this seems to be the most reliable technique that does not
  // use indirect eval (which violates Content Security Policy).
  typeof global === "object" ? global :
  typeof window === "object" ? window : this
);

}).call(this,typeof global !== "undefined" ? global : typeof self !== "undefined" ? self : typeof window !== "undefined" ? window : {})
//# sourceMappingURL=data:application/json;charset:utf-8;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvcmVnZW5lcmF0b3ItYmFiZWwvcnVudGltZS5qcyJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiO0FBQUE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0EiLCJmaWxlIjoiZ2VuZXJhdGVkLmpzIiwic291cmNlUm9vdCI6IiIsInNvdXJjZXNDb250ZW50IjpbIi8qKlxuICogQ29weXJpZ2h0IChjKSAyMDE0LCBGYWNlYm9vaywgSW5jLlxuICogQWxsIHJpZ2h0cyByZXNlcnZlZC5cbiAqXG4gKiBUaGlzIHNvdXJjZSBjb2RlIGlzIGxpY2Vuc2VkIHVuZGVyIHRoZSBCU0Qtc3R5bGUgbGljZW5zZSBmb3VuZCBpbiB0aGVcbiAqIGh0dHBzOi8vcmF3LmdpdGh1Yi5jb20vZmFjZWJvb2svcmVnZW5lcmF0b3IvbWFzdGVyL0xJQ0VOU0UgZmlsZS4gQW5cbiAqIGFkZGl0aW9uYWwgZ3JhbnQgb2YgcGF0ZW50IHJpZ2h0cyBjYW4gYmUgZm91bmQgaW4gdGhlIFBBVEVOVFMgZmlsZSBpblxuICogdGhlIHNhbWUgZGlyZWN0b3J5LlxuICovXG5cbiEoZnVuY3Rpb24oZ2xvYmFsKSB7XG4gIFwidXNlIHN0cmljdFwiO1xuXG4gIHZhciBoYXNPd24gPSBPYmplY3QucHJvdG90eXBlLmhhc093blByb3BlcnR5O1xuICB2YXIgdW5kZWZpbmVkOyAvLyBNb3JlIGNvbXByZXNzaWJsZSB0aGFuIHZvaWQgMC5cbiAgdmFyIGl0ZXJhdG9yU3ltYm9sID1cbiAgICB0eXBlb2YgU3ltYm9sID09PSBcImZ1bmN0aW9uXCIgJiYgU3ltYm9sLml0ZXJhdG9yIHx8IFwiQEBpdGVyYXRvclwiO1xuXG4gIHZhciBpbk1vZHVsZSA9IHR5cGVvZiBtb2R1bGUgPT09IFwib2JqZWN0XCI7XG4gIHZhciBydW50aW1lID0gZ2xvYmFsLnJlZ2VuZXJhdG9yUnVudGltZTtcbiAgaWYgKHJ1bnRpbWUpIHtcbiAgICBpZiAoaW5Nb2R1bGUpIHtcbiAgICAgIC8vIElmIHJlZ2VuZXJhdG9yUnVudGltZSBpcyBkZWZpbmVkIGdsb2JhbGx5IGFuZCB3ZSdyZSBpbiBhIG1vZHVsZSxcbiAgICAgIC8vIG1ha2UgdGhlIGV4cG9ydHMgb2JqZWN0IGlkZW50aWNhbCB0byByZWdlbmVyYXRvclJ1bnRpbWUuXG4gICAgICBtb2R1bGUuZXhwb3J0cyA9IHJ1bnRpbWU7XG4gICAgfVxuICAgIC8vIERvbid0IGJvdGhlciBldmFsdWF0aW5nIHRoZSByZXN0IG9mIHRoaXMgZmlsZSBpZiB0aGUgcnVudGltZSB3YXNcbiAgICAvLyBhbHJlYWR5IGRlZmluZWQgZ2xvYmFsbHkuXG4gICAgcmV0dXJuO1xuICB9XG5cbiAgLy8gRGVmaW5lIHRoZSBydW50aW1lIGdsb2JhbGx5IChhcyBleHBlY3RlZCBieSBnZW5lcmF0ZWQgY29kZSkgYXMgZWl0aGVyXG4gIC8vIG1vZHVsZS5leHBvcnRzIChpZiB3ZSdyZSBpbiBhIG1vZHVsZSkgb3IgYSBuZXcsIGVtcHR5IG9iamVjdC5cbiAgcnVudGltZSA9IGdsb2JhbC5yZWdlbmVyYXRvclJ1bnRpbWUgPSBpbk1vZHVsZSA/IG1vZHVsZS5leHBvcnRzIDoge307XG5cbiAgZnVuY3Rpb24gd3JhcChpbm5lckZuLCBvdXRlckZuLCBzZWxmLCB0cnlMb2NzTGlzdCkge1xuICAgIHJldHVybiBuZXcgR2VuZXJhdG9yKGlubmVyRm4sIG91dGVyRm4sIHNlbGYgfHwgbnVsbCwgdHJ5TG9jc0xpc3QgfHwgW10pO1xuICB9XG4gIHJ1bnRpbWUud3JhcCA9IHdyYXA7XG5cbiAgLy8gVHJ5L2NhdGNoIGhlbHBlciB0byBtaW5pbWl6ZSBkZW9wdGltaXphdGlvbnMuIFJldHVybnMgYSBjb21wbGV0aW9uXG4gIC8vIHJlY29yZCBsaWtlIGNvbnRleHQudHJ5RW50cmllc1tpXS5jb21wbGV0aW9uLiBUaGlzIGludGVyZmFjZSBjb3VsZFxuICAvLyBoYXZlIGJlZW4gKGFuZCB3YXMgcHJldmlvdXNseSkgZGVzaWduZWQgdG8gdGFrZSBhIGNsb3N1cmUgdG8gYmVcbiAgLy8gaW52b2tlZCB3aXRob3V0IGFyZ3VtZW50cywgYnV0IGluIGFsbCB0aGUgY2FzZXMgd2UgY2FyZSBhYm91dCB3ZVxuICAvLyBhbHJlYWR5IGhhdmUgYW4gZXhpc3RpbmcgbWV0aG9kIHdlIHdhbnQgdG8gY2FsbCwgc28gdGhlcmUncyBubyBuZWVkXG4gIC8vIHRvIGNyZWF0ZSBhIG5ldyBmdW5jdGlvbiBvYmplY3QuIFdlIGNhbiBldmVuIGdldCBhd2F5IHdpdGggYXNzdW1pbmdcbiAgLy8gdGhlIG1ldGhvZCB0YWtlcyBleGFjdGx5IG9uZSBhcmd1bWVudCwgc2luY2UgdGhhdCBoYXBwZW5zIHRvIGJlIHRydWVcbiAgLy8gaW4gZXZlcnkgY2FzZSwgc28gd2UgZG9uJ3QgaGF2ZSB0byB0b3VjaCB0aGUgYXJndW1lbnRzIG9iamVjdC4gVGhlXG4gIC8vIG9ubHkgYWRkaXRpb25hbCBhbGxvY2F0aW9uIHJlcXVpcmVkIGlzIHRoZSBjb21wbGV0aW9uIHJlY29yZCwgd2hpY2hcbiAgLy8gaGFzIGEgc3RhYmxlIHNoYXBlIGFuZCBzbyBob3BlZnVsbHkgc2hvdWxkIGJlIGNoZWFwIHRvIGFsbG9jYXRlLlxuICBmdW5jdGlvbiB0cnlDYXRjaChmbiwgb2JqLCBhcmcpIHtcbiAgICB0cnkge1xuICAgICAgcmV0dXJuIHsgdHlwZTogXCJub3JtYWxcIiwgYXJnOiBmbi5jYWxsKG9iaiwgYXJnKSB9O1xuICAgIH0gY2F0Y2ggKGVycikge1xuICAgICAgcmV0dXJuIHsgdHlwZTogXCJ0aHJvd1wiLCBhcmc6IGVyciB9O1xuICAgIH1cbiAgfVxuXG4gIHZhciBHZW5TdGF0ZVN1c3BlbmRlZFN0YXJ0ID0gXCJzdXNwZW5kZWRTdGFydFwiO1xuICB2YXIgR2VuU3RhdGVTdXNwZW5kZWRZaWVsZCA9IFwic3VzcGVuZGVkWWllbGRcIjtcbiAgdmFyIEdlblN0YXRlRXhlY3V0aW5nID0gXCJleGVjdXRpbmdcIjtcbiAgdmFyIEdlblN0YXRlQ29tcGxldGVkID0gXCJjb21wbGV0ZWRcIjtcblxuICAvLyBSZXR1cm5pbmcgdGhpcyBvYmplY3QgZnJvbSB0aGUgaW5uZXJGbiBoYXMgdGhlIHNhbWUgZWZmZWN0IGFzXG4gIC8vIGJyZWFraW5nIG91dCBvZiB0aGUgZGlzcGF0Y2ggc3dpdGNoIHN0YXRlbWVudC5cbiAgdmFyIENvbnRpbnVlU2VudGluZWwgPSB7fTtcblxuICAvLyBEdW1teSBjb25zdHJ1Y3RvciBmdW5jdGlvbnMgdGhhdCB3ZSB1c2UgYXMgdGhlIC5jb25zdHJ1Y3RvciBhbmRcbiAgLy8gLmNvbnN0cnVjdG9yLnByb3RvdHlwZSBwcm9wZXJ0aWVzIGZvciBmdW5jdGlvbnMgdGhhdCByZXR1cm4gR2VuZXJhdG9yXG4gIC8vIG9iamVjdHMuIEZvciBmdWxsIHNwZWMgY29tcGxpYW5jZSwgeW91IG1heSB3aXNoIHRvIGNvbmZpZ3VyZSB5b3VyXG4gIC8vIG1pbmlmaWVyIG5vdCB0byBtYW5nbGUgdGhlIG5hbWVzIG9mIHRoZXNlIHR3byBmdW5jdGlvbnMuXG4gIGZ1bmN0aW9uIEdlbmVyYXRvckZ1bmN0aW9uKCkge31cbiAgZnVuY3Rpb24gR2VuZXJhdG9yRnVuY3Rpb25Qcm90b3R5cGUoKSB7fVxuXG4gIHZhciBHcCA9IEdlbmVyYXRvckZ1bmN0aW9uUHJvdG90eXBlLnByb3RvdHlwZSA9IEdlbmVyYXRvci5wcm90b3R5cGU7XG4gIEdlbmVyYXRvckZ1bmN0aW9uLnByb3RvdHlwZSA9IEdwLmNvbnN0cnVjdG9yID0gR2VuZXJhdG9yRnVuY3Rpb25Qcm90b3R5cGU7XG4gIEdlbmVyYXRvckZ1bmN0aW9uUHJvdG90eXBlLmNvbnN0cnVjdG9yID0gR2VuZXJhdG9yRnVuY3Rpb247XG4gIEdlbmVyYXRvckZ1bmN0aW9uLmRpc3BsYXlOYW1lID0gXCJHZW5lcmF0b3JGdW5jdGlvblwiO1xuXG4gIHJ1bnRpbWUuaXNHZW5lcmF0b3JGdW5jdGlvbiA9IGZ1bmN0aW9uKGdlbkZ1bikge1xuICAgIHZhciBjdG9yID0gdHlwZW9mIGdlbkZ1biA9PT0gXCJmdW5jdGlvblwiICYmIGdlbkZ1bi5jb25zdHJ1Y3RvcjtcbiAgICByZXR1cm4gY3RvclxuICAgICAgPyBjdG9yID09PSBHZW5lcmF0b3JGdW5jdGlvbiB8fFxuICAgICAgICAvLyBGb3IgdGhlIG5hdGl2ZSBHZW5lcmF0b3JGdW5jdGlvbiBjb25zdHJ1Y3RvciwgdGhlIGJlc3Qgd2UgY2FuXG4gICAgICAgIC8vIGRvIGlzIHRvIGNoZWNrIGl0cyAubmFtZSBwcm9wZXJ0eS5cbiAgICAgICAgKGN0b3IuZGlzcGxheU5hbWUgfHwgY3Rvci5uYW1lKSA9PT0gXCJHZW5lcmF0b3JGdW5jdGlvblwiXG4gICAgICA6IGZhbHNlO1xuICB9O1xuXG4gIHJ1bnRpbWUubWFyayA9IGZ1bmN0aW9uKGdlbkZ1bikge1xuICAgIGdlbkZ1bi5fX3Byb3RvX18gPSBHZW5lcmF0b3JGdW5jdGlvblByb3RvdHlwZTtcbiAgICBnZW5GdW4ucHJvdG90eXBlID0gT2JqZWN0LmNyZWF0ZShHcCk7XG4gICAgcmV0dXJuIGdlbkZ1bjtcbiAgfTtcblxuICBydW50aW1lLmFzeW5jID0gZnVuY3Rpb24oaW5uZXJGbiwgb3V0ZXJGbiwgc2VsZiwgdHJ5TG9jc0xpc3QpIHtcbiAgICByZXR1cm4gbmV3IFByb21pc2UoZnVuY3Rpb24ocmVzb2x2ZSwgcmVqZWN0KSB7XG4gICAgICB2YXIgZ2VuZXJhdG9yID0gd3JhcChpbm5lckZuLCBvdXRlckZuLCBzZWxmLCB0cnlMb2NzTGlzdCk7XG4gICAgICB2YXIgY2FsbE5leHQgPSBzdGVwLmJpbmQoZ2VuZXJhdG9yLm5leHQpO1xuICAgICAgdmFyIGNhbGxUaHJvdyA9IHN0ZXAuYmluZChnZW5lcmF0b3JbXCJ0aHJvd1wiXSk7XG5cbiAgICAgIGZ1bmN0aW9uIHN0ZXAoYXJnKSB7XG4gICAgICAgIHZhciByZWNvcmQgPSB0cnlDYXRjaCh0aGlzLCBudWxsLCBhcmcpO1xuICAgICAgICBpZiAocmVjb3JkLnR5cGUgPT09IFwidGhyb3dcIikge1xuICAgICAgICAgIHJlamVjdChyZWNvcmQuYXJnKTtcbiAgICAgICAgICByZXR1cm47XG4gICAgICAgIH1cblxuICAgICAgICB2YXIgaW5mbyA9IHJlY29yZC5hcmc7XG4gICAgICAgIGlmIChpbmZvLmRvbmUpIHtcbiAgICAgICAgICByZXNvbHZlKGluZm8udmFsdWUpO1xuICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgIFByb21pc2UucmVzb2x2ZShpbmZvLnZhbHVlKS50aGVuKGNhbGxOZXh0LCBjYWxsVGhyb3cpO1xuICAgICAgICB9XG4gICAgICB9XG5cbiAgICAgIGNhbGxOZXh0KCk7XG4gICAgfSk7XG4gIH07XG5cbiAgZnVuY3Rpb24gR2VuZXJhdG9yKGlubmVyRm4sIG91dGVyRm4sIHNlbGYsIHRyeUxvY3NMaXN0KSB7XG4gICAgdmFyIGdlbmVyYXRvciA9IG91dGVyRm4gPyBPYmplY3QuY3JlYXRlKG91dGVyRm4ucHJvdG90eXBlKSA6IHRoaXM7XG4gICAgdmFyIGNvbnRleHQgPSBuZXcgQ29udGV4dCh0cnlMb2NzTGlzdCk7XG4gICAgdmFyIHN0YXRlID0gR2VuU3RhdGVTdXNwZW5kZWRTdGFydDtcblxuICAgIGZ1bmN0aW9uIGludm9rZShtZXRob2QsIGFyZykge1xuICAgICAgaWYgKHN0YXRlID09PSBHZW5TdGF0ZUV4ZWN1dGluZykge1xuICAgICAgICB0aHJvdyBuZXcgRXJyb3IoXCJHZW5lcmF0b3IgaXMgYWxyZWFkeSBydW5uaW5nXCIpO1xuICAgICAgfVxuXG4gICAgICBpZiAoc3RhdGUgPT09IEdlblN0YXRlQ29tcGxldGVkKSB7XG4gICAgICAgIC8vIEJlIGZvcmdpdmluZywgcGVyIDI1LjMuMy4zLjMgb2YgdGhlIHNwZWM6XG4gICAgICAgIC8vIGh0dHBzOi8vcGVvcGxlLm1vemlsbGEub3JnL35qb3JlbmRvcmZmL2VzNi1kcmFmdC5odG1sI3NlYy1nZW5lcmF0b3JyZXN1bWVcbiAgICAgICAgcmV0dXJuIGRvbmVSZXN1bHQoKTtcbiAgICAgIH1cblxuICAgICAgd2hpbGUgKHRydWUpIHtcbiAgICAgICAgdmFyIGRlbGVnYXRlID0gY29udGV4dC5kZWxlZ2F0ZTtcbiAgICAgICAgaWYgKGRlbGVnYXRlKSB7XG4gICAgICAgICAgdmFyIHJlY29yZCA9IHRyeUNhdGNoKFxuICAgICAgICAgICAgZGVsZWdhdGUuaXRlcmF0b3JbbWV0aG9kXSxcbiAgICAgICAgICAgIGRlbGVnYXRlLml0ZXJhdG9yLFxuICAgICAgICAgICAgYXJnXG4gICAgICAgICAgKTtcblxuICAgICAgICAgIGlmIChyZWNvcmQudHlwZSA9PT0gXCJ0aHJvd1wiKSB7XG4gICAgICAgICAgICBjb250ZXh0LmRlbGVnYXRlID0gbnVsbDtcblxuICAgICAgICAgICAgLy8gTGlrZSByZXR1cm5pbmcgZ2VuZXJhdG9yLnRocm93KHVuY2F1Z2h0KSwgYnV0IHdpdGhvdXQgdGhlXG4gICAgICAgICAgICAvLyBvdmVyaGVhZCBvZiBhbiBleHRyYSBmdW5jdGlvbiBjYWxsLlxuICAgICAgICAgICAgbWV0aG9kID0gXCJ0aHJvd1wiO1xuICAgICAgICAgICAgYXJnID0gcmVjb3JkLmFyZztcblxuICAgICAgICAgICAgY29udGludWU7XG4gICAgICAgICAgfVxuXG4gICAgICAgICAgLy8gRGVsZWdhdGUgZ2VuZXJhdG9yIHJhbiBhbmQgaGFuZGxlZCBpdHMgb3duIGV4Y2VwdGlvbnMgc29cbiAgICAgICAgICAvLyByZWdhcmRsZXNzIG9mIHdoYXQgdGhlIG1ldGhvZCB3YXMsIHdlIGNvbnRpbnVlIGFzIGlmIGl0IGlzXG4gICAgICAgICAgLy8gXCJuZXh0XCIgd2l0aCBhbiB1bmRlZmluZWQgYXJnLlxuICAgICAgICAgIG1ldGhvZCA9IFwibmV4dFwiO1xuICAgICAgICAgIGFyZyA9IHVuZGVmaW5lZDtcblxuICAgICAgICAgIHZhciBpbmZvID0gcmVjb3JkLmFyZztcbiAgICAgICAgICBpZiAoaW5mby5kb25lKSB7XG4gICAgICAgICAgICBjb250ZXh0W2RlbGVnYXRlLnJlc3VsdE5hbWVdID0gaW5mby52YWx1ZTtcbiAgICAgICAgICAgIGNvbnRleHQubmV4dCA9IGRlbGVnYXRlLm5leHRMb2M7XG4gICAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgIHN0YXRlID0gR2VuU3RhdGVTdXNwZW5kZWRZaWVsZDtcbiAgICAgICAgICAgIHJldHVybiBpbmZvO1xuICAgICAgICAgIH1cblxuICAgICAgICAgIGNvbnRleHQuZGVsZWdhdGUgPSBudWxsO1xuICAgICAgICB9XG5cbiAgICAgICAgaWYgKG1ldGhvZCA9PT0gXCJuZXh0XCIpIHtcbiAgICAgICAgICBpZiAoc3RhdGUgPT09IEdlblN0YXRlU3VzcGVuZGVkU3RhcnQgJiZcbiAgICAgICAgICAgICAgdHlwZW9mIGFyZyAhPT0gXCJ1bmRlZmluZWRcIikge1xuICAgICAgICAgICAgLy8gaHR0cHM6Ly9wZW9wbGUubW96aWxsYS5vcmcvfmpvcmVuZG9yZmYvZXM2LWRyYWZ0Lmh0bWwjc2VjLWdlbmVyYXRvcnJlc3VtZVxuICAgICAgICAgICAgdGhyb3cgbmV3IFR5cGVFcnJvcihcbiAgICAgICAgICAgICAgXCJhdHRlbXB0IHRvIHNlbmQgXCIgKyBKU09OLnN0cmluZ2lmeShhcmcpICsgXCIgdG8gbmV3Ym9ybiBnZW5lcmF0b3JcIlxuICAgICAgICAgICAgKTtcbiAgICAgICAgICB9XG5cbiAgICAgICAgICBpZiAoc3RhdGUgPT09IEdlblN0YXRlU3VzcGVuZGVkWWllbGQpIHtcbiAgICAgICAgICAgIGNvbnRleHQuc2VudCA9IGFyZztcbiAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgZGVsZXRlIGNvbnRleHQuc2VudDtcbiAgICAgICAgICB9XG5cbiAgICAgICAgfSBlbHNlIGlmIChtZXRob2QgPT09IFwidGhyb3dcIikge1xuICAgICAgICAgIGlmIChzdGF0ZSA9PT0gR2VuU3RhdGVTdXNwZW5kZWRTdGFydCkge1xuICAgICAgICAgICAgc3RhdGUgPSBHZW5TdGF0ZUNvbXBsZXRlZDtcbiAgICAgICAgICAgIHRocm93IGFyZztcbiAgICAgICAgICB9XG5cbiAgICAgICAgICBpZiAoY29udGV4dC5kaXNwYXRjaEV4Y2VwdGlvbihhcmcpKSB7XG4gICAgICAgICAgICAvLyBJZiB0aGUgZGlzcGF0Y2hlZCBleGNlcHRpb24gd2FzIGNhdWdodCBieSBhIGNhdGNoIGJsb2NrLFxuICAgICAgICAgICAgLy8gdGhlbiBsZXQgdGhhdCBjYXRjaCBibG9jayBoYW5kbGUgdGhlIGV4Y2VwdGlvbiBub3JtYWxseS5cbiAgICAgICAgICAgIG1ldGhvZCA9IFwibmV4dFwiO1xuICAgICAgICAgICAgYXJnID0gdW5kZWZpbmVkO1xuICAgICAgICAgIH1cblxuICAgICAgICB9IGVsc2UgaWYgKG1ldGhvZCA9PT0gXCJyZXR1cm5cIikge1xuICAgICAgICAgIGNvbnRleHQuYWJydXB0KFwicmV0dXJuXCIsIGFyZyk7XG4gICAgICAgIH1cblxuICAgICAgICBzdGF0ZSA9IEdlblN0YXRlRXhlY3V0aW5nO1xuXG4gICAgICAgIHZhciByZWNvcmQgPSB0cnlDYXRjaChpbm5lckZuLCBzZWxmLCBjb250ZXh0KTtcbiAgICAgICAgaWYgKHJlY29yZC50eXBlID09PSBcIm5vcm1hbFwiKSB7XG4gICAgICAgICAgLy8gSWYgYW4gZXhjZXB0aW9uIGlzIHRocm93biBmcm9tIGlubmVyRm4sIHdlIGxlYXZlIHN0YXRlID09PVxuICAgICAgICAgIC8vIEdlblN0YXRlRXhlY3V0aW5nIGFuZCBsb29wIGJhY2sgZm9yIGFub3RoZXIgaW52b2NhdGlvbi5cbiAgICAgICAgICBzdGF0ZSA9IGNvbnRleHQuZG9uZVxuICAgICAgICAgICAgPyBHZW5TdGF0ZUNvbXBsZXRlZFxuICAgICAgICAgICAgOiBHZW5TdGF0ZVN1c3BlbmRlZFlpZWxkO1xuXG4gICAgICAgICAgdmFyIGluZm8gPSB7XG4gICAgICAgICAgICB2YWx1ZTogcmVjb3JkLmFyZyxcbiAgICAgICAgICAgIGRvbmU6IGNvbnRleHQuZG9uZVxuICAgICAgICAgIH07XG5cbiAgICAgICAgICBpZiAocmVjb3JkLmFyZyA9PT0gQ29udGludWVTZW50aW5lbCkge1xuICAgICAgICAgICAgaWYgKGNvbnRleHQuZGVsZWdhdGUgJiYgbWV0aG9kID09PSBcIm5leHRcIikge1xuICAgICAgICAgICAgICAvLyBEZWxpYmVyYXRlbHkgZm9yZ2V0IHRoZSBsYXN0IHNlbnQgdmFsdWUgc28gdGhhdCB3ZSBkb24ndFxuICAgICAgICAgICAgICAvLyBhY2NpZGVudGFsbHkgcGFzcyBpdCBvbiB0byB0aGUgZGVsZWdhdGUuXG4gICAgICAgICAgICAgIGFyZyA9IHVuZGVmaW5lZDtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgcmV0dXJuIGluZm87XG4gICAgICAgICAgfVxuXG4gICAgICAgIH0gZWxzZSBpZiAocmVjb3JkLnR5cGUgPT09IFwidGhyb3dcIikge1xuICAgICAgICAgIHN0YXRlID0gR2VuU3RhdGVDb21wbGV0ZWQ7XG5cbiAgICAgICAgICBpZiAobWV0aG9kID09PSBcIm5leHRcIikge1xuICAgICAgICAgICAgY29udGV4dC5kaXNwYXRjaEV4Y2VwdGlvbihyZWNvcmQuYXJnKTtcbiAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgYXJnID0gcmVjb3JkLmFyZztcbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG5cbiAgICBnZW5lcmF0b3IubmV4dCA9IGludm9rZS5iaW5kKGdlbmVyYXRvciwgXCJuZXh0XCIpO1xuICAgIGdlbmVyYXRvcltcInRocm93XCJdID0gaW52b2tlLmJpbmQoZ2VuZXJhdG9yLCBcInRocm93XCIpO1xuICAgIGdlbmVyYXRvcltcInJldHVyblwiXSA9IGludm9rZS5iaW5kKGdlbmVyYXRvciwgXCJyZXR1cm5cIik7XG5cbiAgICByZXR1cm4gZ2VuZXJhdG9yO1xuICB9XG5cbiAgR3BbaXRlcmF0b3JTeW1ib2xdID0gZnVuY3Rpb24oKSB7XG4gICAgcmV0dXJuIHRoaXM7XG4gIH07XG5cbiAgR3AudG9TdHJpbmcgPSBmdW5jdGlvbigpIHtcbiAgICByZXR1cm4gXCJbb2JqZWN0IEdlbmVyYXRvcl1cIjtcbiAgfTtcblxuICBmdW5jdGlvbiBwdXNoVHJ5RW50cnkobG9jcykge1xuICAgIHZhciBlbnRyeSA9IHsgdHJ5TG9jOiBsb2NzWzBdIH07XG5cbiAgICBpZiAoMSBpbiBsb2NzKSB7XG4gICAgICBlbnRyeS5jYXRjaExvYyA9IGxvY3NbMV07XG4gICAgfVxuXG4gICAgaWYgKDIgaW4gbG9jcykge1xuICAgICAgZW50cnkuZmluYWxseUxvYyA9IGxvY3NbMl07XG4gICAgICBlbnRyeS5hZnRlckxvYyA9IGxvY3NbM107XG4gICAgfVxuXG4gICAgdGhpcy50cnlFbnRyaWVzLnB1c2goZW50cnkpO1xuICB9XG5cbiAgZnVuY3Rpb24gcmVzZXRUcnlFbnRyeShlbnRyeSkge1xuICAgIHZhciByZWNvcmQgPSBlbnRyeS5jb21wbGV0aW9uIHx8IHt9O1xuICAgIHJlY29yZC50eXBlID0gXCJub3JtYWxcIjtcbiAgICBkZWxldGUgcmVjb3JkLmFyZztcbiAgICBlbnRyeS5jb21wbGV0aW9uID0gcmVjb3JkO1xuICB9XG5cbiAgZnVuY3Rpb24gQ29udGV4dCh0cnlMb2NzTGlzdCkge1xuICAgIC8vIFRoZSByb290IGVudHJ5IG9iamVjdCAoZWZmZWN0aXZlbHkgYSB0cnkgc3RhdGVtZW50IHdpdGhvdXQgYSBjYXRjaFxuICAgIC8vIG9yIGEgZmluYWxseSBibG9jaykgZ2l2ZXMgdXMgYSBwbGFjZSB0byBzdG9yZSB2YWx1ZXMgdGhyb3duIGZyb21cbiAgICAvLyBsb2NhdGlvbnMgd2hlcmUgdGhlcmUgaXMgbm8gZW5jbG9zaW5nIHRyeSBzdGF0ZW1lbnQuXG4gICAgdGhpcy50cnlFbnRyaWVzID0gW3sgdHJ5TG9jOiBcInJvb3RcIiB9XTtcbiAgICB0cnlMb2NzTGlzdC5mb3JFYWNoKHB1c2hUcnlFbnRyeSwgdGhpcyk7XG4gICAgdGhpcy5yZXNldCgpO1xuICB9XG5cbiAgcnVudGltZS5rZXlzID0gZnVuY3Rpb24ob2JqZWN0KSB7XG4gICAgdmFyIGtleXMgPSBbXTtcbiAgICBmb3IgKHZhciBrZXkgaW4gb2JqZWN0KSB7XG4gICAgICBrZXlzLnB1c2goa2V5KTtcbiAgICB9XG4gICAga2V5cy5yZXZlcnNlKCk7XG5cbiAgICAvLyBSYXRoZXIgdGhhbiByZXR1cm5pbmcgYW4gb2JqZWN0IHdpdGggYSBuZXh0IG1ldGhvZCwgd2Uga2VlcFxuICAgIC8vIHRoaW5ncyBzaW1wbGUgYW5kIHJldHVybiB0aGUgbmV4dCBmdW5jdGlvbiBpdHNlbGYuXG4gICAgcmV0dXJuIGZ1bmN0aW9uIG5leHQoKSB7XG4gICAgICB3aGlsZSAoa2V5cy5sZW5ndGgpIHtcbiAgICAgICAgdmFyIGtleSA9IGtleXMucG9wKCk7XG4gICAgICAgIGlmIChrZXkgaW4gb2JqZWN0KSB7XG4gICAgICAgICAgbmV4dC52YWx1ZSA9IGtleTtcbiAgICAgICAgICBuZXh0LmRvbmUgPSBmYWxzZTtcbiAgICAgICAgICByZXR1cm4gbmV4dDtcbiAgICAgICAgfVxuICAgICAgfVxuXG4gICAgICAvLyBUbyBhdm9pZCBjcmVhdGluZyBhbiBhZGRpdGlvbmFsIG9iamVjdCwgd2UganVzdCBoYW5nIHRoZSAudmFsdWVcbiAgICAgIC8vIGFuZCAuZG9uZSBwcm9wZXJ0aWVzIG9mZiB0aGUgbmV4dCBmdW5jdGlvbiBvYmplY3QgaXRzZWxmLiBUaGlzXG4gICAgICAvLyBhbHNvIGVuc3VyZXMgdGhhdCB0aGUgbWluaWZpZXIgd2lsbCBub3QgYW5vbnltaXplIHRoZSBmdW5jdGlvbi5cbiAgICAgIG5leHQuZG9uZSA9IHRydWU7XG4gICAgICByZXR1cm4gbmV4dDtcbiAgICB9O1xuICB9O1xuXG4gIGZ1bmN0aW9uIHZhbHVlcyhpdGVyYWJsZSkge1xuICAgIGlmIChpdGVyYWJsZSkge1xuICAgICAgdmFyIGl0ZXJhdG9yTWV0aG9kID0gaXRlcmFibGVbaXRlcmF0b3JTeW1ib2xdO1xuICAgICAgaWYgKGl0ZXJhdG9yTWV0aG9kKSB7XG4gICAgICAgIHJldHVybiBpdGVyYXRvck1ldGhvZC5jYWxsKGl0ZXJhYmxlKTtcbiAgICAgIH1cblxuICAgICAgaWYgKHR5cGVvZiBpdGVyYWJsZS5uZXh0ID09PSBcImZ1bmN0aW9uXCIpIHtcbiAgICAgICAgcmV0dXJuIGl0ZXJhYmxlO1xuICAgICAgfVxuXG4gICAgICBpZiAoIWlzTmFOKGl0ZXJhYmxlLmxlbmd0aCkpIHtcbiAgICAgICAgdmFyIGkgPSAtMSwgbmV4dCA9IGZ1bmN0aW9uIG5leHQoKSB7XG4gICAgICAgICAgd2hpbGUgKCsraSA8IGl0ZXJhYmxlLmxlbmd0aCkge1xuICAgICAgICAgICAgaWYgKGhhc093bi5jYWxsKGl0ZXJhYmxlLCBpKSkge1xuICAgICAgICAgICAgICBuZXh0LnZhbHVlID0gaXRlcmFibGVbaV07XG4gICAgICAgICAgICAgIG5leHQuZG9uZSA9IGZhbHNlO1xuICAgICAgICAgICAgICByZXR1cm4gbmV4dDtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICB9XG5cbiAgICAgICAgICBuZXh0LnZhbHVlID0gdW5kZWZpbmVkO1xuICAgICAgICAgIG5leHQuZG9uZSA9IHRydWU7XG5cbiAgICAgICAgICByZXR1cm4gbmV4dDtcbiAgICAgICAgfTtcblxuICAgICAgICByZXR1cm4gbmV4dC5uZXh0ID0gbmV4dDtcbiAgICAgIH1cbiAgICB9XG5cbiAgICAvLyBSZXR1cm4gYW4gaXRlcmF0b3Igd2l0aCBubyB2YWx1ZXMuXG4gICAgcmV0dXJuIHsgbmV4dDogZG9uZVJlc3VsdCB9O1xuICB9XG4gIHJ1bnRpbWUudmFsdWVzID0gdmFsdWVzO1xuXG4gIGZ1bmN0aW9uIGRvbmVSZXN1bHQoKSB7XG4gICAgcmV0dXJuIHsgdmFsdWU6IHVuZGVmaW5lZCwgZG9uZTogdHJ1ZSB9O1xuICB9XG5cbiAgQ29udGV4dC5wcm90b3R5cGUgPSB7XG4gICAgY29uc3RydWN0b3I6IENvbnRleHQsXG5cbiAgICByZXNldDogZnVuY3Rpb24oKSB7XG4gICAgICB0aGlzLnByZXYgPSAwO1xuICAgICAgdGhpcy5uZXh0ID0gMDtcbiAgICAgIHRoaXMuc2VudCA9IHVuZGVmaW5lZDtcbiAgICAgIHRoaXMuZG9uZSA9IGZhbHNlO1xuICAgICAgdGhpcy5kZWxlZ2F0ZSA9IG51bGw7XG5cbiAgICAgIHRoaXMudHJ5RW50cmllcy5mb3JFYWNoKHJlc2V0VHJ5RW50cnkpO1xuXG4gICAgICAvLyBQcmUtaW5pdGlhbGl6ZSBhdCBsZWFzdCAyMCB0ZW1wb3JhcnkgdmFyaWFibGVzIHRvIGVuYWJsZSBoaWRkZW5cbiAgICAgIC8vIGNsYXNzIG9wdGltaXphdGlvbnMgZm9yIHNpbXBsZSBnZW5lcmF0b3JzLlxuICAgICAgZm9yICh2YXIgdGVtcEluZGV4ID0gMCwgdGVtcE5hbWU7XG4gICAgICAgICAgIGhhc093bi5jYWxsKHRoaXMsIHRlbXBOYW1lID0gXCJ0XCIgKyB0ZW1wSW5kZXgpIHx8IHRlbXBJbmRleCA8IDIwO1xuICAgICAgICAgICArK3RlbXBJbmRleCkge1xuICAgICAgICB0aGlzW3RlbXBOYW1lXSA9IG51bGw7XG4gICAgICB9XG4gICAgfSxcblxuICAgIHN0b3A6IGZ1bmN0aW9uKCkge1xuICAgICAgdGhpcy5kb25lID0gdHJ1ZTtcblxuICAgICAgdmFyIHJvb3RFbnRyeSA9IHRoaXMudHJ5RW50cmllc1swXTtcbiAgICAgIHZhciByb290UmVjb3JkID0gcm9vdEVudHJ5LmNvbXBsZXRpb247XG4gICAgICBpZiAocm9vdFJlY29yZC50eXBlID09PSBcInRocm93XCIpIHtcbiAgICAgICAgdGhyb3cgcm9vdFJlY29yZC5hcmc7XG4gICAgICB9XG5cbiAgICAgIHJldHVybiB0aGlzLnJ2YWw7XG4gICAgfSxcblxuICAgIGRpc3BhdGNoRXhjZXB0aW9uOiBmdW5jdGlvbihleGNlcHRpb24pIHtcbiAgICAgIGlmICh0aGlzLmRvbmUpIHtcbiAgICAgICAgdGhyb3cgZXhjZXB0aW9uO1xuICAgICAgfVxuXG4gICAgICB2YXIgY29udGV4dCA9IHRoaXM7XG4gICAgICBmdW5jdGlvbiBoYW5kbGUobG9jLCBjYXVnaHQpIHtcbiAgICAgICAgcmVjb3JkLnR5cGUgPSBcInRocm93XCI7XG4gICAgICAgIHJlY29yZC5hcmcgPSBleGNlcHRpb247XG4gICAgICAgIGNvbnRleHQubmV4dCA9IGxvYztcbiAgICAgICAgcmV0dXJuICEhY2F1Z2h0O1xuICAgICAgfVxuXG4gICAgICBmb3IgKHZhciBpID0gdGhpcy50cnlFbnRyaWVzLmxlbmd0aCAtIDE7IGkgPj0gMDsgLS1pKSB7XG4gICAgICAgIHZhciBlbnRyeSA9IHRoaXMudHJ5RW50cmllc1tpXTtcbiAgICAgICAgdmFyIHJlY29yZCA9IGVudHJ5LmNvbXBsZXRpb247XG5cbiAgICAgICAgaWYgKGVudHJ5LnRyeUxvYyA9PT0gXCJyb290XCIpIHtcbiAgICAgICAgICAvLyBFeGNlcHRpb24gdGhyb3duIG91dHNpZGUgb2YgYW55IHRyeSBibG9jayB0aGF0IGNvdWxkIGhhbmRsZVxuICAgICAgICAgIC8vIGl0LCBzbyBzZXQgdGhlIGNvbXBsZXRpb24gdmFsdWUgb2YgdGhlIGVudGlyZSBmdW5jdGlvbiB0b1xuICAgICAgICAgIC8vIHRocm93IHRoZSBleGNlcHRpb24uXG4gICAgICAgICAgcmV0dXJuIGhhbmRsZShcImVuZFwiKTtcbiAgICAgICAgfVxuXG4gICAgICAgIGlmIChlbnRyeS50cnlMb2MgPD0gdGhpcy5wcmV2KSB7XG4gICAgICAgICAgdmFyIGhhc0NhdGNoID0gaGFzT3duLmNhbGwoZW50cnksIFwiY2F0Y2hMb2NcIik7XG4gICAgICAgICAgdmFyIGhhc0ZpbmFsbHkgPSBoYXNPd24uY2FsbChlbnRyeSwgXCJmaW5hbGx5TG9jXCIpO1xuXG4gICAgICAgICAgaWYgKGhhc0NhdGNoICYmIGhhc0ZpbmFsbHkpIHtcbiAgICAgICAgICAgIGlmICh0aGlzLnByZXYgPCBlbnRyeS5jYXRjaExvYykge1xuICAgICAgICAgICAgICByZXR1cm4gaGFuZGxlKGVudHJ5LmNhdGNoTG9jLCB0cnVlKTtcbiAgICAgICAgICAgIH0gZWxzZSBpZiAodGhpcy5wcmV2IDwgZW50cnkuZmluYWxseUxvYykge1xuICAgICAgICAgICAgICByZXR1cm4gaGFuZGxlKGVudHJ5LmZpbmFsbHlMb2MpO1xuICAgICAgICAgICAgfVxuXG4gICAgICAgICAgfSBlbHNlIGlmIChoYXNDYXRjaCkge1xuICAgICAgICAgICAgaWYgKHRoaXMucHJldiA8IGVudHJ5LmNhdGNoTG9jKSB7XG4gICAgICAgICAgICAgIHJldHVybiBoYW5kbGUoZW50cnkuY2F0Y2hMb2MsIHRydWUpO1xuICAgICAgICAgICAgfVxuXG4gICAgICAgICAgfSBlbHNlIGlmIChoYXNGaW5hbGx5KSB7XG4gICAgICAgICAgICBpZiAodGhpcy5wcmV2IDwgZW50cnkuZmluYWxseUxvYykge1xuICAgICAgICAgICAgICByZXR1cm4gaGFuZGxlKGVudHJ5LmZpbmFsbHlMb2MpO1xuICAgICAgICAgICAgfVxuXG4gICAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgIHRocm93IG5ldyBFcnJvcihcInRyeSBzdGF0ZW1lbnQgd2l0aG91dCBjYXRjaCBvciBmaW5hbGx5XCIpO1xuICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG5cbiAgICBhYnJ1cHQ6IGZ1bmN0aW9uKHR5cGUsIGFyZykge1xuICAgICAgZm9yICh2YXIgaSA9IHRoaXMudHJ5RW50cmllcy5sZW5ndGggLSAxOyBpID49IDA7IC0taSkge1xuICAgICAgICB2YXIgZW50cnkgPSB0aGlzLnRyeUVudHJpZXNbaV07XG4gICAgICAgIGlmIChlbnRyeS50cnlMb2MgPD0gdGhpcy5wcmV2ICYmXG4gICAgICAgICAgICBoYXNPd24uY2FsbChlbnRyeSwgXCJmaW5hbGx5TG9jXCIpICYmXG4gICAgICAgICAgICB0aGlzLnByZXYgPCBlbnRyeS5maW5hbGx5TG9jKSB7XG4gICAgICAgICAgdmFyIGZpbmFsbHlFbnRyeSA9IGVudHJ5O1xuICAgICAgICAgIGJyZWFrO1xuICAgICAgICB9XG4gICAgICB9XG5cbiAgICAgIGlmIChmaW5hbGx5RW50cnkgJiZcbiAgICAgICAgICAodHlwZSA9PT0gXCJicmVha1wiIHx8XG4gICAgICAgICAgIHR5cGUgPT09IFwiY29udGludWVcIikgJiZcbiAgICAgICAgICBmaW5hbGx5RW50cnkudHJ5TG9jIDw9IGFyZyAmJlxuICAgICAgICAgIGFyZyA8IGZpbmFsbHlFbnRyeS5maW5hbGx5TG9jKSB7XG4gICAgICAgIC8vIElnbm9yZSB0aGUgZmluYWxseSBlbnRyeSBpZiBjb250cm9sIGlzIG5vdCBqdW1waW5nIHRvIGFcbiAgICAgICAgLy8gbG9jYXRpb24gb3V0c2lkZSB0aGUgdHJ5L2NhdGNoIGJsb2NrLlxuICAgICAgICBmaW5hbGx5RW50cnkgPSBudWxsO1xuICAgICAgfVxuXG4gICAgICB2YXIgcmVjb3JkID0gZmluYWxseUVudHJ5ID8gZmluYWxseUVudHJ5LmNvbXBsZXRpb24gOiB7fTtcbiAgICAgIHJlY29yZC50eXBlID0gdHlwZTtcbiAgICAgIHJlY29yZC5hcmcgPSBhcmc7XG5cbiAgICAgIGlmIChmaW5hbGx5RW50cnkpIHtcbiAgICAgICAgdGhpcy5uZXh0ID0gZmluYWxseUVudHJ5LmZpbmFsbHlMb2M7XG4gICAgICB9IGVsc2Uge1xuICAgICAgICB0aGlzLmNvbXBsZXRlKHJlY29yZCk7XG4gICAgICB9XG5cbiAgICAgIHJldHVybiBDb250aW51ZVNlbnRpbmVsO1xuICAgIH0sXG5cbiAgICBjb21wbGV0ZTogZnVuY3Rpb24ocmVjb3JkLCBhZnRlckxvYykge1xuICAgICAgaWYgKHJlY29yZC50eXBlID09PSBcInRocm93XCIpIHtcbiAgICAgICAgdGhyb3cgcmVjb3JkLmFyZztcbiAgICAgIH1cblxuICAgICAgaWYgKHJlY29yZC50eXBlID09PSBcImJyZWFrXCIgfHxcbiAgICAgICAgICByZWNvcmQudHlwZSA9PT0gXCJjb250aW51ZVwiKSB7XG4gICAgICAgIHRoaXMubmV4dCA9IHJlY29yZC5hcmc7XG4gICAgICB9IGVsc2UgaWYgKHJlY29yZC50eXBlID09PSBcInJldHVyblwiKSB7XG4gICAgICAgIHRoaXMucnZhbCA9IHJlY29yZC5hcmc7XG4gICAgICAgIHRoaXMubmV4dCA9IFwiZW5kXCI7XG4gICAgICB9IGVsc2UgaWYgKHJlY29yZC50eXBlID09PSBcIm5vcm1hbFwiICYmIGFmdGVyTG9jKSB7XG4gICAgICAgIHRoaXMubmV4dCA9IGFmdGVyTG9jO1xuICAgICAgfVxuXG4gICAgICByZXR1cm4gQ29udGludWVTZW50aW5lbDtcbiAgICB9LFxuXG4gICAgZmluaXNoOiBmdW5jdGlvbihmaW5hbGx5TG9jKSB7XG4gICAgICBmb3IgKHZhciBpID0gdGhpcy50cnlFbnRyaWVzLmxlbmd0aCAtIDE7IGkgPj0gMDsgLS1pKSB7XG4gICAgICAgIHZhciBlbnRyeSA9IHRoaXMudHJ5RW50cmllc1tpXTtcbiAgICAgICAgaWYgKGVudHJ5LmZpbmFsbHlMb2MgPT09IGZpbmFsbHlMb2MpIHtcbiAgICAgICAgICByZXR1cm4gdGhpcy5jb21wbGV0ZShlbnRyeS5jb21wbGV0aW9uLCBlbnRyeS5hZnRlckxvYyk7XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9LFxuXG4gICAgXCJjYXRjaFwiOiBmdW5jdGlvbih0cnlMb2MpIHtcbiAgICAgIGZvciAodmFyIGkgPSB0aGlzLnRyeUVudHJpZXMubGVuZ3RoIC0gMTsgaSA+PSAwOyAtLWkpIHtcbiAgICAgICAgdmFyIGVudHJ5ID0gdGhpcy50cnlFbnRyaWVzW2ldO1xuICAgICAgICBpZiAoZW50cnkudHJ5TG9jID09PSB0cnlMb2MpIHtcbiAgICAgICAgICB2YXIgcmVjb3JkID0gZW50cnkuY29tcGxldGlvbjtcbiAgICAgICAgICBpZiAocmVjb3JkLnR5cGUgPT09IFwidGhyb3dcIikge1xuICAgICAgICAgICAgdmFyIHRocm93biA9IHJlY29yZC5hcmc7XG4gICAgICAgICAgICByZXNldFRyeUVudHJ5KGVudHJ5KTtcbiAgICAgICAgICB9XG4gICAgICAgICAgcmV0dXJuIHRocm93bjtcbiAgICAgICAgfVxuICAgICAgfVxuXG4gICAgICAvLyBUaGUgY29udGV4dC5jYXRjaCBtZXRob2QgbXVzdCBvbmx5IGJlIGNhbGxlZCB3aXRoIGEgbG9jYXRpb25cbiAgICAgIC8vIGFyZ3VtZW50IHRoYXQgY29ycmVzcG9uZHMgdG8gYSBrbm93biBjYXRjaCBibG9jay5cbiAgICAgIHRocm93IG5ldyBFcnJvcihcImlsbGVnYWwgY2F0Y2ggYXR0ZW1wdFwiKTtcbiAgICB9LFxuXG4gICAgZGVsZWdhdGVZaWVsZDogZnVuY3Rpb24oaXRlcmFibGUsIHJlc3VsdE5hbWUsIG5leHRMb2MpIHtcbiAgICAgIHRoaXMuZGVsZWdhdGUgPSB7XG4gICAgICAgIGl0ZXJhdG9yOiB2YWx1ZXMoaXRlcmFibGUpLFxuICAgICAgICByZXN1bHROYW1lOiByZXN1bHROYW1lLFxuICAgICAgICBuZXh0TG9jOiBuZXh0TG9jXG4gICAgICB9O1xuXG4gICAgICByZXR1cm4gQ29udGludWVTZW50aW5lbDtcbiAgICB9XG4gIH07XG59KShcbiAgLy8gQW1vbmcgdGhlIHZhcmlvdXMgdHJpY2tzIGZvciBvYnRhaW5pbmcgYSByZWZlcmVuY2UgdG8gdGhlIGdsb2JhbFxuICAvLyBvYmplY3QsIHRoaXMgc2VlbXMgdG8gYmUgdGhlIG1vc3QgcmVsaWFibGUgdGVjaG5pcXVlIHRoYXQgZG9lcyBub3RcbiAgLy8gdXNlIGluZGlyZWN0IGV2YWwgKHdoaWNoIHZpb2xhdGVzIENvbnRlbnQgU2VjdXJpdHkgUG9saWN5KS5cbiAgdHlwZW9mIGdsb2JhbCA9PT0gXCJvYmplY3RcIiA/IGdsb2JhbCA6XG4gIHR5cGVvZiB3aW5kb3cgPT09IFwib2JqZWN0XCIgPyB3aW5kb3cgOiB0aGlzXG4pO1xuIl19
},{}],88:[function(require,module,exports){
module.exports = require("./lib/babel/polyfill");

},{"./lib/babel/polyfill":17}],89:[function(require,module,exports){
"use strict";

module.exports = require("babel-core/polyfill");

},{"babel-core/polyfill":88}]},{},[1,89])
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbIi4uL25vZGVfbW9kdWxlcy9icm93c2VyaWZ5L25vZGVfbW9kdWxlcy9icm93c2VyLXBhY2svX3ByZWx1ZGUuanMiLCIvVXNlcnMvdHJvbmQvZGV2L2VsaXhpci9icmFuZG8vYXNzZXRzL2pzL2JyYW5kby9icmFuZG8uanMiLCIvVXNlcnMvdHJvbmQvZGV2L2VsaXhpci9icmFuZG8vYXNzZXRzL2pzL2JyYW5kby9hdXRvc2x1Zy5qcyIsIi9Vc2Vycy90cm9uZC9kZXYvZWxpeGlyL2JyYW5kby9hc3NldHMvanMvYnJhbmRvL2ZpbHRlcl90YWJsZS5qcyIsIi9Vc2Vycy90cm9uZC9kZXYvZWxpeGlyL2JyYW5kby9hc3NldHMvanMvYnJhbmRvL2ZsYXNoLmpzIiwiL1VzZXJzL3Ryb25kL2Rldi9lbGl4aXIvYnJhbmRvL2Fzc2V0cy9qcy9icmFuZG8vaW1hZ2VzLmpzIiwiL1VzZXJzL3Ryb25kL2Rldi9lbGl4aXIvYnJhbmRvL2Fzc2V0cy9qcy9icmFuZG8vaW5zdGFncmFtLmpzIiwiL1VzZXJzL3Ryb25kL2Rldi9lbGl4aXIvYnJhbmRvL2Fzc2V0cy9qcy9icmFuZG8vbW9iaWxlLmpzIiwiL1VzZXJzL3Ryb25kL2Rldi9lbGl4aXIvYnJhbmRvL2Fzc2V0cy9qcy9icmFuZG8vcGFnZXMuanMiLCIvVXNlcnMvdHJvbmQvZGV2L2VsaXhpci9icmFuZG8vYXNzZXRzL2pzL2JyYW5kby9zZXF1ZW5jZS5qcyIsIi9Vc2Vycy90cm9uZC9kZXYvZWxpeGlyL2JyYW5kby9hc3NldHMvanMvYnJhbmRvL3N0YXRzLmpzIiwiL1VzZXJzL3Ryb25kL2Rldi9lbGl4aXIvYnJhbmRvL2Fzc2V0cy9qcy9icmFuZG8vdGFncy5qcyIsIi9Vc2Vycy90cm9uZC9kZXYvZWxpeGlyL2JyYW5kby9hc3NldHMvanMvYnJhbmRvL3Rvb2xiYXIuanMiLCIvVXNlcnMvdHJvbmQvZGV2L2VsaXhpci9icmFuZG8vYXNzZXRzL2pzL2JyYW5kby91dGlscy5qcyIsIi9Vc2Vycy90cm9uZC9kZXYvZWxpeGlyL2JyYW5kby9hc3NldHMvanMvYnJhbmRvL3ZleC5qcyIsIi9Vc2Vycy90cm9uZC9kZXYvZWxpeGlyL2JyYW5kby9hc3NldHMvanMvYnJhbmRvL3dzLmpzIiwiL1VzZXJzL3Ryb25kL2Rldi9lbGl4aXIvYnJhbmRvL2RlcHMvcGhvZW5peC93ZWIvc3RhdGljL2pzL3Bob2VuaXguanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbGliL2JhYmVsL3BvbHlmaWxsLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvJC5hcnJheS1pbmNsdWRlcy5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzLyQuYXJyYXktbWV0aG9kcy5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzLyQuYXNzZXJ0LmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvJC5hc3NpZ24uanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy8kLmNvZi5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzLyQuY29sbGVjdGlvbi1zdHJvbmcuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy8kLmNvbGxlY3Rpb24td2Vhay5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzLyQuY29sbGVjdGlvbi5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzLyQuY3R4LmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvJC5kZWYuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy8kLmZ3LmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvJC5pbnZva2UuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy8kLml0ZXIuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy8kLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvJC5rZXlvZi5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzLyQub3duLWtleXMuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy8kLnBhcnRpYWwuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy8kLnJlcGxhY2VyLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvJC5zZXQtcHJvdG8uanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy8kLnNwZWNpZXMuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy8kLnN0cmluZy1hdC5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzLyQudGFzay5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzLyQudWlkLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvJC51bnNjb3BlLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvJC53a3MuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczUuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczYuYXJyYXkuY29weS13aXRoaW4uanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczYuYXJyYXkuZmlsbC5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzL2VzNi5hcnJheS5maW5kLWluZGV4LmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvZXM2LmFycmF5LmZpbmQuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczYuYXJyYXkuZnJvbS5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzL2VzNi5hcnJheS5pdGVyYXRvci5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzL2VzNi5hcnJheS5vZi5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzL2VzNi5hcnJheS5zcGVjaWVzLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvZXM2LmZ1bmN0aW9uLm5hbWUuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczYubWFwLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvZXM2Lm1hdGguanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczYubnVtYmVyLmNvbnN0cnVjdG9yLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvZXM2Lm51bWJlci5zdGF0aWNzLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvZXM2Lm9iamVjdC5hc3NpZ24uanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczYub2JqZWN0LmlzLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvZXM2Lm9iamVjdC5zZXQtcHJvdG90eXBlLW9mLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvZXM2Lm9iamVjdC5zdGF0aWNzLWFjY2VwdC1wcmltaXRpdmVzLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvZXM2Lm9iamVjdC50by1zdHJpbmcuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczYucHJvbWlzZS5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzL2VzNi5yZWZsZWN0LmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvZXM2LnJlZ2V4cC5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzL2VzNi5zZXQuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczYuc3RyaW5nLmNvZGUtcG9pbnQtYXQuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczYuc3RyaW5nLmVuZHMtd2l0aC5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzL2VzNi5zdHJpbmcuZnJvbS1jb2RlLXBvaW50LmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvZXM2LnN0cmluZy5pbmNsdWRlcy5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzL2VzNi5zdHJpbmcuaXRlcmF0b3IuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczYuc3RyaW5nLnJhdy5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzL2VzNi5zdHJpbmcucmVwZWF0LmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvZXM2LnN0cmluZy5zdGFydHMtd2l0aC5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzL2VzNi5zeW1ib2wuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczYud2Vhay1tYXAuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczYud2Vhay1zZXQuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczcuYXJyYXkuaW5jbHVkZXMuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczcub2JqZWN0LmdldC1vd24tcHJvcGVydHktZGVzY3JpcHRvcnMuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczcub2JqZWN0LnRvLWFycmF5LmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvZXM3LnJlZ2V4cC5lc2NhcGUuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy9lczcuc3RyaW5nLmF0LmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvanMuYXJyYXkuc3RhdGljcy5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9tb2R1bGVzL3dlYi5kb20uaXRlcmFibGUuanMiLCIuLi9ub2RlX21vZHVsZXMvYmFiZWwvbm9kZV9tb2R1bGVzL2JhYmVsLWNvcmUvbm9kZV9tb2R1bGVzL2NvcmUtanMvbW9kdWxlcy93ZWIuaW1tZWRpYXRlLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9jb3JlLWpzL21vZHVsZXMvd2ViLnRpbWVycy5qcyIsIi4uL25vZGVfbW9kdWxlcy9iYWJlbC9ub2RlX21vZHVsZXMvYmFiZWwtY29yZS9ub2RlX21vZHVsZXMvY29yZS1qcy9zaGltLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL25vZGVfbW9kdWxlcy9yZWdlbmVyYXRvci1iYWJlbC9ydW50aW1lLmpzIiwiLi4vbm9kZV9tb2R1bGVzL2JhYmVsL25vZGVfbW9kdWxlcy9iYWJlbC1jb3JlL3BvbHlmaWxsLmpzIiwiL1VzZXJzL3Ryb25kL2Rldi9lbGl4aXIvYnJhbmRvL25vZGVfbW9kdWxlcy9iYWJlbC9wb2x5ZmlsbC5qcyJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFBQTtBQ0FBLFlBQVksQ0FBQzs7Ozt3QkFFUSxlQUFlOzs7O3FCQUNsQixZQUFZOzs7OzJCQUNOLG1CQUFtQjs7OztzQkFDeEIsYUFBYTs7OztxQkFDZCxZQUFZOzs7O21CQUNkLFVBQVU7Ozs7c0JBQ1AsYUFBYTs7Ozt5QkFDVixnQkFBZ0I7Ozs7cUJBQ3BCLFlBQVk7Ozs7d0JBQ1QsZUFBZTs7OztxQkFDbEIsWUFBWTs7OztvQkFDYixXQUFXOzs7O3VCQUNSLGNBQWM7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QUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNaQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDakJBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDeENBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNqQkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDZkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ2RBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ3pKQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ2xGQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDcEVBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ2xCQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDekNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDSkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDbEJBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQzFJQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ3BHQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDUkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ0xBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDdEJBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNSQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNsQkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDTkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ2pCQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDN0VBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNMQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNOQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDTEE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNoUUE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUM1QkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNoQkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ0xBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNMQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQy9CQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNqQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDWkE7O0FDQUE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ2pCQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDZEE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQzNHQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQzNDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNqQ0E7QUFDQTtBQUNBOztBQ0ZBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ05BO0FBQ0E7QUFDQTs7QUNGQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ3JDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDUkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ3JNQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUM5SEE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQzdCQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNUQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ0pBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNqQkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ3BCQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDWEE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNuQkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNoQkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ2RBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNkQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ3BHQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUN2Q0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDVEE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ0xBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNkQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ25CQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ0pBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDSkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDZkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBOztBQ1JBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNMQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUNsQkE7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTs7QUMzQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7QUFDQTtBQUNBO0FBQ0E7O0FDNWhCQTtBQUNBOzs7O0FDREEsTUFBTSxDQUFDLE9BQU8sR0FBRyxPQUFPLENBQUMscUJBQXFCLENBQUMsQ0FBQyIsImZpbGUiOiJnZW5lcmF0ZWQuanMiLCJzb3VyY2VSb290IjoiIiwic291cmNlc0NvbnRlbnQiOlsiKGZ1bmN0aW9uIGUodCxuLHIpe2Z1bmN0aW9uIHMobyx1KXtpZighbltvXSl7aWYoIXRbb10pe3ZhciBhPXR5cGVvZiByZXF1aXJlPT1cImZ1bmN0aW9uXCImJnJlcXVpcmU7aWYoIXUmJmEpcmV0dXJuIGEobywhMCk7aWYoaSlyZXR1cm4gaShvLCEwKTt2YXIgZj1uZXcgRXJyb3IoXCJDYW5ub3QgZmluZCBtb2R1bGUgJ1wiK28rXCInXCIpO3Rocm93IGYuY29kZT1cIk1PRFVMRV9OT1RfRk9VTkRcIixmfXZhciBsPW5bb109e2V4cG9ydHM6e319O3Rbb11bMF0uY2FsbChsLmV4cG9ydHMsZnVuY3Rpb24oZSl7dmFyIG49dFtvXVsxXVtlXTtyZXR1cm4gcyhuP246ZSl9LGwsbC5leHBvcnRzLGUsdCxuLHIpfXJldHVybiBuW29dLmV4cG9ydHN9dmFyIGk9dHlwZW9mIHJlcXVpcmU9PVwiZnVuY3Rpb25cIiYmcmVxdWlyZTtmb3IodmFyIG89MDtvPHIubGVuZ3RoO28rKylzKHJbb10pO3JldHVybiBzfSkiLCJcInVzZSBzdHJpY3RcIjtcblxuaW1wb3J0IEF1dG9zbHVnIGZyb20gXCIuL2F1dG9zbHVnLmpzXCI7XG5pbXBvcnQgRmxhc2ggZnJvbSBcIi4vZmxhc2guanNcIjtcbmltcG9ydCBGaWx0ZXJUYWJsZSBmcm9tIFwiLi9maWx0ZXJfdGFibGUuanNcIjtcbmltcG9ydCBNb2JpbGUgZnJvbSBcIi4vbW9iaWxlLmpzXCI7XG5pbXBvcnQgVXRpbHMgZnJvbSBcIi4vdXRpbHMuanNcIjtcbmltcG9ydCBWZXggZnJvbSBcIi4vdmV4LmpzXCI7XG5pbXBvcnQgSW1hZ2VzIGZyb20gXCIuL2ltYWdlcy5qc1wiO1xuaW1wb3J0IEluc3RhZ3JhbSBmcm9tIFwiLi9pbnN0YWdyYW0uanNcIjtcbmltcG9ydCBQYWdlcyBmcm9tIFwiLi9wYWdlcy5qc1wiO1xuaW1wb3J0IFNlcXVlbmNlIGZyb20gXCIuL3NlcXVlbmNlLmpzXCI7XG5pbXBvcnQgU3RhdHMgZnJvbSBcIi4vc3RhdHMuanNcIjtcbmltcG9ydCBUYWdzIGZyb20gXCIuL3RhZ3MuanNcIjtcbmltcG9ydCBUb29sYmFyIGZyb20gXCIuL3Rvb2xiYXIuanNcIjtcbmltcG9ydCBXUyBmcm9tIFwiLi93cy5qc1wiO1xuXG5cbiQoKCkgPT4ge1xuICAgIC8qIHNldCB1cCBhdXRvbWF0ZWQgdmVuZG9yZWQganMgc3R1ZmYgKi9cbiAgICBWZXguc2V0dXAoKTtcbiAgICBBdXRvc2x1Zy5zZXR1cCgpO1xuICAgIEZpbHRlclRhYmxlLnNldHVwKCk7XG4gICAgRmxhc2guc2V0dXAoKTtcbiAgICBNb2JpbGUuc2V0dXAoKTtcbiAgICBTZXF1ZW5jZS5zZXR1cCgpO1xuICAgIFRvb2xiYXIuc2V0dXAoKTtcbiAgICBUYWdzLnNldHVwKCk7XG5cbiAgICBzd2l0Y2ggKCQoJ2JvZHknKS5hdHRyKCdkYXRhLXNjcmlwdCcpKSB7XG4gICAgICAgIGNhc2UgXCJpbWFnZXMtaW5kZXhcIjpcbiAgICAgICAgICAgIEltYWdlcy5zZXR1cCgpO1xuICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgIGNhc2UgXCJkYXNoYm9hcmQtc3lzdGVtX2luZm9cIjpcbiAgICAgICAgICAgIFN0YXRzLnNldHVwKCk7XG4gICAgICAgICAgICBicmVhaztcbiAgICAgICAgY2FzZSBcImluc3RhZ3JhbS1pbmRleFwiOlxuICAgICAgICAgICAgSW5zdGFncmFtLnNldHVwKCk7XG4gICAgICAgICAgICBicmVhaztcbiAgICAgICAgY2FzZSBcInBhZ2VzLWluZGV4XCI6XG4gICAgICAgICAgICBQYWdlcy5zZXR1cCgpO1xuICAgICAgICAgICAgYnJlYWs7XG4gICAgfVxuICAgIC8qIHNldCB1cCB3cyAqL1xuICAgIFdTLnNldHVwKCk7XG59KTsiLCJcInVzZSBzdHJpY3RcIjtcblxuY2xhc3MgQXV0b3NsdWcge1xuICAgIHN0YXRpYyBzZXR1cCgpIHtcbiAgICAgICAgLy8gc2V0IHVwIGF1dG8gc2x1Z1xuICAgICAgICAkKCdbZGF0YS1zbHVnLWZyb21dJykuZWFjaCgoaW5kZXgsIGVsZW0pID0+IHtcbiAgICAgICAgICAgIHZhciBzbHVnRnJvbSA9ICQoZWxlbSkuYXR0cignZGF0YS1zbHVnLWZyb20nKTtcbiAgICAgICAgICAgICQoJ1tuYW1lPVwiJyArIHNsdWdGcm9tICsgJ1wiXScpLnNsdWdJdCh7XG4gICAgICAgICAgICAgICAgb3V0cHV0OiAkKGVsZW0pLFxuICAgICAgICAgICAgfSk7XG4gICAgICAgIH0pO1xuICAgIH1cbn1cblxuZXhwb3J0IGRlZmF1bHQgQXV0b3NsdWc7IiwiXCJ1c2Ugc3RyaWN0XCI7XG5cbmNsYXNzIEZpbHRlclRhYmxlIHtcbiAgICBzdGF0aWMgc2V0dXAoKSB7XG4gICAgICAgIC8vIHNldCB1cCB0YWJsZSBmaWx0ZXJpbmdcbiAgICAgICAgJCgnW2RhdGEtZmlsdGVyLXRhYmxlXScpLmVhY2goKGluZGV4LCBlbGVtKSA9PiB7XG4gICAgICAgICAgICAkKGVsZW0pLnNlYXJjaGVyKHtpbnB1dFNlbGVjdG9yOiBcIiNmaWx0ZXItaW5wdXRcIn0pO1xuICAgICAgICB9KTtcbiAgICB9XG59XG5cbmV4cG9ydCBkZWZhdWx0IEZpbHRlclRhYmxlOyIsIlwidXNlIHN0cmljdFwiO1xuXG5jbGFzcyBGbGFzaCB7XG4gICAgc3RhdGljIHNldHVwKCkge1xuICAgICAgICAvLyBzZXQgdXAgZGlzbWlzc2FsIG9mIGZsYXNoIGFsZXJ0c1xuICAgICAgICAkKCdbZGF0YS1kaXNtaXNzXScpLmVhY2goKGluZGV4LCBlbGVtKSA9PiB7XG4gICAgICAgICAgICAkKGVsZW0pLmNsaWNrKGUgPT4ge1xuICAgICAgICAgICAgICAgIGUucHJldmVudERlZmF1bHQoKTtcbiAgICAgICAgICAgICAgICAkKGVsZW0pLnBhcmVudCgpLmhpZGUoKTtcbiAgICAgICAgICAgIH0pO1xuICAgICAgICB9KTtcbiAgICB9XG59XG5cbmV4cG9ydCBkZWZhdWx0IEZsYXNoOyIsIlwidXNlIHN0cmljdFwiO1xuaW1wb3J0IFV0aWxzIGZyb20gXCIuL3V0aWxzLmpzXCI7XG5cbnZhciBpbWFnZVBvb2wgPSBbXTtcbmNsYXNzIEltYWdlcyB7XG4gICAgc3RhdGljIHNldHVwKCkge1xuICAgICAgICB0aGlzLmdldEhhc2goKTtcbiAgICAgICAgdGhpcy5kZWxldGVMaXN0ZW5lcigpO1xuICAgICAgICB0aGlzLmltYWdlU2VsZWN0aW9uTGlzdGVuZXIoKTtcbiAgICAgICAgdGhpcy5pbWFnZVByb3BlcnRpZXNMaXN0ZW5lcigpO1xuICAgIH1cbiAgICBzdGF0aWMgZ2V0SGFzaCgpIHtcbiAgICAgICAgbGV0IGhhc2ggPSBkb2N1bWVudC5sb2NhdGlvbi5oYXNoXG4gICAgICAgIGlmIChoYXNoKSB7XG4gICAgICAgICAgICAvLyBzaG93IHRoZSB0YWJcbiAgICAgICAgICAgIGFjdGl2YXRlX3RhYihcIiN0YWItXCIgKyBoYXNoLnNsaWNlKDEpKTtcbiAgICAgICAgfVxuICAgIH1cbiAgICBzdGF0aWMgaW1hZ2VTZWxlY3Rpb25MaXN0ZW5lcigpIHtcbiAgICAgICAgdmFyIHRoYXQgPSB0aGlzO1xuICAgICAgICAkKCcuaW1hZ2Utc2VsZWN0aW9uLXBvb2wgaW1nJykuY2xpY2soZnVuY3Rpb24oZSkge1xuICAgICAgICAgIGlmICgkKHRoaXMpLmhhc0NsYXNzKCdzZWxlY3RlZCcpKSB7XG4gICAgICAgICAgICAvLyByZW1vdmUgZnJvbSBzZWxlY3RlZCBwb29sXG4gICAgICAgICAgICB2YXIgcG9zO1xuICAgICAgICAgICAgZm9yICh2YXIgaSA9IDA7IGkgPCBpbWFnZVBvb2wubGVuZ3RoOyBpKyspIHtcbiAgICAgICAgICAgICAgaWYgKCBpbWFnZVBvb2xbaV0gPT0gJCh0aGlzKS5hdHRyKCdkYXRhLWlkJykpIHtcbiAgICAgICAgICAgICAgICBwb3MgPSBpO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICBpbWFnZVBvb2wuc3BsaWNlKHBvcywgMSk7XG4gICAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgIC8vIGFkZCB0byBzZWxlY3RlZCBwb29sXG4gICAgICAgICAgICBpZiAoIWltYWdlUG9vbCkge1xuICAgICAgICAgICAgICBpbWFnZVBvb2wgPSBuZXcgQXJyYXkoKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGltYWdlUG9vbC5wdXNoKCQodGhpcykuYXR0cignZGF0YS1pZCcpKTtcbiAgICAgICAgICB9XG4gICAgICAgICAgJCh0aGlzKS50b2dnbGVDbGFzcygnc2VsZWN0ZWQnKTtcbiAgICAgICAgICB0aGF0LmNoZWNrQnV0dG9uRW5hYmxlKCk7XG4gICAgICAgIH0pO1xuICAgIH1cblxuICAgIHN0YXRpYyBpbWFnZVByb3BlcnRpZXNMaXN0ZW5lcigpIHtcbiAgICAgICAgdmFyIHRoYXQgPSB0aGlzO1xuXG4gICAgICAgICQoZG9jdW1lbnQpLm9uKHtcbiAgICAgICAgICAgIG1vdXNlZW50ZXI6IGZ1bmN0aW9uKCl7XG4gICAgICAgICAgICAgICAgJCh0aGlzKS5maW5kKCcub3ZlcmxheScpLmNzcygndmlzaWJpbGl0eScsICd2aXNpYmxlJyk7XG4gICAgICAgICAgICB9LFxuICAgICAgICAgICAgbW91c2VsZWF2ZTogZnVuY3Rpb24oKXtcbiAgICAgICAgICAgICAgICAkKHRoaXMpLmZpbmQoJy5vdmVybGF5JykuY3NzKCd2aXNpYmlsaXR5JywgJ2hpZGRlbicpO1xuICAgICAgICAgICAgfVxuICAgICAgICB9LCAnLmltYWdlLXdyYXBwZXInKTtcblxuICAgICAgICAkKGRvY3VtZW50KS5vbignY2xpY2snLCAnLmVkaXQtcHJvcGVydGllcycsIGZ1bmN0aW9uKGUpIHtcbiAgICAgICAgICAgIGUucHJldmVudERlZmF1bHQoKTtcblxuICAgICAgICAgICAgdmFyIGF0dHJzO1xuICAgICAgICAgICAgdmFyICRjb250ZW50ID0gJCgnPGRpdj4nKTtcbiAgICAgICAgICAgIHZhciAkZm9ybTtcbiAgICAgICAgICAgIHZhciAkaW1nID0gJCh0aGlzKS5wYXJlbnQoKS5wYXJlbnQoKS5maW5kKCdpbWcnKS5jbG9uZSgpO1xuXG4gICAgICAgICAgICB2ZXguZGlhbG9nLm9wZW4oe1xuICAgICAgICAgICAgICAgIG1lc3NhZ2U6ICcnLFxuICAgICAgICAgICAgICAgIGlucHV0OiBmdW5jdGlvbigpIHtcbiAgICAgICAgICAgICAgICAgICAgYXR0cnMgPSB0aGF0Ll9idWlsZEF0dHJzKCRpbWcuZGF0YSgpKTtcbiAgICAgICAgICAgICAgICAgICAgJGNvbnRlbnQuYXBwZW5kKCRpbWcpLmFwcGVuZChhdHRycyk7XG4gICAgICAgICAgICAgICAgICAgIHJldHVybiAkY29udGVudDtcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgICAgIGNhbGxiYWNrOiBmdW5jdGlvbihmb3JtKSB7XG4gICAgICAgICAgICAgICAgICAgIGlmIChmb3JtID09PSBmYWxzZSkge1xuICAgICAgICAgICAgICAgICAgICAgIHJldHVybiBjb25zb2xlLmxvZygnQ2FuY2VsbGVkJyk7XG4gICAgICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgICAgICAgICAgdmFyIGlkID0gZm9ybS5pZDtcbiAgICAgICAgICAgICAgICAgICAgZGVsZXRlIGZvcm0uaWQ7XG4gICAgICAgICAgICAgICAgICAgIHZhciBkYXRhID0ge1xuICAgICAgICAgICAgICAgICAgICAgICAgZm9ybTogZm9ybSxcbiAgICAgICAgICAgICAgICAgICAgICAgIGlkOiBpZFxuICAgICAgICAgICAgICAgICAgICB9XG4gICAgICAgICAgICAgICAgICAgIHRoYXQuX3N1Ym1pdFByb3BlcnRpZXMoZGF0YSk7XG4gICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgfSk7XG4gICAgICAgIH0pO1xuICAgIH1cblxuICAgIHN0YXRpYyBfc3VibWl0UHJvcGVydGllcyhkYXRhKSB7XG4gICAgICAgICQuYWpheCh7XG4gICAgICAgICAgICBoZWFkZXJzOiB7QWNjZXB0IDogXCJhcHBsaWNhdGlvbi9qc29uOyBjaGFyc2V0PXV0Zi04XCJ9LFxuICAgICAgICAgICAgdHlwZTogXCJQT1NUXCIsXG4gICAgICAgICAgICBkYXRhOiBkYXRhLFxuICAgICAgICAgICAgdXJsOiBVdGlscy5hZGRUb1BhdGhOYW1lKCdzZXQtcHJvcGVydGllcycpLFxuICAgICAgICB9KS5kb25lKCQucHJveHkoZnVuY3Rpb24oZGF0YSkge1xuICAgICAgICAgICAgLyoqXG4gICAgICAgICAgICAgKiBDYWxsYmFjayBhZnRlciBjb25maXJtaW5nLlxuICAgICAgICAgICAgICovXG4gICAgICAgICAgICBpZiAoZGF0YS5zdGF0dXMgPT0gJzIwMCcpIHtcbiAgICAgICAgICAgICAgICAvLyBzdWNjZXNzXG4gICAgICAgICAgICAgICAgdmFyICRpbWcgPSAkKCcuaW1hZ2Utc2VyaWUgaW1nW2RhdGEtaWQ9JyArIGRhdGEuaWQgKyAnXScpO1xuICAgICAgICAgICAgICAgICQuZWFjaChkYXRhLmF0dHJzLCBmdW5jdGlvbihhdHRyLCB2YWwpIHtcbiAgICAgICAgICAgICAgICAgICAgJGltZy5hdHRyKCdkYXRhLScgKyBhdHRyLCB2YWwpO1xuICAgICAgICAgICAgICAgIH0pO1xuICAgICAgICAgICAgfVxuICAgICAgICB9KSk7XG4gICAgfVxuXG4gICAgc3RhdGljIF9idWlsZEF0dHJzKGRhdGEpIHtcbiAgICAgICAgdmFyIHRoYXQgPSB0aGlzO1xuICAgICAgICB2YXIgcmV0ID0gJyc7XG4gICAgICAgICQuZWFjaChkYXRhLCBmdW5jdGlvbihhdHRyLCB2YWwpIHtcbiAgICAgICAgICAgIGlmIChhdHRyID09ICdpZCcpIHtcbiAgICAgICAgICAgICAgICByZXQgKz0gJzxpbnB1dCBuYW1lPVwiaWRcIiB0eXBlPVwiaGlkZGVuXCIgdmFsdWU9XCInICsgdmFsICsgJ1wiIC8+JztcbiAgICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAgICAgcmV0ICs9ICc8ZGl2PjxsYWJlbD4nICsgdGhhdC5fY2FwaXRhbGl6ZShhdHRyKSArICc8L2xhYmVsPicgK1xuICAgICAgICAgICAgICAgICAgICAgICAnPGlucHV0IG5hbWU9XCInICsgYXR0ciArICdcIiB0eXBlPVwidGV4dFwiIHZhbHVlPVwiJyArIHZhbCArICdcIiAvPjwvZGl2PidcbiAgICAgICAgICAgIH1cbiAgICAgICAgfSk7XG4gICAgICAgIHJldHVybiByZXQ7XG4gICAgfVxuXG4gICAgc3RhdGljIF9jYXBpdGFsaXplKHdvcmQpIHtcbiAgICAgICByZXR1cm4gJC5jYW1lbENhc2UoXCItXCIgKyB3b3JkKTtcbiAgICB9XG5cbiAgICBzdGF0aWMgY2hlY2tCdXR0b25FbmFibGUoKSB7XG4gICAgICAgIGxldCAkYnRuID0gJCgnLmRlbGV0ZS1zZWxlY3RlZC1pbWFnZXMnKTtcbiAgICAgICAgaWYgKGltYWdlUG9vbC5sZW5ndGggPiAwKSB7XG4gICAgICAgICAgICAkYnRuLnJlbW92ZUF0dHIoJ2Rpc2FibGVkJyk7XG4gICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICAkYnRuLmF0dHIoJ2Rpc2FibGVkJywgJ2Rpc2FibGVkJyk7XG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBzdGF0aWMgZGVsZXRlTGlzdGVuZXIoKSB7XG4gICAgICAgIHZhciB0aGF0ID0gdGhpcztcbiAgICAgICAgJCgnLmRlbGV0ZS1zZWxlY3RlZC1pbWFnZXMnKS5jbGljayhmdW5jdGlvbihlKSB7XG4gICAgICAgICAgICBlLnByZXZlbnREZWZhdWx0KCk7XG4gICAgICAgICAgICB2ZXguZGlhbG9nLmNvbmZpcm0oe1xuICAgICAgICAgICAgICAgIG1lc3NhZ2U6ICdFciBkdSBzaWtrZXIgcMOlIGF0IGR1IHZpbCBzbGV0dGUgZGlzc2UgYmlsZGVuZT8nLFxuICAgICAgICAgICAgICAgIGNhbGxiYWNrOiBmdW5jdGlvbih2YWx1ZSkge1xuICAgICAgICAgICAgICAgICAgICBpZiAodmFsdWUpIHtcbiAgICAgICAgICAgICAgICAgICAgICAgICQodGhpcykucmVtb3ZlQ2xhc3MoXCJidG4tZGFuZ2VyXCIpLmFkZENsYXNzKFwiYnRuLXdhcm5pbmdcIikuaHRtbChcIkxhZ3JlciAuLi5cIik7XG4gICAgICAgICAgICAgICAgICAgICAgICAkLmFqYXgoe1xuICAgICAgICAgICAgICAgICAgICAgICAgICAgIGhlYWRlcnM6IHtBY2NlcHQgOiBcImFwcGxpY2F0aW9uL2pzb247IGNoYXJzZXQ9dXRmLThcIn0sXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgdHlwZTogXCJQT1NUXCIsXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgdXJsOiBVdGlscy5hZGRUb1BhdGhOYW1lKCdkZWxldGUtc2VsZWN0ZWQtaW1hZ2VzJyksXG4gICAgICAgICAgICAgICAgICAgICAgICAgICAgZGF0YToge2lkczogaW1hZ2VQb29sfSxcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICBzdWNjZXNzOiB0aGF0LmRlbGV0ZVN1Y2Nlc3MsXG4gICAgICAgICAgICAgICAgICAgICAgICB9KTtcbiAgICAgICAgICAgICAgICAgICAgfVxuICAgICAgICAgICAgICAgIH1cbiAgICAgICAgICAgIH0pO1xuICAgICAgICB9KTtcbiAgICB9XG4gICAgc3RhdGljIGRlbGV0ZVN1Y2Nlc3MoZGF0YSkge1xuICAgICAgICBpZiAoZGF0YS5zdGF0dXMgPT0gMjAwKSB7XG4gICAgICAgICAgICAkKFwiLmRlbGV0ZS1zZWxlY3RlZC1pbWFnZXNcIikucmVtb3ZlQ2xhc3MoXCJidG4td2FybmluZ1wiKS5hZGRDbGFzcyhcImJ0bi1kYW5nZXJcIikuaHRtbChcIlNsZXR0IHZhbGd0ZSBiaWxkZXJcIik7XG4gICAgICAgICAgICBmb3IgKHZhciBpID0gMDsgaSA8IGRhdGEuaWRzLmxlbmd0aDsgaSsrKSB7XG4gICAgICAgICAgICAgICAgJCgnLmltYWdlLXNlbGVjdGlvbi1wb29sIGltZ1tkYXRhLWlkPScgKyBkYXRhLmlkc1tpXSArICddJykuZmFkZU91dCgpO1xuICAgICAgICAgICAgfVxuICAgICAgICAgICAgaW1hZ2VQb29sID0gW107XG4gICAgICAgIH1cbiAgICB9XG59XG5cbmV4cG9ydCBkZWZhdWx0IEltYWdlczsiLCJcInVzZSBzdHJpY3RcIjtcbmltcG9ydCBVdGlscyBmcm9tIFwiLi91dGlscy5qc1wiO1xuXG52YXIgaW1hZ2VQb29sID0gW107XG5jbGFzcyBJbnN0YWdyYW0ge1xuICAgIHN0YXRpYyBzZXR1cCgpIHtcbiAgICAgICAgdGhpcy5jaGVja0J1dHRvbkVuYWJsZSgpO1xuICAgICAgICB0aGlzLmNoYW5nZVN0YXR1c0xpc3RlbmVyKCk7XG4gICAgICAgIHRoaXMuaW1hZ2VTZWxlY3Rpb25MaXN0ZW5lcigpO1xuICAgIH1cbiAgICBzdGF0aWMgaW1hZ2VTZWxlY3Rpb25MaXN0ZW5lcigpIHtcbiAgICAgICAgdmFyIHRoYXQgPSB0aGlzO1xuICAgICAgICAkKCcuaW1hZ2Utc2VsZWN0aW9uLXBvb2wgaW1nJykuY2xpY2soZnVuY3Rpb24oZSkge1xuICAgICAgICAgIGlmICgkKHRoaXMpLmhhc0NsYXNzKCdzZWxlY3RlZCcpKSB7XG4gICAgICAgICAgICAvLyByZW1vdmUgZnJvbSBzZWxlY3RlZCBwb29sXG4gICAgICAgICAgICB2YXIgcG9zO1xuICAgICAgICAgICAgZm9yICh2YXIgaSA9IDA7IGkgPCBpbWFnZVBvb2wubGVuZ3RoOyBpKyspIHtcbiAgICAgICAgICAgICAgaWYgKCBpbWFnZVBvb2xbaV0gPT0gJCh0aGlzKS5hdHRyKCdkYXRhLWlkJykpIHtcbiAgICAgICAgICAgICAgICBwb3MgPSBpO1xuICAgICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgICB9XG4gICAgICAgICAgICB9XG4gICAgICAgICAgICBpbWFnZVBvb2wuc3BsaWNlKHBvcywgMSk7XG4gICAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgIC8vIGFkZCB0byBzZWxlY3RlZCBwb29sXG4gICAgICAgICAgICBpZiAoIWltYWdlUG9vbCkge1xuICAgICAgICAgICAgICBpbWFnZVBvb2wgPSBuZXcgQXJyYXkoKTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGltYWdlUG9vbC5wdXNoKCQodGhpcykuYXR0cignZGF0YS1pZCcpKTtcbiAgICAgICAgICB9XG4gICAgICAgICAgJCh0aGlzKS50b2dnbGVDbGFzcygnc2VsZWN0ZWQnKTtcbiAgICAgICAgICB0aGF0LmNoZWNrQnV0dG9uRW5hYmxlKCk7XG4gICAgICAgIH0pO1xuICAgIH1cblxuICAgIHN0YXRpYyBjaGVja0J1dHRvbkVuYWJsZSgpIHtcbiAgICAgICAgbGV0ICRidG4gPSAkKCcuZGVsZXRlLXNlbGVjdGVkLWltYWdlcywgLmFwcHJvdmUtc2VsZWN0ZWQtaW1hZ2VzLCAucmVqZWN0LXNlbGVjdGVkLWltYWdlcycpO1xuICAgICAgICBpZiAoaW1hZ2VQb29sLmxlbmd0aCA+IDApIHtcbiAgICAgICAgICAgICRidG4ucmVtb3ZlQXR0cignZGlzYWJsZWQnKTtcbiAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgICRidG4uYXR0cignZGlzYWJsZWQnLCAnZGlzYWJsZWQnKTtcbiAgICAgICAgfVxuICAgIH1cblxuICAgIHN0YXRpYyBjaGFuZ2VTdGF0dXNMaXN0ZW5lcigpIHtcbiAgICAgICAgdmFyIHRoYXQgPSB0aGlzO1xuICAgICAgICAkKCcuZGVsZXRlLXNlbGVjdGVkLWltYWdlcycpLmNsaWNrKGZ1bmN0aW9uKGUpIHtcbiAgICAgICAgICAgIGUucHJldmVudERlZmF1bHQoKTtcbiAgICAgICAgICAgIHRoYXQuY2hhbmdlU3RhdHVzKDAsIGltYWdlUG9vbCk7XG4gICAgICAgIH0pO1xuICAgICAgICAkKCcucmVqZWN0LXNlbGVjdGVkLWltYWdlcycpLmNsaWNrKGZ1bmN0aW9uKGUpIHtcbiAgICAgICAgICAgIGUucHJldmVudERlZmF1bHQoKTtcbiAgICAgICAgICAgIHRoYXQuY2hhbmdlU3RhdHVzKDEsIGltYWdlUG9vbCk7XG4gICAgICAgIH0pO1xuICAgICAgICAkKCcuYXBwcm92ZS1zZWxlY3RlZC1pbWFnZXMnKS5jbGljayhmdW5jdGlvbihlKSB7XG4gICAgICAgICAgICBlLnByZXZlbnREZWZhdWx0KCk7XG4gICAgICAgICAgICB0aGF0LmNoYW5nZVN0YXR1cygyLCBpbWFnZVBvb2wpO1xuICAgICAgICB9KTtcbiAgICB9XG5cbiAgICBzdGF0aWMgY2hhbmdlU3RhdHVzKHN0YXR1cywgaW1hZ2VzKSB7XG4gICAgICAgIHZhciB0aGF0ID0gdGhpcztcbiAgICAgICAgJC5hamF4KHtcbiAgICAgICAgICAgIGhlYWRlcnM6IHtBY2NlcHQgOiBcImFwcGxpY2F0aW9uL2pzb247IGNoYXJzZXQ9dXRmLThcIn0sXG4gICAgICAgICAgICB0eXBlOiBcIlBPU1RcIixcbiAgICAgICAgICAgIHVybDogVXRpbHMuYWRkVG9QYXRoTmFtZSgnY2hhbmdlLXN0YXR1cycpLFxuICAgICAgICAgICAgZGF0YToge2lkczogaW1hZ2VzLCBzdGF0dXM6IHN0YXR1c30sXG4gICAgICAgICAgICBzdWNjZXNzOiB0aGF0LmNoYW5nZVN0YXR1c1N1Y2Nlc3MsXG4gICAgICAgIH0pO1xuICAgIH1cblxuICAgIHN0YXRpYyBjaGFuZ2VTdGF0dXNTdWNjZXNzKGRhdGEpIHtcbiAgICAgICAgbGV0IG5ld19zdGF0dXMgPSBcIlwiXG4gICAgICAgIGlmIChkYXRhLnN0YXR1cyA9PSAyMDApIHtcbiAgICAgICAgICAgIHN3aXRjaCAoZGF0YS5uZXdfc3RhdHVzKSB7XG4gICAgICAgICAgICAgICAgY2FzZSBcIjBcIjogbmV3X3N0YXR1cyA9IFwiZGVsZXRlZFwiOyBicmVhaztcbiAgICAgICAgICAgICAgICBjYXNlIFwiMVwiOiBuZXdfc3RhdHVzID0gXCJyZWplY3RlZFwiOyBicmVhaztcbiAgICAgICAgICAgICAgICBjYXNlIFwiMlwiOiBuZXdfc3RhdHVzID0gXCJhcHByb3ZlZFwiOyBicmVhaztcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGZvciAodmFyIGkgPSAwOyBpIDwgZGF0YS5pZHMubGVuZ3RoOyBpKyspIHtcbiAgICAgICAgICAgICAgICAkKCcuaW1hZ2Utc2VsZWN0aW9uLXBvb2wgaW1nW2RhdGEtaWQ9JyArIGRhdGEuaWRzW2ldICsgJ10nKS5mYWRlT3V0KDUwMCwgZnVuY3Rpb24gKCkge1xuICAgICAgICAgICAgICAgICAgICAkKHRoaXMpXG4gICAgICAgICAgICAgICAgICAgICAgICAuZGV0YWNoKClcbiAgICAgICAgICAgICAgICAgICAgICAgIC5hcHBlbmRUbygnLicgKyBuZXdfc3RhdHVzKVxuICAgICAgICAgICAgICAgICAgICAgICAgLmZhZGVJbigpXG4gICAgICAgICAgICAgICAgICAgICAgICAuYXR0cignZGF0YS1zdGF0dXMnLCBuZXdfc3RhdHVzKTtcbiAgICAgICAgICAgICAgICB9KTtcbiAgICAgICAgICAgIH1cbiAgICAgICAgICAgIGltYWdlUG9vbCA9IFtdO1xuICAgICAgICAgICAgJCgnLmltYWdlLXNlbGVjdGlvbi1wb29sIGltZycpLnJlbW92ZUNsYXNzKCdzZWxlY3RlZCcpO1xuICAgICAgICB9XG4gICAgfVxufVxuXG5leHBvcnQgZGVmYXVsdCBJbnN0YWdyYW07IiwiXCJ1c2Ugc3RyaWN0XCI7XG5cbmNsYXNzIE1vYmlsZSB7XG4gICAgc3RhdGljIHNldHVwKCkge1xuICAgICAgICAvLyBzZXQgdXAgbW9iaWxlIG1lbnVcbiAgICAgICAgJChkb2N1bWVudCkub24oJ2NsaWNrJywgJyNtb2JpbGUtbmF2JywgZnVuY3Rpb24oZSkge1xuICAgICAgICAgICAgJCgnI21lbnUnKS50b2dnbGUoKTtcbiAgICAgICAgfSk7XG4gICAgfVxufVxuXG5leHBvcnQgZGVmYXVsdCBNb2JpbGU7IiwiXCJ1c2Ugc3RyaWN0XCI7XG5cbmNsYXNzIFBhZ2VzIHtcbiAgICBzdGF0aWMgc2V0dXAoKSB7XG4gICAgICAgIHZhciBfdGhpcyA9IHRoaXM7XG4gICAgICAgICQoJy5leHBhbmQtcGFnZS1jaGlsZHJlbicpLmNsaWNrKGZ1bmN0aW9uKGUpIHtcbiAgICAgICAgICAgIF90aGlzLm9uQ2xpY2tFeHBhbmRCdXR0b24oZSwgdGhpcyk7XG4gICAgICAgIH0pO1xuICAgIH1cblxuICAgIHN0YXRpYyBvbkNsaWNrRXhwYW5kQnV0dG9uKGUsIGVsZW0pIHtcbiAgICAgICAgZS5wcmV2ZW50RGVmYXVsdCgpO1xuICAgICAgICAkKGVsZW0pLnRvZ2dsZUNsYXNzKCdhY3RpdmUnKTtcbiAgICAgICAgJCgndHIuY2hpbGRbZGF0YS1wYXJlbnQtaWQ9JyArICQoZWxlbSkuYXR0cignZGF0YS1pZCcpICsgJ10nKS50b2dnbGVDbGFzcygnaGlkZGVuJyk7XG4gICAgfVxufVxuXG5leHBvcnQgZGVmYXVsdCBQYWdlczsiLCJcInVzZSBzdHJpY3RcIjtcblxuY2xhc3MgU2VxdWVuY2Uge1xuICAgIHN0YXRpYyBzZXR1cCgpIHtcbiAgICAgICAgaWYgKCQoJyNzZXF1ZW5jZScpLmxlbmd0aCAhPSAwKSB7XG4gICAgICAgICAgICB2YXIgZWwgPSBkb2N1bWVudC5nZXRFbGVtZW50QnlJZCgnc2VxdWVuY2UnKTtcbiAgICAgICAgICAgIHRoaXMuc29ydGFibGUgPSBuZXcgU29ydGFibGUoZWwsIHtcbiAgICAgICAgICAgICAgICBhbmltYXRpb246IDE1MCxcbiAgICAgICAgICAgICAgICBnaG9zdENsYXNzOiBcInNlcXVlbmNlLWdob3N0XCIsXG4gICAgICAgICAgICAgICAgb25VcGRhdGU6IGZ1bmN0aW9uIChlKSB7XG4gICAgICAgICAgICAgICAgICAgICQoJyNzb3J0LXBvc3QnKS5yZW1vdmVDbGFzcyhcImJ0bi1kZWZhdWx0XCIsIFwiYnRuLXN1Y2Nlc3NcIilcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgLmFkZENsYXNzKFwiYnRuLXdhcm5pbmdcIilcbiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgLmh0bWwoXCJMYWdyZSBueSByZWtrZWbDuGxnZVwiKTtcbiAgICAgICAgICAgICAgICB9LFxuICAgICAgICAgICAgfSk7XG4gICAgICAgICAgICB0aGlzLnNvcnRMaXN0ZW5lcigpO1xuICAgICAgICB9XG4gICAgfVxuXG5cbiAgICBzdGF0aWMgc29ydFN1Y2Nlc3MoZGF0YSkge1xuICAgICAgICBpZiAoZGF0YS5zdGF0dXMgPT0gMjAwKSB7XG4gICAgICAgICAgICAkKFwiI3NvcnQtcG9zdFwiKS5yZW1vdmVDbGFzcyhcImJ0bi13YXJuaW5nXCIpLmFkZENsYXNzKFwiYnRuLXN1Y2Nlc3NcIikuaHRtbChcIk9LIVwiKTtcbiAgICAgICAgfVxuICAgIH1cblxuICAgIHN0YXRpYyBzb3J0TGlzdGVuZXIoKSB7XG4gICAgICAgIHZhciBfdGhpcyA9IHRoaXM7XG4gICAgICAgICQoJyNzb3J0LXBvc3QnKS5vbignY2xpY2snLCBmdW5jdGlvbihlKSB7XG4gICAgICAgICAgICBlLnByZXZlbnREZWZhdWx0KCk7XG4gICAgICAgICAgICAkKHRoaXMpLnJlbW92ZUNsYXNzKFwiYnRuLWRlZmF1bHRcIikuYWRkQ2xhc3MoXCJidG4td2FybmluZ1wiKS5odG1sKFwiTGFncmVyIC4uLlwiKTtcbiAgICAgICAgICAgICQuYWpheCh7XG4gICAgICAgICAgICAgICAgaGVhZGVyczoge0FjY2VwdCA6IFwiYXBwbGljYXRpb24vanNvbjsgY2hhcnNldD11dGYtOFwifSxcbiAgICAgICAgICAgICAgICB0eXBlOiBcIlBPU1RcIixcbiAgICAgICAgICAgICAgICB1cmw6IFwiXCIsXG4gICAgICAgICAgICAgICAgZGF0YToge29yZGVyOiBfdGhpcy5zb3J0YWJsZS50b0FycmF5KCl9LFxuICAgICAgICAgICAgICAgIHN1Y2Nlc3M6IF90aGlzLnNvcnRTdWNjZXNzLFxuICAgICAgICAgICAgfSk7XG4gICAgICAgIH0pO1xuICAgIH1cbn1cblxuZXhwb3J0IGRlZmF1bHQgU2VxdWVuY2U7IiwiXCJ1c2Ugc3RyaWN0XCI7XG5cbmltcG9ydCB7U29ja2V0fSBmcm9tICcuLi8uLi8uLi9kZXBzL3Bob2VuaXgvd2ViL3N0YXRpYy9qcy9waG9lbml4LmpzJ1xuXG5jb25zdCBNQVhfUE9JTlRTID0gMzA7XG5cbmNsYXNzIFN0YXRzIHtcblxuICAgIHN0YXRpYyBzZXR1cCgpIHtcbiAgICAgICAgdmFyIF90aGlzID0gdGhpcztcbiAgICAgICAgdGhpcy50b3RhbE1lbW9yeVBvaW50cyA9IFtdO1xuICAgICAgICB0aGlzLmF0b21NZW1vcnlQb2ludHMgPSBbXTtcbiAgICAgICAgdGhpcy5vcHRzID0ge1xuICAgICAgICAgICAgbGluZVdpZHRoOiAyLFxuICAgICAgICAgICAgdHlwZTogJ2xpbmUnLFxuICAgICAgICAgICAgd2lkdGg6ICcxMTBweCcsXG4gICAgICAgICAgICBoZWlnaHQ6ICc1MHB4JyxcbiAgICAgICAgICAgIGxpbmVDb2xvcjogJyM2Y2M3ZDknLFxuICAgICAgICAgICAgZmlsbENvbG9yOiAnI2UyZjRmNycsXG4gICAgICAgICAgICBzcG90Q29sb3I6IGZhbHNlLFxuICAgICAgICAgICAgbWluU3BvdENvbG9yOiBmYWxzZSxcbiAgICAgICAgICAgIGhpZ2hsaWdodExpbmVDb2xvcjogJ3JnYmEoMCwwLDAsMC4xKScsXG4gICAgICAgICAgICBoaWdobGlnaHRTcG90Q29sb3I6ICcjNmNjN2Q5JyxcbiAgICAgICAgICAgIHNwb3RSYWRpdXM6IDMsXG4gICAgICAgICAgICBjaGFydFJhbmdlTWluOiAwLFxuICAgICAgICAgICAgbWF4U3BvdENvbG9yOiBmYWxzZVxuICAgICAgICB9XG4gICAgICAgIGxldCBzb2NrZXQgPSBuZXcgU29ja2V0KFwiL2FkbWluL3dzXCIpO1xuICAgICAgICBsZXQgdXNlcl90b2tlbiA9IGRvY3VtZW50LnF1ZXJ5U2VsZWN0b3IoXCJtZXRhW25hbWU9XFxcImNoYW5uZWxfdG9rZW5cXFwiXVwiKS5nZXRBdHRyaWJ1dGUoXCJjb250ZW50XCIpO1xuICAgICAgICBzb2NrZXQuY29ubmVjdCh7IHRva2VuOiB1c2VyX3Rva2VuIH0pO1xuICAgICAgICBsZXQgY2hhbiA9IHNvY2tldC5jaGFubmVsKFwic3RhdHNcIiwge30pO1xuICAgICAgICBjaGFuLmpvaW4oKS5yZWNlaXZlKFwib2tcIiwgKHttZXNzYWdlc30pID0+IHtcbiAgICAgICAgICAgIGNvbnNvbGUubG9nKFwiPj4gU3lzdGVtIHN0YXRpc3RpY3MgY2hhbm5lbCByZWFkeVwiKTtcbiAgICAgICAgfSk7XG4gICAgICAgIGNoYW4ub24oXCJ1cGRhdGVcIiwgcGF5bG9hZCA9PiB7XG4gICAgICAgICAgICB0aGlzLnVwZGF0ZShwYXlsb2FkKTtcbiAgICAgICAgfSk7XG4gICAgfVxuXG4gICAgc3RhdGljIHVwZGF0ZShwYXlsb2FkKSB7XG4gICAgICAgIC8vIHVwZGF0ZSBtZW1vcnlcbiAgICAgICAgdGhpcy50b3RhbE1lbW9yeVBvaW50cy5wdXNoKHBheWxvYWQudG90YWxfbWVtb3J5KTtcbiAgICAgICAgaWYgKHRoaXMudG90YWxNZW1vcnlQb2ludHMubGVuZ3RoID4gTUFYX1BPSU5UUykge1xuICAgICAgICAgICAgdGhpcy50b3RhbE1lbW9yeVBvaW50cy5zcGxpY2UoMCwgMSk7XG4gICAgICAgIH1cbiAgICAgICAgJCgnI3RvdGFsLW1lbW9yeSAuc3BhcmtsaW5lJykuc3BhcmtsaW5lKHRoaXMudG90YWxNZW1vcnlQb2ludHMsIHRoaXMub3B0cyk7XG4gICAgICAgICQoJyN0b3RhbC1tZW1vcnkgLnRleHQnKS5odG1sKHRoaXMuaHVtYW5GaWxlU2l6ZShwYXJzZUludChwYXlsb2FkLnRvdGFsX21lbW9yeSksIGZhbHNlKSk7XG5cbiAgICAgICAgdGhpcy5hdG9tTWVtb3J5UG9pbnRzLnB1c2gocGF5bG9hZC5hdG9tX21lbW9yeSk7XG4gICAgICAgIGlmICh0aGlzLmF0b21NZW1vcnlQb2ludHMubGVuZ3RoID4gTUFYX1BPSU5UUykge1xuICAgICAgICAgICAgdGhpcy5hdG9tTWVtb3J5UG9pbnRzLnNwbGljZSgwLCAxKTtcbiAgICAgICAgfVxuICAgICAgICAkKCcjYXRvbS1tZW1vcnkgLnNwYXJrbGluZScpLnNwYXJrbGluZSh0aGlzLmF0b21NZW1vcnlQb2ludHMsIHRoaXMub3B0cyk7XG4gICAgICAgICQoJyNhdG9tLW1lbW9yeSAudGV4dCcpLmh0bWwodGhpcy5odW1hbkZpbGVTaXplKHBhcnNlSW50KHBheWxvYWQuYXRvbV9tZW1vcnkpLCBmYWxzZSkpO1xuXG4gICAgICAgIC8qIGluc3RhZ3JhbSBzdGF0dXMgKi9cbiAgICAgICAgaWYgKHBheWxvYWQuaW5zdGFncmFtX3N0YXR1cykge1xuICAgICAgICAgICAgJCgnI2luc3RhZ3JhbS1zdGF0dXMgLnN0YXR1cycpLmh0bWwoJzxpIGNsYXNzPVwiZmEgZmEtY2hlY2sgZmEtNHhcIj48L2k+JylcbiAgICAgICAgfSBlbHNlIHtcbiAgICAgICAgICAgICQoJyNpbnN0YWdyYW0tc3RhdHVzIC5zdGF0dXMnKS5odG1sKCc8aSBjbGFzcz1cImZhIGZhLXRpbWVzIGZhLTR4XCI+PC9pPicpXG4gICAgICAgIH1cbiAgICB9XG5cbiAgICBzdGF0aWMgaHVtYW5GaWxlU2l6ZShieXRlcywgc2kpIHtcbiAgICAgICAgdmFyIHRocmVzaCA9IHNpID8gMTAwMCA6IDEwMjQ7XG4gICAgICAgIGlmKE1hdGguYWJzKGJ5dGVzKSA8IHRocmVzaCkge1xuICAgICAgICAgICAgcmV0dXJuIGJ5dGVzICsgJyBCJztcbiAgICAgICAgfVxuICAgICAgICB2YXIgdW5pdHMgPSBzaVxuICAgICAgICAgICAgPyBbJ2tCJywnTUInLCdHQicsJ1RCJywnUEInLCdFQicsJ1pCJywnWUInXVxuICAgICAgICAgICAgOiBbJ0tpQicsJ01pQicsJ0dpQicsJ1RpQicsJ1BpQicsJ0VpQicsJ1ppQicsJ1lpQiddO1xuICAgICAgICB2YXIgdSA9IC0xO1xuICAgICAgICBkbyB7XG4gICAgICAgICAgICBieXRlcyAvPSB0aHJlc2g7XG4gICAgICAgICAgICArK3U7XG4gICAgICAgIH0gd2hpbGUgKE1hdGguYWJzKGJ5dGVzKSA+PSB0aHJlc2ggJiYgdSA8IHVuaXRzLmxlbmd0aCAtIDEpO1xuICAgICAgICByZXR1cm4gYnl0ZXMudG9GaXhlZCgxKSArICcgJyArIHVuaXRzW3VdO1xuICAgIH1cblxufVxuXG5leHBvcnQgZGVmYXVsdCBTdGF0czsiLCJcInVzZSBzdHJpY3RcIjtcblxuY2xhc3MgVGFncyB7XG4gICAgc3RhdGljIHNldHVwKCkge1xuICAgICAgICAvLyBzZXQgdXAgdGFnc1xuICAgICAgICAkKCdbZGF0YS10YWdzLWlucHV0XScpLmVhY2goKGluZGV4LCBlbGVtKSA9PiB7XG4gICAgICAgICAgICAkKGVsZW0pLnRhZ3NJbnB1dCh7d2lkdGg6IFwiMTAwJVwiLCBoZWlnaHQ6IFwiMzVweFwiLCBkZWZhdWx0VGV4dDogXCIrXCJ9KTtcbiAgICAgICAgfSk7XG4gICAgfVxufVxuXG5leHBvcnQgZGVmYXVsdCBUYWdzOyIsIlwidXNlIHN0cmljdFwiO1xuXG5jbGFzcyBUb29sYmFyIHtcbiAgICBzdGF0aWMgc2V0dXAoKSB7XG4gICAgICAgIHZhciBfdGhpcyA9IHRoaXM7XG4gICAgICAgICQoJy50b29sYmFyIC5sb2didXR0b24nKS5jbGljayhmdW5jdGlvbihlKSB7XG4gICAgICAgICAgICBfdGhpcy5vbkNsaWNrTG9nQnV0dG9uKGUsIHRoaXMpO1xuICAgICAgICB9KTtcbiAgICB9XG5cbiAgICBzdGF0aWMgb25DbGlja0xvZ0J1dHRvbihlLCBlbGVtKSB7XG4gICAgICAgICQoZWxlbSkudG9nZ2xlQ2xhc3MoJ2FjdGl2ZScpO1xuICAgICAgICAkKCcjbG9nLXdyYXBwZXInKS50b2dnbGUoKTtcbiAgICB9XG59XG5cbmV4cG9ydCBkZWZhdWx0IFRvb2xiYXI7IiwiXCJ1c2Ugc3RyaWN0XCI7XG5cbmNsYXNzIFV0aWxzIHtcbiAgICBzdGF0aWMgYWRkVG9QYXRoTmFtZShyZWxhdGl2ZVVybCkge1xuICAgICAgbGV0IGRpdmlkZXIgPSAod2luZG93LmxvY2F0aW9uLnBhdGhuYW1lLnNsaWNlKC0xKSA9PSBcIi9cIikgPyBcIlwiIDogXCIvXCI7XG4gICAgICByZXR1cm4gd2luZG93LmxvY2F0aW9uLnBhdGhuYW1lICsgZGl2aWRlciArIHJlbGF0aXZlVXJsO1xuICAgIH1cbiAgICBzdGF0aWMgdGVzdCgpIHtcbiAgICAgICAgY29uc29sZS5sb2coXCJ0ZXN0aW5nXCIpO1xuICAgIH1cbn1cblxuZXhwb3J0IGRlZmF1bHQgVXRpbHM7IiwiXCJ1c2Ugc3RyaWN0XCI7XG5cbmNsYXNzIFZleCB7XG4gICAgc3RhdGljIHNldHVwKCkge1xuICAgICAgICAvLyBzZXQgZGVmYXVsdCB0aGVtZSBmb3IgdmV4IGRpYWxvZ3NcbiAgICAgICAgdmV4LmRlZmF1bHRPcHRpb25zLmNsYXNzTmFtZSA9ICd2ZXgtdGhlbWUtcGxhaW4nO1xuICAgICAgICB2ZXguZGlhbG9nLmJ1dHRvbnMuWUVTLnRleHQgPSAnT0snO1xuICAgICAgICB2ZXguZGlhbG9nLmJ1dHRvbnMuTk8udGV4dCA9ICdBbmdyZSc7XG4gICAgfVxufVxuXG5leHBvcnQgZGVmYXVsdCBWZXg7IiwiXCJ1c2Ugc3RyaWN0XCI7XG5cbmltcG9ydCB7U29ja2V0fSBmcm9tICcuLi8uLi8uLi9kZXBzL3Bob2VuaXgvd2ViL3N0YXRpYy9qcy9waG9lbml4LmpzJ1xuXG5jbGFzcyBXUyB7XG4gICAgc3RhdGljIHNldHVwKCkge1xuICAgICAgICB2YXIgX3RoaXMgPSB0aGlzO1xuICAgICAgICBsZXQgc29ja2V0ID0gbmV3IFNvY2tldChcIi9hZG1pbi93c1wiKTtcbiAgICAgICAgbGV0IHVzZXJfdG9rZW4gPSBkb2N1bWVudC5xdWVyeVNlbGVjdG9yKFwibWV0YVtuYW1lPVxcXCJjaGFubmVsX3Rva2VuXFxcIl1cIikuZ2V0QXR0cmlidXRlKFwiY29udGVudFwiKTtcbiAgICAgICAgc29ja2V0LmNvbm5lY3Qoe3Rva2VuOiB1c2VyX3Rva2VufSk7XG4gICAgICAgIGxldCBjaGFuID0gc29ja2V0LmNoYW5uZWwoXCJzeXN0ZW06c3RyZWFtXCIsIHt9KTtcbiAgICAgICAgY2hhbi5qb2luKCkucmVjZWl2ZShcIm9rXCIsICh7bWVzc2FnZXN9KSA9PiB7XG4gICAgICAgICAgICBjb25zb2xlLmxvZyhcIj4+IFN5c3RlbSBjaGFubmVsIHJlYWR5XCIpO1xuICAgICAgICB9KTtcbiAgICAgICAgY2hhbi5vbihcImxvZ19tc2dcIiwgcGF5bG9hZCA9PiB7XG4gICAgICAgICAgICBfdGhpcy5sb2cocGF5bG9hZC5sZXZlbCwgcGF5bG9hZC5pY29uLCBwYXlsb2FkLmJvZHkpO1xuICAgICAgICB9KTtcbiAgICB9XG4gICAgc3RhdGljIGxvZyhsZXZlbCwgaWNvbiwgYm9keSkge1xuICAgICAgICBsZXQgZGF0ZSA9IG5ldyBEYXRlKCk7XG4gICAgICAgICQoYDxsaT48aSBjbGFzcz1cImZhIGZhLWZ3ICR7aWNvbn0gbS1sLXNtIG0tci1zbVwiPiA8L2k+IDxzcGFuIGNsYXNzPVwidGltZSBwLXItc21cIj4ke2RhdGUuZ2V0SG91cnMoKX06JHtkYXRlLmdldE1pbnV0ZXMoKX08L3NwYW4+JHtib2R5fTwvbGk+YCkuYXBwZW5kVG8oXCIjbG9nLWNvbnRlbnRcIik7XG4gICAgfVxufVxuXG5leHBvcnQgZGVmYXVsdCBXUzsiLCIvLyBQaG9lbml4IENoYW5uZWxzIEphdmFTY3JpcHQgY2xpZW50XG4vL1xuLy8gIyMgU29ja2V0IENvbm5lY3Rpb25cbi8vXG4vLyBBIHNpbmdsZSBjb25uZWN0aW9uIGlzIGVzdGFibGlzaGVkIHRvIHRoZSBzZXJ2ZXIgYW5kXG4vLyBjaGFubmVscyBhcmUgbXVsaXRwbGV4ZWQgb3ZlciB0aGUgY29ubmVjdGlvbi5cbi8vIENvbm5lY3QgdG8gdGhlIHNlcnZlciB1c2luZyB0aGUgYFNvY2tldGAgY2xhc3M6XG4vL1xuLy8gICAgIGxldCBzb2NrZXQgPSBuZXcgU29ja2V0KFwiL3dzXCIpXG4vLyAgICAgc29ja2V0LmNvbm5lY3Qoe3VzZXJUb2tlbjogXCIxMjNcIn0pXG4vL1xuLy8gVGhlIGBTb2NrZXRgIGNvbnN0cnVjdG9yIHRha2VzIHRoZSBtb3VudCBwb2ludCBvZiB0aGUgc29ja2V0XG4vLyBhcyB3ZWxsIGFzIG9wdGlvbnMgdGhhdCBjYW4gYmUgZm91bmQgaW4gdGhlIFNvY2tldCBkb2NzLFxuLy8gc3VjaCBhcyBjb25maWd1cmluZyB0aGUgYExvbmdQb2xsYCB0cmFuc3BvcnQsIGFuZCBoZWFydGJlYXQuXG4vLyBTb2NrZXQgcGFyYW1zIGNhbiBhbHNvIGJlIHBhc3NlZCBhcyBhbiBvYmplY3QgbGl0ZXJhbCB0byBgY29ubmVjdGAuXG4vL1xuLy8gIyMgQ2hhbm5lbHNcbi8vXG4vLyBDaGFubmVscyBhcmUgaXNvbGF0ZWQsIGNvbmN1cnJlbnQgcHJvY2Vzc2VzIG9uIHRoZSBzZXJ2ZXIgdGhhdFxuLy8gc3Vic2NyaWJlIHRvIHRvcGljcyBhbmQgYnJva2VyIGV2ZW50cyBiZXR3ZWVuIHRoZSBjbGllbnQgYW5kIHNlcnZlci5cbi8vIFRvIGpvaW4gYSBjaGFubmVsLCB5b3UgbXVzdCBwcm92aWRlIHRoZSB0b3BpYywgYW5kIGNoYW5uZWwgcGFyYW1zIGZvclxuLy8gYXV0aG9yaXphdGlvbi4gSGVyZSdzIGFuIGV4YW1wbGUgY2hhdCByb29tIGV4YW1wbGUgd2hlcmUgYFwibmV3X21zZ1wiYFxuLy8gZXZlbnRzIGFyZSBsaXN0ZW5lZCBmb3IsIG1lc3NhZ2VzIGFyZSBwdXNoZWQgdG8gdGhlIHNlcnZlciwgYW5kXG4vLyB0aGUgY2hhbm5lbCBpcyBqb2luZWQgd2l0aCBvay9lcnJvciBtYXRjaGVzLCBhbmQgYGFmdGVyYCBob29rOlxuLy9cbi8vICAgICBsZXQgY2hhbm5lbCA9IHNvY2tldC5jaGFubmVsKFwicm9vbXM6MTIzXCIsIHt0b2tlbjogcm9vbVRva2VufSlcbi8vICAgICBjaGFubmVsLm9uKFwibmV3X21zZ1wiLCBtc2cgPT4gY29uc29sZS5sb2coXCJHb3QgbWVzc2FnZVwiLCBtc2cpIClcbi8vICAgICAkaW5wdXQub25FbnRlciggZSA9PiB7XG4vLyAgICAgICBjaGFubmVsLnB1c2goXCJuZXdfbXNnXCIsIHtib2R5OiBlLnRhcmdldC52YWx9KVxuLy8gICAgICAgIC5yZWNlaXZlKFwib2tcIiwgKG1zZykgPT4gY29uc29sZS5sb2coXCJjcmVhdGVkIG1lc3NhZ2VcIiwgbXNnKSApXG4vLyAgICAgICAgLnJlY2VpdmUoXCJlcnJvclwiLCAocmVhc29ucykgPT4gY29uc29sZS5sb2coXCJjcmVhdGUgZmFpbGVkXCIsIHJlYXNvbnMpIClcbi8vICAgICAgICAuYWZ0ZXIoMTAwMDAsICgpID0+IGNvbnNvbGUubG9nKFwiTmV0d29ya2luZyBpc3N1ZS4gU3RpbGwgd2FpdGluZy4uLlwiKSApXG4vLyAgICAgfSlcbi8vICAgICBjaGFubmVsLmpvaW4oKVxuLy8gICAgICAgLnJlY2VpdmUoXCJva1wiLCAoe21lc3NhZ2VzfSkgPT4gY29uc29sZS5sb2coXCJjYXRjaGluZyB1cFwiLCBtZXNzYWdlcykgKVxuLy8gICAgICAgLnJlY2VpdmUoXCJlcnJvclwiLCAoe3JlYXNvbn0pID0+IGNvbnNvbGUubG9nKFwiZmFpbGVkIGpvaW5cIiwgcmVhc29uKSApXG4vLyAgICAgICAuYWZ0ZXIoMTAwMDAsICgpID0+IGNvbnNvbGUubG9nKFwiTmV0d29ya2luZyBpc3N1ZS4gU3RpbGwgd2FpdGluZy4uLlwiKSApXG4vL1xuLy9cbi8vICMjIEpvaW5pbmdcbi8vXG4vLyBKb2luaW5nIGEgY2hhbm5lbCB3aXRoIGBjaGFubmVsLmpvaW4odG9waWMsIHBhcmFtcylgLCBiaW5kcyB0aGUgcGFyYW1zIHRvXG4vLyBgY2hhbm5lbC5wYXJhbXNgLiBTdWJzZXF1ZW50IHJlam9pbnMgd2lsbCBzZW5kIHVwIHRoZSBtb2RpZmllZCBwYXJhbXMgZm9yXG4vLyB1cGRhdGluZyBhdXRob3JpemF0aW9uIHBhcmFtcywgb3IgcGFzc2luZyB1cCBsYXN0X21lc3NhZ2VfaWQgaW5mb3JtYXRpb24uXG4vLyBTdWNjZXNzZnVsIGpvaW5zIHJlY2VpdmUgYW4gXCJva1wiIHN0YXR1cywgd2hpbGUgdW5zdWNjZXNzZnVsIGpvaW5zXG4vLyByZWNlaXZlIFwiZXJyb3JcIi5cbi8vXG4vL1xuLy8gIyMgUHVzaGluZyBNZXNzYWdlc1xuLy9cbi8vIEZyb20gdGhlIHByZXZpb3VzIGV4YW1wbGUsIHdlIGNhbiBzZWUgdGhhdCBwdXNoaW5nIG1lc3NhZ2VzIHRvIHRoZSBzZXJ2ZXJcbi8vIGNhbiBiZSBkb25lIHdpdGggYGNoYW5uZWwucHVzaChldmVudE5hbWUsIHBheWxvYWQpYCBhbmQgd2UgY2FuIG9wdGlvbmFsbHlcbi8vIHJlY2VpdmUgcmVzcG9uc2VzIGZyb20gdGhlIHB1c2guIEFkZGl0aW9uYWxseSwgd2UgY2FuIHVzZVxuLy8gYGFmdGVyKG1pbGxzZWMsIGNhbGxiYWNrKWAgdG8gYWJvcnQgd2FpdGluZyBmb3Igb3VyIGByZWNlaXZlYCBob29rcyBhbmRcbi8vIHRha2UgYWN0aW9uIGFmdGVyIHNvbWUgcGVyaW9kIG9mIHdhaXRpbmcuXG4vL1xuLy9cbi8vICMjIFNvY2tldCBIb29rc1xuLy9cbi8vIExpZmVjeWNsZSBldmVudHMgb2YgdGhlIG11bHRpcGxleGVkIGNvbm5lY3Rpb24gY2FuIGJlIGhvb2tlZCBpbnRvIHZpYVxuLy8gYHNvY2tldC5vbkVycm9yKClgIGFuZCBgc29ja2V0Lm9uQ2xvc2UoKWAgZXZlbnRzLCBpZTpcbi8vXG4vLyAgICAgc29ja2V0Lm9uRXJyb3IoICgpID0+IGNvbnNvbGUubG9nKFwidGhlcmUgd2FzIGFuIGVycm9yIHdpdGggdGhlIGNvbm5lY3Rpb24hXCIpIClcbi8vICAgICBzb2NrZXQub25DbG9zZSggKCkgPT4gY29uc29sZS5sb2coXCJ0aGUgY29ubmVjdGlvbiBkcm9wcGVkXCIpIClcbi8vXG4vL1xuLy8gIyMgQ2hhbm5lbCBIb29rc1xuLy9cbi8vIEZvciBlYWNoIGpvaW5lZCBjaGFubmVsLCB5b3UgY2FuIGJpbmQgdG8gYG9uRXJyb3JgIGFuZCBgb25DbG9zZWAgZXZlbnRzXG4vLyB0byBtb25pdG9yIHRoZSBjaGFubmVsIGxpZmVjeWNsZSwgaWU6XG4vL1xuLy8gICAgIGNoYW5uZWwub25FcnJvciggKCkgPT4gY29uc29sZS5sb2coXCJ0aGVyZSB3YXMgYW4gZXJyb3IhXCIpIClcbi8vICAgICBjaGFubmVsLm9uQ2xvc2UoICgpID0+IGNvbnNvbGUubG9nKFwidGhlIGNoYW5uZWwgaGFzIGdvbmUgYXdheSBncmFjZWZ1bGx5XCIpIClcbi8vXG4vLyAjIyMgb25FcnJvciBob29rc1xuLy9cbi8vIGBvbkVycm9yYCBob29rcyBhcmUgaW52b2tlZCBpZiB0aGUgc29ja2V0IGNvbm5lY3Rpb24gZHJvcHMsIG9yIHRoZSBjaGFubmVsXG4vLyBjcmFzaGVzIG9uIHRoZSBzZXJ2ZXIuIEluIGVpdGhlciBjYXNlLCBhIGNoYW5uZWwgcmVqb2luIGlzIGF0dGVtdHBlZFxuLy8gYXV0b21hdGljYWxseSBpbiBhbiBleHBvbmVudGlhbCBiYWNrb2ZmIG1hbm5lci5cbi8vXG4vLyAjIyMgb25DbG9zZSBob29rc1xuLy9cbi8vIGBvbkNsb3NlYCBob29rcyBhcmUgaW52b2tlZCBvbmx5IGluIHR3byBjYXNlcy4gMSkgdGhlIGNoYW5uZWwgZXhwbGljaXRseVxuLy8gY2xvc2VkIG9uIHRoZSBzZXJ2ZXIsIG9yIDIpLiBUaGUgY2xpZW50IGV4cGxpY2l0bHkgY2xvc2VkLCBieSBjYWxsaW5nXG4vLyBgY2hhbm5lbC5sZWF2ZSgpYFxuLy9cblxuY29uc3QgVlNOID0gXCIxLjAuMFwiXG5jb25zdCBTT0NLRVRfU1RBVEVTID0ge2Nvbm5lY3Rpbmc6IDAsIG9wZW46IDEsIGNsb3Npbmc6IDIsIGNsb3NlZDogM31cbmNvbnN0IENIQU5ORUxfU1RBVEVTID0ge1xuICBjbG9zZWQ6IFwiY2xvc2VkXCIsXG4gIGVycm9yZWQ6IFwiZXJyb3JlZFwiLFxuICBqb2luZWQ6IFwiam9pbmVkXCIsXG4gIGpvaW5pbmc6IFwiam9pbmluZ1wiLFxufVxuY29uc3QgQ0hBTk5FTF9FVkVOVFMgPSB7XG4gIGNsb3NlOiBcInBoeF9jbG9zZVwiLFxuICBlcnJvcjogXCJwaHhfZXJyb3JcIixcbiAgam9pbjogXCJwaHhfam9pblwiLFxuICByZXBseTogXCJwaHhfcmVwbHlcIixcbiAgbGVhdmU6IFwicGh4X2xlYXZlXCJcbn1cbmNvbnN0IFRSQU5TUE9SVFMgPSB7XG4gIGxvbmdwb2xsOiBcImxvbmdwb2xsXCIsXG4gIHdlYnNvY2tldDogXCJ3ZWJzb2NrZXRcIlxufVxuXG5jbGFzcyBQdXNoIHtcblxuICAvLyBJbml0aWFsaXplcyB0aGUgUHVzaFxuICAvL1xuICAvLyBjaGFubmVsIC0gVGhlIENoYW5uZWxuZWxcbiAgLy8gZXZlbnQgLSBUaGUgZXZlbnQsIGZvciBleGFtcGxlIGBcInBoeF9qb2luXCJgXG4gIC8vIHBheWxvYWQgLSBUaGUgcGF5bG9hZCwgZm9yIGV4YW1wbGUgYHt1c2VyX2lkOiAxMjN9YFxuICAvL1xuICBjb25zdHJ1Y3RvcihjaGFubmVsLCBldmVudCwgcGF5bG9hZCl7XG4gICAgdGhpcy5jaGFubmVsICAgICAgPSBjaGFubmVsXG4gICAgdGhpcy5ldmVudCAgICAgICAgPSBldmVudFxuICAgIHRoaXMucGF5bG9hZCAgICAgID0gcGF5bG9hZCB8fCB7fVxuICAgIHRoaXMucmVjZWl2ZWRSZXNwID0gbnVsbFxuICAgIHRoaXMuYWZ0ZXJIb29rICAgID0gbnVsbFxuICAgIHRoaXMucmVjSG9va3MgICAgID0gW11cbiAgICB0aGlzLnNlbnQgICAgICAgICA9IGZhbHNlXG4gIH1cblxuICBzZW5kKCl7XG4gICAgY29uc3QgcmVmICAgICAgICAgPSB0aGlzLmNoYW5uZWwuc29ja2V0Lm1ha2VSZWYoKVxuICAgIHRoaXMucmVmRXZlbnQgICAgID0gdGhpcy5jaGFubmVsLnJlcGx5RXZlbnROYW1lKHJlZilcbiAgICB0aGlzLnJlY2VpdmVkUmVzcCA9IG51bGxcbiAgICB0aGlzLnNlbnQgICAgICAgICA9IGZhbHNlXG5cbiAgICB0aGlzLmNoYW5uZWwub24odGhpcy5yZWZFdmVudCwgcGF5bG9hZCA9PiB7XG4gICAgICB0aGlzLnJlY2VpdmVkUmVzcCA9IHBheWxvYWRcbiAgICAgIHRoaXMubWF0Y2hSZWNlaXZlKHBheWxvYWQpXG4gICAgICB0aGlzLmNhbmNlbFJlZkV2ZW50KClcbiAgICAgIHRoaXMuY2FuY2VsQWZ0ZXIoKVxuICAgIH0pXG5cbiAgICB0aGlzLnN0YXJ0QWZ0ZXIoKVxuICAgIHRoaXMuc2VudCA9IHRydWVcbiAgICB0aGlzLmNoYW5uZWwuc29ja2V0LnB1c2goe1xuICAgICAgdG9waWM6IHRoaXMuY2hhbm5lbC50b3BpYyxcbiAgICAgIGV2ZW50OiB0aGlzLmV2ZW50LFxuICAgICAgcGF5bG9hZDogdGhpcy5wYXlsb2FkLFxuICAgICAgcmVmOiByZWZcbiAgICB9KVxuICB9XG5cbiAgcmVjZWl2ZShzdGF0dXMsIGNhbGxiYWNrKXtcbiAgICBpZih0aGlzLnJlY2VpdmVkUmVzcCAmJiB0aGlzLnJlY2VpdmVkUmVzcC5zdGF0dXMgPT09IHN0YXR1cyl7XG4gICAgICBjYWxsYmFjayh0aGlzLnJlY2VpdmVkUmVzcC5yZXNwb25zZSlcbiAgICB9XG5cbiAgICB0aGlzLnJlY0hvb2tzLnB1c2goe3N0YXR1cywgY2FsbGJhY2t9KVxuICAgIHJldHVybiB0aGlzXG4gIH1cblxuICBhZnRlcihtcywgY2FsbGJhY2spe1xuICAgIGlmKHRoaXMuYWZ0ZXJIb29rKXsgdGhyb3coYG9ubHkgYSBzaW5nbGUgYWZ0ZXIgaG9vayBjYW4gYmUgYXBwbGllZCB0byBhIHB1c2hgKSB9XG4gICAgbGV0IHRpbWVyID0gbnVsbFxuICAgIGlmKHRoaXMuc2VudCl7IHRpbWVyID0gc2V0VGltZW91dChjYWxsYmFjaywgbXMpIH1cbiAgICB0aGlzLmFmdGVySG9vayA9IHttczogbXMsIGNhbGxiYWNrOiBjYWxsYmFjaywgdGltZXI6IHRpbWVyfVxuICAgIHJldHVybiB0aGlzXG4gIH1cblxuXG4gIC8vIHByaXZhdGVcblxuICBtYXRjaFJlY2VpdmUoe3N0YXR1cywgcmVzcG9uc2UsIHJlZn0pe1xuICAgIHRoaXMucmVjSG9va3MuZmlsdGVyKCBoID0+IGguc3RhdHVzID09PSBzdGF0dXMgKVxuICAgICAgICAgICAgICAgICAuZm9yRWFjaCggaCA9PiBoLmNhbGxiYWNrKHJlc3BvbnNlKSApXG4gIH1cblxuICBjYW5jZWxSZWZFdmVudCgpeyB0aGlzLmNoYW5uZWwub2ZmKHRoaXMucmVmRXZlbnQpIH1cblxuICBjYW5jZWxBZnRlcigpeyBpZighdGhpcy5hZnRlckhvb2speyByZXR1cm4gfVxuICAgIGNsZWFyVGltZW91dCh0aGlzLmFmdGVySG9vay50aW1lcilcbiAgICB0aGlzLmFmdGVySG9vay50aW1lciA9IG51bGxcbiAgfVxuXG4gIHN0YXJ0QWZ0ZXIoKXsgaWYoIXRoaXMuYWZ0ZXJIb29rKXsgcmV0dXJuIH1cbiAgICBsZXQgY2FsbGJhY2sgPSAoKSA9PiB7XG4gICAgICB0aGlzLmNhbmNlbFJlZkV2ZW50KClcbiAgICAgIHRoaXMuYWZ0ZXJIb29rLmNhbGxiYWNrKClcbiAgICB9XG4gICAgdGhpcy5hZnRlckhvb2sudGltZXIgPSBzZXRUaW1lb3V0KGNhbGxiYWNrLCB0aGlzLmFmdGVySG9vay5tcylcbiAgfVxufVxuXG5leHBvcnQgY2xhc3MgQ2hhbm5lbCB7XG4gIGNvbnN0cnVjdG9yKHRvcGljLCBwYXJhbXMsIHNvY2tldCkge1xuICAgIHRoaXMuc3RhdGUgICAgICAgPSBDSEFOTkVMX1NUQVRFUy5jbG9zZWRcbiAgICB0aGlzLnRvcGljICAgICAgID0gdG9waWNcbiAgICB0aGlzLnBhcmFtcyAgICAgID0gcGFyYW1zIHx8IHt9XG4gICAgdGhpcy5zb2NrZXQgICAgICA9IHNvY2tldFxuICAgIHRoaXMuYmluZGluZ3MgICAgPSBbXVxuICAgIHRoaXMuam9pbmVkT25jZSAgPSBmYWxzZVxuICAgIHRoaXMuam9pblB1c2ggICAgPSBuZXcgUHVzaCh0aGlzLCBDSEFOTkVMX0VWRU5UUy5qb2luLCB0aGlzLnBhcmFtcylcbiAgICB0aGlzLnB1c2hCdWZmZXIgID0gW11cbiAgICB0aGlzLnJlam9pblRpbWVyICA9IG5ldyBUaW1lcihcbiAgICAgICgpID0+IHRoaXMucmVqb2luVW50aWxDb25uZWN0ZWQoKSxcbiAgICAgIHRoaXMuc29ja2V0LnJlY29ubmVjdEFmdGVyTXNcbiAgICApXG4gICAgdGhpcy5qb2luUHVzaC5yZWNlaXZlKFwib2tcIiwgKCkgPT4ge1xuICAgICAgdGhpcy5zdGF0ZSA9IENIQU5ORUxfU1RBVEVTLmpvaW5lZFxuICAgICAgdGhpcy5yZWpvaW5UaW1lci5yZXNldCgpXG4gICAgfSlcbiAgICB0aGlzLm9uQ2xvc2UoICgpID0+IHtcbiAgICAgIHRoaXMuc29ja2V0LmxvZyhcImNoYW5uZWxcIiwgYGNsb3NlICR7dGhpcy50b3BpY31gKVxuICAgICAgdGhpcy5zdGF0ZSA9IENIQU5ORUxfU1RBVEVTLmNsb3NlZFxuICAgICAgdGhpcy5zb2NrZXQucmVtb3ZlKHRoaXMpXG4gICAgfSlcbiAgICB0aGlzLm9uRXJyb3IoIHJlYXNvbiA9PiB7XG4gICAgICB0aGlzLnNvY2tldC5sb2coXCJjaGFubmVsXCIsIGBlcnJvciAke3RoaXMudG9waWN9YCwgcmVhc29uKVxuICAgICAgdGhpcy5zdGF0ZSA9IENIQU5ORUxfU1RBVEVTLmVycm9yZWRcbiAgICAgIHRoaXMucmVqb2luVGltZXIuc2V0VGltZW91dCgpXG4gICAgfSlcbiAgICB0aGlzLm9uKENIQU5ORUxfRVZFTlRTLnJlcGx5LCAocGF5bG9hZCwgcmVmKSA9PiB7XG4gICAgICB0aGlzLnRyaWdnZXIodGhpcy5yZXBseUV2ZW50TmFtZShyZWYpLCBwYXlsb2FkKVxuICAgIH0pXG4gIH1cblxuICByZWpvaW5VbnRpbENvbm5lY3RlZCgpe1xuICAgIHRoaXMucmVqb2luVGltZXIuc2V0VGltZW91dCgpXG4gICAgaWYodGhpcy5zb2NrZXQuaXNDb25uZWN0ZWQoKSl7XG4gICAgICB0aGlzLnJlam9pbigpXG4gICAgfVxuICB9XG5cbiAgam9pbigpe1xuICAgIGlmKHRoaXMuam9pbmVkT25jZSl7XG4gICAgICB0aHJvdyhgdHJpZWQgdG8gam9pbiBtdWx0aXBsZSB0aW1lcy4gJ2pvaW4nIGNhbiBvbmx5IGJlIGNhbGxlZCBhIHNpbmdsZSB0aW1lIHBlciBjaGFubmVsIGluc3RhbmNlYClcbiAgICB9IGVsc2Uge1xuICAgICAgdGhpcy5qb2luZWRPbmNlID0gdHJ1ZVxuICAgIH1cbiAgICB0aGlzLnNlbmRKb2luKClcbiAgICByZXR1cm4gdGhpcy5qb2luUHVzaFxuICB9XG5cbiAgb25DbG9zZShjYWxsYmFjayl7IHRoaXMub24oQ0hBTk5FTF9FVkVOVFMuY2xvc2UsIGNhbGxiYWNrKSB9XG5cbiAgb25FcnJvcihjYWxsYmFjayl7XG4gICAgdGhpcy5vbihDSEFOTkVMX0VWRU5UUy5lcnJvciwgcmVhc29uID0+IGNhbGxiYWNrKHJlYXNvbikgKVxuICB9XG5cbiAgb24oZXZlbnQsIGNhbGxiYWNrKXsgdGhpcy5iaW5kaW5ncy5wdXNoKHtldmVudCwgY2FsbGJhY2t9KSB9XG5cbiAgb2ZmKGV2ZW50KXsgdGhpcy5iaW5kaW5ncyA9IHRoaXMuYmluZGluZ3MuZmlsdGVyKCBiaW5kID0+IGJpbmQuZXZlbnQgIT09IGV2ZW50ICkgfVxuXG4gIGNhblB1c2goKXsgcmV0dXJuIHRoaXMuc29ja2V0LmlzQ29ubmVjdGVkKCkgJiYgdGhpcy5zdGF0ZSA9PT0gQ0hBTk5FTF9TVEFURVMuam9pbmVkIH1cblxuICBwdXNoKGV2ZW50LCBwYXlsb2FkKXtcbiAgICBpZighdGhpcy5qb2luZWRPbmNlKXtcbiAgICAgIHRocm93KGB0cmllZCB0byBwdXNoICcke2V2ZW50fScgdG8gJyR7dGhpcy50b3BpY30nIGJlZm9yZSBqb2luaW5nLiBVc2UgY2hhbm5lbC5qb2luKCkgYmVmb3JlIHB1c2hpbmcgZXZlbnRzYClcbiAgICB9XG4gICAgbGV0IHB1c2hFdmVudCA9IG5ldyBQdXNoKHRoaXMsIGV2ZW50LCBwYXlsb2FkKVxuICAgIGlmKHRoaXMuY2FuUHVzaCgpKXtcbiAgICAgIHB1c2hFdmVudC5zZW5kKClcbiAgICB9IGVsc2Uge1xuICAgICAgdGhpcy5wdXNoQnVmZmVyLnB1c2gocHVzaEV2ZW50KVxuICAgIH1cblxuICAgIHJldHVybiBwdXNoRXZlbnRcbiAgfVxuXG4gIC8vIExlYXZlcyB0aGUgY2hhbm5lbFxuICAvL1xuICAvLyBVbnN1YnNjcmliZXMgZnJvbSBzZXJ2ZXIgZXZlbnRzLCBhbmRcbiAgLy8gaW5zdHJ1Y3RzIGNoYW5uZWwgdG8gdGVybWluYXRlIG9uIHNlcnZlclxuICAvL1xuICAvLyBUcmlnZ2VycyBvbkNsb3NlKCkgaG9va3NcbiAgLy9cbiAgLy8gVG8gcmVjZWl2ZSBsZWF2ZSBhY2tub3dsZWRnZW1lbnRzLCB1c2UgdGhlIGEgYHJlY2VpdmVgXG4gIC8vIGhvb2sgdG8gYmluZCB0byB0aGUgc2VydmVyIGFjaywgaWU6XG4gIC8vXG4gIC8vICAgICBjaGFubmVsLmxlYXZlKCkucmVjZWl2ZShcIm9rXCIsICgpID0+IGFsZXJ0KFwibGVmdCFcIikgKVxuICAvL1xuICBsZWF2ZSgpe1xuICAgIHJldHVybiB0aGlzLnB1c2goQ0hBTk5FTF9FVkVOVFMubGVhdmUpLnJlY2VpdmUoXCJva1wiLCAoKSA9PiB7XG4gICAgICB0aGlzLnNvY2tldC5sb2coXCJjaGFubmVsXCIsIGBsZWF2ZSAke3RoaXMudG9waWN9YClcbiAgICAgIHRoaXMudHJpZ2dlcihDSEFOTkVMX0VWRU5UUy5jbG9zZSwgXCJsZWF2ZVwiKVxuICAgIH0pXG4gIH1cblxuICAvLyBPdmVycmlkYWJsZSBtZXNzYWdlIGhvb2tcbiAgLy9cbiAgLy8gUmVjZWl2ZXMgYWxsIGV2ZW50cyBmb3Igc3BlY2lhbGl6ZWQgbWVzc2FnZSBoYW5kbGluZ1xuICBvbk1lc3NhZ2UoZXZlbnQsIHBheWxvYWQsIHJlZil7fVxuXG4gIC8vIHByaXZhdGVcblxuICBpc01lbWJlcih0b3BpYyl7IHJldHVybiB0aGlzLnRvcGljID09PSB0b3BpYyB9XG5cbiAgc2VuZEpvaW4oKXtcbiAgICB0aGlzLnN0YXRlID0gQ0hBTk5FTF9TVEFURVMuam9pbmluZ1xuICAgIHRoaXMuam9pblB1c2guc2VuZCgpXG4gIH1cblxuICByZWpvaW4oKXtcbiAgICB0aGlzLnNlbmRKb2luKClcbiAgICB0aGlzLnB1c2hCdWZmZXIuZm9yRWFjaCggcHVzaEV2ZW50ID0+IHB1c2hFdmVudC5zZW5kKCkgKVxuICAgIHRoaXMucHVzaEJ1ZmZlciA9IFtdXG4gIH1cblxuICB0cmlnZ2VyKHRyaWdnZXJFdmVudCwgcGF5bG9hZCwgcmVmKXtcbiAgICB0aGlzLm9uTWVzc2FnZSh0cmlnZ2VyRXZlbnQsIHBheWxvYWQsIHJlZilcbiAgICB0aGlzLmJpbmRpbmdzLmZpbHRlciggYmluZCA9PiBiaW5kLmV2ZW50ID09PSB0cmlnZ2VyRXZlbnQgKVxuICAgICAgICAgICAgICAgICAubWFwKCBiaW5kID0+IGJpbmQuY2FsbGJhY2socGF5bG9hZCwgcmVmKSApXG4gIH1cblxuICByZXBseUV2ZW50TmFtZShyZWYpeyByZXR1cm4gYGNoYW5fcmVwbHlfJHtyZWZ9YCB9XG59XG5cbmV4cG9ydCBjbGFzcyBTb2NrZXQge1xuXG4gIC8vIEluaXRpYWxpemVzIHRoZSBTb2NrZXRcbiAgLy9cbiAgLy8gZW5kUG9pbnQgLSBUaGUgc3RyaW5nIFdlYlNvY2tldCBlbmRwb2ludCwgaWUsIFwid3M6Ly9leGFtcGxlLmNvbS93c1wiLFxuICAvLyAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgXCJ3c3M6Ly9leGFtcGxlLmNvbVwiXG4gIC8vICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBcIi93c1wiIChpbmhlcml0ZWQgaG9zdCAmIHByb3RvY29sKVxuICAvLyBvcHRzIC0gT3B0aW9uYWwgY29uZmlndXJhdGlvblxuICAvLyAgIHRyYW5zcG9ydCAtIFRoZSBXZWJzb2NrZXQgVHJhbnNwb3J0LCBmb3IgZXhhbXBsZSBXZWJTb2NrZXQgb3IgUGhvZW5peC5Mb25nUG9sbC5cbiAgLy8gICAgICAgICAgICAgICBEZWZhdWx0cyB0byBXZWJTb2NrZXQgd2l0aCBhdXRvbWF0aWMgTG9uZ1BvbGwgZmFsbGJhY2suXG4gIC8vICAgaGVhcnRiZWF0SW50ZXJ2YWxNcyAtIFRoZSBtaWxsaXNlYyBpbnRlcnZhbCB0byBzZW5kIGEgaGVhcnRiZWF0IG1lc3NhZ2VcbiAgLy8gICByZWNvbm5lY3RBZnRlck1zIC0gVGhlIG9wdGlvbmFsIGZ1bmN0aW9uIHRoYXQgcmV0dXJucyB0aGUgbWlsbHNlY1xuICAvLyAgICAgICAgICAgICAgICAgICAgICByZWNvbm5lY3QgaW50ZXJ2YWwuIERlZmF1bHRzIHRvIHN0ZXBwZWQgYmFja29mZiBvZjpcbiAgLy9cbiAgLy8gICAgIGZ1bmN0aW9uKHRyaWVzKXtcbiAgLy8gICAgICAgcmV0dXJuIFsxMDAwLCA1MDAwLCAxMDAwMF1bdHJpZXMgLSAxXSB8fCAxMDAwMFxuICAvLyAgICAgfVxuICAvL1xuICAvLyAgIGxvZ2dlciAtIFRoZSBvcHRpb25hbCBmdW5jdGlvbiBmb3Igc3BlY2lhbGl6ZWQgbG9nZ2luZywgaWU6XG4gIC8vICAgICBgbG9nZ2VyOiAoa2luZCwgbXNnLCBkYXRhKSA9PiB7IGNvbnNvbGUubG9nKGAke2tpbmR9OiAke21zZ31gLCBkYXRhKSB9XG4gIC8vXG4gIC8vICAgbG9uZ3BvbGxlclRpbWVvdXQgLSBUaGUgbWF4aW11bSB0aW1lb3V0IG9mIGEgbG9uZyBwb2xsIEFKQVggcmVxdWVzdC5cbiAgLy8gICAgICAgICAgICAgICAgICAgICAgICBEZWZhdWx0cyB0byAyMHMgKGRvdWJsZSB0aGUgc2VydmVyIGxvbmcgcG9sbCB0aW1lcikuXG4gIC8vXG4gIC8vIEZvciBJRTggc3VwcG9ydCB1c2UgYW4gRVM1LXNoaW0gKGh0dHBzOi8vZ2l0aHViLmNvbS9lcy1zaGltcy9lczUtc2hpbSlcbiAgLy9cbiAgY29uc3RydWN0b3IoZW5kUG9pbnQsIG9wdHMgPSB7fSl7XG4gICAgdGhpcy5zdGF0ZUNoYW5nZUNhbGxiYWNrcyA9IHtvcGVuOiBbXSwgY2xvc2U6IFtdLCBlcnJvcjogW10sIG1lc3NhZ2U6IFtdfVxuICAgIHRoaXMuY2hhbm5lbHMgICAgICAgICAgICAgPSBbXVxuICAgIHRoaXMuc2VuZEJ1ZmZlciAgICAgICAgICAgPSBbXVxuICAgIHRoaXMucmVmICAgICAgICAgICAgICAgICAgPSAwXG4gICAgdGhpcy50cmFuc3BvcnQgICAgICAgICAgICA9IG9wdHMudHJhbnNwb3J0IHx8IHdpbmRvdy5XZWJTb2NrZXQgfHwgTG9uZ1BvbGxcbiAgICB0aGlzLmhlYXJ0YmVhdEludGVydmFsTXMgID0gb3B0cy5oZWFydGJlYXRJbnRlcnZhbE1zIHx8IDMwMDAwXG4gICAgdGhpcy5yZWNvbm5lY3RBZnRlck1zICAgICA9IG9wdHMucmVjb25uZWN0QWZ0ZXJNcyB8fCBmdW5jdGlvbih0cmllcyl7XG4gICAgICByZXR1cm4gWzEwMDAsIDUwMDAsIDEwMDAwXVt0cmllcyAtIDFdIHx8IDEwMDAwXG4gICAgfVxuICAgIHRoaXMubG9nZ2VyICAgICAgICAgICAgICAgPSBvcHRzLmxvZ2dlciB8fCBmdW5jdGlvbigpe30gLy8gbm9vcFxuICAgIHRoaXMubG9uZ3BvbGxlclRpbWVvdXQgICAgPSBvcHRzLmxvbmdwb2xsZXJUaW1lb3V0IHx8IDIwMDAwXG4gICAgdGhpcy5wYXJhbXMgICAgICAgICAgICAgICA9IHt9XG4gICAgdGhpcy5yZWNvbm5lY3RUaW1lciAgICAgICA9IG5ldyBUaW1lcigoKSA9PiB0aGlzLmNvbm5lY3QodGhpcy5wYXJhbXMpLCB0aGlzLnJlY29ubmVjdEFmdGVyTXMpXG4gICAgdGhpcy5lbmRQb2ludCAgICAgICAgICAgICA9IGAke2VuZFBvaW50fS8ke1RSQU5TUE9SVFMud2Vic29ja2V0fWBcbiAgfVxuXG4gIHByb3RvY29sKCl7IHJldHVybiBsb2NhdGlvbi5wcm90b2NvbC5tYXRjaCgvXmh0dHBzLykgPyBcIndzc1wiIDogXCJ3c1wiIH1cblxuICBlbmRQb2ludFVSTCgpe1xuICAgIGxldCB1cmkgPSBBamF4LmFwcGVuZFBhcmFtcyhcbiAgICAgIEFqYXguYXBwZW5kUGFyYW1zKHRoaXMuZW5kUG9pbnQsIHRoaXMucGFyYW1zKSwge3ZzbjogVlNOfSlcbiAgICBpZih1cmkuY2hhckF0KDApICE9PSBcIi9cIil7IHJldHVybiB1cmkgfVxuICAgIGlmKHVyaS5jaGFyQXQoMSkgPT09IFwiL1wiKXsgcmV0dXJuIGAke3RoaXMucHJvdG9jb2woKX06JHt1cml9YCB9XG5cbiAgICByZXR1cm4gYCR7dGhpcy5wcm90b2NvbCgpfTovLyR7bG9jYXRpb24uaG9zdH0ke3VyaX1gXG4gIH1cblxuICBkaXNjb25uZWN0KGNhbGxiYWNrLCBjb2RlLCByZWFzb24pe1xuICAgIGlmKHRoaXMuY29ubil7XG4gICAgICB0aGlzLmNvbm4ub25jbG9zZSA9IGZ1bmN0aW9uKCl7fSAvLyBub29wXG4gICAgICBpZihjb2RlKXsgdGhpcy5jb25uLmNsb3NlKGNvZGUsIHJlYXNvbiB8fCBcIlwiKSB9IGVsc2UgeyB0aGlzLmNvbm4uY2xvc2UoKSB9XG4gICAgICB0aGlzLmNvbm4gPSBudWxsXG4gICAgfVxuICAgIGNhbGxiYWNrICYmIGNhbGxiYWNrKClcbiAgfVxuXG4gIC8vIHBhcmFtcyAtIFRoZSBwYXJhbXMgdG8gc2VuZCB3aGVuIGNvbm5lY3RpbmcsIGZvciBleGFtcGxlIGB7dXNlcl9pZDogdXNlclRva2VufWBcbiAgY29ubmVjdChwYXJhbXMgPSB7fSl7IHRoaXMucGFyYW1zID0gcGFyYW1zXG4gICAgdGhpcy5kaXNjb25uZWN0KCgpID0+IHtcbiAgICAgIHRoaXMuY29ubiA9IG5ldyB0aGlzLnRyYW5zcG9ydCh0aGlzLmVuZFBvaW50VVJMKCkpXG4gICAgICB0aGlzLmNvbm4udGltZW91dCAgID0gdGhpcy5sb25ncG9sbGVyVGltZW91dFxuICAgICAgdGhpcy5jb25uLm9ub3BlbiAgICA9ICgpID0+IHRoaXMub25Db25uT3BlbigpXG4gICAgICB0aGlzLmNvbm4ub25lcnJvciAgID0gZXJyb3IgPT4gdGhpcy5vbkNvbm5FcnJvcihlcnJvcilcbiAgICAgIHRoaXMuY29ubi5vbm1lc3NhZ2UgPSBldmVudCA9PiB0aGlzLm9uQ29ubk1lc3NhZ2UoZXZlbnQpXG4gICAgICB0aGlzLmNvbm4ub25jbG9zZSAgID0gZXZlbnQgPT4gdGhpcy5vbkNvbm5DbG9zZShldmVudClcbiAgICB9KVxuICB9XG5cbiAgLy8gTG9ncyB0aGUgbWVzc2FnZS4gT3ZlcnJpZGUgYHRoaXMubG9nZ2VyYCBmb3Igc3BlY2lhbGl6ZWQgbG9nZ2luZy4gbm9vcHMgYnkgZGVmYXVsdFxuICBsb2coa2luZCwgbXNnLCBkYXRhKXsgdGhpcy5sb2dnZXIoa2luZCwgbXNnLCBkYXRhKSB9XG5cbiAgLy8gUmVnaXN0ZXJzIGNhbGxiYWNrcyBmb3IgY29ubmVjdGlvbiBzdGF0ZSBjaGFuZ2UgZXZlbnRzXG4gIC8vXG4gIC8vIEV4YW1wbGVzXG4gIC8vXG4gIC8vICAgIHNvY2tldC5vbkVycm9yKGZ1bmN0aW9uKGVycm9yKXsgYWxlcnQoXCJBbiBlcnJvciBvY2N1cnJlZFwiKSB9KVxuICAvL1xuICBvbk9wZW4gICAgIChjYWxsYmFjayl7IHRoaXMuc3RhdGVDaGFuZ2VDYWxsYmFja3Mub3Blbi5wdXNoKGNhbGxiYWNrKSB9XG4gIG9uQ2xvc2UgICAgKGNhbGxiYWNrKXsgdGhpcy5zdGF0ZUNoYW5nZUNhbGxiYWNrcy5jbG9zZS5wdXNoKGNhbGxiYWNrKSB9XG4gIG9uRXJyb3IgICAgKGNhbGxiYWNrKXsgdGhpcy5zdGF0ZUNoYW5nZUNhbGxiYWNrcy5lcnJvci5wdXNoKGNhbGxiYWNrKSB9XG4gIG9uTWVzc2FnZSAgKGNhbGxiYWNrKXsgdGhpcy5zdGF0ZUNoYW5nZUNhbGxiYWNrcy5tZXNzYWdlLnB1c2goY2FsbGJhY2spIH1cblxuICBvbkNvbm5PcGVuKCl7XG4gICAgdGhpcy5sb2coXCJ0cmFuc3BvcnRcIiwgYGNvbm5lY3RlZCB0byAke3RoaXMuZW5kUG9pbnRVUkwoKX1gLCB0aGlzLnRyYW5zcG9ydC5wcm90b3R5cGUpXG4gICAgdGhpcy5mbHVzaFNlbmRCdWZmZXIoKVxuICAgIHRoaXMucmVjb25uZWN0VGltZXIucmVzZXQoKVxuICAgIGlmKCF0aGlzLmNvbm4uc2tpcEhlYXJ0YmVhdCl7XG4gICAgICBjbGVhckludGVydmFsKHRoaXMuaGVhcnRiZWF0VGltZXIpXG4gICAgICB0aGlzLmhlYXJ0YmVhdFRpbWVyID0gc2V0SW50ZXJ2YWwoKCkgPT4gdGhpcy5zZW5kSGVhcnRiZWF0KCksIHRoaXMuaGVhcnRiZWF0SW50ZXJ2YWxNcylcbiAgICB9XG4gICAgdGhpcy5zdGF0ZUNoYW5nZUNhbGxiYWNrcy5vcGVuLmZvckVhY2goIGNhbGxiYWNrID0+IGNhbGxiYWNrKCkgKVxuICB9XG5cbiAgb25Db25uQ2xvc2UoZXZlbnQpe1xuICAgIHRoaXMubG9nKFwidHJhbnNwb3J0XCIsIFwiY2xvc2VcIiwgZXZlbnQpXG4gICAgdGhpcy50cmlnZ2VyQ2hhbkVycm9yKClcbiAgICBjbGVhckludGVydmFsKHRoaXMuaGVhcnRiZWF0VGltZXIpXG4gICAgdGhpcy5yZWNvbm5lY3RUaW1lci5zZXRUaW1lb3V0KClcbiAgICB0aGlzLnN0YXRlQ2hhbmdlQ2FsbGJhY2tzLmNsb3NlLmZvckVhY2goIGNhbGxiYWNrID0+IGNhbGxiYWNrKGV2ZW50KSApXG4gIH1cblxuICBvbkNvbm5FcnJvcihlcnJvcil7XG4gICAgdGhpcy5sb2coXCJ0cmFuc3BvcnRcIiwgZXJyb3IpXG4gICAgdGhpcy50cmlnZ2VyQ2hhbkVycm9yKClcbiAgICB0aGlzLnN0YXRlQ2hhbmdlQ2FsbGJhY2tzLmVycm9yLmZvckVhY2goIGNhbGxiYWNrID0+IGNhbGxiYWNrKGVycm9yKSApXG4gIH1cblxuICB0cmlnZ2VyQ2hhbkVycm9yKCl7XG4gICAgdGhpcy5jaGFubmVscy5mb3JFYWNoKCBjaGFubmVsID0+IGNoYW5uZWwudHJpZ2dlcihDSEFOTkVMX0VWRU5UUy5lcnJvcikgKVxuICB9XG5cbiAgY29ubmVjdGlvblN0YXRlKCl7XG4gICAgc3dpdGNoKHRoaXMuY29ubiAmJiB0aGlzLmNvbm4ucmVhZHlTdGF0ZSl7XG4gICAgICBjYXNlIFNPQ0tFVF9TVEFURVMuY29ubmVjdGluZzogcmV0dXJuIFwiY29ubmVjdGluZ1wiXG4gICAgICBjYXNlIFNPQ0tFVF9TVEFURVMub3BlbjogICAgICAgcmV0dXJuIFwib3BlblwiXG4gICAgICBjYXNlIFNPQ0tFVF9TVEFURVMuY2xvc2luZzogICAgcmV0dXJuIFwiY2xvc2luZ1wiXG4gICAgICBkZWZhdWx0OiAgICAgICAgICAgICAgICAgICAgICAgcmV0dXJuIFwiY2xvc2VkXCJcbiAgICB9XG4gIH1cblxuICBpc0Nvbm5lY3RlZCgpeyByZXR1cm4gdGhpcy5jb25uZWN0aW9uU3RhdGUoKSA9PT0gXCJvcGVuXCIgfVxuXG4gIHJlbW92ZShjaGFubmVsKXtcbiAgICB0aGlzLmNoYW5uZWxzID0gdGhpcy5jaGFubmVscy5maWx0ZXIoIGMgPT4gIWMuaXNNZW1iZXIoY2hhbm5lbC50b3BpYykgKVxuICB9XG5cbiAgY2hhbm5lbCh0b3BpYywgY2hhblBhcmFtcyA9IHt9KXtcbiAgICBsZXQgY2hhbm5lbCA9IG5ldyBDaGFubmVsKHRvcGljLCBjaGFuUGFyYW1zLCB0aGlzKVxuICAgIHRoaXMuY2hhbm5lbHMucHVzaChjaGFubmVsKVxuICAgIHJldHVybiBjaGFubmVsXG4gIH1cblxuICBwdXNoKGRhdGEpe1xuICAgIGxldCB7dG9waWMsIGV2ZW50LCBwYXlsb2FkLCByZWZ9ID0gZGF0YVxuICAgIGxldCBjYWxsYmFjayA9ICgpID0+IHRoaXMuY29ubi5zZW5kKEpTT04uc3RyaW5naWZ5KGRhdGEpKVxuICAgIHRoaXMubG9nKFwicHVzaFwiLCBgJHt0b3BpY30gJHtldmVudH0gKCR7cmVmfSlgLCBwYXlsb2FkKVxuICAgIGlmKHRoaXMuaXNDb25uZWN0ZWQoKSl7XG4gICAgICBjYWxsYmFjaygpXG4gICAgfVxuICAgIGVsc2Uge1xuICAgICAgdGhpcy5zZW5kQnVmZmVyLnB1c2goY2FsbGJhY2spXG4gICAgfVxuICB9XG5cbiAgLy8gUmV0dXJuIHRoZSBuZXh0IG1lc3NhZ2UgcmVmLCBhY2NvdW50aW5nIGZvciBvdmVyZmxvd3NcbiAgbWFrZVJlZigpe1xuICAgIGxldCBuZXdSZWYgPSB0aGlzLnJlZiArIDFcbiAgICBpZihuZXdSZWYgPT09IHRoaXMucmVmKXsgdGhpcy5yZWYgPSAwIH0gZWxzZSB7IHRoaXMucmVmID0gbmV3UmVmIH1cblxuICAgIHJldHVybiB0aGlzLnJlZi50b1N0cmluZygpXG4gIH1cblxuICBzZW5kSGVhcnRiZWF0KCl7XG4gICAgdGhpcy5wdXNoKHt0b3BpYzogXCJwaG9lbml4XCIsIGV2ZW50OiBcImhlYXJ0YmVhdFwiLCBwYXlsb2FkOiB7fSwgcmVmOiB0aGlzLm1ha2VSZWYoKX0pXG4gIH1cblxuICBmbHVzaFNlbmRCdWZmZXIoKXtcbiAgICBpZih0aGlzLmlzQ29ubmVjdGVkKCkgJiYgdGhpcy5zZW5kQnVmZmVyLmxlbmd0aCA+IDApe1xuICAgICAgdGhpcy5zZW5kQnVmZmVyLmZvckVhY2goIGNhbGxiYWNrID0+IGNhbGxiYWNrKCkgKVxuICAgICAgdGhpcy5zZW5kQnVmZmVyID0gW11cbiAgICB9XG4gIH1cblxuICBvbkNvbm5NZXNzYWdlKHJhd01lc3NhZ2Upe1xuICAgIGxldCBtc2cgPSBKU09OLnBhcnNlKHJhd01lc3NhZ2UuZGF0YSlcbiAgICBsZXQge3RvcGljLCBldmVudCwgcGF5bG9hZCwgcmVmfSA9IG1zZ1xuICAgIHRoaXMubG9nKFwicmVjZWl2ZVwiLCBgJHtwYXlsb2FkLnN0YXR1cyB8fCBcIlwifSAke3RvcGljfSAke2V2ZW50fSAke3JlZiAmJiBcIihcIiArIHJlZiArIFwiKVwiIHx8IFwiXCJ9YCwgcGF5bG9hZClcbiAgICB0aGlzLmNoYW5uZWxzLmZpbHRlciggY2hhbm5lbCA9PiBjaGFubmVsLmlzTWVtYmVyKHRvcGljKSApXG4gICAgICAgICAgICAgICAgIC5mb3JFYWNoKCBjaGFubmVsID0+IGNoYW5uZWwudHJpZ2dlcihldmVudCwgcGF5bG9hZCwgcmVmKSApXG4gICAgdGhpcy5zdGF0ZUNoYW5nZUNhbGxiYWNrcy5tZXNzYWdlLmZvckVhY2goIGNhbGxiYWNrID0+IGNhbGxiYWNrKG1zZykgKVxuICB9XG59XG5cblxuZXhwb3J0IGNsYXNzIExvbmdQb2xsIHtcblxuICBjb25zdHJ1Y3RvcihlbmRQb2ludCl7XG4gICAgdGhpcy5lbmRQb2ludCAgICAgICAgPSBudWxsXG4gICAgdGhpcy50b2tlbiAgICAgICAgICAgPSBudWxsXG4gICAgdGhpcy5za2lwSGVhcnRiZWF0ICAgPSB0cnVlXG4gICAgdGhpcy5vbm9wZW4gICAgICAgICAgPSBmdW5jdGlvbigpe30gLy8gbm9vcFxuICAgIHRoaXMub25lcnJvciAgICAgICAgID0gZnVuY3Rpb24oKXt9IC8vIG5vb3BcbiAgICB0aGlzLm9ubWVzc2FnZSAgICAgICA9IGZ1bmN0aW9uKCl7fSAvLyBub29wXG4gICAgdGhpcy5vbmNsb3NlICAgICAgICAgPSBmdW5jdGlvbigpe30gLy8gbm9vcFxuICAgIHRoaXMucG9sbEVuZHBvaW50ICAgID0gdGhpcy5ub3JtYWxpemVFbmRwb2ludChlbmRQb2ludClcbiAgICB0aGlzLnJlYWR5U3RhdGUgICAgICA9IFNPQ0tFVF9TVEFURVMuY29ubmVjdGluZ1xuXG4gICAgdGhpcy5wb2xsKClcbiAgfVxuXG4gIG5vcm1hbGl6ZUVuZHBvaW50KGVuZFBvaW50KXtcbiAgICByZXR1cm4oZW5kUG9pbnRcbiAgICAgIC5yZXBsYWNlKFwid3M6Ly9cIiwgXCJodHRwOi8vXCIpXG4gICAgICAucmVwbGFjZShcIndzczovL1wiLCBcImh0dHBzOi8vXCIpXG4gICAgICAucmVwbGFjZShuZXcgUmVnRXhwKFwiKC4qKVxcL1wiICsgVFJBTlNQT1JUUy53ZWJzb2NrZXQpLCBcIiQxL1wiICsgVFJBTlNQT1JUUy5sb25ncG9sbCkpXG4gIH1cblxuICBlbmRwb2ludFVSTCgpe1xuICAgIHJldHVybiBBamF4LmFwcGVuZFBhcmFtcyh0aGlzLnBvbGxFbmRwb2ludCwge3Rva2VuOiB0aGlzLnRva2VufSlcbiAgfVxuXG4gIGNsb3NlQW5kUmV0cnkoKXtcbiAgICB0aGlzLmNsb3NlKClcbiAgICB0aGlzLnJlYWR5U3RhdGUgPSBTT0NLRVRfU1RBVEVTLmNvbm5lY3RpbmdcbiAgfVxuXG4gIG9udGltZW91dCgpe1xuICAgIHRoaXMub25lcnJvcihcInRpbWVvdXRcIilcbiAgICB0aGlzLmNsb3NlQW5kUmV0cnkoKVxuICB9XG5cbiAgcG9sbCgpe1xuICAgIGlmKCEodGhpcy5yZWFkeVN0YXRlID09PSBTT0NLRVRfU1RBVEVTLm9wZW4gfHwgdGhpcy5yZWFkeVN0YXRlID09PSBTT0NLRVRfU1RBVEVTLmNvbm5lY3RpbmcpKXsgcmV0dXJuIH1cblxuICAgIEFqYXgucmVxdWVzdChcIkdFVFwiLCB0aGlzLmVuZHBvaW50VVJMKCksIFwiYXBwbGljYXRpb24vanNvblwiLCBudWxsLCB0aGlzLnRpbWVvdXQsIHRoaXMub250aW1lb3V0LmJpbmQodGhpcyksIChyZXNwKSA9PiB7XG4gICAgICBpZihyZXNwKXtcbiAgICAgICAgdmFyIHtzdGF0dXMsIHRva2VuLCBtZXNzYWdlc30gPSByZXNwXG4gICAgICAgIHRoaXMudG9rZW4gPSB0b2tlblxuICAgICAgfSBlbHNle1xuICAgICAgICB2YXIgc3RhdHVzID0gMFxuICAgICAgfVxuXG4gICAgICBzd2l0Y2goc3RhdHVzKXtcbiAgICAgICAgY2FzZSAyMDA6XG4gICAgICAgICAgbWVzc2FnZXMuZm9yRWFjaCggbXNnID0+IHRoaXMub25tZXNzYWdlKHtkYXRhOiBKU09OLnN0cmluZ2lmeShtc2cpfSkgKVxuICAgICAgICAgIHRoaXMucG9sbCgpXG4gICAgICAgICAgYnJlYWtcbiAgICAgICAgY2FzZSAyMDQ6XG4gICAgICAgICAgdGhpcy5wb2xsKClcbiAgICAgICAgICBicmVha1xuICAgICAgICBjYXNlIDQxMDpcbiAgICAgICAgICB0aGlzLnJlYWR5U3RhdGUgPSBTT0NLRVRfU1RBVEVTLm9wZW5cbiAgICAgICAgICB0aGlzLm9ub3BlbigpXG4gICAgICAgICAgdGhpcy5wb2xsKClcbiAgICAgICAgICBicmVha1xuICAgICAgICBjYXNlIDA6XG4gICAgICAgIGNhc2UgNTAwOlxuICAgICAgICAgIHRoaXMub25lcnJvcigpXG4gICAgICAgICAgdGhpcy5jbG9zZUFuZFJldHJ5KClcbiAgICAgICAgICBicmVha1xuICAgICAgICBkZWZhdWx0OiB0aHJvdyhgdW5oYW5kbGVkIHBvbGwgc3RhdHVzICR7c3RhdHVzfWApXG4gICAgICB9XG4gICAgfSlcbiAgfVxuXG4gIHNlbmQoYm9keSl7XG4gICAgQWpheC5yZXF1ZXN0KFwiUE9TVFwiLCB0aGlzLmVuZHBvaW50VVJMKCksIFwiYXBwbGljYXRpb24vanNvblwiLCBib2R5LCB0aGlzLnRpbWVvdXQsIHRoaXMub25lcnJvci5iaW5kKHRoaXMsIFwidGltZW91dFwiKSwgKHJlc3ApID0+IHtcbiAgICAgIGlmKCFyZXNwIHx8IHJlc3Auc3RhdHVzICE9PSAyMDApe1xuICAgICAgICB0aGlzLm9uZXJyb3Ioc3RhdHVzKVxuICAgICAgICB0aGlzLmNsb3NlQW5kUmV0cnkoKVxuICAgICAgfVxuICAgIH0pXG4gIH1cblxuICBjbG9zZShjb2RlLCByZWFzb24pe1xuICAgIHRoaXMucmVhZHlTdGF0ZSA9IFNPQ0tFVF9TVEFURVMuY2xvc2VkXG4gICAgdGhpcy5vbmNsb3NlKClcbiAgfVxufVxuXG5cbmV4cG9ydCBjbGFzcyBBamF4IHtcblxuICBzdGF0aWMgcmVxdWVzdChtZXRob2QsIGVuZFBvaW50LCBhY2NlcHQsIGJvZHksIHRpbWVvdXQsIG9udGltZW91dCwgY2FsbGJhY2spe1xuICAgIGlmKHdpbmRvdy5YRG9tYWluUmVxdWVzdCl7XG4gICAgICBsZXQgcmVxID0gbmV3IFhEb21haW5SZXF1ZXN0KCkgLy8gSUU4LCBJRTlcbiAgICAgIHRoaXMueGRvbWFpblJlcXVlc3QocmVxLCBtZXRob2QsIGVuZFBvaW50LCBib2R5LCB0aW1lb3V0LCBvbnRpbWVvdXQsIGNhbGxiYWNrKVxuICAgIH0gZWxzZSB7XG4gICAgICBsZXQgcmVxID0gd2luZG93LlhNTEh0dHBSZXF1ZXN0ID9cbiAgICAgICAgICAgICAgICAgIG5ldyBYTUxIdHRwUmVxdWVzdCgpIDogLy8gSUU3KywgRmlyZWZveCwgQ2hyb21lLCBPcGVyYSwgU2FmYXJpXG4gICAgICAgICAgICAgICAgICBuZXcgQWN0aXZlWE9iamVjdChcIk1pY3Jvc29mdC5YTUxIVFRQXCIpIC8vIElFNiwgSUU1XG4gICAgICB0aGlzLnhoclJlcXVlc3QocmVxLCBtZXRob2QsIGVuZFBvaW50LCBhY2NlcHQsIGJvZHksIHRpbWVvdXQsIG9udGltZW91dCwgY2FsbGJhY2spXG4gICAgfVxuICB9XG5cbiAgc3RhdGljIHhkb21haW5SZXF1ZXN0KHJlcSwgbWV0aG9kLCBlbmRQb2ludCwgYm9keSwgdGltZW91dCwgb250aW1lb3V0LCBjYWxsYmFjayl7XG4gICAgcmVxLnRpbWVvdXQgPSB0aW1lb3V0XG4gICAgcmVxLm9wZW4obWV0aG9kLCBlbmRQb2ludClcbiAgICByZXEub25sb2FkID0gKCkgPT4ge1xuICAgICAgbGV0IHJlc3BvbnNlID0gdGhpcy5wYXJzZUpTT04ocmVxLnJlc3BvbnNlVGV4dClcbiAgICAgIGNhbGxiYWNrICYmIGNhbGxiYWNrKHJlc3BvbnNlKVxuICAgIH1cbiAgICBpZihvbnRpbWVvdXQpeyByZXEub250aW1lb3V0ID0gb250aW1lb3V0IH1cblxuICAgIC8vIFdvcmsgYXJvdW5kIGJ1ZyBpbiBJRTkgdGhhdCByZXF1aXJlcyBhbiBhdHRhY2hlZCBvbnByb2dyZXNzIGhhbmRsZXJcbiAgICByZXEub25wcm9ncmVzcyA9ICgpID0+IHt9XG5cbiAgICByZXEuc2VuZChib2R5KVxuICB9XG5cbiAgc3RhdGljIHhoclJlcXVlc3QocmVxLCBtZXRob2QsIGVuZFBvaW50LCBhY2NlcHQsIGJvZHksIHRpbWVvdXQsIG9udGltZW91dCwgY2FsbGJhY2spe1xuICAgIHJlcS50aW1lb3V0ID0gdGltZW91dFxuICAgIHJlcS5vcGVuKG1ldGhvZCwgZW5kUG9pbnQsIHRydWUpXG4gICAgcmVxLnNldFJlcXVlc3RIZWFkZXIoXCJDb250ZW50LVR5cGVcIiwgYWNjZXB0KVxuICAgIHJlcS5vbmVycm9yID0gKCkgPT4geyBjYWxsYmFjayAmJiBjYWxsYmFjayhudWxsKSB9XG4gICAgcmVxLm9ucmVhZHlzdGF0ZWNoYW5nZSA9ICgpID0+IHtcbiAgICAgIGlmKHJlcS5yZWFkeVN0YXRlID09PSB0aGlzLnN0YXRlcy5jb21wbGV0ZSAmJiBjYWxsYmFjayl7XG4gICAgICAgIGxldCByZXNwb25zZSA9IHRoaXMucGFyc2VKU09OKHJlcS5yZXNwb25zZVRleHQpXG4gICAgICAgIGNhbGxiYWNrKHJlc3BvbnNlKVxuICAgICAgfVxuICAgIH1cbiAgICBpZihvbnRpbWVvdXQpeyByZXEub250aW1lb3V0ID0gb250aW1lb3V0IH1cblxuICAgIHJlcS5zZW5kKGJvZHkpXG4gIH1cblxuICBzdGF0aWMgcGFyc2VKU09OKHJlc3Ape1xuICAgIHJldHVybiAocmVzcCAmJiByZXNwICE9PSBcIlwiKSA/XG4gICAgICAgICAgICAgSlNPTi5wYXJzZShyZXNwKSA6XG4gICAgICAgICAgICAgbnVsbFxuICB9XG5cbiAgc3RhdGljIHNlcmlhbGl6ZShvYmosIHBhcmVudEtleSl7XG4gICAgbGV0IHF1ZXJ5U3RyID0gW107XG4gICAgZm9yKHZhciBrZXkgaW4gb2JqKXsgaWYoIW9iai5oYXNPd25Qcm9wZXJ0eShrZXkpKXsgY29udGludWUgfVxuICAgICAgbGV0IHBhcmFtS2V5ID0gcGFyZW50S2V5ID8gYCR7cGFyZW50S2V5fVske2tleX1dYCA6IGtleVxuICAgICAgbGV0IHBhcmFtVmFsID0gb2JqW2tleV1cbiAgICAgIGlmKHR5cGVvZiBwYXJhbVZhbCA9PT0gXCJvYmplY3RcIil7XG4gICAgICAgIHF1ZXJ5U3RyLnB1c2godGhpcy5zZXJpYWxpemUocGFyYW1WYWwsIHBhcmFtS2V5KSlcbiAgICAgIH0gZWxzZSB7XG4gICAgICAgIHF1ZXJ5U3RyLnB1c2goZW5jb2RlVVJJQ29tcG9uZW50KHBhcmFtS2V5KSArIFwiPVwiICsgZW5jb2RlVVJJQ29tcG9uZW50KHBhcmFtVmFsKSlcbiAgICAgIH1cbiAgICB9XG4gICAgcmV0dXJuIHF1ZXJ5U3RyLmpvaW4oXCImXCIpXG4gIH1cblxuICBzdGF0aWMgYXBwZW5kUGFyYW1zKHVybCwgcGFyYW1zKXtcbiAgICBpZihPYmplY3Qua2V5cyhwYXJhbXMpLmxlbmd0aCA9PT0gMCl7IHJldHVybiB1cmwgfVxuXG4gICAgbGV0IHByZWZpeCA9IHVybC5tYXRjaCgvXFw/LykgPyBcIiZcIiA6IFwiP1wiXG4gICAgcmV0dXJuIGAke3VybH0ke3ByZWZpeH0ke3RoaXMuc2VyaWFsaXplKHBhcmFtcyl9YFxuICB9XG59XG5cbkFqYXguc3RhdGVzID0ge2NvbXBsZXRlOiA0fVxuXG5cbi8vIENyZWF0ZXMgYSB0aW1lciB0aGF0IGFjY2VwdHMgYSBgdGltZXJDYWxjYCBmdW5jdGlvbiB0byBwZXJmb3JtXG4vLyBjYWxjdWxhdGVkIHRpbWVvdXQgcmV0cmllcywgc3VjaCBhcyBleHBvbmVudGlhbCBiYWNrb2ZmLlxuLy9cbi8vICMjIEV4YW1wbGVzXG4vL1xuLy8gICAgbGV0IHJlY29ubmVjdFRpbWVyID0gbmV3IFRpbWVyKCgpID0+IHRoaXMuY29ubmVjdCgpLCBmdW5jdGlvbih0cmllcyl7XG4vLyAgICAgIHJldHVybiBbMTAwMCwgNTAwMCwgMTAwMDBdW3RyaWVzIC0gMV0gfHwgMTAwMDBcbi8vICAgIH0pXG4vLyAgICByZWNvbm5lY3RUaW1lci5zZXRUaW1lb3V0KCkgLy8gZmlyZXMgYWZ0ZXIgMTAwMFxuLy8gICAgcmVjb25uZWN0VGltZXIuc2V0VGltZW91dCgpIC8vIGZpcmVzIGFmdGVyIDUwMDBcbi8vICAgIHJlY29ubmVjdFRpbWVyLnJlc2V0KClcbi8vICAgIHJlY29ubmVjdFRpbWVyLnNldFRpbWVvdXQoKSAvLyBmaXJlcyBhZnRlciAxMDAwXG4vL1xuY2xhc3MgVGltZXIge1xuICBjb25zdHJ1Y3RvcihjYWxsYmFjaywgdGltZXJDYWxjKXtcbiAgICB0aGlzLmNhbGxiYWNrICA9IGNhbGxiYWNrXG4gICAgdGhpcy50aW1lckNhbGMgPSB0aW1lckNhbGNcbiAgICB0aGlzLnRpbWVyICAgICA9IG51bGxcbiAgICB0aGlzLnRyaWVzICAgICA9IDBcbiAgfVxuXG4gIHJlc2V0KCl7XG4gICAgdGhpcy50cmllcyA9IDBcbiAgICBjbGVhclRpbWVvdXQodGhpcy50aW1lcilcbiAgfVxuXG4gIC8vIENhbmNlbHMgYW55IHByZXZpb3VzIHNldFRpbWVvdXQgYW5kIHNjaGVkdWxlcyBjYWxsYmFja1xuICBzZXRUaW1lb3V0KCl7XG4gICAgY2xlYXJUaW1lb3V0KHRoaXMudGltZXIpXG5cbiAgICB0aGlzLnRpbWVyID0gc2V0VGltZW91dCgoKSA9PiB7XG4gICAgICB0aGlzLnRyaWVzID0gdGhpcy50cmllcyArIDFcbiAgICAgIHRoaXMuY2FsbGJhY2soKVxuICAgIH0sIHRoaXMudGltZXJDYWxjKHRoaXMudHJpZXMgKyAxKSlcbiAgfVxufVxuIiwiKGZ1bmN0aW9uIChnbG9iYWwpe1xuXCJ1c2Ugc3RyaWN0XCI7XG5cbmlmIChnbG9iYWwuX2JhYmVsUG9seWZpbGwpIHtcbiAgdGhyb3cgbmV3IEVycm9yKFwib25seSBvbmUgaW5zdGFuY2Ugb2YgYmFiZWwvcG9seWZpbGwgaXMgYWxsb3dlZFwiKTtcbn1cbmdsb2JhbC5fYmFiZWxQb2x5ZmlsbCA9IHRydWU7XG5cbnJlcXVpcmUoXCJjb3JlLWpzL3NoaW1cIik7XG5cbnJlcXVpcmUoXCJyZWdlbmVyYXRvci1iYWJlbC9ydW50aW1lXCIpO1xufSkuY2FsbCh0aGlzLHR5cGVvZiBnbG9iYWwgIT09IFwidW5kZWZpbmVkXCIgPyBnbG9iYWwgOiB0eXBlb2Ygc2VsZiAhPT0gXCJ1bmRlZmluZWRcIiA/IHNlbGYgOiB0eXBlb2Ygd2luZG93ICE9PSBcInVuZGVmaW5lZFwiID8gd2luZG93IDoge30pXG4vLyMgc291cmNlTWFwcGluZ1VSTD1kYXRhOmFwcGxpY2F0aW9uL2pzb247Y2hhcnNldDp1dGYtODtiYXNlNjQsZXlKMlpYSnphVzl1SWpvekxDSnpiM1Z5WTJWeklqcGJJaTR1TDI1dlpHVmZiVzlrZFd4bGN5OWlZV0psYkM5dWIyUmxYMjF2WkhWc1pYTXZZbUZpWld3dFkyOXlaUzlzYVdJdlltRmlaV3d2Y0c5c2VXWnBiR3d1YW5NaVhTd2libUZ0WlhNaU9sdGRMQ0p0WVhCd2FXNW5jeUk2SWp0QlFVRkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJJaXdpWm1sc1pTSTZJbWRsYm1WeVlYUmxaQzVxY3lJc0luTnZkWEpqWlZKdmIzUWlPaUlpTENKemIzVnlZMlZ6UTI5dWRHVnVkQ0k2V3lKY0luVnpaU0J6ZEhKcFkzUmNJanRjYmx4dWFXWWdLR2RzYjJKaGJDNWZZbUZpWld4UWIyeDVabWxzYkNrZ2UxeHVJQ0IwYUhKdmR5QnVaWGNnUlhKeWIzSW9YQ0p2Ym14NUlHOXVaU0JwYm5OMFlXNWpaU0J2WmlCaVlXSmxiQzl3YjJ4NVptbHNiQ0JwY3lCaGJHeHZkMlZrWENJcE8xeHVmVnh1WjJ4dlltRnNMbDlpWVdKbGJGQnZiSGxtYVd4c0lEMGdkSEoxWlR0Y2JseHVjbVZ4ZFdseVpTaGNJbU52Y21VdGFuTXZjMmhwYlZ3aUtUdGNibHh1Y21WeGRXbHlaU2hjSW5KbFoyVnVaWEpoZEc5eUxXSmhZbVZzTDNKMWJuUnBiV1ZjSWlrN0lsMTkiLCIndXNlIHN0cmljdCc7XHJcbi8vIGZhbHNlIC0+IEFycmF5I2luZGV4T2ZcclxuLy8gdHJ1ZSAgLT4gQXJyYXkjaW5jbHVkZXNcclxudmFyICQgPSByZXF1aXJlKCcuLyQnKTtcclxubW9kdWxlLmV4cG9ydHMgPSBmdW5jdGlvbihJU19JTkNMVURFUyl7XHJcbiAgcmV0dXJuIGZ1bmN0aW9uKGVsIC8qLCBmcm9tSW5kZXggPSAwICovKXtcclxuICAgIHZhciBPICAgICAgPSAkLnRvT2JqZWN0KHRoaXMpXHJcbiAgICAgICwgbGVuZ3RoID0gJC50b0xlbmd0aChPLmxlbmd0aClcclxuICAgICAgLCBpbmRleCAgPSAkLnRvSW5kZXgoYXJndW1lbnRzWzFdLCBsZW5ndGgpXHJcbiAgICAgICwgdmFsdWU7XHJcbiAgICBpZihJU19JTkNMVURFUyAmJiBlbCAhPSBlbCl3aGlsZShsZW5ndGggPiBpbmRleCl7XHJcbiAgICAgIHZhbHVlID0gT1tpbmRleCsrXTtcclxuICAgICAgaWYodmFsdWUgIT0gdmFsdWUpcmV0dXJuIHRydWU7XHJcbiAgICB9IGVsc2UgZm9yKDtsZW5ndGggPiBpbmRleDsgaW5kZXgrKylpZihJU19JTkNMVURFUyB8fCBpbmRleCBpbiBPKXtcclxuICAgICAgaWYoT1tpbmRleF0gPT09IGVsKXJldHVybiBJU19JTkNMVURFUyB8fCBpbmRleDtcclxuICAgIH0gcmV0dXJuICFJU19JTkNMVURFUyAmJiAtMTtcclxuICB9O1xyXG59OyIsIid1c2Ugc3RyaWN0JztcclxuLy8gMCAtPiBBcnJheSNmb3JFYWNoXHJcbi8vIDEgLT4gQXJyYXkjbWFwXHJcbi8vIDIgLT4gQXJyYXkjZmlsdGVyXHJcbi8vIDMgLT4gQXJyYXkjc29tZVxyXG4vLyA0IC0+IEFycmF5I2V2ZXJ5XHJcbi8vIDUgLT4gQXJyYXkjZmluZFxyXG4vLyA2IC0+IEFycmF5I2ZpbmRJbmRleFxyXG52YXIgJCAgID0gcmVxdWlyZSgnLi8kJylcclxuICAsIGN0eCA9IHJlcXVpcmUoJy4vJC5jdHgnKTtcclxubW9kdWxlLmV4cG9ydHMgPSBmdW5jdGlvbihUWVBFKXtcclxuICB2YXIgSVNfTUFQICAgICAgICA9IFRZUEUgPT0gMVxyXG4gICAgLCBJU19GSUxURVIgICAgID0gVFlQRSA9PSAyXHJcbiAgICAsIElTX1NPTUUgICAgICAgPSBUWVBFID09IDNcclxuICAgICwgSVNfRVZFUlkgICAgICA9IFRZUEUgPT0gNFxyXG4gICAgLCBJU19GSU5EX0lOREVYID0gVFlQRSA9PSA2XHJcbiAgICAsIE5PX0hPTEVTICAgICAgPSBUWVBFID09IDUgfHwgSVNfRklORF9JTkRFWDtcclxuICByZXR1cm4gZnVuY3Rpb24oY2FsbGJhY2tmbi8qLCB0aGF0ID0gdW5kZWZpbmVkICovKXtcclxuICAgIHZhciBPICAgICAgPSBPYmplY3QoJC5hc3NlcnREZWZpbmVkKHRoaXMpKVxyXG4gICAgICAsIHNlbGYgICA9ICQuRVM1T2JqZWN0KE8pXHJcbiAgICAgICwgZiAgICAgID0gY3R4KGNhbGxiYWNrZm4sIGFyZ3VtZW50c1sxXSwgMylcclxuICAgICAgLCBsZW5ndGggPSAkLnRvTGVuZ3RoKHNlbGYubGVuZ3RoKVxyXG4gICAgICAsIGluZGV4ICA9IDBcclxuICAgICAgLCByZXN1bHQgPSBJU19NQVAgPyBBcnJheShsZW5ndGgpIDogSVNfRklMVEVSID8gW10gOiB1bmRlZmluZWRcclxuICAgICAgLCB2YWwsIHJlcztcclxuICAgIGZvcig7bGVuZ3RoID4gaW5kZXg7IGluZGV4KyspaWYoTk9fSE9MRVMgfHwgaW5kZXggaW4gc2VsZil7XHJcbiAgICAgIHZhbCA9IHNlbGZbaW5kZXhdO1xyXG4gICAgICByZXMgPSBmKHZhbCwgaW5kZXgsIE8pO1xyXG4gICAgICBpZihUWVBFKXtcclxuICAgICAgICBpZihJU19NQVApcmVzdWx0W2luZGV4XSA9IHJlczsgICAgICAgICAgICAvLyBtYXBcclxuICAgICAgICBlbHNlIGlmKHJlcylzd2l0Y2goVFlQRSl7XHJcbiAgICAgICAgICBjYXNlIDM6IHJldHVybiB0cnVlOyAgICAgICAgICAgICAgICAgICAgLy8gc29tZVxyXG4gICAgICAgICAgY2FzZSA1OiByZXR1cm4gdmFsOyAgICAgICAgICAgICAgICAgICAgIC8vIGZpbmRcclxuICAgICAgICAgIGNhc2UgNjogcmV0dXJuIGluZGV4OyAgICAgICAgICAgICAgICAgICAvLyBmaW5kSW5kZXhcclxuICAgICAgICAgIGNhc2UgMjogcmVzdWx0LnB1c2godmFsKTsgICAgICAgICAgICAgICAvLyBmaWx0ZXJcclxuICAgICAgICB9IGVsc2UgaWYoSVNfRVZFUlkpcmV0dXJuIGZhbHNlOyAgICAgICAgICAvLyBldmVyeVxyXG4gICAgICB9XHJcbiAgICB9XHJcbiAgICByZXR1cm4gSVNfRklORF9JTkRFWCA/IC0xIDogSVNfU09NRSB8fCBJU19FVkVSWSA/IElTX0VWRVJZIDogcmVzdWx0O1xyXG4gIH07XHJcbn07IiwidmFyICQgPSByZXF1aXJlKCcuLyQnKTtcclxuZnVuY3Rpb24gYXNzZXJ0KGNvbmRpdGlvbiwgbXNnMSwgbXNnMil7XHJcbiAgaWYoIWNvbmRpdGlvbil0aHJvdyBUeXBlRXJyb3IobXNnMiA/IG1zZzEgKyBtc2cyIDogbXNnMSk7XHJcbn1cclxuYXNzZXJ0LmRlZiA9ICQuYXNzZXJ0RGVmaW5lZDtcclxuYXNzZXJ0LmZuID0gZnVuY3Rpb24oaXQpe1xyXG4gIGlmKCEkLmlzRnVuY3Rpb24oaXQpKXRocm93IFR5cGVFcnJvcihpdCArICcgaXMgbm90IGEgZnVuY3Rpb24hJyk7XHJcbiAgcmV0dXJuIGl0O1xyXG59O1xyXG5hc3NlcnQub2JqID0gZnVuY3Rpb24oaXQpe1xyXG4gIGlmKCEkLmlzT2JqZWN0KGl0KSl0aHJvdyBUeXBlRXJyb3IoaXQgKyAnIGlzIG5vdCBhbiBvYmplY3QhJyk7XHJcbiAgcmV0dXJuIGl0O1xyXG59O1xyXG5hc3NlcnQuaW5zdCA9IGZ1bmN0aW9uKGl0LCBDb25zdHJ1Y3RvciwgbmFtZSl7XHJcbiAgaWYoIShpdCBpbnN0YW5jZW9mIENvbnN0cnVjdG9yKSl0aHJvdyBUeXBlRXJyb3IobmFtZSArIFwiOiB1c2UgdGhlICduZXcnIG9wZXJhdG9yIVwiKTtcclxuICByZXR1cm4gaXQ7XHJcbn07XHJcbm1vZHVsZS5leHBvcnRzID0gYXNzZXJ0OyIsInZhciAkID0gcmVxdWlyZSgnLi8kJyk7XHJcbi8vIDE5LjEuMi4xIE9iamVjdC5hc3NpZ24odGFyZ2V0LCBzb3VyY2UsIC4uLilcclxubW9kdWxlLmV4cG9ydHMgPSBPYmplY3QuYXNzaWduIHx8IGZ1bmN0aW9uKHRhcmdldCwgc291cmNlKXsgLy8gZXNsaW50LWRpc2FibGUtbGluZSBuby11bnVzZWQtdmFyc1xyXG4gIHZhciBUID0gT2JqZWN0KCQuYXNzZXJ0RGVmaW5lZCh0YXJnZXQpKVxyXG4gICAgLCBsID0gYXJndW1lbnRzLmxlbmd0aFxyXG4gICAgLCBpID0gMTtcclxuICB3aGlsZShsID4gaSl7XHJcbiAgICB2YXIgUyAgICAgID0gJC5FUzVPYmplY3QoYXJndW1lbnRzW2krK10pXHJcbiAgICAgICwga2V5cyAgID0gJC5nZXRLZXlzKFMpXHJcbiAgICAgICwgbGVuZ3RoID0ga2V5cy5sZW5ndGhcclxuICAgICAgLCBqICAgICAgPSAwXHJcbiAgICAgICwga2V5O1xyXG4gICAgd2hpbGUobGVuZ3RoID4gailUW2tleSA9IGtleXNbaisrXV0gPSBTW2tleV07XHJcbiAgfVxyXG4gIHJldHVybiBUO1xyXG59OyIsInZhciAkICAgICAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCBUQUcgICAgICA9IHJlcXVpcmUoJy4vJC53a3MnKSgndG9TdHJpbmdUYWcnKVxyXG4gICwgdG9TdHJpbmcgPSB7fS50b1N0cmluZztcclxuZnVuY3Rpb24gY29mKGl0KXtcclxuICByZXR1cm4gdG9TdHJpbmcuY2FsbChpdCkuc2xpY2UoOCwgLTEpO1xyXG59XHJcbmNvZi5jbGFzc29mID0gZnVuY3Rpb24oaXQpe1xyXG4gIHZhciBPLCBUO1xyXG4gIHJldHVybiBpdCA9PSB1bmRlZmluZWQgPyBpdCA9PT0gdW5kZWZpbmVkID8gJ1VuZGVmaW5lZCcgOiAnTnVsbCdcclxuICAgIDogdHlwZW9mIChUID0gKE8gPSBPYmplY3QoaXQpKVtUQUddKSA9PSAnc3RyaW5nJyA/IFQgOiBjb2YoTyk7XHJcbn07XHJcbmNvZi5zZXQgPSBmdW5jdGlvbihpdCwgdGFnLCBzdGF0KXtcclxuICBpZihpdCAmJiAhJC5oYXMoaXQgPSBzdGF0ID8gaXQgOiBpdC5wcm90b3R5cGUsIFRBRykpJC5oaWRlKGl0LCBUQUcsIHRhZyk7XHJcbn07XHJcbm1vZHVsZS5leHBvcnRzID0gY29mOyIsIid1c2Ugc3RyaWN0JztcclxudmFyICQgICAgICAgID0gcmVxdWlyZSgnLi8kJylcclxuICAsIGN0eCAgICAgID0gcmVxdWlyZSgnLi8kLmN0eCcpXHJcbiAgLCBzYWZlICAgICA9IHJlcXVpcmUoJy4vJC51aWQnKS5zYWZlXHJcbiAgLCBhc3NlcnQgICA9IHJlcXVpcmUoJy4vJC5hc3NlcnQnKVxyXG4gICwgJGl0ZXIgICAgPSByZXF1aXJlKCcuLyQuaXRlcicpXHJcbiAgLCBoYXMgICAgICA9ICQuaGFzXHJcbiAgLCBzZXQgICAgICA9ICQuc2V0XHJcbiAgLCBpc09iamVjdCA9ICQuaXNPYmplY3RcclxuICAsIGhpZGUgICAgID0gJC5oaWRlXHJcbiAgLCBzdGVwICAgICA9ICRpdGVyLnN0ZXBcclxuICAsIGlzRnJvemVuID0gT2JqZWN0LmlzRnJvemVuIHx8ICQuY29yZS5PYmplY3QuaXNGcm96ZW5cclxuICAsIElEICAgICAgID0gc2FmZSgnaWQnKVxyXG4gICwgTzEgICAgICAgPSBzYWZlKCdPMScpXHJcbiAgLCBMQVNUICAgICA9IHNhZmUoJ2xhc3QnKVxyXG4gICwgRklSU1QgICAgPSBzYWZlKCdmaXJzdCcpXHJcbiAgLCBJVEVSICAgICA9IHNhZmUoJ2l0ZXInKVxyXG4gICwgU0laRSAgICAgPSAkLkRFU0MgPyBzYWZlKCdzaXplJykgOiAnc2l6ZSdcclxuICAsIGlkICAgICAgID0gMDtcclxuXHJcbmZ1bmN0aW9uIGZhc3RLZXkoaXQsIGNyZWF0ZSl7XHJcbiAgLy8gcmV0dXJuIHByaW1pdGl2ZSB3aXRoIHByZWZpeFxyXG4gIGlmKCFpc09iamVjdChpdCkpcmV0dXJuICh0eXBlb2YgaXQgPT0gJ3N0cmluZycgPyAnUycgOiAnUCcpICsgaXQ7XHJcbiAgLy8gY2FuJ3Qgc2V0IGlkIHRvIGZyb3plbiBvYmplY3RcclxuICBpZihpc0Zyb3plbihpdCkpcmV0dXJuICdGJztcclxuICBpZighaGFzKGl0LCBJRCkpe1xyXG4gICAgLy8gbm90IG5lY2Vzc2FyeSB0byBhZGQgaWRcclxuICAgIGlmKCFjcmVhdGUpcmV0dXJuICdFJztcclxuICAgIC8vIGFkZCBtaXNzaW5nIG9iamVjdCBpZFxyXG4gICAgaGlkZShpdCwgSUQsICsraWQpO1xyXG4gIC8vIHJldHVybiBvYmplY3QgaWQgd2l0aCBwcmVmaXhcclxuICB9IHJldHVybiAnTycgKyBpdFtJRF07XHJcbn1cclxuXHJcbmZ1bmN0aW9uIGdldEVudHJ5KHRoYXQsIGtleSl7XHJcbiAgLy8gZmFzdCBjYXNlXHJcbiAgdmFyIGluZGV4ID0gZmFzdEtleShrZXkpLCBlbnRyeTtcclxuICBpZihpbmRleCAhPSAnRicpcmV0dXJuIHRoYXRbTzFdW2luZGV4XTtcclxuICAvLyBmcm96ZW4gb2JqZWN0IGNhc2VcclxuICBmb3IoZW50cnkgPSB0aGF0W0ZJUlNUXTsgZW50cnk7IGVudHJ5ID0gZW50cnkubil7XHJcbiAgICBpZihlbnRyeS5rID09IGtleSlyZXR1cm4gZW50cnk7XHJcbiAgfVxyXG59XHJcblxyXG5tb2R1bGUuZXhwb3J0cyA9IHtcclxuICBnZXRDb25zdHJ1Y3RvcjogZnVuY3Rpb24oTkFNRSwgSVNfTUFQLCBBRERFUil7XHJcbiAgICBmdW5jdGlvbiBDKGl0ZXJhYmxlKXtcclxuICAgICAgdmFyIHRoYXQgPSBhc3NlcnQuaW5zdCh0aGlzLCBDLCBOQU1FKTtcclxuICAgICAgc2V0KHRoYXQsIE8xLCAkLmNyZWF0ZShudWxsKSk7XHJcbiAgICAgIHNldCh0aGF0LCBTSVpFLCAwKTtcclxuICAgICAgc2V0KHRoYXQsIExBU1QsIHVuZGVmaW5lZCk7XHJcbiAgICAgIHNldCh0aGF0LCBGSVJTVCwgdW5kZWZpbmVkKTtcclxuICAgICAgaWYoaXRlcmFibGUgIT0gdW5kZWZpbmVkKSRpdGVyLmZvck9mKGl0ZXJhYmxlLCBJU19NQVAsIHRoYXRbQURERVJdLCB0aGF0KTtcclxuICAgIH1cclxuICAgICQubWl4KEMucHJvdG90eXBlLCB7XHJcbiAgICAgIC8vIDIzLjEuMy4xIE1hcC5wcm90b3R5cGUuY2xlYXIoKVxyXG4gICAgICAvLyAyMy4yLjMuMiBTZXQucHJvdG90eXBlLmNsZWFyKClcclxuICAgICAgY2xlYXI6IGZ1bmN0aW9uKCl7XHJcbiAgICAgICAgZm9yKHZhciB0aGF0ID0gdGhpcywgZGF0YSA9IHRoYXRbTzFdLCBlbnRyeSA9IHRoYXRbRklSU1RdOyBlbnRyeTsgZW50cnkgPSBlbnRyeS5uKXtcclxuICAgICAgICAgIGVudHJ5LnIgPSB0cnVlO1xyXG4gICAgICAgICAgaWYoZW50cnkucCllbnRyeS5wID0gZW50cnkucC5uID0gdW5kZWZpbmVkO1xyXG4gICAgICAgICAgZGVsZXRlIGRhdGFbZW50cnkuaV07XHJcbiAgICAgICAgfVxyXG4gICAgICAgIHRoYXRbRklSU1RdID0gdGhhdFtMQVNUXSA9IHVuZGVmaW5lZDtcclxuICAgICAgICB0aGF0W1NJWkVdID0gMDtcclxuICAgICAgfSxcclxuICAgICAgLy8gMjMuMS4zLjMgTWFwLnByb3RvdHlwZS5kZWxldGUoa2V5KVxyXG4gICAgICAvLyAyMy4yLjMuNCBTZXQucHJvdG90eXBlLmRlbGV0ZSh2YWx1ZSlcclxuICAgICAgJ2RlbGV0ZSc6IGZ1bmN0aW9uKGtleSl7XHJcbiAgICAgICAgdmFyIHRoYXQgID0gdGhpc1xyXG4gICAgICAgICAgLCBlbnRyeSA9IGdldEVudHJ5KHRoYXQsIGtleSk7XHJcbiAgICAgICAgaWYoZW50cnkpe1xyXG4gICAgICAgICAgdmFyIG5leHQgPSBlbnRyeS5uXHJcbiAgICAgICAgICAgICwgcHJldiA9IGVudHJ5LnA7XHJcbiAgICAgICAgICBkZWxldGUgdGhhdFtPMV1bZW50cnkuaV07XHJcbiAgICAgICAgICBlbnRyeS5yID0gdHJ1ZTtcclxuICAgICAgICAgIGlmKHByZXYpcHJldi5uID0gbmV4dDtcclxuICAgICAgICAgIGlmKG5leHQpbmV4dC5wID0gcHJldjtcclxuICAgICAgICAgIGlmKHRoYXRbRklSU1RdID09IGVudHJ5KXRoYXRbRklSU1RdID0gbmV4dDtcclxuICAgICAgICAgIGlmKHRoYXRbTEFTVF0gPT0gZW50cnkpdGhhdFtMQVNUXSA9IHByZXY7XHJcbiAgICAgICAgICB0aGF0W1NJWkVdLS07XHJcbiAgICAgICAgfSByZXR1cm4gISFlbnRyeTtcclxuICAgICAgfSxcclxuICAgICAgLy8gMjMuMi4zLjYgU2V0LnByb3RvdHlwZS5mb3JFYWNoKGNhbGxiYWNrZm4sIHRoaXNBcmcgPSB1bmRlZmluZWQpXHJcbiAgICAgIC8vIDIzLjEuMy41IE1hcC5wcm90b3R5cGUuZm9yRWFjaChjYWxsYmFja2ZuLCB0aGlzQXJnID0gdW5kZWZpbmVkKVxyXG4gICAgICBmb3JFYWNoOiBmdW5jdGlvbihjYWxsYmFja2ZuIC8qLCB0aGF0ID0gdW5kZWZpbmVkICovKXtcclxuICAgICAgICB2YXIgZiA9IGN0eChjYWxsYmFja2ZuLCBhcmd1bWVudHNbMV0sIDMpXHJcbiAgICAgICAgICAsIGVudHJ5O1xyXG4gICAgICAgIHdoaWxlKGVudHJ5ID0gZW50cnkgPyBlbnRyeS5uIDogdGhpc1tGSVJTVF0pe1xyXG4gICAgICAgICAgZihlbnRyeS52LCBlbnRyeS5rLCB0aGlzKTtcclxuICAgICAgICAgIC8vIHJldmVydCB0byB0aGUgbGFzdCBleGlzdGluZyBlbnRyeVxyXG4gICAgICAgICAgd2hpbGUoZW50cnkgJiYgZW50cnkucillbnRyeSA9IGVudHJ5LnA7XHJcbiAgICAgICAgfVxyXG4gICAgICB9LFxyXG4gICAgICAvLyAyMy4xLjMuNyBNYXAucHJvdG90eXBlLmhhcyhrZXkpXHJcbiAgICAgIC8vIDIzLjIuMy43IFNldC5wcm90b3R5cGUuaGFzKHZhbHVlKVxyXG4gICAgICBoYXM6IGZ1bmN0aW9uKGtleSl7XHJcbiAgICAgICAgcmV0dXJuICEhZ2V0RW50cnkodGhpcywga2V5KTtcclxuICAgICAgfVxyXG4gICAgfSk7XHJcbiAgICBpZigkLkRFU0MpJC5zZXREZXNjKEMucHJvdG90eXBlLCAnc2l6ZScsIHtcclxuICAgICAgZ2V0OiBmdW5jdGlvbigpe1xyXG4gICAgICAgIHJldHVybiBhc3NlcnQuZGVmKHRoaXNbU0laRV0pO1xyXG4gICAgICB9XHJcbiAgICB9KTtcclxuICAgIHJldHVybiBDO1xyXG4gIH0sXHJcbiAgZGVmOiBmdW5jdGlvbih0aGF0LCBrZXksIHZhbHVlKXtcclxuICAgIHZhciBlbnRyeSA9IGdldEVudHJ5KHRoYXQsIGtleSlcclxuICAgICAgLCBwcmV2LCBpbmRleDtcclxuICAgIC8vIGNoYW5nZSBleGlzdGluZyBlbnRyeVxyXG4gICAgaWYoZW50cnkpe1xyXG4gICAgICBlbnRyeS52ID0gdmFsdWU7XHJcbiAgICAvLyBjcmVhdGUgbmV3IGVudHJ5XHJcbiAgICB9IGVsc2Uge1xyXG4gICAgICB0aGF0W0xBU1RdID0gZW50cnkgPSB7XHJcbiAgICAgICAgaTogaW5kZXggPSBmYXN0S2V5KGtleSwgdHJ1ZSksIC8vIDwtIGluZGV4XHJcbiAgICAgICAgazoga2V5LCAgICAgICAgICAgICAgICAgICAgICAgIC8vIDwtIGtleVxyXG4gICAgICAgIHY6IHZhbHVlLCAgICAgICAgICAgICAgICAgICAgICAvLyA8LSB2YWx1ZVxyXG4gICAgICAgIHA6IHByZXYgPSB0aGF0W0xBU1RdLCAgICAgICAgICAvLyA8LSBwcmV2aW91cyBlbnRyeVxyXG4gICAgICAgIG46IHVuZGVmaW5lZCwgICAgICAgICAgICAgICAgICAvLyA8LSBuZXh0IGVudHJ5XHJcbiAgICAgICAgcjogZmFsc2UgICAgICAgICAgICAgICAgICAgICAgIC8vIDwtIHJlbW92ZWRcclxuICAgICAgfTtcclxuICAgICAgaWYoIXRoYXRbRklSU1RdKXRoYXRbRklSU1RdID0gZW50cnk7XHJcbiAgICAgIGlmKHByZXYpcHJldi5uID0gZW50cnk7XHJcbiAgICAgIHRoYXRbU0laRV0rKztcclxuICAgICAgLy8gYWRkIHRvIGluZGV4XHJcbiAgICAgIGlmKGluZGV4ICE9ICdGJyl0aGF0W08xXVtpbmRleF0gPSBlbnRyeTtcclxuICAgIH0gcmV0dXJuIHRoYXQ7XHJcbiAgfSxcclxuICBnZXRFbnRyeTogZ2V0RW50cnksXHJcbiAgZ2V0SXRlckNvbnN0cnVjdG9yOiBmdW5jdGlvbigpe1xyXG4gICAgcmV0dXJuIGZ1bmN0aW9uKGl0ZXJhdGVkLCBraW5kKXtcclxuICAgICAgc2V0KHRoaXMsIElURVIsIHtvOiBpdGVyYXRlZCwgazoga2luZH0pO1xyXG4gICAgfTtcclxuICB9LFxyXG4gIG5leHQ6IGZ1bmN0aW9uKCl7XHJcbiAgICB2YXIgaXRlciAgPSB0aGlzW0lURVJdXHJcbiAgICAgICwga2luZCAgPSBpdGVyLmtcclxuICAgICAgLCBlbnRyeSA9IGl0ZXIubDtcclxuICAgIC8vIHJldmVydCB0byB0aGUgbGFzdCBleGlzdGluZyBlbnRyeVxyXG4gICAgd2hpbGUoZW50cnkgJiYgZW50cnkucillbnRyeSA9IGVudHJ5LnA7XHJcbiAgICAvLyBnZXQgbmV4dCBlbnRyeVxyXG4gICAgaWYoIWl0ZXIubyB8fCAhKGl0ZXIubCA9IGVudHJ5ID0gZW50cnkgPyBlbnRyeS5uIDogaXRlci5vW0ZJUlNUXSkpe1xyXG4gICAgICAvLyBvciBmaW5pc2ggdGhlIGl0ZXJhdGlvblxyXG4gICAgICBpdGVyLm8gPSB1bmRlZmluZWQ7XHJcbiAgICAgIHJldHVybiBzdGVwKDEpO1xyXG4gICAgfVxyXG4gICAgLy8gcmV0dXJuIHN0ZXAgYnkga2luZFxyXG4gICAgaWYoa2luZCA9PSAna2V5JyAgKXJldHVybiBzdGVwKDAsIGVudHJ5LmspO1xyXG4gICAgaWYoa2luZCA9PSAndmFsdWUnKXJldHVybiBzdGVwKDAsIGVudHJ5LnYpO1xyXG4gICAgcmV0dXJuIHN0ZXAoMCwgW2VudHJ5LmssIGVudHJ5LnZdKTtcclxuICB9XHJcbn07IiwiJ3VzZSBzdHJpY3QnO1xyXG52YXIgJCAgICAgICAgID0gcmVxdWlyZSgnLi8kJylcclxuICAsIHNhZmUgICAgICA9IHJlcXVpcmUoJy4vJC51aWQnKS5zYWZlXHJcbiAgLCBhc3NlcnQgICAgPSByZXF1aXJlKCcuLyQuYXNzZXJ0JylcclxuICAsIGZvck9mICAgICA9IHJlcXVpcmUoJy4vJC5pdGVyJykuZm9yT2ZcclxuICAsIGhhcyAgICAgICA9ICQuaGFzXHJcbiAgLCBpc09iamVjdCAgPSAkLmlzT2JqZWN0XHJcbiAgLCBoaWRlICAgICAgPSAkLmhpZGVcclxuICAsIGlzRnJvemVuICA9IE9iamVjdC5pc0Zyb3plbiB8fCAkLmNvcmUuT2JqZWN0LmlzRnJvemVuXHJcbiAgLCBpZCAgICAgICAgPSAwXHJcbiAgLCBJRCAgICAgICAgPSBzYWZlKCdpZCcpXHJcbiAgLCBXRUFLICAgICAgPSBzYWZlKCd3ZWFrJylcclxuICAsIExFQUsgICAgICA9IHNhZmUoJ2xlYWsnKVxyXG4gICwgbWV0aG9kICAgID0gcmVxdWlyZSgnLi8kLmFycmF5LW1ldGhvZHMnKVxyXG4gICwgZmluZCAgICAgID0gbWV0aG9kKDUpXHJcbiAgLCBmaW5kSW5kZXggPSBtZXRob2QoNik7XHJcbmZ1bmN0aW9uIGZpbmRGcm96ZW4oc3RvcmUsIGtleSl7XHJcbiAgcmV0dXJuIGZpbmQuY2FsbChzdG9yZS5hcnJheSwgZnVuY3Rpb24oaXQpe1xyXG4gICAgcmV0dXJuIGl0WzBdID09PSBrZXk7XHJcbiAgfSk7XHJcbn1cclxuLy8gZmFsbGJhY2sgZm9yIGZyb3plbiBrZXlzXHJcbmZ1bmN0aW9uIGxlYWtTdG9yZSh0aGF0KXtcclxuICByZXR1cm4gdGhhdFtMRUFLXSB8fCBoaWRlKHRoYXQsIExFQUssIHtcclxuICAgIGFycmF5OiBbXSxcclxuICAgIGdldDogZnVuY3Rpb24oa2V5KXtcclxuICAgICAgdmFyIGVudHJ5ID0gZmluZEZyb3plbih0aGlzLCBrZXkpO1xyXG4gICAgICBpZihlbnRyeSlyZXR1cm4gZW50cnlbMV07XHJcbiAgICB9LFxyXG4gICAgaGFzOiBmdW5jdGlvbihrZXkpe1xyXG4gICAgICByZXR1cm4gISFmaW5kRnJvemVuKHRoaXMsIGtleSk7XHJcbiAgICB9LFxyXG4gICAgc2V0OiBmdW5jdGlvbihrZXksIHZhbHVlKXtcclxuICAgICAgdmFyIGVudHJ5ID0gZmluZEZyb3plbih0aGlzLCBrZXkpO1xyXG4gICAgICBpZihlbnRyeSllbnRyeVsxXSA9IHZhbHVlO1xyXG4gICAgICBlbHNlIHRoaXMuYXJyYXkucHVzaChba2V5LCB2YWx1ZV0pO1xyXG4gICAgfSxcclxuICAgICdkZWxldGUnOiBmdW5jdGlvbihrZXkpe1xyXG4gICAgICB2YXIgaW5kZXggPSBmaW5kSW5kZXguY2FsbCh0aGlzLmFycmF5LCBmdW5jdGlvbihpdCl7XHJcbiAgICAgICAgcmV0dXJuIGl0WzBdID09PSBrZXk7XHJcbiAgICAgIH0pO1xyXG4gICAgICBpZih+aW5kZXgpdGhpcy5hcnJheS5zcGxpY2UoaW5kZXgsIDEpO1xyXG4gICAgICByZXR1cm4gISF+aW5kZXg7XHJcbiAgICB9XHJcbiAgfSlbTEVBS107XHJcbn1cclxuXHJcbm1vZHVsZS5leHBvcnRzID0ge1xyXG4gIGdldENvbnN0cnVjdG9yOiBmdW5jdGlvbihOQU1FLCBJU19NQVAsIEFEREVSKXtcclxuICAgIGZ1bmN0aW9uIEMoaXRlcmFibGUpe1xyXG4gICAgICAkLnNldChhc3NlcnQuaW5zdCh0aGlzLCBDLCBOQU1FKSwgSUQsIGlkKyspO1xyXG4gICAgICBpZihpdGVyYWJsZSAhPSB1bmRlZmluZWQpZm9yT2YoaXRlcmFibGUsIElTX01BUCwgdGhpc1tBRERFUl0sIHRoaXMpO1xyXG4gICAgfVxyXG4gICAgJC5taXgoQy5wcm90b3R5cGUsIHtcclxuICAgICAgLy8gMjMuMy4zLjIgV2Vha01hcC5wcm90b3R5cGUuZGVsZXRlKGtleSlcclxuICAgICAgLy8gMjMuNC4zLjMgV2Vha1NldC5wcm90b3R5cGUuZGVsZXRlKHZhbHVlKVxyXG4gICAgICAnZGVsZXRlJzogZnVuY3Rpb24oa2V5KXtcclxuICAgICAgICBpZighaXNPYmplY3Qoa2V5KSlyZXR1cm4gZmFsc2U7XHJcbiAgICAgICAgaWYoaXNGcm96ZW4oa2V5KSlyZXR1cm4gbGVha1N0b3JlKHRoaXMpWydkZWxldGUnXShrZXkpO1xyXG4gICAgICAgIHJldHVybiBoYXMoa2V5LCBXRUFLKSAmJiBoYXMoa2V5W1dFQUtdLCB0aGlzW0lEXSkgJiYgZGVsZXRlIGtleVtXRUFLXVt0aGlzW0lEXV07XHJcbiAgICAgIH0sXHJcbiAgICAgIC8vIDIzLjMuMy40IFdlYWtNYXAucHJvdG90eXBlLmhhcyhrZXkpXHJcbiAgICAgIC8vIDIzLjQuMy40IFdlYWtTZXQucHJvdG90eXBlLmhhcyh2YWx1ZSlcclxuICAgICAgaGFzOiBmdW5jdGlvbihrZXkpe1xyXG4gICAgICAgIGlmKCFpc09iamVjdChrZXkpKXJldHVybiBmYWxzZTtcclxuICAgICAgICBpZihpc0Zyb3plbihrZXkpKXJldHVybiBsZWFrU3RvcmUodGhpcykuaGFzKGtleSk7XHJcbiAgICAgICAgcmV0dXJuIGhhcyhrZXksIFdFQUspICYmIGhhcyhrZXlbV0VBS10sIHRoaXNbSURdKTtcclxuICAgICAgfVxyXG4gICAgfSk7XHJcbiAgICByZXR1cm4gQztcclxuICB9LFxyXG4gIGRlZjogZnVuY3Rpb24odGhhdCwga2V5LCB2YWx1ZSl7XHJcbiAgICBpZihpc0Zyb3plbihhc3NlcnQub2JqKGtleSkpKXtcclxuICAgICAgbGVha1N0b3JlKHRoYXQpLnNldChrZXksIHZhbHVlKTtcclxuICAgIH0gZWxzZSB7XHJcbiAgICAgIGhhcyhrZXksIFdFQUspIHx8IGhpZGUoa2V5LCBXRUFLLCB7fSk7XHJcbiAgICAgIGtleVtXRUFLXVt0aGF0W0lEXV0gPSB2YWx1ZTtcclxuICAgIH0gcmV0dXJuIHRoYXQ7XHJcbiAgfSxcclxuICBsZWFrU3RvcmU6IGxlYWtTdG9yZSxcclxuICBXRUFLOiBXRUFLLFxyXG4gIElEOiBJRFxyXG59OyIsIid1c2Ugc3RyaWN0JztcclxudmFyICQgICAgID0gcmVxdWlyZSgnLi8kJylcclxuICAsICRkZWYgID0gcmVxdWlyZSgnLi8kLmRlZicpXHJcbiAgLCAkaXRlciA9IHJlcXVpcmUoJy4vJC5pdGVyJylcclxuICAsIGFzc2VydEluc3RhbmNlID0gcmVxdWlyZSgnLi8kLmFzc2VydCcpLmluc3Q7XHJcblxyXG5tb2R1bGUuZXhwb3J0cyA9IGZ1bmN0aW9uKE5BTUUsIG1ldGhvZHMsIGNvbW1vbiwgSVNfTUFQLCBpc1dlYWspe1xyXG4gIHZhciBCYXNlICA9ICQuZ1tOQU1FXVxyXG4gICAgLCBDICAgICA9IEJhc2VcclxuICAgICwgQURERVIgPSBJU19NQVAgPyAnc2V0JyA6ICdhZGQnXHJcbiAgICAsIHByb3RvID0gQyAmJiBDLnByb3RvdHlwZVxyXG4gICAgLCBPICAgICA9IHt9O1xyXG4gIGZ1bmN0aW9uIGZpeE1ldGhvZChLRVksIENIQUlOKXtcclxuICAgIHZhciBtZXRob2QgPSBwcm90b1tLRVldO1xyXG4gICAgaWYoJC5GVylwcm90b1tLRVldID0gZnVuY3Rpb24oYSwgYil7XHJcbiAgICAgIHZhciByZXN1bHQgPSBtZXRob2QuY2FsbCh0aGlzLCBhID09PSAwID8gMCA6IGEsIGIpO1xyXG4gICAgICByZXR1cm4gQ0hBSU4gPyB0aGlzIDogcmVzdWx0O1xyXG4gICAgfTtcclxuICB9XHJcbiAgaWYoISQuaXNGdW5jdGlvbihDKSB8fCAhKGlzV2VhayB8fCAhJGl0ZXIuQlVHR1kgJiYgcHJvdG8uZm9yRWFjaCAmJiBwcm90by5lbnRyaWVzKSl7XHJcbiAgICAvLyBjcmVhdGUgY29sbGVjdGlvbiBjb25zdHJ1Y3RvclxyXG4gICAgQyA9IGNvbW1vbi5nZXRDb25zdHJ1Y3RvcihOQU1FLCBJU19NQVAsIEFEREVSKTtcclxuICAgICQubWl4KEMucHJvdG90eXBlLCBtZXRob2RzKTtcclxuICB9IGVsc2Uge1xyXG4gICAgdmFyIGluc3QgID0gbmV3IENcclxuICAgICAgLCBjaGFpbiA9IGluc3RbQURERVJdKGlzV2VhayA/IHt9IDogLTAsIDEpXHJcbiAgICAgICwgYnVnZ3laZXJvO1xyXG4gICAgLy8gd3JhcCBmb3IgaW5pdCBjb2xsZWN0aW9ucyBmcm9tIGl0ZXJhYmxlXHJcbiAgICBpZigkaXRlci5mYWlsKGZ1bmN0aW9uKGl0ZXIpe1xyXG4gICAgICBuZXcgQyhpdGVyKTsgLy8gZXNsaW50LWRpc2FibGUtbGluZSBuby1uZXdcclxuICAgIH0pIHx8ICRpdGVyLkRBTkdFUl9DTE9TSU5HKXtcclxuICAgICAgQyA9IGZ1bmN0aW9uKGl0ZXJhYmxlKXtcclxuICAgICAgICBhc3NlcnRJbnN0YW5jZSh0aGlzLCBDLCBOQU1FKTtcclxuICAgICAgICB2YXIgdGhhdCA9IG5ldyBCYXNlO1xyXG4gICAgICAgIGlmKGl0ZXJhYmxlICE9IHVuZGVmaW5lZCkkaXRlci5mb3JPZihpdGVyYWJsZSwgSVNfTUFQLCB0aGF0W0FEREVSXSwgdGhhdCk7XHJcbiAgICAgICAgcmV0dXJuIHRoYXQ7XHJcbiAgICAgIH07XHJcbiAgICAgIEMucHJvdG90eXBlID0gcHJvdG87XHJcbiAgICAgIGlmKCQuRlcpcHJvdG8uY29uc3RydWN0b3IgPSBDO1xyXG4gICAgfVxyXG4gICAgaXNXZWFrIHx8IGluc3QuZm9yRWFjaChmdW5jdGlvbih2YWwsIGtleSl7XHJcbiAgICAgIGJ1Z2d5WmVybyA9IDEgLyBrZXkgPT09IC1JbmZpbml0eTtcclxuICAgIH0pO1xyXG4gICAgLy8gZml4IGNvbnZlcnRpbmcgLTAga2V5IHRvICswXHJcbiAgICBpZihidWdneVplcm8pe1xyXG4gICAgICBmaXhNZXRob2QoJ2RlbGV0ZScpO1xyXG4gICAgICBmaXhNZXRob2QoJ2hhcycpO1xyXG4gICAgICBJU19NQVAgJiYgZml4TWV0aG9kKCdnZXQnKTtcclxuICAgIH1cclxuICAgIC8vICsgZml4IC5hZGQgJiAuc2V0IGZvciBjaGFpbmluZ1xyXG4gICAgaWYoYnVnZ3laZXJvIHx8IGNoYWluICE9PSBpbnN0KWZpeE1ldGhvZChBRERFUiwgdHJ1ZSk7XHJcbiAgfVxyXG5cclxuICByZXF1aXJlKCcuLyQuY29mJykuc2V0KEMsIE5BTUUpO1xyXG4gIHJlcXVpcmUoJy4vJC5zcGVjaWVzJykoQyk7XHJcblxyXG4gIE9bTkFNRV0gPSBDO1xyXG4gICRkZWYoJGRlZi5HICsgJGRlZi5XICsgJGRlZi5GICogKEMgIT0gQmFzZSksIE8pO1xyXG5cclxuICAvLyBhZGQgLmtleXMsIC52YWx1ZXMsIC5lbnRyaWVzLCBbQEBpdGVyYXRvcl1cclxuICAvLyAyMy4xLjMuNCwgMjMuMS4zLjgsIDIzLjEuMy4xMSwgMjMuMS4zLjEyLCAyMy4yLjMuNSwgMjMuMi4zLjgsIDIzLjIuMy4xMCwgMjMuMi4zLjExXHJcbiAgaWYoIWlzV2VhaykkaXRlci5zdGQoXHJcbiAgICBDLCBOQU1FLFxyXG4gICAgY29tbW9uLmdldEl0ZXJDb25zdHJ1Y3RvcigpLCBjb21tb24ubmV4dCxcclxuICAgIElTX01BUCA/ICdrZXkrdmFsdWUnIDogJ3ZhbHVlJyAsICFJU19NQVAsIHRydWVcclxuICApO1xyXG5cclxuICByZXR1cm4gQztcclxufTsiLCIvLyBPcHRpb25hbCAvIHNpbXBsZSBjb250ZXh0IGJpbmRpbmdcclxudmFyIGFzc2VydEZ1bmN0aW9uID0gcmVxdWlyZSgnLi8kLmFzc2VydCcpLmZuO1xyXG5tb2R1bGUuZXhwb3J0cyA9IGZ1bmN0aW9uKGZuLCB0aGF0LCBsZW5ndGgpe1xyXG4gIGFzc2VydEZ1bmN0aW9uKGZuKTtcclxuICBpZih+bGVuZ3RoICYmIHRoYXQgPT09IHVuZGVmaW5lZClyZXR1cm4gZm47XHJcbiAgc3dpdGNoKGxlbmd0aCl7XHJcbiAgICBjYXNlIDE6IHJldHVybiBmdW5jdGlvbihhKXtcclxuICAgICAgcmV0dXJuIGZuLmNhbGwodGhhdCwgYSk7XHJcbiAgICB9O1xyXG4gICAgY2FzZSAyOiByZXR1cm4gZnVuY3Rpb24oYSwgYil7XHJcbiAgICAgIHJldHVybiBmbi5jYWxsKHRoYXQsIGEsIGIpO1xyXG4gICAgfTtcclxuICAgIGNhc2UgMzogcmV0dXJuIGZ1bmN0aW9uKGEsIGIsIGMpe1xyXG4gICAgICByZXR1cm4gZm4uY2FsbCh0aGF0LCBhLCBiLCBjKTtcclxuICAgIH07XHJcbiAgfSByZXR1cm4gZnVuY3Rpb24oLyogLi4uYXJncyAqLyl7XHJcbiAgICAgIHJldHVybiBmbi5hcHBseSh0aGF0LCBhcmd1bWVudHMpO1xyXG4gICAgfTtcclxufTsiLCJ2YXIgJCAgICAgICAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCBnbG9iYWwgICAgID0gJC5nXHJcbiAgLCBjb3JlICAgICAgID0gJC5jb3JlXHJcbiAgLCBpc0Z1bmN0aW9uID0gJC5pc0Z1bmN0aW9uO1xyXG5mdW5jdGlvbiBjdHgoZm4sIHRoYXQpe1xyXG4gIHJldHVybiBmdW5jdGlvbigpe1xyXG4gICAgcmV0dXJuIGZuLmFwcGx5KHRoYXQsIGFyZ3VtZW50cyk7XHJcbiAgfTtcclxufVxyXG5nbG9iYWwuY29yZSA9IGNvcmU7XHJcbi8vIHR5cGUgYml0bWFwXHJcbiRkZWYuRiA9IDE7ICAvLyBmb3JjZWRcclxuJGRlZi5HID0gMjsgIC8vIGdsb2JhbFxyXG4kZGVmLlMgPSA0OyAgLy8gc3RhdGljXHJcbiRkZWYuUCA9IDg7ICAvLyBwcm90b1xyXG4kZGVmLkIgPSAxNjsgLy8gYmluZFxyXG4kZGVmLlcgPSAzMjsgLy8gd3JhcFxyXG5mdW5jdGlvbiAkZGVmKHR5cGUsIG5hbWUsIHNvdXJjZSl7XHJcbiAgdmFyIGtleSwgb3duLCBvdXQsIGV4cFxyXG4gICAgLCBpc0dsb2JhbCA9IHR5cGUgJiAkZGVmLkdcclxuICAgICwgdGFyZ2V0ICAgPSBpc0dsb2JhbCA/IGdsb2JhbCA6IHR5cGUgJiAkZGVmLlNcclxuICAgICAgICA/IGdsb2JhbFtuYW1lXSA6IChnbG9iYWxbbmFtZV0gfHwge30pLnByb3RvdHlwZVxyXG4gICAgLCBleHBvcnRzICA9IGlzR2xvYmFsID8gY29yZSA6IGNvcmVbbmFtZV0gfHwgKGNvcmVbbmFtZV0gPSB7fSk7XHJcbiAgaWYoaXNHbG9iYWwpc291cmNlID0gbmFtZTtcclxuICBmb3Ioa2V5IGluIHNvdXJjZSl7XHJcbiAgICAvLyBjb250YWlucyBpbiBuYXRpdmVcclxuICAgIG93biA9ICEodHlwZSAmICRkZWYuRikgJiYgdGFyZ2V0ICYmIGtleSBpbiB0YXJnZXQ7XHJcbiAgICAvLyBleHBvcnQgbmF0aXZlIG9yIHBhc3NlZFxyXG4gICAgb3V0ID0gKG93biA/IHRhcmdldCA6IHNvdXJjZSlba2V5XTtcclxuICAgIC8vIGJpbmQgdGltZXJzIHRvIGdsb2JhbCBmb3IgY2FsbCBmcm9tIGV4cG9ydCBjb250ZXh0XHJcbiAgICBpZih0eXBlICYgJGRlZi5CICYmIG93billeHAgPSBjdHgob3V0LCBnbG9iYWwpO1xyXG4gICAgZWxzZSBleHAgPSB0eXBlICYgJGRlZi5QICYmIGlzRnVuY3Rpb24ob3V0KSA/IGN0eChGdW5jdGlvbi5jYWxsLCBvdXQpIDogb3V0O1xyXG4gICAgLy8gZXh0ZW5kIGdsb2JhbFxyXG4gICAgaWYodGFyZ2V0ICYmICFvd24pe1xyXG4gICAgICBpZihpc0dsb2JhbCl0YXJnZXRba2V5XSA9IG91dDtcclxuICAgICAgZWxzZSBkZWxldGUgdGFyZ2V0W2tleV0gJiYgJC5oaWRlKHRhcmdldCwga2V5LCBvdXQpO1xyXG4gICAgfVxyXG4gICAgLy8gZXhwb3J0XHJcbiAgICBpZihleHBvcnRzW2tleV0gIT0gb3V0KSQuaGlkZShleHBvcnRzLCBrZXksIGV4cCk7XHJcbiAgfVxyXG59XHJcbm1vZHVsZS5leHBvcnRzID0gJGRlZjsiLCJtb2R1bGUuZXhwb3J0cyA9IGZ1bmN0aW9uKCQpe1xyXG4gICQuRlcgICA9IHRydWU7XHJcbiAgJC5wYXRoID0gJC5nO1xyXG4gIHJldHVybiAkO1xyXG59OyIsIi8vIEZhc3QgYXBwbHlcclxuLy8gaHR0cDovL2pzcGVyZi5sbmtpdC5jb20vZmFzdC1hcHBseS81XHJcbm1vZHVsZS5leHBvcnRzID0gZnVuY3Rpb24oZm4sIGFyZ3MsIHRoYXQpe1xyXG4gIHZhciB1biA9IHRoYXQgPT09IHVuZGVmaW5lZDtcclxuICBzd2l0Y2goYXJncy5sZW5ndGgpe1xyXG4gICAgY2FzZSAwOiByZXR1cm4gdW4gPyBmbigpXHJcbiAgICAgICAgICAgICAgICAgICAgICA6IGZuLmNhbGwodGhhdCk7XHJcbiAgICBjYXNlIDE6IHJldHVybiB1biA/IGZuKGFyZ3NbMF0pXHJcbiAgICAgICAgICAgICAgICAgICAgICA6IGZuLmNhbGwodGhhdCwgYXJnc1swXSk7XHJcbiAgICBjYXNlIDI6IHJldHVybiB1biA/IGZuKGFyZ3NbMF0sIGFyZ3NbMV0pXHJcbiAgICAgICAgICAgICAgICAgICAgICA6IGZuLmNhbGwodGhhdCwgYXJnc1swXSwgYXJnc1sxXSk7XHJcbiAgICBjYXNlIDM6IHJldHVybiB1biA/IGZuKGFyZ3NbMF0sIGFyZ3NbMV0sIGFyZ3NbMl0pXHJcbiAgICAgICAgICAgICAgICAgICAgICA6IGZuLmNhbGwodGhhdCwgYXJnc1swXSwgYXJnc1sxXSwgYXJnc1syXSk7XHJcbiAgICBjYXNlIDQ6IHJldHVybiB1biA/IGZuKGFyZ3NbMF0sIGFyZ3NbMV0sIGFyZ3NbMl0sIGFyZ3NbM10pXHJcbiAgICAgICAgICAgICAgICAgICAgICA6IGZuLmNhbGwodGhhdCwgYXJnc1swXSwgYXJnc1sxXSwgYXJnc1syXSwgYXJnc1szXSk7XHJcbiAgICBjYXNlIDU6IHJldHVybiB1biA/IGZuKGFyZ3NbMF0sIGFyZ3NbMV0sIGFyZ3NbMl0sIGFyZ3NbM10sIGFyZ3NbNF0pXHJcbiAgICAgICAgICAgICAgICAgICAgICA6IGZuLmNhbGwodGhhdCwgYXJnc1swXSwgYXJnc1sxXSwgYXJnc1syXSwgYXJnc1szXSwgYXJnc1s0XSk7XHJcbiAgfSByZXR1cm4gICAgICAgICAgICAgIGZuLmFwcGx5KHRoYXQsIGFyZ3MpO1xyXG59OyIsIid1c2Ugc3RyaWN0JztcclxudmFyICQgICAgICAgICAgICAgICAgID0gcmVxdWlyZSgnLi8kJylcclxuICAsIGN0eCAgICAgICAgICAgICAgID0gcmVxdWlyZSgnLi8kLmN0eCcpXHJcbiAgLCBjb2YgICAgICAgICAgICAgICA9IHJlcXVpcmUoJy4vJC5jb2YnKVxyXG4gICwgJGRlZiAgICAgICAgICAgICAgPSByZXF1aXJlKCcuLyQuZGVmJylcclxuICAsIGFzc2VydE9iamVjdCAgICAgID0gcmVxdWlyZSgnLi8kLmFzc2VydCcpLm9ialxyXG4gICwgU1lNQk9MX0lURVJBVE9SICAgPSByZXF1aXJlKCcuLyQud2tzJykoJ2l0ZXJhdG9yJylcclxuICAsIEZGX0lURVJBVE9SICAgICAgID0gJ0BAaXRlcmF0b3InXHJcbiAgLCBJdGVyYXRvcnMgICAgICAgICA9IHt9XHJcbiAgLCBJdGVyYXRvclByb3RvdHlwZSA9IHt9O1xyXG4vLyBTYWZhcmkgaGFzIGJ5Z2d5IGl0ZXJhdG9ycyB3L28gYG5leHRgXHJcbnZhciBCVUdHWSA9ICdrZXlzJyBpbiBbXSAmJiAhKCduZXh0JyBpbiBbXS5rZXlzKCkpO1xyXG4vLyAyNS4xLjIuMS4xICVJdGVyYXRvclByb3RvdHlwZSVbQEBpdGVyYXRvcl0oKVxyXG5zZXRJdGVyYXRvcihJdGVyYXRvclByb3RvdHlwZSwgJC50aGF0KTtcclxuZnVuY3Rpb24gc2V0SXRlcmF0b3IoTywgdmFsdWUpe1xyXG4gICQuaGlkZShPLCBTWU1CT0xfSVRFUkFUT1IsIHZhbHVlKTtcclxuICAvLyBBZGQgaXRlcmF0b3IgZm9yIEZGIGl0ZXJhdG9yIHByb3RvY29sXHJcbiAgaWYoRkZfSVRFUkFUT1IgaW4gW10pJC5oaWRlKE8sIEZGX0lURVJBVE9SLCB2YWx1ZSk7XHJcbn1cclxuZnVuY3Rpb24gZGVmaW5lSXRlcmF0b3IoQ29uc3RydWN0b3IsIE5BTUUsIHZhbHVlLCBERUZBVUxUKXtcclxuICB2YXIgcHJvdG8gPSBDb25zdHJ1Y3Rvci5wcm90b3R5cGVcclxuICAgICwgaXRlciAgPSBwcm90b1tTWU1CT0xfSVRFUkFUT1JdIHx8IHByb3RvW0ZGX0lURVJBVE9SXSB8fCBERUZBVUxUICYmIHByb3RvW0RFRkFVTFRdIHx8IHZhbHVlO1xyXG4gIC8vIERlZmluZSBpdGVyYXRvclxyXG4gIGlmKCQuRlcpc2V0SXRlcmF0b3IocHJvdG8sIGl0ZXIpO1xyXG4gIGlmKGl0ZXIgIT09IHZhbHVlKXtcclxuICAgIHZhciBpdGVyUHJvdG8gPSAkLmdldFByb3RvKGl0ZXIuY2FsbChuZXcgQ29uc3RydWN0b3IpKTtcclxuICAgIC8vIFNldCBAQHRvU3RyaW5nVGFnIHRvIG5hdGl2ZSBpdGVyYXRvcnNcclxuICAgIGNvZi5zZXQoaXRlclByb3RvLCBOQU1FICsgJyBJdGVyYXRvcicsIHRydWUpO1xyXG4gICAgLy8gRkYgZml4XHJcbiAgICBpZigkLkZXKSQuaGFzKHByb3RvLCBGRl9JVEVSQVRPUikgJiYgc2V0SXRlcmF0b3IoaXRlclByb3RvLCAkLnRoYXQpO1xyXG4gIH1cclxuICAvLyBQbHVnIGZvciBsaWJyYXJ5XHJcbiAgSXRlcmF0b3JzW05BTUVdID0gaXRlcjtcclxuICAvLyBGRiAmIHY4IGZpeFxyXG4gIEl0ZXJhdG9yc1tOQU1FICsgJyBJdGVyYXRvciddID0gJC50aGF0O1xyXG4gIHJldHVybiBpdGVyO1xyXG59XHJcbmZ1bmN0aW9uIGdldEl0ZXJhdG9yKGl0KXtcclxuICB2YXIgU3ltYm9sICA9ICQuZy5TeW1ib2xcclxuICAgICwgZXh0ICAgICA9IGl0W1N5bWJvbCAmJiBTeW1ib2wuaXRlcmF0b3IgfHwgRkZfSVRFUkFUT1JdXHJcbiAgICAsIGdldEl0ZXIgPSBleHQgfHwgaXRbU1lNQk9MX0lURVJBVE9SXSB8fCBJdGVyYXRvcnNbY29mLmNsYXNzb2YoaXQpXTtcclxuICByZXR1cm4gYXNzZXJ0T2JqZWN0KGdldEl0ZXIuY2FsbChpdCkpO1xyXG59XHJcbmZ1bmN0aW9uIGNsb3NlSXRlcmF0b3IoaXRlcmF0b3Ipe1xyXG4gIHZhciByZXQgPSBpdGVyYXRvclsncmV0dXJuJ107XHJcbiAgaWYocmV0ICE9PSB1bmRlZmluZWQpYXNzZXJ0T2JqZWN0KHJldC5jYWxsKGl0ZXJhdG9yKSk7XHJcbn1cclxuZnVuY3Rpb24gc3RlcENhbGwoaXRlcmF0b3IsIGZuLCB2YWx1ZSwgZW50cmllcyl7XHJcbiAgdHJ5IHtcclxuICAgIHJldHVybiBlbnRyaWVzID8gZm4oYXNzZXJ0T2JqZWN0KHZhbHVlKVswXSwgdmFsdWVbMV0pIDogZm4odmFsdWUpO1xyXG4gIH0gY2F0Y2goZSl7XHJcbiAgICBjbG9zZUl0ZXJhdG9yKGl0ZXJhdG9yKTtcclxuICAgIHRocm93IGU7XHJcbiAgfVxyXG59XHJcbnZhciBEQU5HRVJfQ0xPU0lORyA9IHRydWU7XHJcbiFmdW5jdGlvbigpe1xyXG4gIHRyeSB7XHJcbiAgICB2YXIgaXRlciA9IFsxXS5rZXlzKCk7XHJcbiAgICBpdGVyWydyZXR1cm4nXSA9IGZ1bmN0aW9uKCl7IERBTkdFUl9DTE9TSU5HID0gZmFsc2U7IH07XHJcbiAgICBBcnJheS5mcm9tKGl0ZXIsIGZ1bmN0aW9uKCl7IHRocm93IDI7IH0pO1xyXG4gIH0gY2F0Y2goZSl7IC8qIGVtcHR5ICovIH1cclxufSgpO1xyXG52YXIgJGl0ZXIgPSBtb2R1bGUuZXhwb3J0cyA9IHtcclxuICBCVUdHWTogQlVHR1ksXHJcbiAgREFOR0VSX0NMT1NJTkc6IERBTkdFUl9DTE9TSU5HLFxyXG4gIGZhaWw6IGZ1bmN0aW9uKGV4ZWMpe1xyXG4gICAgdmFyIGZhaWwgPSB0cnVlO1xyXG4gICAgdHJ5IHtcclxuICAgICAgdmFyIGFyciAgPSBbW3t9LCAxXV1cclxuICAgICAgICAsIGl0ZXIgPSBhcnJbU1lNQk9MX0lURVJBVE9SXSgpXHJcbiAgICAgICAgLCBuZXh0ID0gaXRlci5uZXh0O1xyXG4gICAgICBpdGVyLm5leHQgPSBmdW5jdGlvbigpe1xyXG4gICAgICAgIGZhaWwgPSBmYWxzZTtcclxuICAgICAgICByZXR1cm4gbmV4dC5jYWxsKHRoaXMpO1xyXG4gICAgICB9O1xyXG4gICAgICBhcnJbU1lNQk9MX0lURVJBVE9SXSA9IGZ1bmN0aW9uKCl7XHJcbiAgICAgICAgcmV0dXJuIGl0ZXI7XHJcbiAgICAgIH07XHJcbiAgICAgIGV4ZWMoYXJyKTtcclxuICAgIH0gY2F0Y2goZSl7IC8qIGVtcHR5ICovIH1cclxuICAgIHJldHVybiBmYWlsO1xyXG4gIH0sXHJcbiAgSXRlcmF0b3JzOiBJdGVyYXRvcnMsXHJcbiAgcHJvdG90eXBlOiBJdGVyYXRvclByb3RvdHlwZSxcclxuICBzdGVwOiBmdW5jdGlvbihkb25lLCB2YWx1ZSl7XHJcbiAgICByZXR1cm4ge3ZhbHVlOiB2YWx1ZSwgZG9uZTogISFkb25lfTtcclxuICB9LFxyXG4gIHN0ZXBDYWxsOiBzdGVwQ2FsbCxcclxuICBjbG9zZTogY2xvc2VJdGVyYXRvcixcclxuICBpczogZnVuY3Rpb24oaXQpe1xyXG4gICAgdmFyIE8gICAgICA9IE9iamVjdChpdClcclxuICAgICAgLCBTeW1ib2wgPSAkLmcuU3ltYm9sXHJcbiAgICAgICwgU1lNICAgID0gU3ltYm9sICYmIFN5bWJvbC5pdGVyYXRvciB8fCBGRl9JVEVSQVRPUjtcclxuICAgIHJldHVybiBTWU0gaW4gTyB8fCBTWU1CT0xfSVRFUkFUT1IgaW4gTyB8fCAkLmhhcyhJdGVyYXRvcnMsIGNvZi5jbGFzc29mKE8pKTtcclxuICB9LFxyXG4gIGdldDogZ2V0SXRlcmF0b3IsXHJcbiAgc2V0OiBzZXRJdGVyYXRvcixcclxuICBjcmVhdGU6IGZ1bmN0aW9uKENvbnN0cnVjdG9yLCBOQU1FLCBuZXh0LCBwcm90byl7XHJcbiAgICBDb25zdHJ1Y3Rvci5wcm90b3R5cGUgPSAkLmNyZWF0ZShwcm90byB8fCAkaXRlci5wcm90b3R5cGUsIHtuZXh0OiAkLmRlc2MoMSwgbmV4dCl9KTtcclxuICAgIGNvZi5zZXQoQ29uc3RydWN0b3IsIE5BTUUgKyAnIEl0ZXJhdG9yJyk7XHJcbiAgfSxcclxuICBkZWZpbmU6IGRlZmluZUl0ZXJhdG9yLFxyXG4gIHN0ZDogZnVuY3Rpb24oQmFzZSwgTkFNRSwgQ29uc3RydWN0b3IsIG5leHQsIERFRkFVTFQsIElTX1NFVCwgRk9SQ0Upe1xyXG4gICAgZnVuY3Rpb24gY3JlYXRlSXRlcihraW5kKXtcclxuICAgICAgcmV0dXJuIGZ1bmN0aW9uKCl7XHJcbiAgICAgICAgcmV0dXJuIG5ldyBDb25zdHJ1Y3Rvcih0aGlzLCBraW5kKTtcclxuICAgICAgfTtcclxuICAgIH1cclxuICAgICRpdGVyLmNyZWF0ZShDb25zdHJ1Y3RvciwgTkFNRSwgbmV4dCk7XHJcbiAgICB2YXIgZW50cmllcyA9IGNyZWF0ZUl0ZXIoJ2tleSt2YWx1ZScpXHJcbiAgICAgICwgdmFsdWVzICA9IGNyZWF0ZUl0ZXIoJ3ZhbHVlJylcclxuICAgICAgLCBwcm90byAgID0gQmFzZS5wcm90b3R5cGVcclxuICAgICAgLCBtZXRob2RzLCBrZXk7XHJcbiAgICBpZihERUZBVUxUID09ICd2YWx1ZScpdmFsdWVzID0gZGVmaW5lSXRlcmF0b3IoQmFzZSwgTkFNRSwgdmFsdWVzLCAndmFsdWVzJyk7XHJcbiAgICBlbHNlIGVudHJpZXMgPSBkZWZpbmVJdGVyYXRvcihCYXNlLCBOQU1FLCBlbnRyaWVzLCAnZW50cmllcycpO1xyXG4gICAgaWYoREVGQVVMVCl7XHJcbiAgICAgIG1ldGhvZHMgPSB7XHJcbiAgICAgICAgZW50cmllczogZW50cmllcyxcclxuICAgICAgICBrZXlzOiAgICBJU19TRVQgPyB2YWx1ZXMgOiBjcmVhdGVJdGVyKCdrZXknKSxcclxuICAgICAgICB2YWx1ZXM6ICB2YWx1ZXNcclxuICAgICAgfTtcclxuICAgICAgJGRlZigkZGVmLlAgKyAkZGVmLkYgKiBCVUdHWSwgTkFNRSwgbWV0aG9kcyk7XHJcbiAgICAgIGlmKEZPUkNFKWZvcihrZXkgaW4gbWV0aG9kcyl7XHJcbiAgICAgICAgaWYoIShrZXkgaW4gcHJvdG8pKSQuaGlkZShwcm90bywga2V5LCBtZXRob2RzW2tleV0pO1xyXG4gICAgICB9XHJcbiAgICB9XHJcbiAgfSxcclxuICBmb3JPZjogZnVuY3Rpb24oaXRlcmFibGUsIGVudHJpZXMsIGZuLCB0aGF0KXtcclxuICAgIHZhciBpdGVyYXRvciA9IGdldEl0ZXJhdG9yKGl0ZXJhYmxlKVxyXG4gICAgICAsIGYgPSBjdHgoZm4sIHRoYXQsIGVudHJpZXMgPyAyIDogMSlcclxuICAgICAgLCBzdGVwO1xyXG4gICAgd2hpbGUoIShzdGVwID0gaXRlcmF0b3IubmV4dCgpKS5kb25lKXtcclxuICAgICAgaWYoc3RlcENhbGwoaXRlcmF0b3IsIGYsIHN0ZXAudmFsdWUsIGVudHJpZXMpID09PSBmYWxzZSl7XHJcbiAgICAgICAgcmV0dXJuIGNsb3NlSXRlcmF0b3IoaXRlcmF0b3IpO1xyXG4gICAgICB9XHJcbiAgICB9XHJcbiAgfVxyXG59OyIsIid1c2Ugc3RyaWN0JztcclxudmFyIGdsb2JhbCA9IHR5cGVvZiBzZWxmICE9ICd1bmRlZmluZWQnID8gc2VsZiA6IEZ1bmN0aW9uKCdyZXR1cm4gdGhpcycpKClcclxuICAsIGNvcmUgICA9IHt9XHJcbiAgLCBkZWZpbmVQcm9wZXJ0eSA9IE9iamVjdC5kZWZpbmVQcm9wZXJ0eVxyXG4gICwgaGFzT3duUHJvcGVydHkgPSB7fS5oYXNPd25Qcm9wZXJ0eVxyXG4gICwgY2VpbCAgPSBNYXRoLmNlaWxcclxuICAsIGZsb29yID0gTWF0aC5mbG9vclxyXG4gICwgbWF4ICAgPSBNYXRoLm1heFxyXG4gICwgbWluICAgPSBNYXRoLm1pbjtcclxuLy8gVGhlIGVuZ2luZSB3b3JrcyBmaW5lIHdpdGggZGVzY3JpcHRvcnM/IFRoYW5rJ3MgSUU4IGZvciBoaXMgZnVubnkgZGVmaW5lUHJvcGVydHkuXHJcbnZhciBERVNDID0gISFmdW5jdGlvbigpe1xyXG4gIHRyeSB7XHJcbiAgICByZXR1cm4gZGVmaW5lUHJvcGVydHkoe30sICdhJywge2dldDogZnVuY3Rpb24oKXsgcmV0dXJuIDI7IH19KS5hID09IDI7XHJcbiAgfSBjYXRjaChlKXsgLyogZW1wdHkgKi8gfVxyXG59KCk7XHJcbnZhciBoaWRlID0gY3JlYXRlRGVmaW5lcigxKTtcclxuLy8gNy4xLjQgVG9JbnRlZ2VyXHJcbmZ1bmN0aW9uIHRvSW50ZWdlcihpdCl7XHJcbiAgcmV0dXJuIGlzTmFOKGl0ID0gK2l0KSA/IDAgOiAoaXQgPiAwID8gZmxvb3IgOiBjZWlsKShpdCk7XHJcbn1cclxuZnVuY3Rpb24gZGVzYyhiaXRtYXAsIHZhbHVlKXtcclxuICByZXR1cm4ge1xyXG4gICAgZW51bWVyYWJsZSAgOiAhKGJpdG1hcCAmIDEpLFxyXG4gICAgY29uZmlndXJhYmxlOiAhKGJpdG1hcCAmIDIpLFxyXG4gICAgd3JpdGFibGUgICAgOiAhKGJpdG1hcCAmIDQpLFxyXG4gICAgdmFsdWUgICAgICAgOiB2YWx1ZVxyXG4gIH07XHJcbn1cclxuZnVuY3Rpb24gc2ltcGxlU2V0KG9iamVjdCwga2V5LCB2YWx1ZSl7XHJcbiAgb2JqZWN0W2tleV0gPSB2YWx1ZTtcclxuICByZXR1cm4gb2JqZWN0O1xyXG59XHJcbmZ1bmN0aW9uIGNyZWF0ZURlZmluZXIoYml0bWFwKXtcclxuICByZXR1cm4gREVTQyA/IGZ1bmN0aW9uKG9iamVjdCwga2V5LCB2YWx1ZSl7XHJcbiAgICByZXR1cm4gJC5zZXREZXNjKG9iamVjdCwga2V5LCBkZXNjKGJpdG1hcCwgdmFsdWUpKTsgLy8gZXNsaW50LWRpc2FibGUtbGluZSBuby11c2UtYmVmb3JlLWRlZmluZVxyXG4gIH0gOiBzaW1wbGVTZXQ7XHJcbn1cclxuXHJcbmZ1bmN0aW9uIGlzT2JqZWN0KGl0KXtcclxuICByZXR1cm4gaXQgIT09IG51bGwgJiYgKHR5cGVvZiBpdCA9PSAnb2JqZWN0JyB8fCB0eXBlb2YgaXQgPT0gJ2Z1bmN0aW9uJyk7XHJcbn1cclxuZnVuY3Rpb24gaXNGdW5jdGlvbihpdCl7XHJcbiAgcmV0dXJuIHR5cGVvZiBpdCA9PSAnZnVuY3Rpb24nO1xyXG59XHJcbmZ1bmN0aW9uIGFzc2VydERlZmluZWQoaXQpe1xyXG4gIGlmKGl0ID09IHVuZGVmaW5lZCl0aHJvdyBUeXBlRXJyb3IoXCJDYW4ndCBjYWxsIG1ldGhvZCBvbiAgXCIgKyBpdCk7XHJcbiAgcmV0dXJuIGl0O1xyXG59XHJcblxyXG52YXIgJCA9IG1vZHVsZS5leHBvcnRzID0gcmVxdWlyZSgnLi8kLmZ3Jykoe1xyXG4gIGc6IGdsb2JhbCxcclxuICBjb3JlOiBjb3JlLFxyXG4gIGh0bWw6IGdsb2JhbC5kb2N1bWVudCAmJiBkb2N1bWVudC5kb2N1bWVudEVsZW1lbnQsXHJcbiAgLy8gaHR0cDovL2pzcGVyZi5jb20vY29yZS1qcy1pc29iamVjdFxyXG4gIGlzT2JqZWN0OiAgIGlzT2JqZWN0LFxyXG4gIGlzRnVuY3Rpb246IGlzRnVuY3Rpb24sXHJcbiAgaXQ6IGZ1bmN0aW9uKGl0KXtcclxuICAgIHJldHVybiBpdDtcclxuICB9LFxyXG4gIHRoYXQ6IGZ1bmN0aW9uKCl7XHJcbiAgICByZXR1cm4gdGhpcztcclxuICB9LFxyXG4gIC8vIDcuMS40IFRvSW50ZWdlclxyXG4gIHRvSW50ZWdlcjogdG9JbnRlZ2VyLFxyXG4gIC8vIDcuMS4xNSBUb0xlbmd0aFxyXG4gIHRvTGVuZ3RoOiBmdW5jdGlvbihpdCl7XHJcbiAgICByZXR1cm4gaXQgPiAwID8gbWluKHRvSW50ZWdlcihpdCksIDB4MWZmZmZmZmZmZmZmZmYpIDogMDsgLy8gcG93KDIsIDUzKSAtIDEgPT0gOTAwNzE5OTI1NDc0MDk5MVxyXG4gIH0sXHJcbiAgdG9JbmRleDogZnVuY3Rpb24oaW5kZXgsIGxlbmd0aCl7XHJcbiAgICBpbmRleCA9IHRvSW50ZWdlcihpbmRleCk7XHJcbiAgICByZXR1cm4gaW5kZXggPCAwID8gbWF4KGluZGV4ICsgbGVuZ3RoLCAwKSA6IG1pbihpbmRleCwgbGVuZ3RoKTtcclxuICB9LFxyXG4gIGhhczogZnVuY3Rpb24oaXQsIGtleSl7XHJcbiAgICByZXR1cm4gaGFzT3duUHJvcGVydHkuY2FsbChpdCwga2V5KTtcclxuICB9LFxyXG4gIGNyZWF0ZTogICAgIE9iamVjdC5jcmVhdGUsXHJcbiAgZ2V0UHJvdG86ICAgT2JqZWN0LmdldFByb3RvdHlwZU9mLFxyXG4gIERFU0M6ICAgICAgIERFU0MsXHJcbiAgZGVzYzogICAgICAgZGVzYyxcclxuICBnZXREZXNjOiAgICBPYmplY3QuZ2V0T3duUHJvcGVydHlEZXNjcmlwdG9yLFxyXG4gIHNldERlc2M6ICAgIGRlZmluZVByb3BlcnR5LFxyXG4gIGdldEtleXM6ICAgIE9iamVjdC5rZXlzLFxyXG4gIGdldE5hbWVzOiAgIE9iamVjdC5nZXRPd25Qcm9wZXJ0eU5hbWVzLFxyXG4gIGdldFN5bWJvbHM6IE9iamVjdC5nZXRPd25Qcm9wZXJ0eVN5bWJvbHMsXHJcbiAgLy8gRHVtbXksIGZpeCBmb3Igbm90IGFycmF5LWxpa2UgRVMzIHN0cmluZyBpbiBlczUgbW9kdWxlXHJcbiAgYXNzZXJ0RGVmaW5lZDogYXNzZXJ0RGVmaW5lZCxcclxuICBFUzVPYmplY3Q6IE9iamVjdCxcclxuICB0b09iamVjdDogZnVuY3Rpb24oaXQpe1xyXG4gICAgcmV0dXJuICQuRVM1T2JqZWN0KGFzc2VydERlZmluZWQoaXQpKTtcclxuICB9LFxyXG4gIGhpZGU6IGhpZGUsXHJcbiAgZGVmOiBjcmVhdGVEZWZpbmVyKDApLFxyXG4gIHNldDogZ2xvYmFsLlN5bWJvbCA/IHNpbXBsZVNldCA6IGhpZGUsXHJcbiAgbWl4OiBmdW5jdGlvbih0YXJnZXQsIHNyYyl7XHJcbiAgICBmb3IodmFyIGtleSBpbiBzcmMpaGlkZSh0YXJnZXQsIGtleSwgc3JjW2tleV0pO1xyXG4gICAgcmV0dXJuIHRhcmdldDtcclxuICB9LFxyXG4gIGVhY2g6IFtdLmZvckVhY2hcclxufSk7XHJcbmlmKHR5cGVvZiBfX2UgIT0gJ3VuZGVmaW5lZCcpX19lID0gY29yZTtcclxuaWYodHlwZW9mIF9fZyAhPSAndW5kZWZpbmVkJylfX2cgPSBnbG9iYWw7IiwidmFyICQgPSByZXF1aXJlKCcuLyQnKTtcclxubW9kdWxlLmV4cG9ydHMgPSBmdW5jdGlvbihvYmplY3QsIGVsKXtcclxuICB2YXIgTyAgICAgID0gJC50b09iamVjdChvYmplY3QpXHJcbiAgICAsIGtleXMgICA9ICQuZ2V0S2V5cyhPKVxyXG4gICAgLCBsZW5ndGggPSBrZXlzLmxlbmd0aFxyXG4gICAgLCBpbmRleCAgPSAwXHJcbiAgICAsIGtleTtcclxuICB3aGlsZShsZW5ndGggPiBpbmRleClpZihPW2tleSA9IGtleXNbaW5kZXgrK11dID09PSBlbClyZXR1cm4ga2V5O1xyXG59OyIsInZhciAkICAgICAgICAgICAgPSByZXF1aXJlKCcuLyQnKVxyXG4gICwgYXNzZXJ0T2JqZWN0ID0gcmVxdWlyZSgnLi8kLmFzc2VydCcpLm9iajtcclxubW9kdWxlLmV4cG9ydHMgPSBmdW5jdGlvbihpdCl7XHJcbiAgYXNzZXJ0T2JqZWN0KGl0KTtcclxuICByZXR1cm4gJC5nZXRTeW1ib2xzID8gJC5nZXROYW1lcyhpdCkuY29uY2F0KCQuZ2V0U3ltYm9scyhpdCkpIDogJC5nZXROYW1lcyhpdCk7XHJcbn07IiwiJ3VzZSBzdHJpY3QnO1xyXG52YXIgJCAgICAgID0gcmVxdWlyZSgnLi8kJylcclxuICAsIGludm9rZSA9IHJlcXVpcmUoJy4vJC5pbnZva2UnKVxyXG4gICwgYXNzZXJ0RnVuY3Rpb24gPSByZXF1aXJlKCcuLyQuYXNzZXJ0JykuZm47XHJcbm1vZHVsZS5leHBvcnRzID0gZnVuY3Rpb24oLyogLi4ucGFyZ3MgKi8pe1xyXG4gIHZhciBmbiAgICAgPSBhc3NlcnRGdW5jdGlvbih0aGlzKVxyXG4gICAgLCBsZW5ndGggPSBhcmd1bWVudHMubGVuZ3RoXHJcbiAgICAsIHBhcmdzICA9IEFycmF5KGxlbmd0aClcclxuICAgICwgaSAgICAgID0gMFxyXG4gICAgLCBfICAgICAgPSAkLnBhdGguX1xyXG4gICAgLCBob2xkZXIgPSBmYWxzZTtcclxuICB3aGlsZShsZW5ndGggPiBpKWlmKChwYXJnc1tpXSA9IGFyZ3VtZW50c1tpKytdKSA9PT0gXylob2xkZXIgPSB0cnVlO1xyXG4gIHJldHVybiBmdW5jdGlvbigvKiAuLi5hcmdzICovKXtcclxuICAgIHZhciB0aGF0ICAgID0gdGhpc1xyXG4gICAgICAsIF9sZW5ndGggPSBhcmd1bWVudHMubGVuZ3RoXHJcbiAgICAgICwgaiA9IDAsIGsgPSAwLCBhcmdzO1xyXG4gICAgaWYoIWhvbGRlciAmJiAhX2xlbmd0aClyZXR1cm4gaW52b2tlKGZuLCBwYXJncywgdGhhdCk7XHJcbiAgICBhcmdzID0gcGFyZ3Muc2xpY2UoKTtcclxuICAgIGlmKGhvbGRlcilmb3IoO2xlbmd0aCA+IGo7IGorKylpZihhcmdzW2pdID09PSBfKWFyZ3Nbal0gPSBhcmd1bWVudHNbaysrXTtcclxuICAgIHdoaWxlKF9sZW5ndGggPiBrKWFyZ3MucHVzaChhcmd1bWVudHNbaysrXSk7XHJcbiAgICByZXR1cm4gaW52b2tlKGZuLCBhcmdzLCB0aGF0KTtcclxuICB9O1xyXG59OyIsIid1c2Ugc3RyaWN0JztcclxubW9kdWxlLmV4cG9ydHMgPSBmdW5jdGlvbihyZWdFeHAsIHJlcGxhY2UsIGlzU3RhdGljKXtcclxuICB2YXIgcmVwbGFjZXIgPSByZXBsYWNlID09PSBPYmplY3QocmVwbGFjZSkgPyBmdW5jdGlvbihwYXJ0KXtcclxuICAgIHJldHVybiByZXBsYWNlW3BhcnRdO1xyXG4gIH0gOiByZXBsYWNlO1xyXG4gIHJldHVybiBmdW5jdGlvbihpdCl7XHJcbiAgICByZXR1cm4gU3RyaW5nKGlzU3RhdGljID8gaXQgOiB0aGlzKS5yZXBsYWNlKHJlZ0V4cCwgcmVwbGFjZXIpO1xyXG4gIH07XHJcbn07IiwiLy8gV29ya3Mgd2l0aCBfX3Byb3RvX18gb25seS4gT2xkIHY4IGNhbid0IHdvcmtzIHdpdGggbnVsbCBwcm90byBvYmplY3RzLlxyXG4vKmVzbGludC1kaXNhYmxlIG5vLXByb3RvICovXHJcbnZhciAkICAgICAgPSByZXF1aXJlKCcuLyQnKVxyXG4gICwgYXNzZXJ0ID0gcmVxdWlyZSgnLi8kLmFzc2VydCcpO1xyXG5tb2R1bGUuZXhwb3J0cyA9IE9iamVjdC5zZXRQcm90b3R5cGVPZiB8fCAoJ19fcHJvdG9fXycgaW4ge30gLy8gZXNsaW50LWRpc2FibGUtbGluZVxyXG4gID8gZnVuY3Rpb24oYnVnZ3ksIHNldCl7XHJcbiAgICAgIHRyeSB7XHJcbiAgICAgICAgc2V0ID0gcmVxdWlyZSgnLi8kLmN0eCcpKEZ1bmN0aW9uLmNhbGwsICQuZ2V0RGVzYyhPYmplY3QucHJvdG90eXBlLCAnX19wcm90b19fJykuc2V0LCAyKTtcclxuICAgICAgICBzZXQoe30sIFtdKTtcclxuICAgICAgfSBjYXRjaChlKXsgYnVnZ3kgPSB0cnVlOyB9XHJcbiAgICAgIHJldHVybiBmdW5jdGlvbihPLCBwcm90byl7XHJcbiAgICAgICAgYXNzZXJ0Lm9iaihPKTtcclxuICAgICAgICBhc3NlcnQocHJvdG8gPT09IG51bGwgfHwgJC5pc09iamVjdChwcm90byksIHByb3RvLCBcIjogY2FuJ3Qgc2V0IGFzIHByb3RvdHlwZSFcIik7XHJcbiAgICAgICAgaWYoYnVnZ3kpTy5fX3Byb3RvX18gPSBwcm90bztcclxuICAgICAgICBlbHNlIHNldChPLCBwcm90byk7XHJcbiAgICAgICAgcmV0dXJuIE87XHJcbiAgICAgIH07XHJcbiAgICB9KClcclxuICA6IHVuZGVmaW5lZCk7IiwidmFyICQgPSByZXF1aXJlKCcuLyQnKTtcclxubW9kdWxlLmV4cG9ydHMgPSBmdW5jdGlvbihDKXtcclxuICBpZigkLkRFU0MgJiYgJC5GVykkLnNldERlc2MoQywgcmVxdWlyZSgnLi8kLndrcycpKCdzcGVjaWVzJyksIHtcclxuICAgIGNvbmZpZ3VyYWJsZTogdHJ1ZSxcclxuICAgIGdldDogJC50aGF0XHJcbiAgfSk7XHJcbn07IiwiJ3VzZSBzdHJpY3QnO1xyXG4vLyB0cnVlICAtPiBTdHJpbmcjYXRcclxuLy8gZmFsc2UgLT4gU3RyaW5nI2NvZGVQb2ludEF0XHJcbnZhciAkID0gcmVxdWlyZSgnLi8kJyk7XHJcbm1vZHVsZS5leHBvcnRzID0gZnVuY3Rpb24oVE9fU1RSSU5HKXtcclxuICByZXR1cm4gZnVuY3Rpb24ocG9zKXtcclxuICAgIHZhciBzID0gU3RyaW5nKCQuYXNzZXJ0RGVmaW5lZCh0aGlzKSlcclxuICAgICAgLCBpID0gJC50b0ludGVnZXIocG9zKVxyXG4gICAgICAsIGwgPSBzLmxlbmd0aFxyXG4gICAgICAsIGEsIGI7XHJcbiAgICBpZihpIDwgMCB8fCBpID49IGwpcmV0dXJuIFRPX1NUUklORyA/ICcnIDogdW5kZWZpbmVkO1xyXG4gICAgYSA9IHMuY2hhckNvZGVBdChpKTtcclxuICAgIHJldHVybiBhIDwgMHhkODAwIHx8IGEgPiAweGRiZmYgfHwgaSArIDEgPT09IGxcclxuICAgICAgfHwgKGIgPSBzLmNoYXJDb2RlQXQoaSArIDEpKSA8IDB4ZGMwMCB8fCBiID4gMHhkZmZmXHJcbiAgICAgICAgPyBUT19TVFJJTkcgPyBzLmNoYXJBdChpKSA6IGFcclxuICAgICAgICA6IFRPX1NUUklORyA/IHMuc2xpY2UoaSwgaSArIDIpIDogKGEgLSAweGQ4MDAgPDwgMTApICsgKGIgLSAweGRjMDApICsgMHgxMDAwMDtcclxuICB9O1xyXG59OyIsIid1c2Ugc3RyaWN0JztcclxudmFyICQgICAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCBjdHggICAgPSByZXF1aXJlKCcuLyQuY3R4JylcclxuICAsIGNvZiAgICA9IHJlcXVpcmUoJy4vJC5jb2YnKVxyXG4gICwgaW52b2tlID0gcmVxdWlyZSgnLi8kLmludm9rZScpXHJcbiAgLCBnbG9iYWwgICAgICAgICAgICAgPSAkLmdcclxuICAsIGlzRnVuY3Rpb24gICAgICAgICA9ICQuaXNGdW5jdGlvblxyXG4gICwgc2V0VGFzayAgICAgICAgICAgID0gZ2xvYmFsLnNldEltbWVkaWF0ZVxyXG4gICwgY2xlYXJUYXNrICAgICAgICAgID0gZ2xvYmFsLmNsZWFySW1tZWRpYXRlXHJcbiAgLCBwb3N0TWVzc2FnZSAgICAgICAgPSBnbG9iYWwucG9zdE1lc3NhZ2VcclxuICAsIGFkZEV2ZW50TGlzdGVuZXIgICA9IGdsb2JhbC5hZGRFdmVudExpc3RlbmVyXHJcbiAgLCBNZXNzYWdlQ2hhbm5lbCAgICAgPSBnbG9iYWwuTWVzc2FnZUNoYW5uZWxcclxuICAsIGNvdW50ZXIgICAgICAgICAgICA9IDBcclxuICAsIHF1ZXVlICAgICAgICAgICAgICA9IHt9XHJcbiAgLCBPTlJFQURZU1RBVEVDSEFOR0UgPSAnb25yZWFkeXN0YXRlY2hhbmdlJ1xyXG4gICwgZGVmZXIsIGNoYW5uZWwsIHBvcnQ7XHJcbmZ1bmN0aW9uIHJ1bigpe1xyXG4gIHZhciBpZCA9ICt0aGlzO1xyXG4gIGlmKCQuaGFzKHF1ZXVlLCBpZCkpe1xyXG4gICAgdmFyIGZuID0gcXVldWVbaWRdO1xyXG4gICAgZGVsZXRlIHF1ZXVlW2lkXTtcclxuICAgIGZuKCk7XHJcbiAgfVxyXG59XHJcbmZ1bmN0aW9uIGxpc3RuZXIoZXZlbnQpe1xyXG4gIHJ1bi5jYWxsKGV2ZW50LmRhdGEpO1xyXG59XHJcbi8vIE5vZGUuanMgMC45KyAmIElFMTArIGhhcyBzZXRJbW1lZGlhdGUsIG90aGVyd2lzZTpcclxuaWYoIWlzRnVuY3Rpb24oc2V0VGFzaykgfHwgIWlzRnVuY3Rpb24oY2xlYXJUYXNrKSl7XHJcbiAgc2V0VGFzayA9IGZ1bmN0aW9uKGZuKXtcclxuICAgIHZhciBhcmdzID0gW10sIGkgPSAxO1xyXG4gICAgd2hpbGUoYXJndW1lbnRzLmxlbmd0aCA+IGkpYXJncy5wdXNoKGFyZ3VtZW50c1tpKytdKTtcclxuICAgIHF1ZXVlWysrY291bnRlcl0gPSBmdW5jdGlvbigpe1xyXG4gICAgICBpbnZva2UoaXNGdW5jdGlvbihmbikgPyBmbiA6IEZ1bmN0aW9uKGZuKSwgYXJncyk7XHJcbiAgICB9O1xyXG4gICAgZGVmZXIoY291bnRlcik7XHJcbiAgICByZXR1cm4gY291bnRlcjtcclxuICB9O1xyXG4gIGNsZWFyVGFzayA9IGZ1bmN0aW9uKGlkKXtcclxuICAgIGRlbGV0ZSBxdWV1ZVtpZF07XHJcbiAgfTtcclxuICAvLyBOb2RlLmpzIDAuOC1cclxuICBpZihjb2YoZ2xvYmFsLnByb2Nlc3MpID09ICdwcm9jZXNzJyl7XHJcbiAgICBkZWZlciA9IGZ1bmN0aW9uKGlkKXtcclxuICAgICAgZ2xvYmFsLnByb2Nlc3MubmV4dFRpY2soY3R4KHJ1biwgaWQsIDEpKTtcclxuICAgIH07XHJcbiAgLy8gTW9kZXJuIGJyb3dzZXJzLCBza2lwIGltcGxlbWVudGF0aW9uIGZvciBXZWJXb3JrZXJzXHJcbiAgLy8gSUU4IGhhcyBwb3N0TWVzc2FnZSwgYnV0IGl0J3Mgc3luYyAmIHR5cGVvZiBpdHMgcG9zdE1lc3NhZ2UgaXMgb2JqZWN0XHJcbiAgfSBlbHNlIGlmKGFkZEV2ZW50TGlzdGVuZXIgJiYgaXNGdW5jdGlvbihwb3N0TWVzc2FnZSkgJiYgISQuZy5pbXBvcnRTY3JpcHRzKXtcclxuICAgIGRlZmVyID0gZnVuY3Rpb24oaWQpe1xyXG4gICAgICBwb3N0TWVzc2FnZShpZCwgJyonKTtcclxuICAgIH07XHJcbiAgICBhZGRFdmVudExpc3RlbmVyKCdtZXNzYWdlJywgbGlzdG5lciwgZmFsc2UpO1xyXG4gIC8vIFdlYldvcmtlcnNcclxuICB9IGVsc2UgaWYoaXNGdW5jdGlvbihNZXNzYWdlQ2hhbm5lbCkpe1xyXG4gICAgY2hhbm5lbCA9IG5ldyBNZXNzYWdlQ2hhbm5lbDtcclxuICAgIHBvcnQgICAgPSBjaGFubmVsLnBvcnQyO1xyXG4gICAgY2hhbm5lbC5wb3J0MS5vbm1lc3NhZ2UgPSBsaXN0bmVyO1xyXG4gICAgZGVmZXIgPSBjdHgocG9ydC5wb3N0TWVzc2FnZSwgcG9ydCwgMSk7XHJcbiAgLy8gSUU4LVxyXG4gIH0gZWxzZSBpZigkLmcuZG9jdW1lbnQgJiYgT05SRUFEWVNUQVRFQ0hBTkdFIGluIGRvY3VtZW50LmNyZWF0ZUVsZW1lbnQoJ3NjcmlwdCcpKXtcclxuICAgIGRlZmVyID0gZnVuY3Rpb24oaWQpe1xyXG4gICAgICAkLmh0bWwuYXBwZW5kQ2hpbGQoZG9jdW1lbnQuY3JlYXRlRWxlbWVudCgnc2NyaXB0JykpW09OUkVBRFlTVEFURUNIQU5HRV0gPSBmdW5jdGlvbigpe1xyXG4gICAgICAgICQuaHRtbC5yZW1vdmVDaGlsZCh0aGlzKTtcclxuICAgICAgICBydW4uY2FsbChpZCk7XHJcbiAgICAgIH07XHJcbiAgICB9O1xyXG4gIC8vIFJlc3Qgb2xkIGJyb3dzZXJzXHJcbiAgfSBlbHNlIHtcclxuICAgIGRlZmVyID0gZnVuY3Rpb24oaWQpe1xyXG4gICAgICBzZXRUaW1lb3V0KGN0eChydW4sIGlkLCAxKSwgMCk7XHJcbiAgICB9O1xyXG4gIH1cclxufVxyXG5tb2R1bGUuZXhwb3J0cyA9IHtcclxuICBzZXQ6ICAgc2V0VGFzayxcclxuICBjbGVhcjogY2xlYXJUYXNrXHJcbn07IiwidmFyIHNpZCA9IDA7XHJcbmZ1bmN0aW9uIHVpZChrZXkpe1xyXG4gIHJldHVybiAnU3ltYm9sKCcgKyBrZXkgKyAnKV8nICsgKCsrc2lkICsgTWF0aC5yYW5kb20oKSkudG9TdHJpbmcoMzYpO1xyXG59XHJcbnVpZC5zYWZlID0gcmVxdWlyZSgnLi8kJykuZy5TeW1ib2wgfHwgdWlkO1xyXG5tb2R1bGUuZXhwb3J0cyA9IHVpZDsiLCIvLyAyMi4xLjMuMzEgQXJyYXkucHJvdG90eXBlW0BAdW5zY29wYWJsZXNdXHJcbnZhciAkICAgICAgICAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCBVTlNDT1BBQkxFUyA9IHJlcXVpcmUoJy4vJC53a3MnKSgndW5zY29wYWJsZXMnKTtcclxuaWYoJC5GVyAmJiAhKFVOU0NPUEFCTEVTIGluIFtdKSkkLmhpZGUoQXJyYXkucHJvdG90eXBlLCBVTlNDT1BBQkxFUywge30pO1xyXG5tb2R1bGUuZXhwb3J0cyA9IGZ1bmN0aW9uKGtleSl7XHJcbiAgaWYoJC5GVylbXVtVTlNDT1BBQkxFU11ba2V5XSA9IHRydWU7XHJcbn07IiwidmFyIGdsb2JhbCA9IHJlcXVpcmUoJy4vJCcpLmdcclxuICAsIHN0b3JlICA9IHt9O1xyXG5tb2R1bGUuZXhwb3J0cyA9IGZ1bmN0aW9uKG5hbWUpe1xyXG4gIHJldHVybiBzdG9yZVtuYW1lXSB8fCAoc3RvcmVbbmFtZV0gPVxyXG4gICAgZ2xvYmFsLlN5bWJvbCAmJiBnbG9iYWwuU3ltYm9sW25hbWVdIHx8IHJlcXVpcmUoJy4vJC51aWQnKS5zYWZlKCdTeW1ib2wuJyArIG5hbWUpKTtcclxufTsiLCJ2YXIgJCAgICAgICAgICAgICAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCBjb2YgICAgICAgICAgICAgID0gcmVxdWlyZSgnLi8kLmNvZicpXHJcbiAgLCAkZGVmICAgICAgICAgICAgID0gcmVxdWlyZSgnLi8kLmRlZicpXHJcbiAgLCBpbnZva2UgICAgICAgICAgID0gcmVxdWlyZSgnLi8kLmludm9rZScpXHJcbiAgLCBhcnJheU1ldGhvZCAgICAgID0gcmVxdWlyZSgnLi8kLmFycmF5LW1ldGhvZHMnKVxyXG4gICwgSUVfUFJPVE8gICAgICAgICA9IHJlcXVpcmUoJy4vJC51aWQnKS5zYWZlKCdfX3Byb3RvX18nKVxyXG4gICwgYXNzZXJ0ICAgICAgICAgICA9IHJlcXVpcmUoJy4vJC5hc3NlcnQnKVxyXG4gICwgYXNzZXJ0T2JqZWN0ICAgICA9IGFzc2VydC5vYmpcclxuICAsIE9iamVjdFByb3RvICAgICAgPSBPYmplY3QucHJvdG90eXBlXHJcbiAgLCBBICAgICAgICAgICAgICAgID0gW11cclxuICAsIHNsaWNlICAgICAgICAgICAgPSBBLnNsaWNlXHJcbiAgLCBpbmRleE9mICAgICAgICAgID0gQS5pbmRleE9mXHJcbiAgLCBjbGFzc29mICAgICAgICAgID0gY29mLmNsYXNzb2ZcclxuICAsIGRlZmluZVByb3BlcnRpZXMgPSBPYmplY3QuZGVmaW5lUHJvcGVydGllc1xyXG4gICwgaGFzICAgICAgICAgICAgICA9ICQuaGFzXHJcbiAgLCBkZWZpbmVQcm9wZXJ0eSAgID0gJC5zZXREZXNjXHJcbiAgLCBnZXRPd25EZXNjcmlwdG9yID0gJC5nZXREZXNjXHJcbiAgLCBpc0Z1bmN0aW9uICAgICAgID0gJC5pc0Z1bmN0aW9uXHJcbiAgLCB0b09iamVjdCAgICAgICAgID0gJC50b09iamVjdFxyXG4gICwgdG9MZW5ndGggICAgICAgICA9ICQudG9MZW5ndGhcclxuICAsIElFOF9ET01fREVGSU5FICAgPSBmYWxzZTtcclxuXHJcbmlmKCEkLkRFU0Mpe1xyXG4gIHRyeSB7XHJcbiAgICBJRThfRE9NX0RFRklORSA9IGRlZmluZVByb3BlcnR5KGRvY3VtZW50LmNyZWF0ZUVsZW1lbnQoJ2RpdicpLCAneCcsXHJcbiAgICAgIHtnZXQ6IGZ1bmN0aW9uKCl7IHJldHVybiA4OyB9fVxyXG4gICAgKS54ID09IDg7XHJcbiAgfSBjYXRjaChlKXsgLyogZW1wdHkgKi8gfVxyXG4gICQuc2V0RGVzYyA9IGZ1bmN0aW9uKE8sIFAsIEF0dHJpYnV0ZXMpe1xyXG4gICAgaWYoSUU4X0RPTV9ERUZJTkUpdHJ5IHtcclxuICAgICAgcmV0dXJuIGRlZmluZVByb3BlcnR5KE8sIFAsIEF0dHJpYnV0ZXMpO1xyXG4gICAgfSBjYXRjaChlKXsgLyogZW1wdHkgKi8gfVxyXG4gICAgaWYoJ2dldCcgaW4gQXR0cmlidXRlcyB8fCAnc2V0JyBpbiBBdHRyaWJ1dGVzKXRocm93IFR5cGVFcnJvcignQWNjZXNzb3JzIG5vdCBzdXBwb3J0ZWQhJyk7XHJcbiAgICBpZigndmFsdWUnIGluIEF0dHJpYnV0ZXMpYXNzZXJ0T2JqZWN0KE8pW1BdID0gQXR0cmlidXRlcy52YWx1ZTtcclxuICAgIHJldHVybiBPO1xyXG4gIH07XHJcbiAgJC5nZXREZXNjID0gZnVuY3Rpb24oTywgUCl7XHJcbiAgICBpZihJRThfRE9NX0RFRklORSl0cnkge1xyXG4gICAgICByZXR1cm4gZ2V0T3duRGVzY3JpcHRvcihPLCBQKTtcclxuICAgIH0gY2F0Y2goZSl7IC8qIGVtcHR5ICovIH1cclxuICAgIGlmKGhhcyhPLCBQKSlyZXR1cm4gJC5kZXNjKCFPYmplY3RQcm90by5wcm9wZXJ0eUlzRW51bWVyYWJsZS5jYWxsKE8sIFApLCBPW1BdKTtcclxuICB9O1xyXG4gIGRlZmluZVByb3BlcnRpZXMgPSBmdW5jdGlvbihPLCBQcm9wZXJ0aWVzKXtcclxuICAgIGFzc2VydE9iamVjdChPKTtcclxuICAgIHZhciBrZXlzICAgPSAkLmdldEtleXMoUHJvcGVydGllcylcclxuICAgICAgLCBsZW5ndGggPSBrZXlzLmxlbmd0aFxyXG4gICAgICAsIGkgPSAwXHJcbiAgICAgICwgUDtcclxuICAgIHdoaWxlKGxlbmd0aCA+IGkpJC5zZXREZXNjKE8sIFAgPSBrZXlzW2krK10sIFByb3BlcnRpZXNbUF0pO1xyXG4gICAgcmV0dXJuIE87XHJcbiAgfTtcclxufVxyXG4kZGVmKCRkZWYuUyArICRkZWYuRiAqICEkLkRFU0MsICdPYmplY3QnLCB7XHJcbiAgLy8gMTkuMS4yLjYgLyAxNS4yLjMuMyBPYmplY3QuZ2V0T3duUHJvcGVydHlEZXNjcmlwdG9yKE8sIFApXHJcbiAgZ2V0T3duUHJvcGVydHlEZXNjcmlwdG9yOiAkLmdldERlc2MsXHJcbiAgLy8gMTkuMS4yLjQgLyAxNS4yLjMuNiBPYmplY3QuZGVmaW5lUHJvcGVydHkoTywgUCwgQXR0cmlidXRlcylcclxuICBkZWZpbmVQcm9wZXJ0eTogJC5zZXREZXNjLFxyXG4gIC8vIDE5LjEuMi4zIC8gMTUuMi4zLjcgT2JqZWN0LmRlZmluZVByb3BlcnRpZXMoTywgUHJvcGVydGllcylcclxuICBkZWZpbmVQcm9wZXJ0aWVzOiBkZWZpbmVQcm9wZXJ0aWVzXHJcbn0pO1xyXG5cclxuICAvLyBJRSA4LSBkb24ndCBlbnVtIGJ1ZyBrZXlzXHJcbnZhciBrZXlzMSA9ICgnY29uc3RydWN0b3IsaGFzT3duUHJvcGVydHksaXNQcm90b3R5cGVPZixwcm9wZXJ0eUlzRW51bWVyYWJsZSwnICtcclxuICAgICAgICAgICAgJ3RvTG9jYWxlU3RyaW5nLHRvU3RyaW5nLHZhbHVlT2YnKS5zcGxpdCgnLCcpXHJcbiAgLy8gQWRkaXRpb25hbCBrZXlzIGZvciBnZXRPd25Qcm9wZXJ0eU5hbWVzXHJcbiAgLCBrZXlzMiA9IGtleXMxLmNvbmNhdCgnbGVuZ3RoJywgJ3Byb3RvdHlwZScpXHJcbiAgLCBrZXlzTGVuMSA9IGtleXMxLmxlbmd0aDtcclxuXHJcbi8vIENyZWF0ZSBvYmplY3Qgd2l0aCBgbnVsbGAgcHJvdG90eXBlOiB1c2UgaWZyYW1lIE9iamVjdCB3aXRoIGNsZWFyZWQgcHJvdG90eXBlXHJcbnZhciBjcmVhdGVEaWN0ID0gZnVuY3Rpb24oKXtcclxuICAvLyBUaHJhc2gsIHdhc3RlIGFuZCBzb2RvbXk6IElFIEdDIGJ1Z1xyXG4gIHZhciBpZnJhbWUgPSBkb2N1bWVudC5jcmVhdGVFbGVtZW50KCdpZnJhbWUnKVxyXG4gICAgLCBpICAgICAgPSBrZXlzTGVuMVxyXG4gICAgLCBpZnJhbWVEb2N1bWVudDtcclxuICBpZnJhbWUuc3R5bGUuZGlzcGxheSA9ICdub25lJztcclxuICAkLmh0bWwuYXBwZW5kQ2hpbGQoaWZyYW1lKTtcclxuICBpZnJhbWUuc3JjID0gJ2phdmFzY3JpcHQ6JzsgLy8gZXNsaW50LWRpc2FibGUtbGluZSBuby1zY3JpcHQtdXJsXHJcbiAgLy8gY3JlYXRlRGljdCA9IGlmcmFtZS5jb250ZW50V2luZG93Lk9iamVjdDtcclxuICAvLyBodG1sLnJlbW92ZUNoaWxkKGlmcmFtZSk7XHJcbiAgaWZyYW1lRG9jdW1lbnQgPSBpZnJhbWUuY29udGVudFdpbmRvdy5kb2N1bWVudDtcclxuICBpZnJhbWVEb2N1bWVudC5vcGVuKCk7XHJcbiAgaWZyYW1lRG9jdW1lbnQud3JpdGUoJzxzY3JpcHQ+ZG9jdW1lbnQuRj1PYmplY3Q8L3NjcmlwdD4nKTtcclxuICBpZnJhbWVEb2N1bWVudC5jbG9zZSgpO1xyXG4gIGNyZWF0ZURpY3QgPSBpZnJhbWVEb2N1bWVudC5GO1xyXG4gIHdoaWxlKGktLSlkZWxldGUgY3JlYXRlRGljdC5wcm90b3R5cGVba2V5czFbaV1dO1xyXG4gIHJldHVybiBjcmVhdGVEaWN0KCk7XHJcbn07XHJcbmZ1bmN0aW9uIGNyZWF0ZUdldEtleXMobmFtZXMsIGxlbmd0aCl7XHJcbiAgcmV0dXJuIGZ1bmN0aW9uKG9iamVjdCl7XHJcbiAgICB2YXIgTyAgICAgID0gdG9PYmplY3Qob2JqZWN0KVxyXG4gICAgICAsIGkgICAgICA9IDBcclxuICAgICAgLCByZXN1bHQgPSBbXVxyXG4gICAgICAsIGtleTtcclxuICAgIGZvcihrZXkgaW4gTylpZihrZXkgIT0gSUVfUFJPVE8paGFzKE8sIGtleSkgJiYgcmVzdWx0LnB1c2goa2V5KTtcclxuICAgIC8vIERvbid0IGVudW0gYnVnICYgaGlkZGVuIGtleXNcclxuICAgIHdoaWxlKGxlbmd0aCA+IGkpaWYoaGFzKE8sIGtleSA9IG5hbWVzW2krK10pKXtcclxuICAgICAgfmluZGV4T2YuY2FsbChyZXN1bHQsIGtleSkgfHwgcmVzdWx0LnB1c2goa2V5KTtcclxuICAgIH1cclxuICAgIHJldHVybiByZXN1bHQ7XHJcbiAgfTtcclxufVxyXG5mdW5jdGlvbiBpc1ByaW1pdGl2ZShpdCl7IHJldHVybiAhJC5pc09iamVjdChpdCk7IH1cclxuZnVuY3Rpb24gRW1wdHkoKXt9XHJcbiRkZWYoJGRlZi5TLCAnT2JqZWN0Jywge1xyXG4gIC8vIDE5LjEuMi45IC8gMTUuMi4zLjIgT2JqZWN0LmdldFByb3RvdHlwZU9mKE8pXHJcbiAgZ2V0UHJvdG90eXBlT2Y6ICQuZ2V0UHJvdG8gPSAkLmdldFByb3RvIHx8IGZ1bmN0aW9uKE8pe1xyXG4gICAgTyA9IE9iamVjdChhc3NlcnQuZGVmKE8pKTtcclxuICAgIGlmKGhhcyhPLCBJRV9QUk9UTykpcmV0dXJuIE9bSUVfUFJPVE9dO1xyXG4gICAgaWYoaXNGdW5jdGlvbihPLmNvbnN0cnVjdG9yKSAmJiBPIGluc3RhbmNlb2YgTy5jb25zdHJ1Y3Rvcil7XHJcbiAgICAgIHJldHVybiBPLmNvbnN0cnVjdG9yLnByb3RvdHlwZTtcclxuICAgIH0gcmV0dXJuIE8gaW5zdGFuY2VvZiBPYmplY3QgPyBPYmplY3RQcm90byA6IG51bGw7XHJcbiAgfSxcclxuICAvLyAxOS4xLjIuNyAvIDE1LjIuMy40IE9iamVjdC5nZXRPd25Qcm9wZXJ0eU5hbWVzKE8pXHJcbiAgZ2V0T3duUHJvcGVydHlOYW1lczogJC5nZXROYW1lcyA9ICQuZ2V0TmFtZXMgfHwgY3JlYXRlR2V0S2V5cyhrZXlzMiwga2V5czIubGVuZ3RoLCB0cnVlKSxcclxuICAvLyAxOS4xLjIuMiAvIDE1LjIuMy41IE9iamVjdC5jcmVhdGUoTyBbLCBQcm9wZXJ0aWVzXSlcclxuICBjcmVhdGU6ICQuY3JlYXRlID0gJC5jcmVhdGUgfHwgZnVuY3Rpb24oTywgLyo/Ki9Qcm9wZXJ0aWVzKXtcclxuICAgIHZhciByZXN1bHQ7XHJcbiAgICBpZihPICE9PSBudWxsKXtcclxuICAgICAgRW1wdHkucHJvdG90eXBlID0gYXNzZXJ0T2JqZWN0KE8pO1xyXG4gICAgICByZXN1bHQgPSBuZXcgRW1wdHkoKTtcclxuICAgICAgRW1wdHkucHJvdG90eXBlID0gbnVsbDtcclxuICAgICAgLy8gYWRkIFwiX19wcm90b19fXCIgZm9yIE9iamVjdC5nZXRQcm90b3R5cGVPZiBzaGltXHJcbiAgICAgIHJlc3VsdFtJRV9QUk9UT10gPSBPO1xyXG4gICAgfSBlbHNlIHJlc3VsdCA9IGNyZWF0ZURpY3QoKTtcclxuICAgIHJldHVybiBQcm9wZXJ0aWVzID09PSB1bmRlZmluZWQgPyByZXN1bHQgOiBkZWZpbmVQcm9wZXJ0aWVzKHJlc3VsdCwgUHJvcGVydGllcyk7XHJcbiAgfSxcclxuICAvLyAxOS4xLjIuMTQgLyAxNS4yLjMuMTQgT2JqZWN0LmtleXMoTylcclxuICBrZXlzOiAkLmdldEtleXMgPSAkLmdldEtleXMgfHwgY3JlYXRlR2V0S2V5cyhrZXlzMSwga2V5c0xlbjEsIGZhbHNlKSxcclxuICAvLyAxOS4xLjIuMTcgLyAxNS4yLjMuOCBPYmplY3Quc2VhbChPKVxyXG4gIHNlYWw6ICQuaXQsIC8vIDwtIGNhcFxyXG4gIC8vIDE5LjEuMi41IC8gMTUuMi4zLjkgT2JqZWN0LmZyZWV6ZShPKVxyXG4gIGZyZWV6ZTogJC5pdCwgLy8gPC0gY2FwXHJcbiAgLy8gMTkuMS4yLjE1IC8gMTUuMi4zLjEwIE9iamVjdC5wcmV2ZW50RXh0ZW5zaW9ucyhPKVxyXG4gIHByZXZlbnRFeHRlbnNpb25zOiAkLml0LCAvLyA8LSBjYXBcclxuICAvLyAxOS4xLjIuMTMgLyAxNS4yLjMuMTEgT2JqZWN0LmlzU2VhbGVkKE8pXHJcbiAgaXNTZWFsZWQ6IGlzUHJpbWl0aXZlLCAvLyA8LSBjYXBcclxuICAvLyAxOS4xLjIuMTIgLyAxNS4yLjMuMTIgT2JqZWN0LmlzRnJvemVuKE8pXHJcbiAgaXNGcm96ZW46IGlzUHJpbWl0aXZlLCAvLyA8LSBjYXBcclxuICAvLyAxOS4xLjIuMTEgLyAxNS4yLjMuMTMgT2JqZWN0LmlzRXh0ZW5zaWJsZShPKVxyXG4gIGlzRXh0ZW5zaWJsZTogJC5pc09iamVjdCAvLyA8LSBjYXBcclxufSk7XHJcblxyXG4vLyAxOS4yLjMuMiAvIDE1LjMuNC41IEZ1bmN0aW9uLnByb3RvdHlwZS5iaW5kKHRoaXNBcmcsIGFyZ3MuLi4pXHJcbiRkZWYoJGRlZi5QLCAnRnVuY3Rpb24nLCB7XHJcbiAgYmluZDogZnVuY3Rpb24odGhhdCAvKiwgYXJncy4uLiAqLyl7XHJcbiAgICB2YXIgZm4gICAgICAgPSBhc3NlcnQuZm4odGhpcylcclxuICAgICAgLCBwYXJ0QXJncyA9IHNsaWNlLmNhbGwoYXJndW1lbnRzLCAxKTtcclxuICAgIGZ1bmN0aW9uIGJvdW5kKC8qIGFyZ3MuLi4gKi8pe1xyXG4gICAgICB2YXIgYXJncyA9IHBhcnRBcmdzLmNvbmNhdChzbGljZS5jYWxsKGFyZ3VtZW50cykpO1xyXG4gICAgICByZXR1cm4gaW52b2tlKGZuLCBhcmdzLCB0aGlzIGluc3RhbmNlb2YgYm91bmQgPyAkLmNyZWF0ZShmbi5wcm90b3R5cGUpIDogdGhhdCk7XHJcbiAgICB9XHJcbiAgICBpZihmbi5wcm90b3R5cGUpYm91bmQucHJvdG90eXBlID0gZm4ucHJvdG90eXBlO1xyXG4gICAgcmV0dXJuIGJvdW5kO1xyXG4gIH1cclxufSk7XHJcblxyXG4vLyBGaXggZm9yIG5vdCBhcnJheS1saWtlIEVTMyBzdHJpbmdcclxuZnVuY3Rpb24gYXJyYXlNZXRob2RGaXgoZm4pe1xyXG4gIHJldHVybiBmdW5jdGlvbigpe1xyXG4gICAgcmV0dXJuIGZuLmFwcGx5KCQuRVM1T2JqZWN0KHRoaXMpLCBhcmd1bWVudHMpO1xyXG4gIH07XHJcbn1cclxuaWYoISgwIGluIE9iamVjdCgneicpICYmICd6J1swXSA9PSAneicpKXtcclxuICAkLkVTNU9iamVjdCA9IGZ1bmN0aW9uKGl0KXtcclxuICAgIHJldHVybiBjb2YoaXQpID09ICdTdHJpbmcnID8gaXQuc3BsaXQoJycpIDogT2JqZWN0KGl0KTtcclxuICB9O1xyXG59XHJcbiRkZWYoJGRlZi5QICsgJGRlZi5GICogKCQuRVM1T2JqZWN0ICE9IE9iamVjdCksICdBcnJheScsIHtcclxuICBzbGljZTogYXJyYXlNZXRob2RGaXgoc2xpY2UpLFxyXG4gIGpvaW46IGFycmF5TWV0aG9kRml4KEEuam9pbilcclxufSk7XHJcblxyXG4vLyAyMi4xLjIuMiAvIDE1LjQuMy4yIEFycmF5LmlzQXJyYXkoYXJnKVxyXG4kZGVmKCRkZWYuUywgJ0FycmF5Jywge1xyXG4gIGlzQXJyYXk6IGZ1bmN0aW9uKGFyZyl7XHJcbiAgICByZXR1cm4gY29mKGFyZykgPT0gJ0FycmF5JztcclxuICB9XHJcbn0pO1xyXG5mdW5jdGlvbiBjcmVhdGVBcnJheVJlZHVjZShpc1JpZ2h0KXtcclxuICByZXR1cm4gZnVuY3Rpb24oY2FsbGJhY2tmbiwgbWVtbyl7XHJcbiAgICBhc3NlcnQuZm4oY2FsbGJhY2tmbik7XHJcbiAgICB2YXIgTyAgICAgID0gdG9PYmplY3QodGhpcylcclxuICAgICAgLCBsZW5ndGggPSB0b0xlbmd0aChPLmxlbmd0aClcclxuICAgICAgLCBpbmRleCAgPSBpc1JpZ2h0ID8gbGVuZ3RoIC0gMSA6IDBcclxuICAgICAgLCBpICAgICAgPSBpc1JpZ2h0ID8gLTEgOiAxO1xyXG4gICAgaWYoYXJndW1lbnRzLmxlbmd0aCA8IDIpZm9yKDs7KXtcclxuICAgICAgaWYoaW5kZXggaW4gTyl7XHJcbiAgICAgICAgbWVtbyA9IE9baW5kZXhdO1xyXG4gICAgICAgIGluZGV4ICs9IGk7XHJcbiAgICAgICAgYnJlYWs7XHJcbiAgICAgIH1cclxuICAgICAgaW5kZXggKz0gaTtcclxuICAgICAgYXNzZXJ0KGlzUmlnaHQgPyBpbmRleCA+PSAwIDogbGVuZ3RoID4gaW5kZXgsICdSZWR1Y2Ugb2YgZW1wdHkgYXJyYXkgd2l0aCBubyBpbml0aWFsIHZhbHVlJyk7XHJcbiAgICB9XHJcbiAgICBmb3IoO2lzUmlnaHQgPyBpbmRleCA+PSAwIDogbGVuZ3RoID4gaW5kZXg7IGluZGV4ICs9IGkpaWYoaW5kZXggaW4gTyl7XHJcbiAgICAgIG1lbW8gPSBjYWxsYmFja2ZuKG1lbW8sIE9baW5kZXhdLCBpbmRleCwgdGhpcyk7XHJcbiAgICB9XHJcbiAgICByZXR1cm4gbWVtbztcclxuICB9O1xyXG59XHJcbiRkZWYoJGRlZi5QLCAnQXJyYXknLCB7XHJcbiAgLy8gMjIuMS4zLjEwIC8gMTUuNC40LjE4IEFycmF5LnByb3RvdHlwZS5mb3JFYWNoKGNhbGxiYWNrZm4gWywgdGhpc0FyZ10pXHJcbiAgZm9yRWFjaDogJC5lYWNoID0gJC5lYWNoIHx8IGFycmF5TWV0aG9kKDApLFxyXG4gIC8vIDIyLjEuMy4xNSAvIDE1LjQuNC4xOSBBcnJheS5wcm90b3R5cGUubWFwKGNhbGxiYWNrZm4gWywgdGhpc0FyZ10pXHJcbiAgbWFwOiBhcnJheU1ldGhvZCgxKSxcclxuICAvLyAyMi4xLjMuNyAvIDE1LjQuNC4yMCBBcnJheS5wcm90b3R5cGUuZmlsdGVyKGNhbGxiYWNrZm4gWywgdGhpc0FyZ10pXHJcbiAgZmlsdGVyOiBhcnJheU1ldGhvZCgyKSxcclxuICAvLyAyMi4xLjMuMjMgLyAxNS40LjQuMTcgQXJyYXkucHJvdG90eXBlLnNvbWUoY2FsbGJhY2tmbiBbLCB0aGlzQXJnXSlcclxuICBzb21lOiBhcnJheU1ldGhvZCgzKSxcclxuICAvLyAyMi4xLjMuNSAvIDE1LjQuNC4xNiBBcnJheS5wcm90b3R5cGUuZXZlcnkoY2FsbGJhY2tmbiBbLCB0aGlzQXJnXSlcclxuICBldmVyeTogYXJyYXlNZXRob2QoNCksXHJcbiAgLy8gMjIuMS4zLjE4IC8gMTUuNC40LjIxIEFycmF5LnByb3RvdHlwZS5yZWR1Y2UoY2FsbGJhY2tmbiBbLCBpbml0aWFsVmFsdWVdKVxyXG4gIHJlZHVjZTogY3JlYXRlQXJyYXlSZWR1Y2UoZmFsc2UpLFxyXG4gIC8vIDIyLjEuMy4xOSAvIDE1LjQuNC4yMiBBcnJheS5wcm90b3R5cGUucmVkdWNlUmlnaHQoY2FsbGJhY2tmbiBbLCBpbml0aWFsVmFsdWVdKVxyXG4gIHJlZHVjZVJpZ2h0OiBjcmVhdGVBcnJheVJlZHVjZSh0cnVlKSxcclxuICAvLyAyMi4xLjMuMTEgLyAxNS40LjQuMTQgQXJyYXkucHJvdG90eXBlLmluZGV4T2Yoc2VhcmNoRWxlbWVudCBbLCBmcm9tSW5kZXhdKVxyXG4gIGluZGV4T2Y6IGluZGV4T2YgPSBpbmRleE9mIHx8IHJlcXVpcmUoJy4vJC5hcnJheS1pbmNsdWRlcycpKGZhbHNlKSxcclxuICAvLyAyMi4xLjMuMTQgLyAxNS40LjQuMTUgQXJyYXkucHJvdG90eXBlLmxhc3RJbmRleE9mKHNlYXJjaEVsZW1lbnQgWywgZnJvbUluZGV4XSlcclxuICBsYXN0SW5kZXhPZjogZnVuY3Rpb24oZWwsIGZyb21JbmRleCAvKiA9IEBbKi0xXSAqLyl7XHJcbiAgICB2YXIgTyAgICAgID0gdG9PYmplY3QodGhpcylcclxuICAgICAgLCBsZW5ndGggPSB0b0xlbmd0aChPLmxlbmd0aClcclxuICAgICAgLCBpbmRleCAgPSBsZW5ndGggLSAxO1xyXG4gICAgaWYoYXJndW1lbnRzLmxlbmd0aCA+IDEpaW5kZXggPSBNYXRoLm1pbihpbmRleCwgJC50b0ludGVnZXIoZnJvbUluZGV4KSk7XHJcbiAgICBpZihpbmRleCA8IDApaW5kZXggPSB0b0xlbmd0aChsZW5ndGggKyBpbmRleCk7XHJcbiAgICBmb3IoO2luZGV4ID49IDA7IGluZGV4LS0paWYoaW5kZXggaW4gTylpZihPW2luZGV4XSA9PT0gZWwpcmV0dXJuIGluZGV4O1xyXG4gICAgcmV0dXJuIC0xO1xyXG4gIH1cclxufSk7XHJcblxyXG4vLyAyMS4xLjMuMjUgLyAxNS41LjQuMjAgU3RyaW5nLnByb3RvdHlwZS50cmltKClcclxuJGRlZigkZGVmLlAsICdTdHJpbmcnLCB7dHJpbTogcmVxdWlyZSgnLi8kLnJlcGxhY2VyJykoL15cXHMqKFtcXHNcXFNdKlxcUyk/XFxzKiQvLCAnJDEnKX0pO1xyXG5cclxuLy8gMjAuMy4zLjEgLyAxNS45LjQuNCBEYXRlLm5vdygpXHJcbiRkZWYoJGRlZi5TLCAnRGF0ZScsIHtub3c6IGZ1bmN0aW9uKCl7XHJcbiAgcmV0dXJuICtuZXcgRGF0ZTtcclxufX0pO1xyXG5cclxuZnVuY3Rpb24gbHoobnVtKXtcclxuICByZXR1cm4gbnVtID4gOSA/IG51bSA6ICcwJyArIG51bTtcclxufVxyXG4vLyAyMC4zLjQuMzYgLyAxNS45LjUuNDMgRGF0ZS5wcm90b3R5cGUudG9JU09TdHJpbmcoKVxyXG4kZGVmKCRkZWYuUCwgJ0RhdGUnLCB7dG9JU09TdHJpbmc6IGZ1bmN0aW9uKCl7XHJcbiAgaWYoIWlzRmluaXRlKHRoaXMpKXRocm93IFJhbmdlRXJyb3IoJ0ludmFsaWQgdGltZSB2YWx1ZScpO1xyXG4gIHZhciBkID0gdGhpc1xyXG4gICAgLCB5ID0gZC5nZXRVVENGdWxsWWVhcigpXHJcbiAgICAsIG0gPSBkLmdldFVUQ01pbGxpc2Vjb25kcygpXHJcbiAgICAsIHMgPSB5IDwgMCA/ICctJyA6IHkgPiA5OTk5ID8gJysnIDogJyc7XHJcbiAgcmV0dXJuIHMgKyAoJzAwMDAwJyArIE1hdGguYWJzKHkpKS5zbGljZShzID8gLTYgOiAtNCkgK1xyXG4gICAgJy0nICsgbHooZC5nZXRVVENNb250aCgpICsgMSkgKyAnLScgKyBseihkLmdldFVUQ0RhdGUoKSkgK1xyXG4gICAgJ1QnICsgbHooZC5nZXRVVENIb3VycygpKSArICc6JyArIGx6KGQuZ2V0VVRDTWludXRlcygpKSArXHJcbiAgICAnOicgKyBseihkLmdldFVUQ1NlY29uZHMoKSkgKyAnLicgKyAobSA+IDk5ID8gbSA6ICcwJyArIGx6KG0pKSArICdaJztcclxufX0pO1xyXG5cclxuaWYoY2xhc3NvZihmdW5jdGlvbigpeyByZXR1cm4gYXJndW1lbnRzOyB9KCkpID09ICdPYmplY3QnKWNvZi5jbGFzc29mID0gZnVuY3Rpb24oaXQpe1xyXG4gIHZhciB0YWcgPSBjbGFzc29mKGl0KTtcclxuICByZXR1cm4gdGFnID09ICdPYmplY3QnICYmIGlzRnVuY3Rpb24oaXQuY2FsbGVlKSA/ICdBcmd1bWVudHMnIDogdGFnO1xyXG59OyIsIid1c2Ugc3RyaWN0JztcclxudmFyICQgICAgICAgPSByZXF1aXJlKCcuLyQnKVxyXG4gICwgJGRlZiAgICA9IHJlcXVpcmUoJy4vJC5kZWYnKVxyXG4gICwgdG9JbmRleCA9ICQudG9JbmRleDtcclxuJGRlZigkZGVmLlAsICdBcnJheScsIHtcclxuICAvLyAyMi4xLjMuMyBBcnJheS5wcm90b3R5cGUuY29weVdpdGhpbih0YXJnZXQsIHN0YXJ0LCBlbmQgPSB0aGlzLmxlbmd0aClcclxuICBjb3B5V2l0aGluOiBmdW5jdGlvbih0YXJnZXQvKiA9IDAgKi8sIHN0YXJ0IC8qID0gMCwgZW5kID0gQGxlbmd0aCAqLyl7XHJcbiAgICB2YXIgTyAgICAgPSBPYmplY3QoJC5hc3NlcnREZWZpbmVkKHRoaXMpKVxyXG4gICAgICAsIGxlbiAgID0gJC50b0xlbmd0aChPLmxlbmd0aClcclxuICAgICAgLCB0byAgICA9IHRvSW5kZXgodGFyZ2V0LCBsZW4pXHJcbiAgICAgICwgZnJvbSAgPSB0b0luZGV4KHN0YXJ0LCBsZW4pXHJcbiAgICAgICwgZW5kICAgPSBhcmd1bWVudHNbMl1cclxuICAgICAgLCBmaW4gICA9IGVuZCA9PT0gdW5kZWZpbmVkID8gbGVuIDogdG9JbmRleChlbmQsIGxlbilcclxuICAgICAgLCBjb3VudCA9IE1hdGgubWluKGZpbiAtIGZyb20sIGxlbiAtIHRvKVxyXG4gICAgICAsIGluYyAgID0gMTtcclxuICAgIGlmKGZyb20gPCB0byAmJiB0byA8IGZyb20gKyBjb3VudCl7XHJcbiAgICAgIGluYyAgPSAtMTtcclxuICAgICAgZnJvbSA9IGZyb20gKyBjb3VudCAtIDE7XHJcbiAgICAgIHRvICAgPSB0byAgICsgY291bnQgLSAxO1xyXG4gICAgfVxyXG4gICAgd2hpbGUoY291bnQtLSA+IDApe1xyXG4gICAgICBpZihmcm9tIGluIE8pT1t0b10gPSBPW2Zyb21dO1xyXG4gICAgICBlbHNlIGRlbGV0ZSBPW3RvXTtcclxuICAgICAgdG8gICArPSBpbmM7XHJcbiAgICAgIGZyb20gKz0gaW5jO1xyXG4gICAgfSByZXR1cm4gTztcclxuICB9XHJcbn0pO1xyXG5yZXF1aXJlKCcuLyQudW5zY29wZScpKCdjb3B5V2l0aGluJyk7IiwiJ3VzZSBzdHJpY3QnO1xyXG52YXIgJCAgICAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCAkZGVmICAgID0gcmVxdWlyZSgnLi8kLmRlZicpXHJcbiAgLCB0b0luZGV4ID0gJC50b0luZGV4O1xyXG4kZGVmKCRkZWYuUCwgJ0FycmF5Jywge1xyXG4gIC8vIDIyLjEuMy42IEFycmF5LnByb3RvdHlwZS5maWxsKHZhbHVlLCBzdGFydCA9IDAsIGVuZCA9IHRoaXMubGVuZ3RoKVxyXG4gIGZpbGw6IGZ1bmN0aW9uKHZhbHVlIC8qLCBzdGFydCA9IDAsIGVuZCA9IEBsZW5ndGggKi8pe1xyXG4gICAgdmFyIE8gICAgICA9IE9iamVjdCgkLmFzc2VydERlZmluZWQodGhpcykpXHJcbiAgICAgICwgbGVuZ3RoID0gJC50b0xlbmd0aChPLmxlbmd0aClcclxuICAgICAgLCBpbmRleCAgPSB0b0luZGV4KGFyZ3VtZW50c1sxXSwgbGVuZ3RoKVxyXG4gICAgICAsIGVuZCAgICA9IGFyZ3VtZW50c1syXVxyXG4gICAgICAsIGVuZFBvcyA9IGVuZCA9PT0gdW5kZWZpbmVkID8gbGVuZ3RoIDogdG9JbmRleChlbmQsIGxlbmd0aCk7XHJcbiAgICB3aGlsZShlbmRQb3MgPiBpbmRleClPW2luZGV4KytdID0gdmFsdWU7XHJcbiAgICByZXR1cm4gTztcclxuICB9XHJcbn0pO1xyXG5yZXF1aXJlKCcuLyQudW5zY29wZScpKCdmaWxsJyk7IiwidmFyICRkZWYgPSByZXF1aXJlKCcuLyQuZGVmJyk7XHJcbiRkZWYoJGRlZi5QLCAnQXJyYXknLCB7XHJcbiAgLy8gMjIuMS4zLjkgQXJyYXkucHJvdG90eXBlLmZpbmRJbmRleChwcmVkaWNhdGUsIHRoaXNBcmcgPSB1bmRlZmluZWQpXHJcbiAgZmluZEluZGV4OiByZXF1aXJlKCcuLyQuYXJyYXktbWV0aG9kcycpKDYpXHJcbn0pO1xyXG5yZXF1aXJlKCcuLyQudW5zY29wZScpKCdmaW5kSW5kZXgnKTsiLCJ2YXIgJGRlZiA9IHJlcXVpcmUoJy4vJC5kZWYnKTtcclxuJGRlZigkZGVmLlAsICdBcnJheScsIHtcclxuICAvLyAyMi4xLjMuOCBBcnJheS5wcm90b3R5cGUuZmluZChwcmVkaWNhdGUsIHRoaXNBcmcgPSB1bmRlZmluZWQpXHJcbiAgZmluZDogcmVxdWlyZSgnLi8kLmFycmF5LW1ldGhvZHMnKSg1KVxyXG59KTtcclxucmVxdWlyZSgnLi8kLnVuc2NvcGUnKSgnZmluZCcpOyIsInZhciAkICAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCBjdHggICA9IHJlcXVpcmUoJy4vJC5jdHgnKVxyXG4gICwgJGRlZiAgPSByZXF1aXJlKCcuLyQuZGVmJylcclxuICAsICRpdGVyID0gcmVxdWlyZSgnLi8kLml0ZXInKVxyXG4gICwgc3RlcENhbGwgPSAkaXRlci5zdGVwQ2FsbDtcclxuJGRlZigkZGVmLlMgKyAkZGVmLkYgKiAkaXRlci5EQU5HRVJfQ0xPU0lORywgJ0FycmF5Jywge1xyXG4gIC8vIDIyLjEuMi4xIEFycmF5LmZyb20oYXJyYXlMaWtlLCBtYXBmbiA9IHVuZGVmaW5lZCwgdGhpc0FyZyA9IHVuZGVmaW5lZClcclxuICBmcm9tOiBmdW5jdGlvbihhcnJheUxpa2UvKiwgbWFwZm4gPSB1bmRlZmluZWQsIHRoaXNBcmcgPSB1bmRlZmluZWQqLyl7XHJcbiAgICB2YXIgTyAgICAgICA9IE9iamVjdCgkLmFzc2VydERlZmluZWQoYXJyYXlMaWtlKSlcclxuICAgICAgLCBtYXBmbiAgID0gYXJndW1lbnRzWzFdXHJcbiAgICAgICwgbWFwcGluZyA9IG1hcGZuICE9PSB1bmRlZmluZWRcclxuICAgICAgLCBmICAgICAgID0gbWFwcGluZyA/IGN0eChtYXBmbiwgYXJndW1lbnRzWzJdLCAyKSA6IHVuZGVmaW5lZFxyXG4gICAgICAsIGluZGV4ICAgPSAwXHJcbiAgICAgICwgbGVuZ3RoLCByZXN1bHQsIHN0ZXAsIGl0ZXJhdG9yO1xyXG4gICAgaWYoJGl0ZXIuaXMoTykpe1xyXG4gICAgICBpdGVyYXRvciA9ICRpdGVyLmdldChPKTtcclxuICAgICAgLy8gc3RyYW5nZSBJRSBxdWlya3MgbW9kZSBidWcgLT4gdXNlIHR5cGVvZiBpbnN0ZWFkIG9mIGlzRnVuY3Rpb25cclxuICAgICAgcmVzdWx0ICAgPSBuZXcgKHR5cGVvZiB0aGlzID09ICdmdW5jdGlvbicgPyB0aGlzIDogQXJyYXkpO1xyXG4gICAgICBmb3IoOyAhKHN0ZXAgPSBpdGVyYXRvci5uZXh0KCkpLmRvbmU7IGluZGV4Kyspe1xyXG4gICAgICAgIHJlc3VsdFtpbmRleF0gPSBtYXBwaW5nID8gc3RlcENhbGwoaXRlcmF0b3IsIGYsIFtzdGVwLnZhbHVlLCBpbmRleF0sIHRydWUpIDogc3RlcC52YWx1ZTtcclxuICAgICAgfVxyXG4gICAgfSBlbHNlIHtcclxuICAgICAgLy8gc3RyYW5nZSBJRSBxdWlya3MgbW9kZSBidWcgLT4gdXNlIHR5cGVvZiBpbnN0ZWFkIG9mIGlzRnVuY3Rpb25cclxuICAgICAgcmVzdWx0ID0gbmV3ICh0eXBlb2YgdGhpcyA9PSAnZnVuY3Rpb24nID8gdGhpcyA6IEFycmF5KShsZW5ndGggPSAkLnRvTGVuZ3RoKE8ubGVuZ3RoKSk7XHJcbiAgICAgIGZvcig7IGxlbmd0aCA+IGluZGV4OyBpbmRleCsrKXtcclxuICAgICAgICByZXN1bHRbaW5kZXhdID0gbWFwcGluZyA/IGYoT1tpbmRleF0sIGluZGV4KSA6IE9baW5kZXhdO1xyXG4gICAgICB9XHJcbiAgICB9XHJcbiAgICByZXN1bHQubGVuZ3RoID0gaW5kZXg7XHJcbiAgICByZXR1cm4gcmVzdWx0O1xyXG4gIH1cclxufSk7IiwidmFyICQgICAgICAgICAgPSByZXF1aXJlKCcuLyQnKVxyXG4gICwgc2V0VW5zY29wZSA9IHJlcXVpcmUoJy4vJC51bnNjb3BlJylcclxuICAsIElURVIgICAgICAgPSByZXF1aXJlKCcuLyQudWlkJykuc2FmZSgnaXRlcicpXHJcbiAgLCAkaXRlciAgICAgID0gcmVxdWlyZSgnLi8kLml0ZXInKVxyXG4gICwgc3RlcCAgICAgICA9ICRpdGVyLnN0ZXBcclxuICAsIEl0ZXJhdG9ycyAgPSAkaXRlci5JdGVyYXRvcnM7XHJcblxyXG4vLyAyMi4xLjMuNCBBcnJheS5wcm90b3R5cGUuZW50cmllcygpXHJcbi8vIDIyLjEuMy4xMyBBcnJheS5wcm90b3R5cGUua2V5cygpXHJcbi8vIDIyLjEuMy4yOSBBcnJheS5wcm90b3R5cGUudmFsdWVzKClcclxuLy8gMjIuMS4zLjMwIEFycmF5LnByb3RvdHlwZVtAQGl0ZXJhdG9yXSgpXHJcbiRpdGVyLnN0ZChBcnJheSwgJ0FycmF5JywgZnVuY3Rpb24oaXRlcmF0ZWQsIGtpbmQpe1xyXG4gICQuc2V0KHRoaXMsIElURVIsIHtvOiAkLnRvT2JqZWN0KGl0ZXJhdGVkKSwgaTogMCwgazoga2luZH0pO1xyXG4vLyAyMi4xLjUuMi4xICVBcnJheUl0ZXJhdG9yUHJvdG90eXBlJS5uZXh0KClcclxufSwgZnVuY3Rpb24oKXtcclxuICB2YXIgaXRlciAgPSB0aGlzW0lURVJdXHJcbiAgICAsIE8gICAgID0gaXRlci5vXHJcbiAgICAsIGtpbmQgID0gaXRlci5rXHJcbiAgICAsIGluZGV4ID0gaXRlci5pKys7XHJcbiAgaWYoIU8gfHwgaW5kZXggPj0gTy5sZW5ndGgpe1xyXG4gICAgaXRlci5vID0gdW5kZWZpbmVkO1xyXG4gICAgcmV0dXJuIHN0ZXAoMSk7XHJcbiAgfVxyXG4gIGlmKGtpbmQgPT0gJ2tleScgIClyZXR1cm4gc3RlcCgwLCBpbmRleCk7XHJcbiAgaWYoa2luZCA9PSAndmFsdWUnKXJldHVybiBzdGVwKDAsIE9baW5kZXhdKTtcclxuICByZXR1cm4gc3RlcCgwLCBbaW5kZXgsIE9baW5kZXhdXSk7XHJcbn0sICd2YWx1ZScpO1xyXG5cclxuLy8gYXJndW1lbnRzTGlzdFtAQGl0ZXJhdG9yXSBpcyAlQXJyYXlQcm90b192YWx1ZXMlICg5LjQuNC42LCA5LjQuNC43KVxyXG5JdGVyYXRvcnMuQXJndW1lbnRzID0gSXRlcmF0b3JzLkFycmF5O1xyXG5cclxuc2V0VW5zY29wZSgna2V5cycpO1xyXG5zZXRVbnNjb3BlKCd2YWx1ZXMnKTtcclxuc2V0VW5zY29wZSgnZW50cmllcycpOyIsInZhciAkZGVmID0gcmVxdWlyZSgnLi8kLmRlZicpO1xyXG4kZGVmKCRkZWYuUywgJ0FycmF5Jywge1xyXG4gIC8vIDIyLjEuMi4zIEFycmF5Lm9mKCAuLi5pdGVtcylcclxuICBvZjogZnVuY3Rpb24oLyogLi4uYXJncyAqLyl7XHJcbiAgICB2YXIgaW5kZXggID0gMFxyXG4gICAgICAsIGxlbmd0aCA9IGFyZ3VtZW50cy5sZW5ndGhcclxuICAgICAgLy8gc3RyYW5nZSBJRSBxdWlya3MgbW9kZSBidWcgLT4gdXNlIHR5cGVvZiBpbnN0ZWFkIG9mIGlzRnVuY3Rpb25cclxuICAgICAgLCByZXN1bHQgPSBuZXcgKHR5cGVvZiB0aGlzID09ICdmdW5jdGlvbicgPyB0aGlzIDogQXJyYXkpKGxlbmd0aCk7XHJcbiAgICB3aGlsZShsZW5ndGggPiBpbmRleClyZXN1bHRbaW5kZXhdID0gYXJndW1lbnRzW2luZGV4KytdO1xyXG4gICAgcmVzdWx0Lmxlbmd0aCA9IGxlbmd0aDtcclxuICAgIHJldHVybiByZXN1bHQ7XHJcbiAgfVxyXG59KTsiLCJyZXF1aXJlKCcuLyQuc3BlY2llcycpKEFycmF5KTsiLCIndXNlIHN0cmljdCc7XHJcbnZhciAkICAgID0gcmVxdWlyZSgnLi8kJylcclxuICAsIE5BTUUgPSAnbmFtZSdcclxuICAsIHNldERlc2MgPSAkLnNldERlc2NcclxuICAsIEZ1bmN0aW9uUHJvdG8gPSBGdW5jdGlvbi5wcm90b3R5cGU7XHJcbi8vIDE5LjIuNC4yIG5hbWVcclxuTkFNRSBpbiBGdW5jdGlvblByb3RvIHx8ICQuRlcgJiYgJC5ERVNDICYmIHNldERlc2MoRnVuY3Rpb25Qcm90bywgTkFNRSwge1xyXG4gIGNvbmZpZ3VyYWJsZTogdHJ1ZSxcclxuICBnZXQ6IGZ1bmN0aW9uKCl7XHJcbiAgICB2YXIgbWF0Y2ggPSBTdHJpbmcodGhpcykubWF0Y2goL15cXHMqZnVuY3Rpb24gKFteIChdKikvKVxyXG4gICAgICAsIG5hbWUgID0gbWF0Y2ggPyBtYXRjaFsxXSA6ICcnO1xyXG4gICAgJC5oYXModGhpcywgTkFNRSkgfHwgc2V0RGVzYyh0aGlzLCBOQU1FLCAkLmRlc2MoNSwgbmFtZSkpO1xyXG4gICAgcmV0dXJuIG5hbWU7XHJcbiAgfSxcclxuICBzZXQ6IGZ1bmN0aW9uKHZhbHVlKXtcclxuICAgICQuaGFzKHRoaXMsIE5BTUUpIHx8IHNldERlc2ModGhpcywgTkFNRSwgJC5kZXNjKDAsIHZhbHVlKSk7XHJcbiAgfVxyXG59KTsiLCIndXNlIHN0cmljdCc7XHJcbnZhciBzdHJvbmcgPSByZXF1aXJlKCcuLyQuY29sbGVjdGlvbi1zdHJvbmcnKTtcclxuXHJcbi8vIDIzLjEgTWFwIE9iamVjdHNcclxucmVxdWlyZSgnLi8kLmNvbGxlY3Rpb24nKSgnTWFwJywge1xyXG4gIC8vIDIzLjEuMy42IE1hcC5wcm90b3R5cGUuZ2V0KGtleSlcclxuICBnZXQ6IGZ1bmN0aW9uKGtleSl7XHJcbiAgICB2YXIgZW50cnkgPSBzdHJvbmcuZ2V0RW50cnkodGhpcywga2V5KTtcclxuICAgIHJldHVybiBlbnRyeSAmJiBlbnRyeS52O1xyXG4gIH0sXHJcbiAgLy8gMjMuMS4zLjkgTWFwLnByb3RvdHlwZS5zZXQoa2V5LCB2YWx1ZSlcclxuICBzZXQ6IGZ1bmN0aW9uKGtleSwgdmFsdWUpe1xyXG4gICAgcmV0dXJuIHN0cm9uZy5kZWYodGhpcywga2V5ID09PSAwID8gMCA6IGtleSwgdmFsdWUpO1xyXG4gIH1cclxufSwgc3Ryb25nLCB0cnVlKTsiLCJ2YXIgSW5maW5pdHkgPSAxIC8gMFxyXG4gICwgJGRlZiAgPSByZXF1aXJlKCcuLyQuZGVmJylcclxuICAsIEUgICAgID0gTWF0aC5FXHJcbiAgLCBwb3cgICA9IE1hdGgucG93XHJcbiAgLCBhYnMgICA9IE1hdGguYWJzXHJcbiAgLCBleHAgICA9IE1hdGguZXhwXHJcbiAgLCBsb2cgICA9IE1hdGgubG9nXHJcbiAgLCBzcXJ0ICA9IE1hdGguc3FydFxyXG4gICwgY2VpbCAgPSBNYXRoLmNlaWxcclxuICAsIGZsb29yID0gTWF0aC5mbG9vclxyXG4gICwgc2lnbiAgPSBNYXRoLnNpZ24gfHwgZnVuY3Rpb24oeCl7XHJcbiAgICAgIHJldHVybiAoeCA9ICt4KSA9PSAwIHx8IHggIT0geCA/IHggOiB4IDwgMCA/IC0xIDogMTtcclxuICAgIH07XHJcblxyXG4vLyAyMC4yLjIuNSBNYXRoLmFzaW5oKHgpXHJcbmZ1bmN0aW9uIGFzaW5oKHgpe1xyXG4gIHJldHVybiAhaXNGaW5pdGUoeCA9ICt4KSB8fCB4ID09IDAgPyB4IDogeCA8IDAgPyAtYXNpbmgoLXgpIDogbG9nKHggKyBzcXJ0KHggKiB4ICsgMSkpO1xyXG59XHJcbi8vIDIwLjIuMi4xNCBNYXRoLmV4cG0xKHgpXHJcbmZ1bmN0aW9uIGV4cG0xKHgpe1xyXG4gIHJldHVybiAoeCA9ICt4KSA9PSAwID8geCA6IHggPiAtMWUtNiAmJiB4IDwgMWUtNiA/IHggKyB4ICogeCAvIDIgOiBleHAoeCkgLSAxO1xyXG59XHJcblxyXG4kZGVmKCRkZWYuUywgJ01hdGgnLCB7XHJcbiAgLy8gMjAuMi4yLjMgTWF0aC5hY29zaCh4KVxyXG4gIGFjb3NoOiBmdW5jdGlvbih4KXtcclxuICAgIHJldHVybiAoeCA9ICt4KSA8IDEgPyBOYU4gOiBpc0Zpbml0ZSh4KSA/IGxvZyh4IC8gRSArIHNxcnQoeCArIDEpICogc3FydCh4IC0gMSkgLyBFKSArIDEgOiB4O1xyXG4gIH0sXHJcbiAgLy8gMjAuMi4yLjUgTWF0aC5hc2luaCh4KVxyXG4gIGFzaW5oOiBhc2luaCxcclxuICAvLyAyMC4yLjIuNyBNYXRoLmF0YW5oKHgpXHJcbiAgYXRhbmg6IGZ1bmN0aW9uKHgpe1xyXG4gICAgcmV0dXJuICh4ID0gK3gpID09IDAgPyB4IDogbG9nKCgxICsgeCkgLyAoMSAtIHgpKSAvIDI7XHJcbiAgfSxcclxuICAvLyAyMC4yLjIuOSBNYXRoLmNicnQoeClcclxuICBjYnJ0OiBmdW5jdGlvbih4KXtcclxuICAgIHJldHVybiBzaWduKHggPSAreCkgKiBwb3coYWJzKHgpLCAxIC8gMyk7XHJcbiAgfSxcclxuICAvLyAyMC4yLjIuMTEgTWF0aC5jbHozMih4KVxyXG4gIGNsejMyOiBmdW5jdGlvbih4KXtcclxuICAgIHJldHVybiAoeCA+Pj49IDApID8gMzIgLSB4LnRvU3RyaW5nKDIpLmxlbmd0aCA6IDMyO1xyXG4gIH0sXHJcbiAgLy8gMjAuMi4yLjEyIE1hdGguY29zaCh4KVxyXG4gIGNvc2g6IGZ1bmN0aW9uKHgpe1xyXG4gICAgcmV0dXJuIChleHAoeCA9ICt4KSArIGV4cCgteCkpIC8gMjtcclxuICB9LFxyXG4gIC8vIDIwLjIuMi4xNCBNYXRoLmV4cG0xKHgpXHJcbiAgZXhwbTE6IGV4cG0xLFxyXG4gIC8vIDIwLjIuMi4xNiBNYXRoLmZyb3VuZCh4KVxyXG4gIC8vIFRPRE86IGZhbGxiYWNrIGZvciBJRTktXHJcbiAgZnJvdW5kOiBmdW5jdGlvbih4KXtcclxuICAgIHJldHVybiBuZXcgRmxvYXQzMkFycmF5KFt4XSlbMF07XHJcbiAgfSxcclxuICAvLyAyMC4yLjIuMTcgTWF0aC5oeXBvdChbdmFsdWUxWywgdmFsdWUyWywg4oCmIF1dXSlcclxuICBoeXBvdDogZnVuY3Rpb24odmFsdWUxLCB2YWx1ZTIpeyAvLyBlc2xpbnQtZGlzYWJsZS1saW5lIG5vLXVudXNlZC12YXJzXHJcbiAgICB2YXIgc3VtICA9IDBcclxuICAgICAgLCBsZW4xID0gYXJndW1lbnRzLmxlbmd0aFxyXG4gICAgICAsIGxlbjIgPSBsZW4xXHJcbiAgICAgICwgYXJncyA9IEFycmF5KGxlbjEpXHJcbiAgICAgICwgbGFyZyA9IC1JbmZpbml0eVxyXG4gICAgICAsIGFyZztcclxuICAgIHdoaWxlKGxlbjEtLSl7XHJcbiAgICAgIGFyZyA9IGFyZ3NbbGVuMV0gPSArYXJndW1lbnRzW2xlbjFdO1xyXG4gICAgICBpZihhcmcgPT0gSW5maW5pdHkgfHwgYXJnID09IC1JbmZpbml0eSlyZXR1cm4gSW5maW5pdHk7XHJcbiAgICAgIGlmKGFyZyA+IGxhcmcpbGFyZyA9IGFyZztcclxuICAgIH1cclxuICAgIGxhcmcgPSBhcmcgfHwgMTtcclxuICAgIHdoaWxlKGxlbjItLSlzdW0gKz0gcG93KGFyZ3NbbGVuMl0gLyBsYXJnLCAyKTtcclxuICAgIHJldHVybiBsYXJnICogc3FydChzdW0pO1xyXG4gIH0sXHJcbiAgLy8gMjAuMi4yLjE4IE1hdGguaW11bCh4LCB5KVxyXG4gIGltdWw6IGZ1bmN0aW9uKHgsIHkpe1xyXG4gICAgdmFyIFVJbnQxNiA9IDB4ZmZmZlxyXG4gICAgICAsIHhuID0gK3hcclxuICAgICAgLCB5biA9ICt5XHJcbiAgICAgICwgeGwgPSBVSW50MTYgJiB4blxyXG4gICAgICAsIHlsID0gVUludDE2ICYgeW47XHJcbiAgICByZXR1cm4gMCB8IHhsICogeWwgKyAoKFVJbnQxNiAmIHhuID4+PiAxNikgKiB5bCArIHhsICogKFVJbnQxNiAmIHluID4+PiAxNikgPDwgMTYgPj4+IDApO1xyXG4gIH0sXHJcbiAgLy8gMjAuMi4yLjIwIE1hdGgubG9nMXAoeClcclxuICBsb2cxcDogZnVuY3Rpb24oeCl7XHJcbiAgICByZXR1cm4gKHggPSAreCkgPiAtMWUtOCAmJiB4IDwgMWUtOCA/IHggLSB4ICogeCAvIDIgOiBsb2coMSArIHgpO1xyXG4gIH0sXHJcbiAgLy8gMjAuMi4yLjIxIE1hdGgubG9nMTAoeClcclxuICBsb2cxMDogZnVuY3Rpb24oeCl7XHJcbiAgICByZXR1cm4gbG9nKHgpIC8gTWF0aC5MTjEwO1xyXG4gIH0sXHJcbiAgLy8gMjAuMi4yLjIyIE1hdGgubG9nMih4KVxyXG4gIGxvZzI6IGZ1bmN0aW9uKHgpe1xyXG4gICAgcmV0dXJuIGxvZyh4KSAvIE1hdGguTE4yO1xyXG4gIH0sXHJcbiAgLy8gMjAuMi4yLjI4IE1hdGguc2lnbih4KVxyXG4gIHNpZ246IHNpZ24sXHJcbiAgLy8gMjAuMi4yLjMwIE1hdGguc2luaCh4KVxyXG4gIHNpbmg6IGZ1bmN0aW9uKHgpe1xyXG4gICAgcmV0dXJuIGFicyh4ID0gK3gpIDwgMSA/IChleHBtMSh4KSAtIGV4cG0xKC14KSkgLyAyIDogKGV4cCh4IC0gMSkgLSBleHAoLXggLSAxKSkgKiAoRSAvIDIpO1xyXG4gIH0sXHJcbiAgLy8gMjAuMi4yLjMzIE1hdGgudGFuaCh4KVxyXG4gIHRhbmg6IGZ1bmN0aW9uKHgpe1xyXG4gICAgdmFyIGEgPSBleHBtMSh4ID0gK3gpXHJcbiAgICAgICwgYiA9IGV4cG0xKC14KTtcclxuICAgIHJldHVybiBhID09IEluZmluaXR5ID8gMSA6IGIgPT0gSW5maW5pdHkgPyAtMSA6IChhIC0gYikgLyAoZXhwKHgpICsgZXhwKC14KSk7XHJcbiAgfSxcclxuICAvLyAyMC4yLjIuMzQgTWF0aC50cnVuYyh4KVxyXG4gIHRydW5jOiBmdW5jdGlvbihpdCl7XHJcbiAgICByZXR1cm4gKGl0ID4gMCA/IGZsb29yIDogY2VpbCkoaXQpO1xyXG4gIH1cclxufSk7IiwiJ3VzZSBzdHJpY3QnO1xyXG52YXIgJCAgICAgICAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCBpc09iamVjdCAgID0gJC5pc09iamVjdFxyXG4gICwgaXNGdW5jdGlvbiA9ICQuaXNGdW5jdGlvblxyXG4gICwgTlVNQkVSICAgICA9ICdOdW1iZXInXHJcbiAgLCBOdW1iZXIgICAgID0gJC5nW05VTUJFUl1cclxuICAsIEJhc2UgICAgICAgPSBOdW1iZXJcclxuICAsIHByb3RvICAgICAgPSBOdW1iZXIucHJvdG90eXBlO1xyXG5mdW5jdGlvbiB0b1ByaW1pdGl2ZShpdCl7XHJcbiAgdmFyIGZuLCB2YWw7XHJcbiAgaWYoaXNGdW5jdGlvbihmbiA9IGl0LnZhbHVlT2YpICYmICFpc09iamVjdCh2YWwgPSBmbi5jYWxsKGl0KSkpcmV0dXJuIHZhbDtcclxuICBpZihpc0Z1bmN0aW9uKGZuID0gaXQudG9TdHJpbmcpICYmICFpc09iamVjdCh2YWwgPSBmbi5jYWxsKGl0KSkpcmV0dXJuIHZhbDtcclxuICB0aHJvdyBUeXBlRXJyb3IoXCJDYW4ndCBjb252ZXJ0IG9iamVjdCB0byBudW1iZXJcIik7XHJcbn1cclxuZnVuY3Rpb24gdG9OdW1iZXIoaXQpe1xyXG4gIGlmKGlzT2JqZWN0KGl0KSlpdCA9IHRvUHJpbWl0aXZlKGl0KTtcclxuICBpZih0eXBlb2YgaXQgPT0gJ3N0cmluZycgJiYgaXQubGVuZ3RoID4gMiAmJiBpdC5jaGFyQ29kZUF0KDApID09IDQ4KXtcclxuICAgIHZhciBiaW5hcnkgPSBmYWxzZTtcclxuICAgIHN3aXRjaChpdC5jaGFyQ29kZUF0KDEpKXtcclxuICAgICAgY2FzZSA2NiA6IGNhc2UgOTggIDogYmluYXJ5ID0gdHJ1ZTtcclxuICAgICAgY2FzZSA3OSA6IGNhc2UgMTExIDogcmV0dXJuIHBhcnNlSW50KGl0LnNsaWNlKDIpLCBiaW5hcnkgPyAyIDogOCk7XHJcbiAgICB9XHJcbiAgfSByZXR1cm4gK2l0O1xyXG59XHJcbmlmKCQuRlcgJiYgIShOdW1iZXIoJzBvMScpICYmIE51bWJlcignMGIxJykpKXtcclxuICBOdW1iZXIgPSBmdW5jdGlvbiBOdW1iZXIoaXQpe1xyXG4gICAgcmV0dXJuIHRoaXMgaW5zdGFuY2VvZiBOdW1iZXIgPyBuZXcgQmFzZSh0b051bWJlcihpdCkpIDogdG9OdW1iZXIoaXQpO1xyXG4gIH07XHJcbiAgJC5lYWNoLmNhbGwoJC5ERVNDID8gJC5nZXROYW1lcyhCYXNlKSA6IChcclxuICAgICAgLy8gRVMzOlxyXG4gICAgICAnTUFYX1ZBTFVFLE1JTl9WQUxVRSxOYU4sTkVHQVRJVkVfSU5GSU5JVFksUE9TSVRJVkVfSU5GSU5JVFksJyArXHJcbiAgICAgIC8vIEVTNiAoaW4gY2FzZSwgaWYgbW9kdWxlcyB3aXRoIEVTNiBOdW1iZXIgc3RhdGljcyByZXF1aXJlZCBiZWZvcmUpOlxyXG4gICAgICAnRVBTSUxPTixpc0Zpbml0ZSxpc0ludGVnZXIsaXNOYU4saXNTYWZlSW50ZWdlcixNQVhfU0FGRV9JTlRFR0VSLCcgK1xyXG4gICAgICAnTUlOX1NBRkVfSU5URUdFUixwYXJzZUZsb2F0LHBhcnNlSW50LGlzSW50ZWdlcidcclxuICAgICkuc3BsaXQoJywnKSwgZnVuY3Rpb24oa2V5KXtcclxuICAgICAgaWYoJC5oYXMoQmFzZSwga2V5KSAmJiAhJC5oYXMoTnVtYmVyLCBrZXkpKXtcclxuICAgICAgICAkLnNldERlc2MoTnVtYmVyLCBrZXksICQuZ2V0RGVzYyhCYXNlLCBrZXkpKTtcclxuICAgICAgfVxyXG4gICAgfVxyXG4gICk7XHJcbiAgTnVtYmVyLnByb3RvdHlwZSA9IHByb3RvO1xyXG4gIHByb3RvLmNvbnN0cnVjdG9yID0gTnVtYmVyO1xyXG4gICQuaGlkZSgkLmcsIE5VTUJFUiwgTnVtYmVyKTtcclxufSIsInZhciAkICAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCAkZGVmICA9IHJlcXVpcmUoJy4vJC5kZWYnKVxyXG4gICwgYWJzICAgPSBNYXRoLmFic1xyXG4gICwgZmxvb3IgPSBNYXRoLmZsb29yXHJcbiAgLCBNQVhfU0FGRV9JTlRFR0VSID0gMHgxZmZmZmZmZmZmZmZmZjsgLy8gcG93KDIsIDUzKSAtIDEgPT0gOTAwNzE5OTI1NDc0MDk5MTtcclxuZnVuY3Rpb24gaXNJbnRlZ2VyKGl0KXtcclxuICByZXR1cm4gISQuaXNPYmplY3QoaXQpICYmIGlzRmluaXRlKGl0KSAmJiBmbG9vcihpdCkgPT09IGl0O1xyXG59XHJcbiRkZWYoJGRlZi5TLCAnTnVtYmVyJywge1xyXG4gIC8vIDIwLjEuMi4xIE51bWJlci5FUFNJTE9OXHJcbiAgRVBTSUxPTjogTWF0aC5wb3coMiwgLTUyKSxcclxuICAvLyAyMC4xLjIuMiBOdW1iZXIuaXNGaW5pdGUobnVtYmVyKVxyXG4gIGlzRmluaXRlOiBmdW5jdGlvbihpdCl7XHJcbiAgICByZXR1cm4gdHlwZW9mIGl0ID09ICdudW1iZXInICYmIGlzRmluaXRlKGl0KTtcclxuICB9LFxyXG4gIC8vIDIwLjEuMi4zIE51bWJlci5pc0ludGVnZXIobnVtYmVyKVxyXG4gIGlzSW50ZWdlcjogaXNJbnRlZ2VyLFxyXG4gIC8vIDIwLjEuMi40IE51bWJlci5pc05hTihudW1iZXIpXHJcbiAgaXNOYU46IGZ1bmN0aW9uKG51bWJlcil7XHJcbiAgICByZXR1cm4gbnVtYmVyICE9IG51bWJlcjtcclxuICB9LFxyXG4gIC8vIDIwLjEuMi41IE51bWJlci5pc1NhZmVJbnRlZ2VyKG51bWJlcilcclxuICBpc1NhZmVJbnRlZ2VyOiBmdW5jdGlvbihudW1iZXIpe1xyXG4gICAgcmV0dXJuIGlzSW50ZWdlcihudW1iZXIpICYmIGFicyhudW1iZXIpIDw9IE1BWF9TQUZFX0lOVEVHRVI7XHJcbiAgfSxcclxuICAvLyAyMC4xLjIuNiBOdW1iZXIuTUFYX1NBRkVfSU5URUdFUlxyXG4gIE1BWF9TQUZFX0lOVEVHRVI6IE1BWF9TQUZFX0lOVEVHRVIsXHJcbiAgLy8gMjAuMS4yLjEwIE51bWJlci5NSU5fU0FGRV9JTlRFR0VSXHJcbiAgTUlOX1NBRkVfSU5URUdFUjogLU1BWF9TQUZFX0lOVEVHRVIsXHJcbiAgLy8gMjAuMS4yLjEyIE51bWJlci5wYXJzZUZsb2F0KHN0cmluZylcclxuICBwYXJzZUZsb2F0OiBwYXJzZUZsb2F0LFxyXG4gIC8vIDIwLjEuMi4xMyBOdW1iZXIucGFyc2VJbnQoc3RyaW5nLCByYWRpeClcclxuICBwYXJzZUludDogcGFyc2VJbnRcclxufSk7IiwiLy8gMTkuMS4zLjEgT2JqZWN0LmFzc2lnbih0YXJnZXQsIHNvdXJjZSlcclxudmFyICRkZWYgPSByZXF1aXJlKCcuLyQuZGVmJyk7XHJcbiRkZWYoJGRlZi5TLCAnT2JqZWN0Jywge2Fzc2lnbjogcmVxdWlyZSgnLi8kLmFzc2lnbicpfSk7IiwiLy8gMTkuMS4zLjEwIE9iamVjdC5pcyh2YWx1ZTEsIHZhbHVlMilcclxudmFyICRkZWYgPSByZXF1aXJlKCcuLyQuZGVmJyk7XHJcbiRkZWYoJGRlZi5TLCAnT2JqZWN0Jywge1xyXG4gIGlzOiBmdW5jdGlvbih4LCB5KXtcclxuICAgIHJldHVybiB4ID09PSB5ID8geCAhPT0gMCB8fCAxIC8geCA9PT0gMSAvIHkgOiB4ICE9IHggJiYgeSAhPSB5O1xyXG4gIH1cclxufSk7IiwiLy8gMTkuMS4zLjE5IE9iamVjdC5zZXRQcm90b3R5cGVPZihPLCBwcm90bylcclxudmFyICRkZWYgPSByZXF1aXJlKCcuLyQuZGVmJyk7XHJcbiRkZWYoJGRlZi5TLCAnT2JqZWN0Jywge3NldFByb3RvdHlwZU9mOiByZXF1aXJlKCcuLyQuc2V0LXByb3RvJyl9KTsiLCJ2YXIgJCAgICAgICAgPSByZXF1aXJlKCcuLyQnKVxyXG4gICwgJGRlZiAgICAgPSByZXF1aXJlKCcuLyQuZGVmJylcclxuICAsIGlzT2JqZWN0ID0gJC5pc09iamVjdFxyXG4gICwgdG9PYmplY3QgPSAkLnRvT2JqZWN0O1xyXG5mdW5jdGlvbiB3cmFwT2JqZWN0TWV0aG9kKE1FVEhPRCwgTU9ERSl7XHJcbiAgdmFyIGZuICA9ICgkLmNvcmUuT2JqZWN0IHx8IHt9KVtNRVRIT0RdIHx8IE9iamVjdFtNRVRIT0RdXHJcbiAgICAsIGYgICA9IDBcclxuICAgICwgbyAgID0ge307XHJcbiAgb1tNRVRIT0RdID0gTU9ERSA9PSAxID8gZnVuY3Rpb24oaXQpe1xyXG4gICAgcmV0dXJuIGlzT2JqZWN0KGl0KSA/IGZuKGl0KSA6IGl0O1xyXG4gIH0gOiBNT0RFID09IDIgPyBmdW5jdGlvbihpdCl7XHJcbiAgICByZXR1cm4gaXNPYmplY3QoaXQpID8gZm4oaXQpIDogdHJ1ZTtcclxuICB9IDogTU9ERSA9PSAzID8gZnVuY3Rpb24oaXQpe1xyXG4gICAgcmV0dXJuIGlzT2JqZWN0KGl0KSA/IGZuKGl0KSA6IGZhbHNlO1xyXG4gIH0gOiBNT0RFID09IDQgPyBmdW5jdGlvbihpdCwga2V5KXtcclxuICAgIHJldHVybiBmbih0b09iamVjdChpdCksIGtleSk7XHJcbiAgfSA6IE1PREUgPT0gNSA/IGZ1bmN0aW9uKGl0KXtcclxuICAgIHJldHVybiBmbihPYmplY3QoJC5hc3NlcnREZWZpbmVkKGl0KSkpO1xyXG4gIH0gOiBmdW5jdGlvbihpdCl7XHJcbiAgICByZXR1cm4gZm4odG9PYmplY3QoaXQpKTtcclxuICB9O1xyXG4gIHRyeSB7XHJcbiAgICBmbigneicpO1xyXG4gIH0gY2F0Y2goZSl7XHJcbiAgICBmID0gMTtcclxuICB9XHJcbiAgJGRlZigkZGVmLlMgKyAkZGVmLkYgKiBmLCAnT2JqZWN0Jywgbyk7XHJcbn1cclxud3JhcE9iamVjdE1ldGhvZCgnZnJlZXplJywgMSk7XHJcbndyYXBPYmplY3RNZXRob2QoJ3NlYWwnLCAxKTtcclxud3JhcE9iamVjdE1ldGhvZCgncHJldmVudEV4dGVuc2lvbnMnLCAxKTtcclxud3JhcE9iamVjdE1ldGhvZCgnaXNGcm96ZW4nLCAyKTtcclxud3JhcE9iamVjdE1ldGhvZCgnaXNTZWFsZWQnLCAyKTtcclxud3JhcE9iamVjdE1ldGhvZCgnaXNFeHRlbnNpYmxlJywgMyk7XHJcbndyYXBPYmplY3RNZXRob2QoJ2dldE93blByb3BlcnR5RGVzY3JpcHRvcicsIDQpO1xyXG53cmFwT2JqZWN0TWV0aG9kKCdnZXRQcm90b3R5cGVPZicsIDUpO1xyXG53cmFwT2JqZWN0TWV0aG9kKCdrZXlzJyk7XHJcbndyYXBPYmplY3RNZXRob2QoJ2dldE93blByb3BlcnR5TmFtZXMnKTsiLCIndXNlIHN0cmljdCc7XHJcbi8vIDE5LjEuMy42IE9iamVjdC5wcm90b3R5cGUudG9TdHJpbmcoKVxyXG52YXIgJCAgID0gcmVxdWlyZSgnLi8kJylcclxuICAsIGNvZiA9IHJlcXVpcmUoJy4vJC5jb2YnKVxyXG4gICwgdG1wID0ge307XHJcbnRtcFtyZXF1aXJlKCcuLyQud2tzJykoJ3RvU3RyaW5nVGFnJyldID0gJ3onO1xyXG5pZigkLkZXICYmIGNvZih0bXApICE9ICd6JykkLmhpZGUoT2JqZWN0LnByb3RvdHlwZSwgJ3RvU3RyaW5nJywgZnVuY3Rpb24oKXtcclxuICByZXR1cm4gJ1tvYmplY3QgJyArIGNvZi5jbGFzc29mKHRoaXMpICsgJ10nO1xyXG59KTsiLCIndXNlIHN0cmljdCc7XHJcbnZhciAkICAgICAgID0gcmVxdWlyZSgnLi8kJylcclxuICAsIGN0eCAgICAgPSByZXF1aXJlKCcuLyQuY3R4JylcclxuICAsIGNvZiAgICAgPSByZXF1aXJlKCcuLyQuY29mJylcclxuICAsICRkZWYgICAgPSByZXF1aXJlKCcuLyQuZGVmJylcclxuICAsIGFzc2VydCAgPSByZXF1aXJlKCcuLyQuYXNzZXJ0JylcclxuICAsICRpdGVyICAgPSByZXF1aXJlKCcuLyQuaXRlcicpXHJcbiAgLCBTUEVDSUVTID0gcmVxdWlyZSgnLi8kLndrcycpKCdzcGVjaWVzJylcclxuICAsIFJFQ09SRCAgPSByZXF1aXJlKCcuLyQudWlkJykuc2FmZSgncmVjb3JkJylcclxuICAsIGZvck9mICAgPSAkaXRlci5mb3JPZlxyXG4gICwgUFJPTUlTRSA9ICdQcm9taXNlJ1xyXG4gICwgZ2xvYmFsICA9ICQuZ1xyXG4gICwgcHJvY2VzcyA9IGdsb2JhbC5wcm9jZXNzXHJcbiAgLCBhc2FwICAgID0gcHJvY2VzcyAmJiBwcm9jZXNzLm5leHRUaWNrIHx8IHJlcXVpcmUoJy4vJC50YXNrJykuc2V0XHJcbiAgLCBQcm9taXNlID0gZ2xvYmFsW1BST01JU0VdXHJcbiAgLCBCYXNlICAgID0gUHJvbWlzZVxyXG4gICwgaXNGdW5jdGlvbiAgICAgPSAkLmlzRnVuY3Rpb25cclxuICAsIGlzT2JqZWN0ICAgICAgID0gJC5pc09iamVjdFxyXG4gICwgYXNzZXJ0RnVuY3Rpb24gPSBhc3NlcnQuZm5cclxuICAsIGFzc2VydE9iamVjdCAgID0gYXNzZXJ0Lm9ialxyXG4gICwgdGVzdDtcclxuZnVuY3Rpb24gZ2V0Q29uc3RydWN0b3IoQyl7XHJcbiAgdmFyIFMgPSBhc3NlcnRPYmplY3QoQylbU1BFQ0lFU107XHJcbiAgcmV0dXJuIFMgIT0gdW5kZWZpbmVkID8gUyA6IEM7XHJcbn1cclxuaXNGdW5jdGlvbihQcm9taXNlKSAmJiBpc0Z1bmN0aW9uKFByb21pc2UucmVzb2x2ZSlcclxuJiYgUHJvbWlzZS5yZXNvbHZlKHRlc3QgPSBuZXcgUHJvbWlzZShmdW5jdGlvbigpe30pKSA9PSB0ZXN0XHJcbnx8IGZ1bmN0aW9uKCl7XHJcbiAgZnVuY3Rpb24gaXNUaGVuYWJsZShpdCl7XHJcbiAgICB2YXIgdGhlbjtcclxuICAgIGlmKGlzT2JqZWN0KGl0KSl0aGVuID0gaXQudGhlbjtcclxuICAgIHJldHVybiBpc0Z1bmN0aW9uKHRoZW4pID8gdGhlbiA6IGZhbHNlO1xyXG4gIH1cclxuICBmdW5jdGlvbiBoYW5kbGVkUmVqZWN0aW9uT3JIYXNPblJlamVjdGVkKHByb21pc2Upe1xyXG4gICAgdmFyIHJlY29yZCA9IHByb21pc2VbUkVDT1JEXVxyXG4gICAgICAsIGNoYWluICA9IHJlY29yZC5jXHJcbiAgICAgICwgaSAgICAgID0gMFxyXG4gICAgICAsIHJlYWN0O1xyXG4gICAgaWYocmVjb3JkLmgpcmV0dXJuIHRydWU7XHJcbiAgICB3aGlsZShjaGFpbi5sZW5ndGggPiBpKXtcclxuICAgICAgcmVhY3QgPSBjaGFpbltpKytdO1xyXG4gICAgICBpZihyZWFjdC5mYWlsIHx8IGhhbmRsZWRSZWplY3Rpb25Pckhhc09uUmVqZWN0ZWQocmVhY3QuUCkpcmV0dXJuIHRydWU7XHJcbiAgICB9XHJcbiAgfVxyXG4gIGZ1bmN0aW9uIG5vdGlmeShyZWNvcmQsIGlzUmVqZWN0KXtcclxuICAgIHZhciBjaGFpbiA9IHJlY29yZC5jO1xyXG4gICAgaWYoaXNSZWplY3QgfHwgY2hhaW4ubGVuZ3RoKWFzYXAoZnVuY3Rpb24oKXtcclxuICAgICAgdmFyIHByb21pc2UgPSByZWNvcmQucFxyXG4gICAgICAgICwgdmFsdWUgICA9IHJlY29yZC52XHJcbiAgICAgICAgLCBvayAgICAgID0gcmVjb3JkLnMgPT0gMVxyXG4gICAgICAgICwgaSAgICAgICA9IDA7XHJcbiAgICAgIGlmKGlzUmVqZWN0ICYmICFoYW5kbGVkUmVqZWN0aW9uT3JIYXNPblJlamVjdGVkKHByb21pc2UpKXtcclxuICAgICAgICBzZXRUaW1lb3V0KGZ1bmN0aW9uKCl7XHJcbiAgICAgICAgICBpZighaGFuZGxlZFJlamVjdGlvbk9ySGFzT25SZWplY3RlZChwcm9taXNlKSl7XHJcbiAgICAgICAgICAgIGlmKGNvZihwcm9jZXNzKSA9PSAncHJvY2Vzcycpe1xyXG4gICAgICAgICAgICAgIHByb2Nlc3MuZW1pdCgndW5oYW5kbGVkUmVqZWN0aW9uJywgdmFsdWUsIHByb21pc2UpO1xyXG4gICAgICAgICAgICB9IGVsc2UgaWYoZ2xvYmFsLmNvbnNvbGUgJiYgaXNGdW5jdGlvbihjb25zb2xlLmVycm9yKSl7XHJcbiAgICAgICAgICAgICAgY29uc29sZS5lcnJvcignVW5oYW5kbGVkIHByb21pc2UgcmVqZWN0aW9uJywgdmFsdWUpO1xyXG4gICAgICAgICAgICB9XHJcbiAgICAgICAgICB9XHJcbiAgICAgICAgfSwgMWUzKTtcclxuICAgICAgfSBlbHNlIHdoaWxlKGNoYWluLmxlbmd0aCA+IGkpIWZ1bmN0aW9uKHJlYWN0KXtcclxuICAgICAgICB2YXIgY2IgPSBvayA/IHJlYWN0Lm9rIDogcmVhY3QuZmFpbFxyXG4gICAgICAgICAgLCByZXQsIHRoZW47XHJcbiAgICAgICAgdHJ5IHtcclxuICAgICAgICAgIGlmKGNiKXtcclxuICAgICAgICAgICAgaWYoIW9rKXJlY29yZC5oID0gdHJ1ZTtcclxuICAgICAgICAgICAgcmV0ID0gY2IgPT09IHRydWUgPyB2YWx1ZSA6IGNiKHZhbHVlKTtcclxuICAgICAgICAgICAgaWYocmV0ID09PSByZWFjdC5QKXtcclxuICAgICAgICAgICAgICByZWFjdC5yZWooVHlwZUVycm9yKFBST01JU0UgKyAnLWNoYWluIGN5Y2xlJykpO1xyXG4gICAgICAgICAgICB9IGVsc2UgaWYodGhlbiA9IGlzVGhlbmFibGUocmV0KSl7XHJcbiAgICAgICAgICAgICAgdGhlbi5jYWxsKHJldCwgcmVhY3QucmVzLCByZWFjdC5yZWopO1xyXG4gICAgICAgICAgICB9IGVsc2UgcmVhY3QucmVzKHJldCk7XHJcbiAgICAgICAgICB9IGVsc2UgcmVhY3QucmVqKHZhbHVlKTtcclxuICAgICAgICB9IGNhdGNoKGVycil7XHJcbiAgICAgICAgICByZWFjdC5yZWooZXJyKTtcclxuICAgICAgICB9XHJcbiAgICAgIH0oY2hhaW5baSsrXSk7XHJcbiAgICAgIGNoYWluLmxlbmd0aCA9IDA7XHJcbiAgICB9KTtcclxuICB9XHJcbiAgZnVuY3Rpb24gcmVqZWN0KHZhbHVlKXtcclxuICAgIHZhciByZWNvcmQgPSB0aGlzO1xyXG4gICAgaWYocmVjb3JkLmQpcmV0dXJuO1xyXG4gICAgcmVjb3JkLmQgPSB0cnVlO1xyXG4gICAgcmVjb3JkID0gcmVjb3JkLnIgfHwgcmVjb3JkOyAvLyB1bndyYXBcclxuICAgIHJlY29yZC52ID0gdmFsdWU7XHJcbiAgICByZWNvcmQucyA9IDI7XHJcbiAgICBub3RpZnkocmVjb3JkLCB0cnVlKTtcclxuICB9XHJcbiAgZnVuY3Rpb24gcmVzb2x2ZSh2YWx1ZSl7XHJcbiAgICB2YXIgcmVjb3JkID0gdGhpc1xyXG4gICAgICAsIHRoZW4sIHdyYXBwZXI7XHJcbiAgICBpZihyZWNvcmQuZClyZXR1cm47XHJcbiAgICByZWNvcmQuZCA9IHRydWU7XHJcbiAgICByZWNvcmQgPSByZWNvcmQuciB8fCByZWNvcmQ7IC8vIHVud3JhcFxyXG4gICAgdHJ5IHtcclxuICAgICAgaWYodGhlbiA9IGlzVGhlbmFibGUodmFsdWUpKXtcclxuICAgICAgICB3cmFwcGVyID0ge3I6IHJlY29yZCwgZDogZmFsc2V9OyAvLyB3cmFwXHJcbiAgICAgICAgdGhlbi5jYWxsKHZhbHVlLCBjdHgocmVzb2x2ZSwgd3JhcHBlciwgMSksIGN0eChyZWplY3QsIHdyYXBwZXIsIDEpKTtcclxuICAgICAgfSBlbHNlIHtcclxuICAgICAgICByZWNvcmQudiA9IHZhbHVlO1xyXG4gICAgICAgIHJlY29yZC5zID0gMTtcclxuICAgICAgICBub3RpZnkocmVjb3JkKTtcclxuICAgICAgfVxyXG4gICAgfSBjYXRjaChlcnIpe1xyXG4gICAgICByZWplY3QuY2FsbCh3cmFwcGVyIHx8IHtyOiByZWNvcmQsIGQ6IGZhbHNlfSwgZXJyKTsgLy8gd3JhcFxyXG4gICAgfVxyXG4gIH1cclxuICAvLyAyNS40LjMuMSBQcm9taXNlKGV4ZWN1dG9yKVxyXG4gIFByb21pc2UgPSBmdW5jdGlvbihleGVjdXRvcil7XHJcbiAgICBhc3NlcnRGdW5jdGlvbihleGVjdXRvcik7XHJcbiAgICB2YXIgcmVjb3JkID0ge1xyXG4gICAgICBwOiBhc3NlcnQuaW5zdCh0aGlzLCBQcm9taXNlLCBQUk9NSVNFKSwgLy8gPC0gcHJvbWlzZVxyXG4gICAgICBjOiBbXSwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgLy8gPC0gY2hhaW5cclxuICAgICAgczogMCwgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIC8vIDwtIHN0YXRlXHJcbiAgICAgIGQ6IGZhbHNlLCAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAvLyA8LSBkb25lXHJcbiAgICAgIHY6IHVuZGVmaW5lZCwgICAgICAgICAgICAgICAgICAgICAgICAgICAvLyA8LSB2YWx1ZVxyXG4gICAgICBoOiBmYWxzZSAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgLy8gPC0gaGFuZGxlZCByZWplY3Rpb25cclxuICAgIH07XHJcbiAgICAkLmhpZGUodGhpcywgUkVDT1JELCByZWNvcmQpO1xyXG4gICAgdHJ5IHtcclxuICAgICAgZXhlY3V0b3IoY3R4KHJlc29sdmUsIHJlY29yZCwgMSksIGN0eChyZWplY3QsIHJlY29yZCwgMSkpO1xyXG4gICAgfSBjYXRjaChlcnIpe1xyXG4gICAgICByZWplY3QuY2FsbChyZWNvcmQsIGVycik7XHJcbiAgICB9XHJcbiAgfTtcclxuICAkLm1peChQcm9taXNlLnByb3RvdHlwZSwge1xyXG4gICAgLy8gMjUuNC41LjMgUHJvbWlzZS5wcm90b3R5cGUudGhlbihvbkZ1bGZpbGxlZCwgb25SZWplY3RlZClcclxuICAgIHRoZW46IGZ1bmN0aW9uKG9uRnVsZmlsbGVkLCBvblJlamVjdGVkKXtcclxuICAgICAgdmFyIFMgPSBhc3NlcnRPYmplY3QoYXNzZXJ0T2JqZWN0KHRoaXMpLmNvbnN0cnVjdG9yKVtTUEVDSUVTXTtcclxuICAgICAgdmFyIHJlYWN0ID0ge1xyXG4gICAgICAgIG9rOiAgIGlzRnVuY3Rpb24ob25GdWxmaWxsZWQpID8gb25GdWxmaWxsZWQgOiB0cnVlLFxyXG4gICAgICAgIGZhaWw6IGlzRnVuY3Rpb24ob25SZWplY3RlZCkgID8gb25SZWplY3RlZCAgOiBmYWxzZVxyXG4gICAgICB9O1xyXG4gICAgICB2YXIgUCA9IHJlYWN0LlAgPSBuZXcgKFMgIT0gdW5kZWZpbmVkID8gUyA6IFByb21pc2UpKGZ1bmN0aW9uKHJlcywgcmVqKXtcclxuICAgICAgICByZWFjdC5yZXMgPSBhc3NlcnRGdW5jdGlvbihyZXMpO1xyXG4gICAgICAgIHJlYWN0LnJlaiA9IGFzc2VydEZ1bmN0aW9uKHJlaik7XHJcbiAgICAgIH0pO1xyXG4gICAgICB2YXIgcmVjb3JkID0gdGhpc1tSRUNPUkRdO1xyXG4gICAgICByZWNvcmQuYy5wdXNoKHJlYWN0KTtcclxuICAgICAgcmVjb3JkLnMgJiYgbm90aWZ5KHJlY29yZCk7XHJcbiAgICAgIHJldHVybiBQO1xyXG4gICAgfSxcclxuICAgIC8vIDI1LjQuNS4xIFByb21pc2UucHJvdG90eXBlLmNhdGNoKG9uUmVqZWN0ZWQpXHJcbiAgICAnY2F0Y2gnOiBmdW5jdGlvbihvblJlamVjdGVkKXtcclxuICAgICAgcmV0dXJuIHRoaXMudGhlbih1bmRlZmluZWQsIG9uUmVqZWN0ZWQpO1xyXG4gICAgfVxyXG4gIH0pO1xyXG59KCk7XHJcbiRkZWYoJGRlZi5HICsgJGRlZi5XICsgJGRlZi5GICogKFByb21pc2UgIT0gQmFzZSksIHtQcm9taXNlOiBQcm9taXNlfSk7XHJcbiRkZWYoJGRlZi5TLCBQUk9NSVNFLCB7XHJcbiAgLy8gMjUuNC40LjUgUHJvbWlzZS5yZWplY3QocilcclxuICByZWplY3Q6IGZ1bmN0aW9uKHIpe1xyXG4gICAgcmV0dXJuIG5ldyAoZ2V0Q29uc3RydWN0b3IodGhpcykpKGZ1bmN0aW9uKHJlcywgcmVqKXtcclxuICAgICAgcmVqKHIpO1xyXG4gICAgfSk7XHJcbiAgfSxcclxuICAvLyAyNS40LjQuNiBQcm9taXNlLnJlc29sdmUoeClcclxuICByZXNvbHZlOiBmdW5jdGlvbih4KXtcclxuICAgIHJldHVybiBpc09iamVjdCh4KSAmJiBSRUNPUkQgaW4geCAmJiAkLmdldFByb3RvKHgpID09PSB0aGlzLnByb3RvdHlwZVxyXG4gICAgICA/IHggOiBuZXcgKGdldENvbnN0cnVjdG9yKHRoaXMpKShmdW5jdGlvbihyZXMpe1xyXG4gICAgICAgIHJlcyh4KTtcclxuICAgICAgfSk7XHJcbiAgfVxyXG59KTtcclxuJGRlZigkZGVmLlMgKyAkZGVmLkYgKiAoJGl0ZXIuZmFpbChmdW5jdGlvbihpdGVyKXtcclxuICBQcm9taXNlLmFsbChpdGVyKVsnY2F0Y2gnXShmdW5jdGlvbigpe30pO1xyXG59KSB8fCAkaXRlci5EQU5HRVJfQ0xPU0lORyksIFBST01JU0UsIHtcclxuICAvLyAyNS40LjQuMSBQcm9taXNlLmFsbChpdGVyYWJsZSlcclxuICBhbGw6IGZ1bmN0aW9uKGl0ZXJhYmxlKXtcclxuICAgIHZhciBDICAgICAgPSBnZXRDb25zdHJ1Y3Rvcih0aGlzKVxyXG4gICAgICAsIHZhbHVlcyA9IFtdO1xyXG4gICAgcmV0dXJuIG5ldyBDKGZ1bmN0aW9uKHJlc29sdmUsIHJlamVjdCl7XHJcbiAgICAgIGZvck9mKGl0ZXJhYmxlLCBmYWxzZSwgdmFsdWVzLnB1c2gsIHZhbHVlcyk7XHJcbiAgICAgIHZhciByZW1haW5pbmcgPSB2YWx1ZXMubGVuZ3RoXHJcbiAgICAgICAgLCByZXN1bHRzICAgPSBBcnJheShyZW1haW5pbmcpO1xyXG4gICAgICBpZihyZW1haW5pbmcpJC5lYWNoLmNhbGwodmFsdWVzLCBmdW5jdGlvbihwcm9taXNlLCBpbmRleCl7XHJcbiAgICAgICAgQy5yZXNvbHZlKHByb21pc2UpLnRoZW4oZnVuY3Rpb24odmFsdWUpe1xyXG4gICAgICAgICAgcmVzdWx0c1tpbmRleF0gPSB2YWx1ZTtcclxuICAgICAgICAgIC0tcmVtYWluaW5nIHx8IHJlc29sdmUocmVzdWx0cyk7XHJcbiAgICAgICAgfSwgcmVqZWN0KTtcclxuICAgICAgfSk7XHJcbiAgICAgIGVsc2UgcmVzb2x2ZShyZXN1bHRzKTtcclxuICAgIH0pO1xyXG4gIH0sXHJcbiAgLy8gMjUuNC40LjQgUHJvbWlzZS5yYWNlKGl0ZXJhYmxlKVxyXG4gIHJhY2U6IGZ1bmN0aW9uKGl0ZXJhYmxlKXtcclxuICAgIHZhciBDID0gZ2V0Q29uc3RydWN0b3IodGhpcyk7XHJcbiAgICByZXR1cm4gbmV3IEMoZnVuY3Rpb24ocmVzb2x2ZSwgcmVqZWN0KXtcclxuICAgICAgZm9yT2YoaXRlcmFibGUsIGZhbHNlLCBmdW5jdGlvbihwcm9taXNlKXtcclxuICAgICAgICBDLnJlc29sdmUocHJvbWlzZSkudGhlbihyZXNvbHZlLCByZWplY3QpO1xyXG4gICAgICB9KTtcclxuICAgIH0pO1xyXG4gIH1cclxufSk7XHJcbmNvZi5zZXQoUHJvbWlzZSwgUFJPTUlTRSk7XHJcbnJlcXVpcmUoJy4vJC5zcGVjaWVzJykoUHJvbWlzZSk7IiwidmFyICQgICAgICAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCAkZGVmICAgICAgPSByZXF1aXJlKCcuLyQuZGVmJylcclxuICAsIHNldFByb3RvICA9IHJlcXVpcmUoJy4vJC5zZXQtcHJvdG8nKVxyXG4gICwgJGl0ZXIgICAgID0gcmVxdWlyZSgnLi8kLml0ZXInKVxyXG4gICwgSVRFUiAgICAgID0gcmVxdWlyZSgnLi8kLnVpZCcpLnNhZmUoJ2l0ZXInKVxyXG4gICwgc3RlcCAgICAgID0gJGl0ZXIuc3RlcFxyXG4gICwgYXNzZXJ0ICAgID0gcmVxdWlyZSgnLi8kLmFzc2VydCcpXHJcbiAgLCBpc09iamVjdCAgPSAkLmlzT2JqZWN0XHJcbiAgLCBnZXREZXNjICAgPSAkLmdldERlc2NcclxuICAsIHNldERlc2MgICA9ICQuc2V0RGVzY1xyXG4gICwgZ2V0UHJvdG8gID0gJC5nZXRQcm90b1xyXG4gICwgYXBwbHkgICAgID0gRnVuY3Rpb24uYXBwbHlcclxuICAsIGFzc2VydE9iamVjdCA9IGFzc2VydC5vYmpcclxuICAsIGlzRXh0ZW5zaWJsZSA9IE9iamVjdC5pc0V4dGVuc2libGUgfHwgJC5pdDtcclxuZnVuY3Rpb24gRW51bWVyYXRlKGl0ZXJhdGVkKXtcclxuICB2YXIga2V5cyA9IFtdLCBrZXk7XHJcbiAgZm9yKGtleSBpbiBpdGVyYXRlZClrZXlzLnB1c2goa2V5KTtcclxuICAkLnNldCh0aGlzLCBJVEVSLCB7bzogaXRlcmF0ZWQsIGE6IGtleXMsIGk6IDB9KTtcclxufVxyXG4kaXRlci5jcmVhdGUoRW51bWVyYXRlLCAnT2JqZWN0JywgZnVuY3Rpb24oKXtcclxuICB2YXIgaXRlciA9IHRoaXNbSVRFUl1cclxuICAgICwga2V5cyA9IGl0ZXIuYVxyXG4gICAgLCBrZXk7XHJcbiAgZG8ge1xyXG4gICAgaWYoaXRlci5pID49IGtleXMubGVuZ3RoKXJldHVybiBzdGVwKDEpO1xyXG4gIH0gd2hpbGUoISgoa2V5ID0ga2V5c1tpdGVyLmkrK10pIGluIGl0ZXIubykpO1xyXG4gIHJldHVybiBzdGVwKDAsIGtleSk7XHJcbn0pO1xyXG5cclxuZnVuY3Rpb24gd3JhcChmbil7XHJcbiAgcmV0dXJuIGZ1bmN0aW9uKGl0KXtcclxuICAgIGFzc2VydE9iamVjdChpdCk7XHJcbiAgICB0cnkge1xyXG4gICAgICBmbi5hcHBseSh1bmRlZmluZWQsIGFyZ3VtZW50cyk7XHJcbiAgICAgIHJldHVybiB0cnVlO1xyXG4gICAgfSBjYXRjaChlKXtcclxuICAgICAgcmV0dXJuIGZhbHNlO1xyXG4gICAgfVxyXG4gIH07XHJcbn1cclxuXHJcbmZ1bmN0aW9uIHJlZmxlY3RHZXQodGFyZ2V0LCBwcm9wZXJ0eUtleS8qLCByZWNlaXZlciovKXtcclxuICB2YXIgcmVjZWl2ZXIgPSBhcmd1bWVudHMubGVuZ3RoIDwgMyA/IHRhcmdldCA6IGFyZ3VtZW50c1syXVxyXG4gICAgLCBkZXNjID0gZ2V0RGVzYyhhc3NlcnRPYmplY3QodGFyZ2V0KSwgcHJvcGVydHlLZXkpLCBwcm90bztcclxuICBpZihkZXNjKXJldHVybiAkLmhhcyhkZXNjLCAndmFsdWUnKVxyXG4gICAgPyBkZXNjLnZhbHVlXHJcbiAgICA6IGRlc2MuZ2V0ID09PSB1bmRlZmluZWRcclxuICAgICAgPyB1bmRlZmluZWRcclxuICAgICAgOiBkZXNjLmdldC5jYWxsKHJlY2VpdmVyKTtcclxuICByZXR1cm4gaXNPYmplY3QocHJvdG8gPSBnZXRQcm90byh0YXJnZXQpKVxyXG4gICAgPyByZWZsZWN0R2V0KHByb3RvLCBwcm9wZXJ0eUtleSwgcmVjZWl2ZXIpXHJcbiAgICA6IHVuZGVmaW5lZDtcclxufVxyXG5mdW5jdGlvbiByZWZsZWN0U2V0KHRhcmdldCwgcHJvcGVydHlLZXksIFYvKiwgcmVjZWl2ZXIqLyl7XHJcbiAgdmFyIHJlY2VpdmVyID0gYXJndW1lbnRzLmxlbmd0aCA8IDQgPyB0YXJnZXQgOiBhcmd1bWVudHNbM11cclxuICAgICwgb3duRGVzYyAgPSBnZXREZXNjKGFzc2VydE9iamVjdCh0YXJnZXQpLCBwcm9wZXJ0eUtleSlcclxuICAgICwgZXhpc3RpbmdEZXNjcmlwdG9yLCBwcm90bztcclxuICBpZighb3duRGVzYyl7XHJcbiAgICBpZihpc09iamVjdChwcm90byA9IGdldFByb3RvKHRhcmdldCkpKXtcclxuICAgICAgcmV0dXJuIHJlZmxlY3RTZXQocHJvdG8sIHByb3BlcnR5S2V5LCBWLCByZWNlaXZlcik7XHJcbiAgICB9XHJcbiAgICBvd25EZXNjID0gJC5kZXNjKDApO1xyXG4gIH1cclxuICBpZigkLmhhcyhvd25EZXNjLCAndmFsdWUnKSl7XHJcbiAgICBpZihvd25EZXNjLndyaXRhYmxlID09PSBmYWxzZSB8fCAhaXNPYmplY3QocmVjZWl2ZXIpKXJldHVybiBmYWxzZTtcclxuICAgIGV4aXN0aW5nRGVzY3JpcHRvciA9IGdldERlc2MocmVjZWl2ZXIsIHByb3BlcnR5S2V5KSB8fCAkLmRlc2MoMCk7XHJcbiAgICBleGlzdGluZ0Rlc2NyaXB0b3IudmFsdWUgPSBWO1xyXG4gICAgc2V0RGVzYyhyZWNlaXZlciwgcHJvcGVydHlLZXksIGV4aXN0aW5nRGVzY3JpcHRvcik7XHJcbiAgICByZXR1cm4gdHJ1ZTtcclxuICB9XHJcbiAgcmV0dXJuIG93bkRlc2Muc2V0ID09PSB1bmRlZmluZWQgPyBmYWxzZSA6IChvd25EZXNjLnNldC5jYWxsKHJlY2VpdmVyLCBWKSwgdHJ1ZSk7XHJcbn1cclxuXHJcbnZhciByZWZsZWN0ID0ge1xyXG4gIC8vIDI2LjEuMSBSZWZsZWN0LmFwcGx5KHRhcmdldCwgdGhpc0FyZ3VtZW50LCBhcmd1bWVudHNMaXN0KVxyXG4gIGFwcGx5OiByZXF1aXJlKCcuLyQuY3R4JykoRnVuY3Rpb24uY2FsbCwgYXBwbHksIDMpLFxyXG4gIC8vIDI2LjEuMiBSZWZsZWN0LmNvbnN0cnVjdCh0YXJnZXQsIGFyZ3VtZW50c0xpc3QgWywgbmV3VGFyZ2V0XSlcclxuICBjb25zdHJ1Y3Q6IGZ1bmN0aW9uKHRhcmdldCwgYXJndW1lbnRzTGlzdCAvKiwgbmV3VGFyZ2V0Ki8pe1xyXG4gICAgdmFyIHByb3RvICAgID0gYXNzZXJ0LmZuKGFyZ3VtZW50cy5sZW5ndGggPCAzID8gdGFyZ2V0IDogYXJndW1lbnRzWzJdKS5wcm90b3R5cGVcclxuICAgICAgLCBpbnN0YW5jZSA9ICQuY3JlYXRlKGlzT2JqZWN0KHByb3RvKSA/IHByb3RvIDogT2JqZWN0LnByb3RvdHlwZSlcclxuICAgICAgLCByZXN1bHQgICA9IGFwcGx5LmNhbGwodGFyZ2V0LCBpbnN0YW5jZSwgYXJndW1lbnRzTGlzdCk7XHJcbiAgICByZXR1cm4gaXNPYmplY3QocmVzdWx0KSA/IHJlc3VsdCA6IGluc3RhbmNlO1xyXG4gIH0sXHJcbiAgLy8gMjYuMS4zIFJlZmxlY3QuZGVmaW5lUHJvcGVydHkodGFyZ2V0LCBwcm9wZXJ0eUtleSwgYXR0cmlidXRlcylcclxuICBkZWZpbmVQcm9wZXJ0eTogd3JhcChzZXREZXNjKSxcclxuICAvLyAyNi4xLjQgUmVmbGVjdC5kZWxldGVQcm9wZXJ0eSh0YXJnZXQsIHByb3BlcnR5S2V5KVxyXG4gIGRlbGV0ZVByb3BlcnR5OiBmdW5jdGlvbih0YXJnZXQsIHByb3BlcnR5S2V5KXtcclxuICAgIHZhciBkZXNjID0gZ2V0RGVzYyhhc3NlcnRPYmplY3QodGFyZ2V0KSwgcHJvcGVydHlLZXkpO1xyXG4gICAgcmV0dXJuIGRlc2MgJiYgIWRlc2MuY29uZmlndXJhYmxlID8gZmFsc2UgOiBkZWxldGUgdGFyZ2V0W3Byb3BlcnR5S2V5XTtcclxuICB9LFxyXG4gIC8vIDI2LjEuNSBSZWZsZWN0LmVudW1lcmF0ZSh0YXJnZXQpXHJcbiAgZW51bWVyYXRlOiBmdW5jdGlvbih0YXJnZXQpe1xyXG4gICAgcmV0dXJuIG5ldyBFbnVtZXJhdGUoYXNzZXJ0T2JqZWN0KHRhcmdldCkpO1xyXG4gIH0sXHJcbiAgLy8gMjYuMS42IFJlZmxlY3QuZ2V0KHRhcmdldCwgcHJvcGVydHlLZXkgWywgcmVjZWl2ZXJdKVxyXG4gIGdldDogcmVmbGVjdEdldCxcclxuICAvLyAyNi4xLjcgUmVmbGVjdC5nZXRPd25Qcm9wZXJ0eURlc2NyaXB0b3IodGFyZ2V0LCBwcm9wZXJ0eUtleSlcclxuICBnZXRPd25Qcm9wZXJ0eURlc2NyaXB0b3I6IGZ1bmN0aW9uKHRhcmdldCwgcHJvcGVydHlLZXkpe1xyXG4gICAgcmV0dXJuIGdldERlc2MoYXNzZXJ0T2JqZWN0KHRhcmdldCksIHByb3BlcnR5S2V5KTtcclxuICB9LFxyXG4gIC8vIDI2LjEuOCBSZWZsZWN0LmdldFByb3RvdHlwZU9mKHRhcmdldClcclxuICBnZXRQcm90b3R5cGVPZjogZnVuY3Rpb24odGFyZ2V0KXtcclxuICAgIHJldHVybiBnZXRQcm90byhhc3NlcnRPYmplY3QodGFyZ2V0KSk7XHJcbiAgfSxcclxuICAvLyAyNi4xLjkgUmVmbGVjdC5oYXModGFyZ2V0LCBwcm9wZXJ0eUtleSlcclxuICBoYXM6IGZ1bmN0aW9uKHRhcmdldCwgcHJvcGVydHlLZXkpe1xyXG4gICAgcmV0dXJuIHByb3BlcnR5S2V5IGluIHRhcmdldDtcclxuICB9LFxyXG4gIC8vIDI2LjEuMTAgUmVmbGVjdC5pc0V4dGVuc2libGUodGFyZ2V0KVxyXG4gIGlzRXh0ZW5zaWJsZTogZnVuY3Rpb24odGFyZ2V0KXtcclxuICAgIHJldHVybiAhIWlzRXh0ZW5zaWJsZShhc3NlcnRPYmplY3QodGFyZ2V0KSk7XHJcbiAgfSxcclxuICAvLyAyNi4xLjExIFJlZmxlY3Qub3duS2V5cyh0YXJnZXQpXHJcbiAgb3duS2V5czogcmVxdWlyZSgnLi8kLm93bi1rZXlzJyksXHJcbiAgLy8gMjYuMS4xMiBSZWZsZWN0LnByZXZlbnRFeHRlbnNpb25zKHRhcmdldClcclxuICBwcmV2ZW50RXh0ZW5zaW9uczogd3JhcChPYmplY3QucHJldmVudEV4dGVuc2lvbnMgfHwgJC5pdCksXHJcbiAgLy8gMjYuMS4xMyBSZWZsZWN0LnNldCh0YXJnZXQsIHByb3BlcnR5S2V5LCBWIFssIHJlY2VpdmVyXSlcclxuICBzZXQ6IHJlZmxlY3RTZXRcclxufTtcclxuLy8gMjYuMS4xNCBSZWZsZWN0LnNldFByb3RvdHlwZU9mKHRhcmdldCwgcHJvdG8pXHJcbmlmKHNldFByb3RvKXJlZmxlY3Quc2V0UHJvdG90eXBlT2YgPSBmdW5jdGlvbih0YXJnZXQsIHByb3RvKXtcclxuICBzZXRQcm90byhhc3NlcnRPYmplY3QodGFyZ2V0KSwgcHJvdG8pO1xyXG4gIHJldHVybiB0cnVlO1xyXG59O1xyXG5cclxuJGRlZigkZGVmLkcsIHtSZWZsZWN0OiB7fX0pO1xyXG4kZGVmKCRkZWYuUywgJ1JlZmxlY3QnLCByZWZsZWN0KTsiLCJ2YXIgJCAgICAgID0gcmVxdWlyZSgnLi8kJylcclxuICAsIGNvZiAgICA9IHJlcXVpcmUoJy4vJC5jb2YnKVxyXG4gICwgUmVnRXhwID0gJC5nLlJlZ0V4cFxyXG4gICwgQmFzZSAgID0gUmVnRXhwXHJcbiAgLCBwcm90byAgPSBSZWdFeHAucHJvdG90eXBlO1xyXG5pZigkLkZXICYmICQuREVTQyl7XHJcbiAgLy8gUmVnRXhwIGFsbG93cyBhIHJlZ2V4IHdpdGggZmxhZ3MgYXMgdGhlIHBhdHRlcm5cclxuICBpZighZnVuY3Rpb24oKXt0cnl7IHJldHVybiBSZWdFeHAoL2EvZywgJ2knKSA9PSAnL2EvaSc7IH1jYXRjaChlKXsgLyogZW1wdHkgKi8gfX0oKSl7XHJcbiAgICBSZWdFeHAgPSBmdW5jdGlvbiBSZWdFeHAocGF0dGVybiwgZmxhZ3Mpe1xyXG4gICAgICByZXR1cm4gbmV3IEJhc2UoY29mKHBhdHRlcm4pID09ICdSZWdFeHAnICYmIGZsYWdzICE9PSB1bmRlZmluZWRcclxuICAgICAgICA/IHBhdHRlcm4uc291cmNlIDogcGF0dGVybiwgZmxhZ3MpO1xyXG4gICAgfTtcclxuICAgICQuZWFjaC5jYWxsKCQuZ2V0TmFtZXMoQmFzZSksIGZ1bmN0aW9uKGtleSl7XHJcbiAgICAgIGtleSBpbiBSZWdFeHAgfHwgJC5zZXREZXNjKFJlZ0V4cCwga2V5LCB7XHJcbiAgICAgICAgY29uZmlndXJhYmxlOiB0cnVlLFxyXG4gICAgICAgIGdldDogZnVuY3Rpb24oKXsgcmV0dXJuIEJhc2Vba2V5XTsgfSxcclxuICAgICAgICBzZXQ6IGZ1bmN0aW9uKGl0KXsgQmFzZVtrZXldID0gaXQ7IH1cclxuICAgICAgfSk7XHJcbiAgICB9KTtcclxuICAgIHByb3RvLmNvbnN0cnVjdG9yID0gUmVnRXhwO1xyXG4gICAgUmVnRXhwLnByb3RvdHlwZSA9IHByb3RvO1xyXG4gICAgJC5oaWRlKCQuZywgJ1JlZ0V4cCcsIFJlZ0V4cCk7XHJcbiAgfVxyXG4gIC8vIDIxLjIuNS4zIGdldCBSZWdFeHAucHJvdG90eXBlLmZsYWdzKClcclxuICBpZigvLi9nLmZsYWdzICE9ICdnJykkLnNldERlc2MocHJvdG8sICdmbGFncycsIHtcclxuICAgIGNvbmZpZ3VyYWJsZTogdHJ1ZSxcclxuICAgIGdldDogcmVxdWlyZSgnLi8kLnJlcGxhY2VyJykoL14uKlxcLyhcXHcqKSQvLCAnJDEnKVxyXG4gIH0pO1xyXG59XHJcbnJlcXVpcmUoJy4vJC5zcGVjaWVzJykoUmVnRXhwKTsiLCIndXNlIHN0cmljdCc7XHJcbnZhciBzdHJvbmcgPSByZXF1aXJlKCcuLyQuY29sbGVjdGlvbi1zdHJvbmcnKTtcclxuXHJcbi8vIDIzLjIgU2V0IE9iamVjdHNcclxucmVxdWlyZSgnLi8kLmNvbGxlY3Rpb24nKSgnU2V0Jywge1xyXG4gIC8vIDIzLjIuMy4xIFNldC5wcm90b3R5cGUuYWRkKHZhbHVlKVxyXG4gIGFkZDogZnVuY3Rpb24odmFsdWUpe1xyXG4gICAgcmV0dXJuIHN0cm9uZy5kZWYodGhpcywgdmFsdWUgPSB2YWx1ZSA9PT0gMCA/IDAgOiB2YWx1ZSwgdmFsdWUpO1xyXG4gIH1cclxufSwgc3Ryb25nKTsiLCJ2YXIgJGRlZiA9IHJlcXVpcmUoJy4vJC5kZWYnKTtcclxuJGRlZigkZGVmLlAsICdTdHJpbmcnLCB7XHJcbiAgLy8gMjEuMS4zLjMgU3RyaW5nLnByb3RvdHlwZS5jb2RlUG9pbnRBdChwb3MpXHJcbiAgY29kZVBvaW50QXQ6IHJlcXVpcmUoJy4vJC5zdHJpbmctYXQnKShmYWxzZSlcclxufSk7IiwiJ3VzZSBzdHJpY3QnO1xyXG52YXIgJCAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCBjb2YgID0gcmVxdWlyZSgnLi8kLmNvZicpXHJcbiAgLCAkZGVmID0gcmVxdWlyZSgnLi8kLmRlZicpXHJcbiAgLCB0b0xlbmd0aCA9ICQudG9MZW5ndGg7XHJcblxyXG4kZGVmKCRkZWYuUCwgJ1N0cmluZycsIHtcclxuICAvLyAyMS4xLjMuNiBTdHJpbmcucHJvdG90eXBlLmVuZHNXaXRoKHNlYXJjaFN0cmluZyBbLCBlbmRQb3NpdGlvbl0pXHJcbiAgZW5kc1dpdGg6IGZ1bmN0aW9uKHNlYXJjaFN0cmluZyAvKiwgZW5kUG9zaXRpb24gPSBAbGVuZ3RoICovKXtcclxuICAgIGlmKGNvZihzZWFyY2hTdHJpbmcpID09ICdSZWdFeHAnKXRocm93IFR5cGVFcnJvcigpO1xyXG4gICAgdmFyIHRoYXQgPSBTdHJpbmcoJC5hc3NlcnREZWZpbmVkKHRoaXMpKVxyXG4gICAgICAsIGVuZFBvc2l0aW9uID0gYXJndW1lbnRzWzFdXHJcbiAgICAgICwgbGVuID0gdG9MZW5ndGgodGhhdC5sZW5ndGgpXHJcbiAgICAgICwgZW5kID0gZW5kUG9zaXRpb24gPT09IHVuZGVmaW5lZCA/IGxlbiA6IE1hdGgubWluKHRvTGVuZ3RoKGVuZFBvc2l0aW9uKSwgbGVuKTtcclxuICAgIHNlYXJjaFN0cmluZyArPSAnJztcclxuICAgIHJldHVybiB0aGF0LnNsaWNlKGVuZCAtIHNlYXJjaFN0cmluZy5sZW5ndGgsIGVuZCkgPT09IHNlYXJjaFN0cmluZztcclxuICB9XHJcbn0pOyIsInZhciAkZGVmICAgID0gcmVxdWlyZSgnLi8kLmRlZicpXHJcbiAgLCB0b0luZGV4ID0gcmVxdWlyZSgnLi8kJykudG9JbmRleFxyXG4gICwgZnJvbUNoYXJDb2RlID0gU3RyaW5nLmZyb21DaGFyQ29kZTtcclxuXHJcbiRkZWYoJGRlZi5TLCAnU3RyaW5nJywge1xyXG4gIC8vIDIxLjEuMi4yIFN0cmluZy5mcm9tQ29kZVBvaW50KC4uLmNvZGVQb2ludHMpXHJcbiAgZnJvbUNvZGVQb2ludDogZnVuY3Rpb24oeCl7IC8vIGVzbGludC1kaXNhYmxlLWxpbmUgbm8tdW51c2VkLXZhcnNcclxuICAgIHZhciByZXMgPSBbXVxyXG4gICAgICAsIGxlbiA9IGFyZ3VtZW50cy5sZW5ndGhcclxuICAgICAgLCBpICAgPSAwXHJcbiAgICAgICwgY29kZTtcclxuICAgIHdoaWxlKGxlbiA+IGkpe1xyXG4gICAgICBjb2RlID0gK2FyZ3VtZW50c1tpKytdO1xyXG4gICAgICBpZih0b0luZGV4KGNvZGUsIDB4MTBmZmZmKSAhPT0gY29kZSl0aHJvdyBSYW5nZUVycm9yKGNvZGUgKyAnIGlzIG5vdCBhIHZhbGlkIGNvZGUgcG9pbnQnKTtcclxuICAgICAgcmVzLnB1c2goY29kZSA8IDB4MTAwMDBcclxuICAgICAgICA/IGZyb21DaGFyQ29kZShjb2RlKVxyXG4gICAgICAgIDogZnJvbUNoYXJDb2RlKCgoY29kZSAtPSAweDEwMDAwKSA+PiAxMCkgKyAweGQ4MDAsIGNvZGUgJSAweDQwMCArIDB4ZGMwMClcclxuICAgICAgKTtcclxuICAgIH0gcmV0dXJuIHJlcy5qb2luKCcnKTtcclxuICB9XHJcbn0pOyIsIid1c2Ugc3RyaWN0JztcclxudmFyICQgICAgPSByZXF1aXJlKCcuLyQnKVxyXG4gICwgY29mICA9IHJlcXVpcmUoJy4vJC5jb2YnKVxyXG4gICwgJGRlZiA9IHJlcXVpcmUoJy4vJC5kZWYnKTtcclxuXHJcbiRkZWYoJGRlZi5QLCAnU3RyaW5nJywge1xyXG4gIC8vIDIxLjEuMy43IFN0cmluZy5wcm90b3R5cGUuaW5jbHVkZXMoc2VhcmNoU3RyaW5nLCBwb3NpdGlvbiA9IDApXHJcbiAgaW5jbHVkZXM6IGZ1bmN0aW9uKHNlYXJjaFN0cmluZyAvKiwgcG9zaXRpb24gPSAwICovKXtcclxuICAgIGlmKGNvZihzZWFyY2hTdHJpbmcpID09ICdSZWdFeHAnKXRocm93IFR5cGVFcnJvcigpO1xyXG4gICAgcmV0dXJuICEhflN0cmluZygkLmFzc2VydERlZmluZWQodGhpcykpLmluZGV4T2Yoc2VhcmNoU3RyaW5nLCBhcmd1bWVudHNbMV0pO1xyXG4gIH1cclxufSk7IiwidmFyIHNldCAgID0gcmVxdWlyZSgnLi8kJykuc2V0XHJcbiAgLCBhdCAgICA9IHJlcXVpcmUoJy4vJC5zdHJpbmctYXQnKSh0cnVlKVxyXG4gICwgSVRFUiAgPSByZXF1aXJlKCcuLyQudWlkJykuc2FmZSgnaXRlcicpXHJcbiAgLCAkaXRlciA9IHJlcXVpcmUoJy4vJC5pdGVyJylcclxuICAsIHN0ZXAgID0gJGl0ZXIuc3RlcDtcclxuXHJcbi8vIDIxLjEuMy4yNyBTdHJpbmcucHJvdG90eXBlW0BAaXRlcmF0b3JdKClcclxuJGl0ZXIuc3RkKFN0cmluZywgJ1N0cmluZycsIGZ1bmN0aW9uKGl0ZXJhdGVkKXtcclxuICBzZXQodGhpcywgSVRFUiwge286IFN0cmluZyhpdGVyYXRlZCksIGk6IDB9KTtcclxuLy8gMjEuMS41LjIuMSAlU3RyaW5nSXRlcmF0b3JQcm90b3R5cGUlLm5leHQoKVxyXG59LCBmdW5jdGlvbigpe1xyXG4gIHZhciBpdGVyICA9IHRoaXNbSVRFUl1cclxuICAgICwgTyAgICAgPSBpdGVyLm9cclxuICAgICwgaW5kZXggPSBpdGVyLmlcclxuICAgICwgcG9pbnQ7XHJcbiAgaWYoaW5kZXggPj0gTy5sZW5ndGgpcmV0dXJuIHN0ZXAoMSk7XHJcbiAgcG9pbnQgPSBhdC5jYWxsKE8sIGluZGV4KTtcclxuICBpdGVyLmkgKz0gcG9pbnQubGVuZ3RoO1xyXG4gIHJldHVybiBzdGVwKDAsIHBvaW50KTtcclxufSk7IiwidmFyICQgICAgPSByZXF1aXJlKCcuLyQnKVxyXG4gICwgJGRlZiA9IHJlcXVpcmUoJy4vJC5kZWYnKTtcclxuXHJcbiRkZWYoJGRlZi5TLCAnU3RyaW5nJywge1xyXG4gIC8vIDIxLjEuMi40IFN0cmluZy5yYXcoY2FsbFNpdGUsIC4uLnN1YnN0aXR1dGlvbnMpXHJcbiAgcmF3OiBmdW5jdGlvbihjYWxsU2l0ZSl7XHJcbiAgICB2YXIgcmF3ID0gJC50b09iamVjdChjYWxsU2l0ZS5yYXcpXHJcbiAgICAgICwgbGVuID0gJC50b0xlbmd0aChyYXcubGVuZ3RoKVxyXG4gICAgICAsIHNsbiA9IGFyZ3VtZW50cy5sZW5ndGhcclxuICAgICAgLCByZXMgPSBbXVxyXG4gICAgICAsIGkgICA9IDA7XHJcbiAgICB3aGlsZShsZW4gPiBpKXtcclxuICAgICAgcmVzLnB1c2goU3RyaW5nKHJhd1tpKytdKSk7XHJcbiAgICAgIGlmKGkgPCBzbG4pcmVzLnB1c2goU3RyaW5nKGFyZ3VtZW50c1tpXSkpO1xyXG4gICAgfSByZXR1cm4gcmVzLmpvaW4oJycpO1xyXG4gIH1cclxufSk7IiwiJ3VzZSBzdHJpY3QnO1xyXG52YXIgJCAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCAkZGVmID0gcmVxdWlyZSgnLi8kLmRlZicpO1xyXG5cclxuJGRlZigkZGVmLlAsICdTdHJpbmcnLCB7XHJcbiAgLy8gMjEuMS4zLjEzIFN0cmluZy5wcm90b3R5cGUucmVwZWF0KGNvdW50KVxyXG4gIHJlcGVhdDogZnVuY3Rpb24oY291bnQpe1xyXG4gICAgdmFyIHN0ciA9IFN0cmluZygkLmFzc2VydERlZmluZWQodGhpcykpXHJcbiAgICAgICwgcmVzID0gJydcclxuICAgICAgLCBuICAgPSAkLnRvSW50ZWdlcihjb3VudCk7XHJcbiAgICBpZihuIDwgMCB8fCBuID09IEluZmluaXR5KXRocm93IFJhbmdlRXJyb3IoXCJDb3VudCBjYW4ndCBiZSBuZWdhdGl2ZVwiKTtcclxuICAgIGZvcig7biA+IDA7IChuID4+Pj0gMSkgJiYgKHN0ciArPSBzdHIpKWlmKG4gJiAxKXJlcyArPSBzdHI7XHJcbiAgICByZXR1cm4gcmVzO1xyXG4gIH1cclxufSk7IiwiJ3VzZSBzdHJpY3QnO1xyXG52YXIgJCAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCBjb2YgID0gcmVxdWlyZSgnLi8kLmNvZicpXHJcbiAgLCAkZGVmID0gcmVxdWlyZSgnLi8kLmRlZicpO1xyXG5cclxuJGRlZigkZGVmLlAsICdTdHJpbmcnLCB7XHJcbiAgLy8gMjEuMS4zLjE4IFN0cmluZy5wcm90b3R5cGUuc3RhcnRzV2l0aChzZWFyY2hTdHJpbmcgWywgcG9zaXRpb24gXSlcclxuICBzdGFydHNXaXRoOiBmdW5jdGlvbihzZWFyY2hTdHJpbmcgLyosIHBvc2l0aW9uID0gMCAqLyl7XHJcbiAgICBpZihjb2Yoc2VhcmNoU3RyaW5nKSA9PSAnUmVnRXhwJyl0aHJvdyBUeXBlRXJyb3IoKTtcclxuICAgIHZhciB0aGF0ICA9IFN0cmluZygkLmFzc2VydERlZmluZWQodGhpcykpXHJcbiAgICAgICwgaW5kZXggPSAkLnRvTGVuZ3RoKE1hdGgubWluKGFyZ3VtZW50c1sxXSwgdGhhdC5sZW5ndGgpKTtcclxuICAgIHNlYXJjaFN0cmluZyArPSAnJztcclxuICAgIHJldHVybiB0aGF0LnNsaWNlKGluZGV4LCBpbmRleCArIHNlYXJjaFN0cmluZy5sZW5ndGgpID09PSBzZWFyY2hTdHJpbmc7XHJcbiAgfVxyXG59KTsiLCIndXNlIHN0cmljdCc7XHJcbi8vIEVDTUFTY3JpcHQgNiBzeW1ib2xzIHNoaW1cclxudmFyICQgICAgICAgID0gcmVxdWlyZSgnLi8kJylcclxuICAsIHNldFRhZyAgID0gcmVxdWlyZSgnLi8kLmNvZicpLnNldFxyXG4gICwgdWlkICAgICAgPSByZXF1aXJlKCcuLyQudWlkJylcclxuICAsICRkZWYgICAgID0gcmVxdWlyZSgnLi8kLmRlZicpXHJcbiAgLCBrZXlPZiAgICA9IHJlcXVpcmUoJy4vJC5rZXlvZicpXHJcbiAgLCBoYXMgICAgICA9ICQuaGFzXHJcbiAgLCBoaWRlICAgICA9ICQuaGlkZVxyXG4gICwgZ2V0TmFtZXMgPSAkLmdldE5hbWVzXHJcbiAgLCB0b09iamVjdCA9ICQudG9PYmplY3RcclxuICAsIFN5bWJvbCAgID0gJC5nLlN5bWJvbFxyXG4gICwgQmFzZSAgICAgPSBTeW1ib2xcclxuICAsIHNldHRlciAgID0gZmFsc2VcclxuICAsIFRBRyAgICAgID0gdWlkLnNhZmUoJ3RhZycpXHJcbiAgLCBTeW1ib2xSZWdpc3RyeSA9IHt9XHJcbiAgLCBBbGxTeW1ib2xzICAgICA9IHt9O1xyXG5cclxuZnVuY3Rpb24gd3JhcCh0YWcpe1xyXG4gIHZhciBzeW0gPSBBbGxTeW1ib2xzW3RhZ10gPSAkLnNldCgkLmNyZWF0ZShTeW1ib2wucHJvdG90eXBlKSwgVEFHLCB0YWcpO1xyXG4gICQuREVTQyAmJiBzZXR0ZXIgJiYgJC5zZXREZXNjKE9iamVjdC5wcm90b3R5cGUsIHRhZywge1xyXG4gICAgY29uZmlndXJhYmxlOiB0cnVlLFxyXG4gICAgc2V0OiBmdW5jdGlvbih2YWx1ZSl7XHJcbiAgICAgIGhpZGUodGhpcywgdGFnLCB2YWx1ZSk7XHJcbiAgICB9XHJcbiAgfSk7XHJcbiAgcmV0dXJuIHN5bTtcclxufVxyXG5cclxuLy8gMTkuNC4xLjEgU3ltYm9sKFtkZXNjcmlwdGlvbl0pXHJcbmlmKCEkLmlzRnVuY3Rpb24oU3ltYm9sKSl7XHJcbiAgU3ltYm9sID0gZnVuY3Rpb24oZGVzY3JpcHRpb24pe1xyXG4gICAgaWYodGhpcyBpbnN0YW5jZW9mIFN5bWJvbCl0aHJvdyBUeXBlRXJyb3IoJ1N5bWJvbCBpcyBub3QgYSBjb25zdHJ1Y3RvcicpO1xyXG4gICAgcmV0dXJuIHdyYXAodWlkKGRlc2NyaXB0aW9uKSk7XHJcbiAgfTtcclxuICBoaWRlKFN5bWJvbC5wcm90b3R5cGUsICd0b1N0cmluZycsIGZ1bmN0aW9uKCl7XHJcbiAgICByZXR1cm4gdGhpc1tUQUddO1xyXG4gIH0pO1xyXG59XHJcbiRkZWYoJGRlZi5HICsgJGRlZi5XLCB7U3ltYm9sOiBTeW1ib2x9KTtcclxuXHJcbnZhciBzeW1ib2xTdGF0aWNzID0ge1xyXG4gIC8vIDE5LjQuMi4xIFN5bWJvbC5mb3Ioa2V5KVxyXG4gICdmb3InOiBmdW5jdGlvbihrZXkpe1xyXG4gICAgcmV0dXJuIGhhcyhTeW1ib2xSZWdpc3RyeSwga2V5ICs9ICcnKVxyXG4gICAgICA/IFN5bWJvbFJlZ2lzdHJ5W2tleV1cclxuICAgICAgOiBTeW1ib2xSZWdpc3RyeVtrZXldID0gU3ltYm9sKGtleSk7XHJcbiAgfSxcclxuICAvLyAxOS40LjIuNSBTeW1ib2wua2V5Rm9yKHN5bSlcclxuICBrZXlGb3I6IGZ1bmN0aW9uKGtleSl7XHJcbiAgICByZXR1cm4ga2V5T2YoU3ltYm9sUmVnaXN0cnksIGtleSk7XHJcbiAgfSxcclxuICBwdXJlOiB1aWQuc2FmZSxcclxuICBzZXQ6ICQuc2V0LFxyXG4gIHVzZVNldHRlcjogZnVuY3Rpb24oKXsgc2V0dGVyID0gdHJ1ZTsgfSxcclxuICB1c2VTaW1wbGU6IGZ1bmN0aW9uKCl7IHNldHRlciA9IGZhbHNlOyB9XHJcbn07XHJcbi8vIDE5LjQuMi4yIFN5bWJvbC5oYXNJbnN0YW5jZVxyXG4vLyAxOS40LjIuMyBTeW1ib2wuaXNDb25jYXRTcHJlYWRhYmxlXHJcbi8vIDE5LjQuMi40IFN5bWJvbC5pdGVyYXRvclxyXG4vLyAxOS40LjIuNiBTeW1ib2wubWF0Y2hcclxuLy8gMTkuNC4yLjggU3ltYm9sLnJlcGxhY2VcclxuLy8gMTkuNC4yLjkgU3ltYm9sLnNlYXJjaFxyXG4vLyAxOS40LjIuMTAgU3ltYm9sLnNwZWNpZXNcclxuLy8gMTkuNC4yLjExIFN5bWJvbC5zcGxpdFxyXG4vLyAxOS40LjIuMTIgU3ltYm9sLnRvUHJpbWl0aXZlXHJcbi8vIDE5LjQuMi4xMyBTeW1ib2wudG9TdHJpbmdUYWdcclxuLy8gMTkuNC4yLjE0IFN5bWJvbC51bnNjb3BhYmxlc1xyXG4kLmVhY2guY2FsbCgoXHJcbiAgICAnaGFzSW5zdGFuY2UsaXNDb25jYXRTcHJlYWRhYmxlLGl0ZXJhdG9yLG1hdGNoLHJlcGxhY2Usc2VhcmNoLCcgK1xyXG4gICAgJ3NwZWNpZXMsc3BsaXQsdG9QcmltaXRpdmUsdG9TdHJpbmdUYWcsdW5zY29wYWJsZXMnXHJcbiAgKS5zcGxpdCgnLCcpLCBmdW5jdGlvbihpdCl7XHJcbiAgICB2YXIgc3ltID0gcmVxdWlyZSgnLi8kLndrcycpKGl0KTtcclxuICAgIHN5bWJvbFN0YXRpY3NbaXRdID0gU3ltYm9sID09PSBCYXNlID8gc3ltIDogd3JhcChzeW0pO1xyXG4gIH1cclxuKTtcclxuXHJcbnNldHRlciA9IHRydWU7XHJcblxyXG4kZGVmKCRkZWYuUywgJ1N5bWJvbCcsIHN5bWJvbFN0YXRpY3MpO1xyXG5cclxuJGRlZigkZGVmLlMgKyAkZGVmLkYgKiAoU3ltYm9sICE9IEJhc2UpLCAnT2JqZWN0Jywge1xyXG4gIC8vIDE5LjEuMi43IE9iamVjdC5nZXRPd25Qcm9wZXJ0eU5hbWVzKE8pXHJcbiAgZ2V0T3duUHJvcGVydHlOYW1lczogZnVuY3Rpb24oaXQpe1xyXG4gICAgdmFyIG5hbWVzID0gZ2V0TmFtZXModG9PYmplY3QoaXQpKSwgcmVzdWx0ID0gW10sIGtleSwgaSA9IDA7XHJcbiAgICB3aGlsZShuYW1lcy5sZW5ndGggPiBpKWhhcyhBbGxTeW1ib2xzLCBrZXkgPSBuYW1lc1tpKytdKSB8fCByZXN1bHQucHVzaChrZXkpO1xyXG4gICAgcmV0dXJuIHJlc3VsdDtcclxuICB9LFxyXG4gIC8vIDE5LjEuMi44IE9iamVjdC5nZXRPd25Qcm9wZXJ0eVN5bWJvbHMoTylcclxuICBnZXRPd25Qcm9wZXJ0eVN5bWJvbHM6IGZ1bmN0aW9uKGl0KXtcclxuICAgIHZhciBuYW1lcyA9IGdldE5hbWVzKHRvT2JqZWN0KGl0KSksIHJlc3VsdCA9IFtdLCBrZXksIGkgPSAwO1xyXG4gICAgd2hpbGUobmFtZXMubGVuZ3RoID4gaSloYXMoQWxsU3ltYm9scywga2V5ID0gbmFtZXNbaSsrXSkgJiYgcmVzdWx0LnB1c2goQWxsU3ltYm9sc1trZXldKTtcclxuICAgIHJldHVybiByZXN1bHQ7XHJcbiAgfVxyXG59KTtcclxuXHJcbnNldFRhZyhTeW1ib2wsICdTeW1ib2wnKTtcclxuLy8gMjAuMi4xLjkgTWF0aFtAQHRvU3RyaW5nVGFnXVxyXG5zZXRUYWcoTWF0aCwgJ01hdGgnLCB0cnVlKTtcclxuLy8gMjQuMy4zIEpTT05bQEB0b1N0cmluZ1RhZ11cclxuc2V0VGFnKCQuZy5KU09OLCAnSlNPTicsIHRydWUpOyIsIid1c2Ugc3RyaWN0JztcclxudmFyICQgICAgICAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCB3ZWFrICAgICAgPSByZXF1aXJlKCcuLyQuY29sbGVjdGlvbi13ZWFrJylcclxuICAsIGxlYWtTdG9yZSA9IHdlYWsubGVha1N0b3JlXHJcbiAgLCBJRCAgICAgICAgPSB3ZWFrLklEXHJcbiAgLCBXRUFLICAgICAgPSB3ZWFrLldFQUtcclxuICAsIGhhcyAgICAgICA9ICQuaGFzXHJcbiAgLCBpc09iamVjdCAgPSAkLmlzT2JqZWN0XHJcbiAgLCBpc0Zyb3plbiAgPSBPYmplY3QuaXNGcm96ZW4gfHwgJC5jb3JlLk9iamVjdC5pc0Zyb3plblxyXG4gICwgdG1wICAgICAgID0ge307XHJcblxyXG4vLyAyMy4zIFdlYWtNYXAgT2JqZWN0c1xyXG52YXIgV2Vha01hcCA9IHJlcXVpcmUoJy4vJC5jb2xsZWN0aW9uJykoJ1dlYWtNYXAnLCB7XHJcbiAgLy8gMjMuMy4zLjMgV2Vha01hcC5wcm90b3R5cGUuZ2V0KGtleSlcclxuICBnZXQ6IGZ1bmN0aW9uKGtleSl7XHJcbiAgICBpZihpc09iamVjdChrZXkpKXtcclxuICAgICAgaWYoaXNGcm96ZW4oa2V5KSlyZXR1cm4gbGVha1N0b3JlKHRoaXMpLmdldChrZXkpO1xyXG4gICAgICBpZihoYXMoa2V5LCBXRUFLKSlyZXR1cm4ga2V5W1dFQUtdW3RoaXNbSURdXTtcclxuICAgIH1cclxuICB9LFxyXG4gIC8vIDIzLjMuMy41IFdlYWtNYXAucHJvdG90eXBlLnNldChrZXksIHZhbHVlKVxyXG4gIHNldDogZnVuY3Rpb24oa2V5LCB2YWx1ZSl7XHJcbiAgICByZXR1cm4gd2Vhay5kZWYodGhpcywga2V5LCB2YWx1ZSk7XHJcbiAgfVxyXG59LCB3ZWFrLCB0cnVlLCB0cnVlKTtcclxuXHJcbi8vIElFMTEgV2Vha01hcCBmcm96ZW4ga2V5cyBmaXhcclxuaWYoJC5GVyAmJiBuZXcgV2Vha01hcCgpLnNldCgoT2JqZWN0LmZyZWV6ZSB8fCBPYmplY3QpKHRtcCksIDcpLmdldCh0bXApICE9IDcpe1xyXG4gICQuZWFjaC5jYWxsKFsnZGVsZXRlJywgJ2hhcycsICdnZXQnLCAnc2V0J10sIGZ1bmN0aW9uKGtleSl7XHJcbiAgICB2YXIgbWV0aG9kID0gV2Vha01hcC5wcm90b3R5cGVba2V5XTtcclxuICAgIFdlYWtNYXAucHJvdG90eXBlW2tleV0gPSBmdW5jdGlvbihhLCBiKXtcclxuICAgICAgLy8gc3RvcmUgZnJvemVuIG9iamVjdHMgb24gbGVha3kgbWFwXHJcbiAgICAgIGlmKGlzT2JqZWN0KGEpICYmIGlzRnJvemVuKGEpKXtcclxuICAgICAgICB2YXIgcmVzdWx0ID0gbGVha1N0b3JlKHRoaXMpW2tleV0oYSwgYik7XHJcbiAgICAgICAgcmV0dXJuIGtleSA9PSAnc2V0JyA/IHRoaXMgOiByZXN1bHQ7XHJcbiAgICAgIC8vIHN0b3JlIGFsbCB0aGUgcmVzdCBvbiBuYXRpdmUgd2Vha21hcFxyXG4gICAgICB9IHJldHVybiBtZXRob2QuY2FsbCh0aGlzLCBhLCBiKTtcclxuICAgIH07XHJcbiAgfSk7XHJcbn0iLCIndXNlIHN0cmljdCc7XHJcbnZhciB3ZWFrID0gcmVxdWlyZSgnLi8kLmNvbGxlY3Rpb24td2VhaycpO1xyXG5cclxuLy8gMjMuNCBXZWFrU2V0IE9iamVjdHNcclxucmVxdWlyZSgnLi8kLmNvbGxlY3Rpb24nKSgnV2Vha1NldCcsIHtcclxuICAvLyAyMy40LjMuMSBXZWFrU2V0LnByb3RvdHlwZS5hZGQodmFsdWUpXHJcbiAgYWRkOiBmdW5jdGlvbih2YWx1ZSl7XHJcbiAgICByZXR1cm4gd2Vhay5kZWYodGhpcywgdmFsdWUsIHRydWUpO1xyXG4gIH1cclxufSwgd2VhaywgZmFsc2UsIHRydWUpOyIsIi8vIGh0dHBzOi8vZ2l0aHViLmNvbS9kb21lbmljL0FycmF5LnByb3RvdHlwZS5pbmNsdWRlc1xyXG52YXIgJGRlZiA9IHJlcXVpcmUoJy4vJC5kZWYnKTtcclxuJGRlZigkZGVmLlAsICdBcnJheScsIHtcclxuICBpbmNsdWRlczogcmVxdWlyZSgnLi8kLmFycmF5LWluY2x1ZGVzJykodHJ1ZSlcclxufSk7XHJcbnJlcXVpcmUoJy4vJC51bnNjb3BlJykoJ2luY2x1ZGVzJyk7IiwiLy8gaHR0cHM6Ly9naXN0LmdpdGh1Yi5jb20vV2ViUmVmbGVjdGlvbi85MzUzNzgxXHJcbnZhciAkICAgICAgID0gcmVxdWlyZSgnLi8kJylcclxuICAsICRkZWYgICAgPSByZXF1aXJlKCcuLyQuZGVmJylcclxuICAsIG93bktleXMgPSByZXF1aXJlKCcuLyQub3duLWtleXMnKTtcclxuXHJcbiRkZWYoJGRlZi5TLCAnT2JqZWN0Jywge1xyXG4gIGdldE93blByb3BlcnR5RGVzY3JpcHRvcnM6IGZ1bmN0aW9uKG9iamVjdCl7XHJcbiAgICB2YXIgTyAgICAgID0gJC50b09iamVjdChvYmplY3QpXHJcbiAgICAgICwgcmVzdWx0ID0ge307XHJcbiAgICAkLmVhY2guY2FsbChvd25LZXlzKE8pLCBmdW5jdGlvbihrZXkpe1xyXG4gICAgICAkLnNldERlc2MocmVzdWx0LCBrZXksICQuZGVzYygwLCAkLmdldERlc2MoTywga2V5KSkpO1xyXG4gICAgfSk7XHJcbiAgICByZXR1cm4gcmVzdWx0O1xyXG4gIH1cclxufSk7IiwiLy8gaHR0cDovL2dvby5nbC9Ya0JyakRcclxudmFyICQgICAgPSByZXF1aXJlKCcuLyQnKVxyXG4gICwgJGRlZiA9IHJlcXVpcmUoJy4vJC5kZWYnKTtcclxuZnVuY3Rpb24gY3JlYXRlT2JqZWN0VG9BcnJheShpc0VudHJpZXMpe1xyXG4gIHJldHVybiBmdW5jdGlvbihvYmplY3Qpe1xyXG4gICAgdmFyIE8gICAgICA9ICQudG9PYmplY3Qob2JqZWN0KVxyXG4gICAgICAsIGtleXMgICA9ICQuZ2V0S2V5cyhvYmplY3QpXHJcbiAgICAgICwgbGVuZ3RoID0ga2V5cy5sZW5ndGhcclxuICAgICAgLCBpICAgICAgPSAwXHJcbiAgICAgICwgcmVzdWx0ID0gQXJyYXkobGVuZ3RoKVxyXG4gICAgICAsIGtleTtcclxuICAgIGlmKGlzRW50cmllcyl3aGlsZShsZW5ndGggPiBpKXJlc3VsdFtpXSA9IFtrZXkgPSBrZXlzW2krK10sIE9ba2V5XV07XHJcbiAgICBlbHNlIHdoaWxlKGxlbmd0aCA+IGkpcmVzdWx0W2ldID0gT1trZXlzW2krK11dO1xyXG4gICAgcmV0dXJuIHJlc3VsdDtcclxuICB9O1xyXG59XHJcbiRkZWYoJGRlZi5TLCAnT2JqZWN0Jywge1xyXG4gIHZhbHVlczogIGNyZWF0ZU9iamVjdFRvQXJyYXkoZmFsc2UpLFxyXG4gIGVudHJpZXM6IGNyZWF0ZU9iamVjdFRvQXJyYXkodHJ1ZSlcclxufSk7IiwiLy8gaHR0cHM6Ly9naXN0LmdpdGh1Yi5jb20va2FuZ2F4Lzk2OTgxMDBcclxudmFyICRkZWYgPSByZXF1aXJlKCcuLyQuZGVmJyk7XHJcbiRkZWYoJGRlZi5TLCAnUmVnRXhwJywge1xyXG4gIGVzY2FwZTogcmVxdWlyZSgnLi8kLnJlcGxhY2VyJykoLyhbXFxcXFxcLVtcXF17fSgpKis/LixeJHxdKS9nLCAnXFxcXCQxJywgdHJ1ZSlcclxufSk7IiwiLy8gaHR0cHM6Ly9naXRodWIuY29tL21hdGhpYXNieW5lbnMvU3RyaW5nLnByb3RvdHlwZS5hdFxyXG52YXIgJGRlZiA9IHJlcXVpcmUoJy4vJC5kZWYnKTtcclxuJGRlZigkZGVmLlAsICdTdHJpbmcnLCB7XHJcbiAgYXQ6IHJlcXVpcmUoJy4vJC5zdHJpbmctYXQnKSh0cnVlKVxyXG59KTsiLCIvLyBKYXZhU2NyaXB0IDEuNiAvIFN0cmF3bWFuIGFycmF5IHN0YXRpY3Mgc2hpbVxyXG52YXIgJCAgICAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCAkZGVmICAgID0gcmVxdWlyZSgnLi8kLmRlZicpXHJcbiAgLCBjb3JlICAgID0gJC5jb3JlXHJcbiAgLCBzdGF0aWNzID0ge307XHJcbmZ1bmN0aW9uIHNldFN0YXRpY3Moa2V5cywgbGVuZ3RoKXtcclxuICAkLmVhY2guY2FsbChrZXlzLnNwbGl0KCcsJyksIGZ1bmN0aW9uKGtleSl7XHJcbiAgICBpZihsZW5ndGggPT0gdW5kZWZpbmVkICYmIGtleSBpbiBjb3JlLkFycmF5KXN0YXRpY3Nba2V5XSA9IGNvcmUuQXJyYXlba2V5XTtcclxuICAgIGVsc2UgaWYoa2V5IGluIFtdKXN0YXRpY3Nba2V5XSA9IHJlcXVpcmUoJy4vJC5jdHgnKShGdW5jdGlvbi5jYWxsLCBbXVtrZXldLCBsZW5ndGgpO1xyXG4gIH0pO1xyXG59XHJcbnNldFN0YXRpY3MoJ3BvcCxyZXZlcnNlLHNoaWZ0LGtleXMsdmFsdWVzLGVudHJpZXMnLCAxKTtcclxuc2V0U3RhdGljcygnaW5kZXhPZixldmVyeSxzb21lLGZvckVhY2gsbWFwLGZpbHRlcixmaW5kLGZpbmRJbmRleCxpbmNsdWRlcycsIDMpO1xyXG5zZXRTdGF0aWNzKCdqb2luLHNsaWNlLGNvbmNhdCxwdXNoLHNwbGljZSx1bnNoaWZ0LHNvcnQsbGFzdEluZGV4T2YsJyArXHJcbiAgICAgICAgICAgJ3JlZHVjZSxyZWR1Y2VSaWdodCxjb3B5V2l0aGluLGZpbGwsdHVybicpO1xyXG4kZGVmKCRkZWYuUywgJ0FycmF5Jywgc3RhdGljcyk7IiwicmVxdWlyZSgnLi9lczYuYXJyYXkuaXRlcmF0b3InKTtcclxudmFyICQgICAgICAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCBJdGVyYXRvcnMgPSByZXF1aXJlKCcuLyQuaXRlcicpLkl0ZXJhdG9yc1xyXG4gICwgSVRFUkFUT1IgID0gcmVxdWlyZSgnLi8kLndrcycpKCdpdGVyYXRvcicpXHJcbiAgLCBOb2RlTGlzdCAgPSAkLmcuTm9kZUxpc3Q7XHJcbmlmKCQuRlcgJiYgTm9kZUxpc3QgJiYgIShJVEVSQVRPUiBpbiBOb2RlTGlzdC5wcm90b3R5cGUpKXtcclxuICAkLmhpZGUoTm9kZUxpc3QucHJvdG90eXBlLCBJVEVSQVRPUiwgSXRlcmF0b3JzLkFycmF5KTtcclxufVxyXG5JdGVyYXRvcnMuTm9kZUxpc3QgPSBJdGVyYXRvcnMuQXJyYXk7IiwidmFyICRkZWYgID0gcmVxdWlyZSgnLi8kLmRlZicpXHJcbiAgLCAkdGFzayA9IHJlcXVpcmUoJy4vJC50YXNrJyk7XHJcbiRkZWYoJGRlZi5HICsgJGRlZi5CLCB7XHJcbiAgc2V0SW1tZWRpYXRlOiAgICR0YXNrLnNldCxcclxuICBjbGVhckltbWVkaWF0ZTogJHRhc2suY2xlYXJcclxufSk7IiwiLy8gaWU5LSBzZXRUaW1lb3V0ICYgc2V0SW50ZXJ2YWwgYWRkaXRpb25hbCBwYXJhbWV0ZXJzIGZpeFxyXG52YXIgJCAgICAgICA9IHJlcXVpcmUoJy4vJCcpXHJcbiAgLCAkZGVmICAgID0gcmVxdWlyZSgnLi8kLmRlZicpXHJcbiAgLCBpbnZva2UgID0gcmVxdWlyZSgnLi8kLmludm9rZScpXHJcbiAgLCBwYXJ0aWFsID0gcmVxdWlyZSgnLi8kLnBhcnRpYWwnKVxyXG4gICwgTVNJRSAgICA9ICEhJC5nLm5hdmlnYXRvciAmJiAvTVNJRSAuXFwuLy50ZXN0KG5hdmlnYXRvci51c2VyQWdlbnQpOyAvLyA8LSBkaXJ0eSBpZTktIGNoZWNrXHJcbmZ1bmN0aW9uIHdyYXAoc2V0KXtcclxuICByZXR1cm4gTVNJRSA/IGZ1bmN0aW9uKGZuLCB0aW1lIC8qLCAuLi5hcmdzICovKXtcclxuICAgIHJldHVybiBzZXQoaW52b2tlKFxyXG4gICAgICBwYXJ0aWFsLFxyXG4gICAgICBbXS5zbGljZS5jYWxsKGFyZ3VtZW50cywgMiksXHJcbiAgICAgICQuaXNGdW5jdGlvbihmbikgPyBmbiA6IEZ1bmN0aW9uKGZuKVxyXG4gICAgKSwgdGltZSk7XHJcbiAgfSA6IHNldDtcclxufVxyXG4kZGVmKCRkZWYuRyArICRkZWYuQiArICRkZWYuRiAqIE1TSUUsIHtcclxuICBzZXRUaW1lb3V0OiAgd3JhcCgkLmcuc2V0VGltZW91dCksXHJcbiAgc2V0SW50ZXJ2YWw6IHdyYXAoJC5nLnNldEludGVydmFsKVxyXG59KTsiLCJyZXF1aXJlKCcuL21vZHVsZXMvZXM1Jyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczYuc3ltYm9sJyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczYub2JqZWN0LmFzc2lnbicpO1xyXG5yZXF1aXJlKCcuL21vZHVsZXMvZXM2Lm9iamVjdC5pcycpO1xyXG5yZXF1aXJlKCcuL21vZHVsZXMvZXM2Lm9iamVjdC5zZXQtcHJvdG90eXBlLW9mJyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczYub2JqZWN0LnRvLXN0cmluZycpO1xyXG5yZXF1aXJlKCcuL21vZHVsZXMvZXM2Lm9iamVjdC5zdGF0aWNzLWFjY2VwdC1wcmltaXRpdmVzJyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczYuZnVuY3Rpb24ubmFtZScpO1xyXG5yZXF1aXJlKCcuL21vZHVsZXMvZXM2Lm51bWJlci5jb25zdHJ1Y3RvcicpO1xyXG5yZXF1aXJlKCcuL21vZHVsZXMvZXM2Lm51bWJlci5zdGF0aWNzJyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczYubWF0aCcpO1xyXG5yZXF1aXJlKCcuL21vZHVsZXMvZXM2LnN0cmluZy5mcm9tLWNvZGUtcG9pbnQnKTtcclxucmVxdWlyZSgnLi9tb2R1bGVzL2VzNi5zdHJpbmcucmF3Jyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczYuc3RyaW5nLml0ZXJhdG9yJyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczYuc3RyaW5nLmNvZGUtcG9pbnQtYXQnKTtcclxucmVxdWlyZSgnLi9tb2R1bGVzL2VzNi5zdHJpbmcuZW5kcy13aXRoJyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczYuc3RyaW5nLmluY2x1ZGVzJyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczYuc3RyaW5nLnJlcGVhdCcpO1xyXG5yZXF1aXJlKCcuL21vZHVsZXMvZXM2LnN0cmluZy5zdGFydHMtd2l0aCcpO1xyXG5yZXF1aXJlKCcuL21vZHVsZXMvZXM2LmFycmF5LmZyb20nKTtcclxucmVxdWlyZSgnLi9tb2R1bGVzL2VzNi5hcnJheS5vZicpO1xyXG5yZXF1aXJlKCcuL21vZHVsZXMvZXM2LmFycmF5Lml0ZXJhdG9yJyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczYuYXJyYXkuc3BlY2llcycpO1xyXG5yZXF1aXJlKCcuL21vZHVsZXMvZXM2LmFycmF5LmNvcHktd2l0aGluJyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczYuYXJyYXkuZmlsbCcpO1xyXG5yZXF1aXJlKCcuL21vZHVsZXMvZXM2LmFycmF5LmZpbmQnKTtcclxucmVxdWlyZSgnLi9tb2R1bGVzL2VzNi5hcnJheS5maW5kLWluZGV4Jyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczYucmVnZXhwJyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczYucHJvbWlzZScpO1xyXG5yZXF1aXJlKCcuL21vZHVsZXMvZXM2Lm1hcCcpO1xyXG5yZXF1aXJlKCcuL21vZHVsZXMvZXM2LnNldCcpO1xyXG5yZXF1aXJlKCcuL21vZHVsZXMvZXM2LndlYWstbWFwJyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczYud2Vhay1zZXQnKTtcclxucmVxdWlyZSgnLi9tb2R1bGVzL2VzNi5yZWZsZWN0Jyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczcuYXJyYXkuaW5jbHVkZXMnKTtcclxucmVxdWlyZSgnLi9tb2R1bGVzL2VzNy5zdHJpbmcuYXQnKTtcclxucmVxdWlyZSgnLi9tb2R1bGVzL2VzNy5yZWdleHAuZXNjYXBlJyk7XHJcbnJlcXVpcmUoJy4vbW9kdWxlcy9lczcub2JqZWN0LmdldC1vd24tcHJvcGVydHktZGVzY3JpcHRvcnMnKTtcclxucmVxdWlyZSgnLi9tb2R1bGVzL2VzNy5vYmplY3QudG8tYXJyYXknKTtcclxucmVxdWlyZSgnLi9tb2R1bGVzL2pzLmFycmF5LnN0YXRpY3MnKTtcclxucmVxdWlyZSgnLi9tb2R1bGVzL3dlYi50aW1lcnMnKTtcclxucmVxdWlyZSgnLi9tb2R1bGVzL3dlYi5pbW1lZGlhdGUnKTtcclxucmVxdWlyZSgnLi9tb2R1bGVzL3dlYi5kb20uaXRlcmFibGUnKTtcclxubW9kdWxlLmV4cG9ydHMgPSByZXF1aXJlKCcuL21vZHVsZXMvJCcpLmNvcmU7IiwiKGZ1bmN0aW9uIChnbG9iYWwpe1xuLyoqXG4gKiBDb3B5cmlnaHQgKGMpIDIwMTQsIEZhY2Vib29rLCBJbmMuXG4gKiBBbGwgcmlnaHRzIHJlc2VydmVkLlxuICpcbiAqIFRoaXMgc291cmNlIGNvZGUgaXMgbGljZW5zZWQgdW5kZXIgdGhlIEJTRC1zdHlsZSBsaWNlbnNlIGZvdW5kIGluIHRoZVxuICogaHR0cHM6Ly9yYXcuZ2l0aHViLmNvbS9mYWNlYm9vay9yZWdlbmVyYXRvci9tYXN0ZXIvTElDRU5TRSBmaWxlLiBBblxuICogYWRkaXRpb25hbCBncmFudCBvZiBwYXRlbnQgcmlnaHRzIGNhbiBiZSBmb3VuZCBpbiB0aGUgUEFURU5UUyBmaWxlIGluXG4gKiB0aGUgc2FtZSBkaXJlY3RvcnkuXG4gKi9cblxuIShmdW5jdGlvbihnbG9iYWwpIHtcbiAgXCJ1c2Ugc3RyaWN0XCI7XG5cbiAgdmFyIGhhc093biA9IE9iamVjdC5wcm90b3R5cGUuaGFzT3duUHJvcGVydHk7XG4gIHZhciB1bmRlZmluZWQ7IC8vIE1vcmUgY29tcHJlc3NpYmxlIHRoYW4gdm9pZCAwLlxuICB2YXIgaXRlcmF0b3JTeW1ib2wgPVxuICAgIHR5cGVvZiBTeW1ib2wgPT09IFwiZnVuY3Rpb25cIiAmJiBTeW1ib2wuaXRlcmF0b3IgfHwgXCJAQGl0ZXJhdG9yXCI7XG5cbiAgdmFyIGluTW9kdWxlID0gdHlwZW9mIG1vZHVsZSA9PT0gXCJvYmplY3RcIjtcbiAgdmFyIHJ1bnRpbWUgPSBnbG9iYWwucmVnZW5lcmF0b3JSdW50aW1lO1xuICBpZiAocnVudGltZSkge1xuICAgIGlmIChpbk1vZHVsZSkge1xuICAgICAgLy8gSWYgcmVnZW5lcmF0b3JSdW50aW1lIGlzIGRlZmluZWQgZ2xvYmFsbHkgYW5kIHdlJ3JlIGluIGEgbW9kdWxlLFxuICAgICAgLy8gbWFrZSB0aGUgZXhwb3J0cyBvYmplY3QgaWRlbnRpY2FsIHRvIHJlZ2VuZXJhdG9yUnVudGltZS5cbiAgICAgIG1vZHVsZS5leHBvcnRzID0gcnVudGltZTtcbiAgICB9XG4gICAgLy8gRG9uJ3QgYm90aGVyIGV2YWx1YXRpbmcgdGhlIHJlc3Qgb2YgdGhpcyBmaWxlIGlmIHRoZSBydW50aW1lIHdhc1xuICAgIC8vIGFscmVhZHkgZGVmaW5lZCBnbG9iYWxseS5cbiAgICByZXR1cm47XG4gIH1cblxuICAvLyBEZWZpbmUgdGhlIHJ1bnRpbWUgZ2xvYmFsbHkgKGFzIGV4cGVjdGVkIGJ5IGdlbmVyYXRlZCBjb2RlKSBhcyBlaXRoZXJcbiAgLy8gbW9kdWxlLmV4cG9ydHMgKGlmIHdlJ3JlIGluIGEgbW9kdWxlKSBvciBhIG5ldywgZW1wdHkgb2JqZWN0LlxuICBydW50aW1lID0gZ2xvYmFsLnJlZ2VuZXJhdG9yUnVudGltZSA9IGluTW9kdWxlID8gbW9kdWxlLmV4cG9ydHMgOiB7fTtcblxuICBmdW5jdGlvbiB3cmFwKGlubmVyRm4sIG91dGVyRm4sIHNlbGYsIHRyeUxvY3NMaXN0KSB7XG4gICAgcmV0dXJuIG5ldyBHZW5lcmF0b3IoaW5uZXJGbiwgb3V0ZXJGbiwgc2VsZiB8fCBudWxsLCB0cnlMb2NzTGlzdCB8fCBbXSk7XG4gIH1cbiAgcnVudGltZS53cmFwID0gd3JhcDtcblxuICAvLyBUcnkvY2F0Y2ggaGVscGVyIHRvIG1pbmltaXplIGRlb3B0aW1pemF0aW9ucy4gUmV0dXJucyBhIGNvbXBsZXRpb25cbiAgLy8gcmVjb3JkIGxpa2UgY29udGV4dC50cnlFbnRyaWVzW2ldLmNvbXBsZXRpb24uIFRoaXMgaW50ZXJmYWNlIGNvdWxkXG4gIC8vIGhhdmUgYmVlbiAoYW5kIHdhcyBwcmV2aW91c2x5KSBkZXNpZ25lZCB0byB0YWtlIGEgY2xvc3VyZSB0byBiZVxuICAvLyBpbnZva2VkIHdpdGhvdXQgYXJndW1lbnRzLCBidXQgaW4gYWxsIHRoZSBjYXNlcyB3ZSBjYXJlIGFib3V0IHdlXG4gIC8vIGFscmVhZHkgaGF2ZSBhbiBleGlzdGluZyBtZXRob2Qgd2Ugd2FudCB0byBjYWxsLCBzbyB0aGVyZSdzIG5vIG5lZWRcbiAgLy8gdG8gY3JlYXRlIGEgbmV3IGZ1bmN0aW9uIG9iamVjdC4gV2UgY2FuIGV2ZW4gZ2V0IGF3YXkgd2l0aCBhc3N1bWluZ1xuICAvLyB0aGUgbWV0aG9kIHRha2VzIGV4YWN0bHkgb25lIGFyZ3VtZW50LCBzaW5jZSB0aGF0IGhhcHBlbnMgdG8gYmUgdHJ1ZVxuICAvLyBpbiBldmVyeSBjYXNlLCBzbyB3ZSBkb24ndCBoYXZlIHRvIHRvdWNoIHRoZSBhcmd1bWVudHMgb2JqZWN0LiBUaGVcbiAgLy8gb25seSBhZGRpdGlvbmFsIGFsbG9jYXRpb24gcmVxdWlyZWQgaXMgdGhlIGNvbXBsZXRpb24gcmVjb3JkLCB3aGljaFxuICAvLyBoYXMgYSBzdGFibGUgc2hhcGUgYW5kIHNvIGhvcGVmdWxseSBzaG91bGQgYmUgY2hlYXAgdG8gYWxsb2NhdGUuXG4gIGZ1bmN0aW9uIHRyeUNhdGNoKGZuLCBvYmosIGFyZykge1xuICAgIHRyeSB7XG4gICAgICByZXR1cm4geyB0eXBlOiBcIm5vcm1hbFwiLCBhcmc6IGZuLmNhbGwob2JqLCBhcmcpIH07XG4gICAgfSBjYXRjaCAoZXJyKSB7XG4gICAgICByZXR1cm4geyB0eXBlOiBcInRocm93XCIsIGFyZzogZXJyIH07XG4gICAgfVxuICB9XG5cbiAgdmFyIEdlblN0YXRlU3VzcGVuZGVkU3RhcnQgPSBcInN1c3BlbmRlZFN0YXJ0XCI7XG4gIHZhciBHZW5TdGF0ZVN1c3BlbmRlZFlpZWxkID0gXCJzdXNwZW5kZWRZaWVsZFwiO1xuICB2YXIgR2VuU3RhdGVFeGVjdXRpbmcgPSBcImV4ZWN1dGluZ1wiO1xuICB2YXIgR2VuU3RhdGVDb21wbGV0ZWQgPSBcImNvbXBsZXRlZFwiO1xuXG4gIC8vIFJldHVybmluZyB0aGlzIG9iamVjdCBmcm9tIHRoZSBpbm5lckZuIGhhcyB0aGUgc2FtZSBlZmZlY3QgYXNcbiAgLy8gYnJlYWtpbmcgb3V0IG9mIHRoZSBkaXNwYXRjaCBzd2l0Y2ggc3RhdGVtZW50LlxuICB2YXIgQ29udGludWVTZW50aW5lbCA9IHt9O1xuXG4gIC8vIER1bW15IGNvbnN0cnVjdG9yIGZ1bmN0aW9ucyB0aGF0IHdlIHVzZSBhcyB0aGUgLmNvbnN0cnVjdG9yIGFuZFxuICAvLyAuY29uc3RydWN0b3IucHJvdG90eXBlIHByb3BlcnRpZXMgZm9yIGZ1bmN0aW9ucyB0aGF0IHJldHVybiBHZW5lcmF0b3JcbiAgLy8gb2JqZWN0cy4gRm9yIGZ1bGwgc3BlYyBjb21wbGlhbmNlLCB5b3UgbWF5IHdpc2ggdG8gY29uZmlndXJlIHlvdXJcbiAgLy8gbWluaWZpZXIgbm90IHRvIG1hbmdsZSB0aGUgbmFtZXMgb2YgdGhlc2UgdHdvIGZ1bmN0aW9ucy5cbiAgZnVuY3Rpb24gR2VuZXJhdG9yRnVuY3Rpb24oKSB7fVxuICBmdW5jdGlvbiBHZW5lcmF0b3JGdW5jdGlvblByb3RvdHlwZSgpIHt9XG5cbiAgdmFyIEdwID0gR2VuZXJhdG9yRnVuY3Rpb25Qcm90b3R5cGUucHJvdG90eXBlID0gR2VuZXJhdG9yLnByb3RvdHlwZTtcbiAgR2VuZXJhdG9yRnVuY3Rpb24ucHJvdG90eXBlID0gR3AuY29uc3RydWN0b3IgPSBHZW5lcmF0b3JGdW5jdGlvblByb3RvdHlwZTtcbiAgR2VuZXJhdG9yRnVuY3Rpb25Qcm90b3R5cGUuY29uc3RydWN0b3IgPSBHZW5lcmF0b3JGdW5jdGlvbjtcbiAgR2VuZXJhdG9yRnVuY3Rpb24uZGlzcGxheU5hbWUgPSBcIkdlbmVyYXRvckZ1bmN0aW9uXCI7XG5cbiAgcnVudGltZS5pc0dlbmVyYXRvckZ1bmN0aW9uID0gZnVuY3Rpb24oZ2VuRnVuKSB7XG4gICAgdmFyIGN0b3IgPSB0eXBlb2YgZ2VuRnVuID09PSBcImZ1bmN0aW9uXCIgJiYgZ2VuRnVuLmNvbnN0cnVjdG9yO1xuICAgIHJldHVybiBjdG9yXG4gICAgICA/IGN0b3IgPT09IEdlbmVyYXRvckZ1bmN0aW9uIHx8XG4gICAgICAgIC8vIEZvciB0aGUgbmF0aXZlIEdlbmVyYXRvckZ1bmN0aW9uIGNvbnN0cnVjdG9yLCB0aGUgYmVzdCB3ZSBjYW5cbiAgICAgICAgLy8gZG8gaXMgdG8gY2hlY2sgaXRzIC5uYW1lIHByb3BlcnR5LlxuICAgICAgICAoY3Rvci5kaXNwbGF5TmFtZSB8fCBjdG9yLm5hbWUpID09PSBcIkdlbmVyYXRvckZ1bmN0aW9uXCJcbiAgICAgIDogZmFsc2U7XG4gIH07XG5cbiAgcnVudGltZS5tYXJrID0gZnVuY3Rpb24oZ2VuRnVuKSB7XG4gICAgZ2VuRnVuLl9fcHJvdG9fXyA9IEdlbmVyYXRvckZ1bmN0aW9uUHJvdG90eXBlO1xuICAgIGdlbkZ1bi5wcm90b3R5cGUgPSBPYmplY3QuY3JlYXRlKEdwKTtcbiAgICByZXR1cm4gZ2VuRnVuO1xuICB9O1xuXG4gIHJ1bnRpbWUuYXN5bmMgPSBmdW5jdGlvbihpbm5lckZuLCBvdXRlckZuLCBzZWxmLCB0cnlMb2NzTGlzdCkge1xuICAgIHJldHVybiBuZXcgUHJvbWlzZShmdW5jdGlvbihyZXNvbHZlLCByZWplY3QpIHtcbiAgICAgIHZhciBnZW5lcmF0b3IgPSB3cmFwKGlubmVyRm4sIG91dGVyRm4sIHNlbGYsIHRyeUxvY3NMaXN0KTtcbiAgICAgIHZhciBjYWxsTmV4dCA9IHN0ZXAuYmluZChnZW5lcmF0b3IubmV4dCk7XG4gICAgICB2YXIgY2FsbFRocm93ID0gc3RlcC5iaW5kKGdlbmVyYXRvcltcInRocm93XCJdKTtcblxuICAgICAgZnVuY3Rpb24gc3RlcChhcmcpIHtcbiAgICAgICAgdmFyIHJlY29yZCA9IHRyeUNhdGNoKHRoaXMsIG51bGwsIGFyZyk7XG4gICAgICAgIGlmIChyZWNvcmQudHlwZSA9PT0gXCJ0aHJvd1wiKSB7XG4gICAgICAgICAgcmVqZWN0KHJlY29yZC5hcmcpO1xuICAgICAgICAgIHJldHVybjtcbiAgICAgICAgfVxuXG4gICAgICAgIHZhciBpbmZvID0gcmVjb3JkLmFyZztcbiAgICAgICAgaWYgKGluZm8uZG9uZSkge1xuICAgICAgICAgIHJlc29sdmUoaW5mby52YWx1ZSk7XG4gICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgUHJvbWlzZS5yZXNvbHZlKGluZm8udmFsdWUpLnRoZW4oY2FsbE5leHQsIGNhbGxUaHJvdyk7XG4gICAgICAgIH1cbiAgICAgIH1cblxuICAgICAgY2FsbE5leHQoKTtcbiAgICB9KTtcbiAgfTtcblxuICBmdW5jdGlvbiBHZW5lcmF0b3IoaW5uZXJGbiwgb3V0ZXJGbiwgc2VsZiwgdHJ5TG9jc0xpc3QpIHtcbiAgICB2YXIgZ2VuZXJhdG9yID0gb3V0ZXJGbiA/IE9iamVjdC5jcmVhdGUob3V0ZXJGbi5wcm90b3R5cGUpIDogdGhpcztcbiAgICB2YXIgY29udGV4dCA9IG5ldyBDb250ZXh0KHRyeUxvY3NMaXN0KTtcbiAgICB2YXIgc3RhdGUgPSBHZW5TdGF0ZVN1c3BlbmRlZFN0YXJ0O1xuXG4gICAgZnVuY3Rpb24gaW52b2tlKG1ldGhvZCwgYXJnKSB7XG4gICAgICBpZiAoc3RhdGUgPT09IEdlblN0YXRlRXhlY3V0aW5nKSB7XG4gICAgICAgIHRocm93IG5ldyBFcnJvcihcIkdlbmVyYXRvciBpcyBhbHJlYWR5IHJ1bm5pbmdcIik7XG4gICAgICB9XG5cbiAgICAgIGlmIChzdGF0ZSA9PT0gR2VuU3RhdGVDb21wbGV0ZWQpIHtcbiAgICAgICAgLy8gQmUgZm9yZ2l2aW5nLCBwZXIgMjUuMy4zLjMuMyBvZiB0aGUgc3BlYzpcbiAgICAgICAgLy8gaHR0cHM6Ly9wZW9wbGUubW96aWxsYS5vcmcvfmpvcmVuZG9yZmYvZXM2LWRyYWZ0Lmh0bWwjc2VjLWdlbmVyYXRvcnJlc3VtZVxuICAgICAgICByZXR1cm4gZG9uZVJlc3VsdCgpO1xuICAgICAgfVxuXG4gICAgICB3aGlsZSAodHJ1ZSkge1xuICAgICAgICB2YXIgZGVsZWdhdGUgPSBjb250ZXh0LmRlbGVnYXRlO1xuICAgICAgICBpZiAoZGVsZWdhdGUpIHtcbiAgICAgICAgICB2YXIgcmVjb3JkID0gdHJ5Q2F0Y2goXG4gICAgICAgICAgICBkZWxlZ2F0ZS5pdGVyYXRvclttZXRob2RdLFxuICAgICAgICAgICAgZGVsZWdhdGUuaXRlcmF0b3IsXG4gICAgICAgICAgICBhcmdcbiAgICAgICAgICApO1xuXG4gICAgICAgICAgaWYgKHJlY29yZC50eXBlID09PSBcInRocm93XCIpIHtcbiAgICAgICAgICAgIGNvbnRleHQuZGVsZWdhdGUgPSBudWxsO1xuXG4gICAgICAgICAgICAvLyBMaWtlIHJldHVybmluZyBnZW5lcmF0b3IudGhyb3codW5jYXVnaHQpLCBidXQgd2l0aG91dCB0aGVcbiAgICAgICAgICAgIC8vIG92ZXJoZWFkIG9mIGFuIGV4dHJhIGZ1bmN0aW9uIGNhbGwuXG4gICAgICAgICAgICBtZXRob2QgPSBcInRocm93XCI7XG4gICAgICAgICAgICBhcmcgPSByZWNvcmQuYXJnO1xuXG4gICAgICAgICAgICBjb250aW51ZTtcbiAgICAgICAgICB9XG5cbiAgICAgICAgICAvLyBEZWxlZ2F0ZSBnZW5lcmF0b3IgcmFuIGFuZCBoYW5kbGVkIGl0cyBvd24gZXhjZXB0aW9ucyBzb1xuICAgICAgICAgIC8vIHJlZ2FyZGxlc3Mgb2Ygd2hhdCB0aGUgbWV0aG9kIHdhcywgd2UgY29udGludWUgYXMgaWYgaXQgaXNcbiAgICAgICAgICAvLyBcIm5leHRcIiB3aXRoIGFuIHVuZGVmaW5lZCBhcmcuXG4gICAgICAgICAgbWV0aG9kID0gXCJuZXh0XCI7XG4gICAgICAgICAgYXJnID0gdW5kZWZpbmVkO1xuXG4gICAgICAgICAgdmFyIGluZm8gPSByZWNvcmQuYXJnO1xuICAgICAgICAgIGlmIChpbmZvLmRvbmUpIHtcbiAgICAgICAgICAgIGNvbnRleHRbZGVsZWdhdGUucmVzdWx0TmFtZV0gPSBpbmZvLnZhbHVlO1xuICAgICAgICAgICAgY29udGV4dC5uZXh0ID0gZGVsZWdhdGUubmV4dExvYztcbiAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgc3RhdGUgPSBHZW5TdGF0ZVN1c3BlbmRlZFlpZWxkO1xuICAgICAgICAgICAgcmV0dXJuIGluZm87XG4gICAgICAgICAgfVxuXG4gICAgICAgICAgY29udGV4dC5kZWxlZ2F0ZSA9IG51bGw7XG4gICAgICAgIH1cblxuICAgICAgICBpZiAobWV0aG9kID09PSBcIm5leHRcIikge1xuICAgICAgICAgIGlmIChzdGF0ZSA9PT0gR2VuU3RhdGVTdXNwZW5kZWRTdGFydCAmJlxuICAgICAgICAgICAgICB0eXBlb2YgYXJnICE9PSBcInVuZGVmaW5lZFwiKSB7XG4gICAgICAgICAgICAvLyBodHRwczovL3Blb3BsZS5tb3ppbGxhLm9yZy9+am9yZW5kb3JmZi9lczYtZHJhZnQuaHRtbCNzZWMtZ2VuZXJhdG9ycmVzdW1lXG4gICAgICAgICAgICB0aHJvdyBuZXcgVHlwZUVycm9yKFxuICAgICAgICAgICAgICBcImF0dGVtcHQgdG8gc2VuZCBcIiArIEpTT04uc3RyaW5naWZ5KGFyZykgKyBcIiB0byBuZXdib3JuIGdlbmVyYXRvclwiXG4gICAgICAgICAgICApO1xuICAgICAgICAgIH1cblxuICAgICAgICAgIGlmIChzdGF0ZSA9PT0gR2VuU3RhdGVTdXNwZW5kZWRZaWVsZCkge1xuICAgICAgICAgICAgY29udGV4dC5zZW50ID0gYXJnO1xuICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICBkZWxldGUgY29udGV4dC5zZW50O1xuICAgICAgICAgIH1cblxuICAgICAgICB9IGVsc2UgaWYgKG1ldGhvZCA9PT0gXCJ0aHJvd1wiKSB7XG4gICAgICAgICAgaWYgKHN0YXRlID09PSBHZW5TdGF0ZVN1c3BlbmRlZFN0YXJ0KSB7XG4gICAgICAgICAgICBzdGF0ZSA9IEdlblN0YXRlQ29tcGxldGVkO1xuICAgICAgICAgICAgdGhyb3cgYXJnO1xuICAgICAgICAgIH1cblxuICAgICAgICAgIGlmIChjb250ZXh0LmRpc3BhdGNoRXhjZXB0aW9uKGFyZykpIHtcbiAgICAgICAgICAgIC8vIElmIHRoZSBkaXNwYXRjaGVkIGV4Y2VwdGlvbiB3YXMgY2F1Z2h0IGJ5IGEgY2F0Y2ggYmxvY2ssXG4gICAgICAgICAgICAvLyB0aGVuIGxldCB0aGF0IGNhdGNoIGJsb2NrIGhhbmRsZSB0aGUgZXhjZXB0aW9uIG5vcm1hbGx5LlxuICAgICAgICAgICAgbWV0aG9kID0gXCJuZXh0XCI7XG4gICAgICAgICAgICBhcmcgPSB1bmRlZmluZWQ7XG4gICAgICAgICAgfVxuXG4gICAgICAgIH0gZWxzZSBpZiAobWV0aG9kID09PSBcInJldHVyblwiKSB7XG4gICAgICAgICAgY29udGV4dC5hYnJ1cHQoXCJyZXR1cm5cIiwgYXJnKTtcbiAgICAgICAgfVxuXG4gICAgICAgIHN0YXRlID0gR2VuU3RhdGVFeGVjdXRpbmc7XG5cbiAgICAgICAgdmFyIHJlY29yZCA9IHRyeUNhdGNoKGlubmVyRm4sIHNlbGYsIGNvbnRleHQpO1xuICAgICAgICBpZiAocmVjb3JkLnR5cGUgPT09IFwibm9ybWFsXCIpIHtcbiAgICAgICAgICAvLyBJZiBhbiBleGNlcHRpb24gaXMgdGhyb3duIGZyb20gaW5uZXJGbiwgd2UgbGVhdmUgc3RhdGUgPT09XG4gICAgICAgICAgLy8gR2VuU3RhdGVFeGVjdXRpbmcgYW5kIGxvb3AgYmFjayBmb3IgYW5vdGhlciBpbnZvY2F0aW9uLlxuICAgICAgICAgIHN0YXRlID0gY29udGV4dC5kb25lXG4gICAgICAgICAgICA/IEdlblN0YXRlQ29tcGxldGVkXG4gICAgICAgICAgICA6IEdlblN0YXRlU3VzcGVuZGVkWWllbGQ7XG5cbiAgICAgICAgICB2YXIgaW5mbyA9IHtcbiAgICAgICAgICAgIHZhbHVlOiByZWNvcmQuYXJnLFxuICAgICAgICAgICAgZG9uZTogY29udGV4dC5kb25lXG4gICAgICAgICAgfTtcblxuICAgICAgICAgIGlmIChyZWNvcmQuYXJnID09PSBDb250aW51ZVNlbnRpbmVsKSB7XG4gICAgICAgICAgICBpZiAoY29udGV4dC5kZWxlZ2F0ZSAmJiBtZXRob2QgPT09IFwibmV4dFwiKSB7XG4gICAgICAgICAgICAgIC8vIERlbGliZXJhdGVseSBmb3JnZXQgdGhlIGxhc3Qgc2VudCB2YWx1ZSBzbyB0aGF0IHdlIGRvbid0XG4gICAgICAgICAgICAgIC8vIGFjY2lkZW50YWxseSBwYXNzIGl0IG9uIHRvIHRoZSBkZWxlZ2F0ZS5cbiAgICAgICAgICAgICAgYXJnID0gdW5kZWZpbmVkO1xuICAgICAgICAgICAgfVxuICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICByZXR1cm4gaW5mbztcbiAgICAgICAgICB9XG5cbiAgICAgICAgfSBlbHNlIGlmIChyZWNvcmQudHlwZSA9PT0gXCJ0aHJvd1wiKSB7XG4gICAgICAgICAgc3RhdGUgPSBHZW5TdGF0ZUNvbXBsZXRlZDtcblxuICAgICAgICAgIGlmIChtZXRob2QgPT09IFwibmV4dFwiKSB7XG4gICAgICAgICAgICBjb250ZXh0LmRpc3BhdGNoRXhjZXB0aW9uKHJlY29yZC5hcmcpO1xuICAgICAgICAgIH0gZWxzZSB7XG4gICAgICAgICAgICBhcmcgPSByZWNvcmQuYXJnO1xuICAgICAgICAgIH1cbiAgICAgICAgfVxuICAgICAgfVxuICAgIH1cblxuICAgIGdlbmVyYXRvci5uZXh0ID0gaW52b2tlLmJpbmQoZ2VuZXJhdG9yLCBcIm5leHRcIik7XG4gICAgZ2VuZXJhdG9yW1widGhyb3dcIl0gPSBpbnZva2UuYmluZChnZW5lcmF0b3IsIFwidGhyb3dcIik7XG4gICAgZ2VuZXJhdG9yW1wicmV0dXJuXCJdID0gaW52b2tlLmJpbmQoZ2VuZXJhdG9yLCBcInJldHVyblwiKTtcblxuICAgIHJldHVybiBnZW5lcmF0b3I7XG4gIH1cblxuICBHcFtpdGVyYXRvclN5bWJvbF0gPSBmdW5jdGlvbigpIHtcbiAgICByZXR1cm4gdGhpcztcbiAgfTtcblxuICBHcC50b1N0cmluZyA9IGZ1bmN0aW9uKCkge1xuICAgIHJldHVybiBcIltvYmplY3QgR2VuZXJhdG9yXVwiO1xuICB9O1xuXG4gIGZ1bmN0aW9uIHB1c2hUcnlFbnRyeShsb2NzKSB7XG4gICAgdmFyIGVudHJ5ID0geyB0cnlMb2M6IGxvY3NbMF0gfTtcblxuICAgIGlmICgxIGluIGxvY3MpIHtcbiAgICAgIGVudHJ5LmNhdGNoTG9jID0gbG9jc1sxXTtcbiAgICB9XG5cbiAgICBpZiAoMiBpbiBsb2NzKSB7XG4gICAgICBlbnRyeS5maW5hbGx5TG9jID0gbG9jc1syXTtcbiAgICAgIGVudHJ5LmFmdGVyTG9jID0gbG9jc1szXTtcbiAgICB9XG5cbiAgICB0aGlzLnRyeUVudHJpZXMucHVzaChlbnRyeSk7XG4gIH1cblxuICBmdW5jdGlvbiByZXNldFRyeUVudHJ5KGVudHJ5KSB7XG4gICAgdmFyIHJlY29yZCA9IGVudHJ5LmNvbXBsZXRpb24gfHwge307XG4gICAgcmVjb3JkLnR5cGUgPSBcIm5vcm1hbFwiO1xuICAgIGRlbGV0ZSByZWNvcmQuYXJnO1xuICAgIGVudHJ5LmNvbXBsZXRpb24gPSByZWNvcmQ7XG4gIH1cblxuICBmdW5jdGlvbiBDb250ZXh0KHRyeUxvY3NMaXN0KSB7XG4gICAgLy8gVGhlIHJvb3QgZW50cnkgb2JqZWN0IChlZmZlY3RpdmVseSBhIHRyeSBzdGF0ZW1lbnQgd2l0aG91dCBhIGNhdGNoXG4gICAgLy8gb3IgYSBmaW5hbGx5IGJsb2NrKSBnaXZlcyB1cyBhIHBsYWNlIHRvIHN0b3JlIHZhbHVlcyB0aHJvd24gZnJvbVxuICAgIC8vIGxvY2F0aW9ucyB3aGVyZSB0aGVyZSBpcyBubyBlbmNsb3NpbmcgdHJ5IHN0YXRlbWVudC5cbiAgICB0aGlzLnRyeUVudHJpZXMgPSBbeyB0cnlMb2M6IFwicm9vdFwiIH1dO1xuICAgIHRyeUxvY3NMaXN0LmZvckVhY2gocHVzaFRyeUVudHJ5LCB0aGlzKTtcbiAgICB0aGlzLnJlc2V0KCk7XG4gIH1cblxuICBydW50aW1lLmtleXMgPSBmdW5jdGlvbihvYmplY3QpIHtcbiAgICB2YXIga2V5cyA9IFtdO1xuICAgIGZvciAodmFyIGtleSBpbiBvYmplY3QpIHtcbiAgICAgIGtleXMucHVzaChrZXkpO1xuICAgIH1cbiAgICBrZXlzLnJldmVyc2UoKTtcblxuICAgIC8vIFJhdGhlciB0aGFuIHJldHVybmluZyBhbiBvYmplY3Qgd2l0aCBhIG5leHQgbWV0aG9kLCB3ZSBrZWVwXG4gICAgLy8gdGhpbmdzIHNpbXBsZSBhbmQgcmV0dXJuIHRoZSBuZXh0IGZ1bmN0aW9uIGl0c2VsZi5cbiAgICByZXR1cm4gZnVuY3Rpb24gbmV4dCgpIHtcbiAgICAgIHdoaWxlIChrZXlzLmxlbmd0aCkge1xuICAgICAgICB2YXIga2V5ID0ga2V5cy5wb3AoKTtcbiAgICAgICAgaWYgKGtleSBpbiBvYmplY3QpIHtcbiAgICAgICAgICBuZXh0LnZhbHVlID0ga2V5O1xuICAgICAgICAgIG5leHQuZG9uZSA9IGZhbHNlO1xuICAgICAgICAgIHJldHVybiBuZXh0O1xuICAgICAgICB9XG4gICAgICB9XG5cbiAgICAgIC8vIFRvIGF2b2lkIGNyZWF0aW5nIGFuIGFkZGl0aW9uYWwgb2JqZWN0LCB3ZSBqdXN0IGhhbmcgdGhlIC52YWx1ZVxuICAgICAgLy8gYW5kIC5kb25lIHByb3BlcnRpZXMgb2ZmIHRoZSBuZXh0IGZ1bmN0aW9uIG9iamVjdCBpdHNlbGYuIFRoaXNcbiAgICAgIC8vIGFsc28gZW5zdXJlcyB0aGF0IHRoZSBtaW5pZmllciB3aWxsIG5vdCBhbm9ueW1pemUgdGhlIGZ1bmN0aW9uLlxuICAgICAgbmV4dC5kb25lID0gdHJ1ZTtcbiAgICAgIHJldHVybiBuZXh0O1xuICAgIH07XG4gIH07XG5cbiAgZnVuY3Rpb24gdmFsdWVzKGl0ZXJhYmxlKSB7XG4gICAgaWYgKGl0ZXJhYmxlKSB7XG4gICAgICB2YXIgaXRlcmF0b3JNZXRob2QgPSBpdGVyYWJsZVtpdGVyYXRvclN5bWJvbF07XG4gICAgICBpZiAoaXRlcmF0b3JNZXRob2QpIHtcbiAgICAgICAgcmV0dXJuIGl0ZXJhdG9yTWV0aG9kLmNhbGwoaXRlcmFibGUpO1xuICAgICAgfVxuXG4gICAgICBpZiAodHlwZW9mIGl0ZXJhYmxlLm5leHQgPT09IFwiZnVuY3Rpb25cIikge1xuICAgICAgICByZXR1cm4gaXRlcmFibGU7XG4gICAgICB9XG5cbiAgICAgIGlmICghaXNOYU4oaXRlcmFibGUubGVuZ3RoKSkge1xuICAgICAgICB2YXIgaSA9IC0xLCBuZXh0ID0gZnVuY3Rpb24gbmV4dCgpIHtcbiAgICAgICAgICB3aGlsZSAoKytpIDwgaXRlcmFibGUubGVuZ3RoKSB7XG4gICAgICAgICAgICBpZiAoaGFzT3duLmNhbGwoaXRlcmFibGUsIGkpKSB7XG4gICAgICAgICAgICAgIG5leHQudmFsdWUgPSBpdGVyYWJsZVtpXTtcbiAgICAgICAgICAgICAgbmV4dC5kb25lID0gZmFsc2U7XG4gICAgICAgICAgICAgIHJldHVybiBuZXh0O1xuICAgICAgICAgICAgfVxuICAgICAgICAgIH1cblxuICAgICAgICAgIG5leHQudmFsdWUgPSB1bmRlZmluZWQ7XG4gICAgICAgICAgbmV4dC5kb25lID0gdHJ1ZTtcblxuICAgICAgICAgIHJldHVybiBuZXh0O1xuICAgICAgICB9O1xuXG4gICAgICAgIHJldHVybiBuZXh0Lm5leHQgPSBuZXh0O1xuICAgICAgfVxuICAgIH1cblxuICAgIC8vIFJldHVybiBhbiBpdGVyYXRvciB3aXRoIG5vIHZhbHVlcy5cbiAgICByZXR1cm4geyBuZXh0OiBkb25lUmVzdWx0IH07XG4gIH1cbiAgcnVudGltZS52YWx1ZXMgPSB2YWx1ZXM7XG5cbiAgZnVuY3Rpb24gZG9uZVJlc3VsdCgpIHtcbiAgICByZXR1cm4geyB2YWx1ZTogdW5kZWZpbmVkLCBkb25lOiB0cnVlIH07XG4gIH1cblxuICBDb250ZXh0LnByb3RvdHlwZSA9IHtcbiAgICBjb25zdHJ1Y3RvcjogQ29udGV4dCxcblxuICAgIHJlc2V0OiBmdW5jdGlvbigpIHtcbiAgICAgIHRoaXMucHJldiA9IDA7XG4gICAgICB0aGlzLm5leHQgPSAwO1xuICAgICAgdGhpcy5zZW50ID0gdW5kZWZpbmVkO1xuICAgICAgdGhpcy5kb25lID0gZmFsc2U7XG4gICAgICB0aGlzLmRlbGVnYXRlID0gbnVsbDtcblxuICAgICAgdGhpcy50cnlFbnRyaWVzLmZvckVhY2gocmVzZXRUcnlFbnRyeSk7XG5cbiAgICAgIC8vIFByZS1pbml0aWFsaXplIGF0IGxlYXN0IDIwIHRlbXBvcmFyeSB2YXJpYWJsZXMgdG8gZW5hYmxlIGhpZGRlblxuICAgICAgLy8gY2xhc3Mgb3B0aW1pemF0aW9ucyBmb3Igc2ltcGxlIGdlbmVyYXRvcnMuXG4gICAgICBmb3IgKHZhciB0ZW1wSW5kZXggPSAwLCB0ZW1wTmFtZTtcbiAgICAgICAgICAgaGFzT3duLmNhbGwodGhpcywgdGVtcE5hbWUgPSBcInRcIiArIHRlbXBJbmRleCkgfHwgdGVtcEluZGV4IDwgMjA7XG4gICAgICAgICAgICsrdGVtcEluZGV4KSB7XG4gICAgICAgIHRoaXNbdGVtcE5hbWVdID0gbnVsbDtcbiAgICAgIH1cbiAgICB9LFxuXG4gICAgc3RvcDogZnVuY3Rpb24oKSB7XG4gICAgICB0aGlzLmRvbmUgPSB0cnVlO1xuXG4gICAgICB2YXIgcm9vdEVudHJ5ID0gdGhpcy50cnlFbnRyaWVzWzBdO1xuICAgICAgdmFyIHJvb3RSZWNvcmQgPSByb290RW50cnkuY29tcGxldGlvbjtcbiAgICAgIGlmIChyb290UmVjb3JkLnR5cGUgPT09IFwidGhyb3dcIikge1xuICAgICAgICB0aHJvdyByb290UmVjb3JkLmFyZztcbiAgICAgIH1cblxuICAgICAgcmV0dXJuIHRoaXMucnZhbDtcbiAgICB9LFxuXG4gICAgZGlzcGF0Y2hFeGNlcHRpb246IGZ1bmN0aW9uKGV4Y2VwdGlvbikge1xuICAgICAgaWYgKHRoaXMuZG9uZSkge1xuICAgICAgICB0aHJvdyBleGNlcHRpb247XG4gICAgICB9XG5cbiAgICAgIHZhciBjb250ZXh0ID0gdGhpcztcbiAgICAgIGZ1bmN0aW9uIGhhbmRsZShsb2MsIGNhdWdodCkge1xuICAgICAgICByZWNvcmQudHlwZSA9IFwidGhyb3dcIjtcbiAgICAgICAgcmVjb3JkLmFyZyA9IGV4Y2VwdGlvbjtcbiAgICAgICAgY29udGV4dC5uZXh0ID0gbG9jO1xuICAgICAgICByZXR1cm4gISFjYXVnaHQ7XG4gICAgICB9XG5cbiAgICAgIGZvciAodmFyIGkgPSB0aGlzLnRyeUVudHJpZXMubGVuZ3RoIC0gMTsgaSA+PSAwOyAtLWkpIHtcbiAgICAgICAgdmFyIGVudHJ5ID0gdGhpcy50cnlFbnRyaWVzW2ldO1xuICAgICAgICB2YXIgcmVjb3JkID0gZW50cnkuY29tcGxldGlvbjtcblxuICAgICAgICBpZiAoZW50cnkudHJ5TG9jID09PSBcInJvb3RcIikge1xuICAgICAgICAgIC8vIEV4Y2VwdGlvbiB0aHJvd24gb3V0c2lkZSBvZiBhbnkgdHJ5IGJsb2NrIHRoYXQgY291bGQgaGFuZGxlXG4gICAgICAgICAgLy8gaXQsIHNvIHNldCB0aGUgY29tcGxldGlvbiB2YWx1ZSBvZiB0aGUgZW50aXJlIGZ1bmN0aW9uIHRvXG4gICAgICAgICAgLy8gdGhyb3cgdGhlIGV4Y2VwdGlvbi5cbiAgICAgICAgICByZXR1cm4gaGFuZGxlKFwiZW5kXCIpO1xuICAgICAgICB9XG5cbiAgICAgICAgaWYgKGVudHJ5LnRyeUxvYyA8PSB0aGlzLnByZXYpIHtcbiAgICAgICAgICB2YXIgaGFzQ2F0Y2ggPSBoYXNPd24uY2FsbChlbnRyeSwgXCJjYXRjaExvY1wiKTtcbiAgICAgICAgICB2YXIgaGFzRmluYWxseSA9IGhhc093bi5jYWxsKGVudHJ5LCBcImZpbmFsbHlMb2NcIik7XG5cbiAgICAgICAgICBpZiAoaGFzQ2F0Y2ggJiYgaGFzRmluYWxseSkge1xuICAgICAgICAgICAgaWYgKHRoaXMucHJldiA8IGVudHJ5LmNhdGNoTG9jKSB7XG4gICAgICAgICAgICAgIHJldHVybiBoYW5kbGUoZW50cnkuY2F0Y2hMb2MsIHRydWUpO1xuICAgICAgICAgICAgfSBlbHNlIGlmICh0aGlzLnByZXYgPCBlbnRyeS5maW5hbGx5TG9jKSB7XG4gICAgICAgICAgICAgIHJldHVybiBoYW5kbGUoZW50cnkuZmluYWxseUxvYyk7XG4gICAgICAgICAgICB9XG5cbiAgICAgICAgICB9IGVsc2UgaWYgKGhhc0NhdGNoKSB7XG4gICAgICAgICAgICBpZiAodGhpcy5wcmV2IDwgZW50cnkuY2F0Y2hMb2MpIHtcbiAgICAgICAgICAgICAgcmV0dXJuIGhhbmRsZShlbnRyeS5jYXRjaExvYywgdHJ1ZSk7XG4gICAgICAgICAgICB9XG5cbiAgICAgICAgICB9IGVsc2UgaWYgKGhhc0ZpbmFsbHkpIHtcbiAgICAgICAgICAgIGlmICh0aGlzLnByZXYgPCBlbnRyeS5maW5hbGx5TG9jKSB7XG4gICAgICAgICAgICAgIHJldHVybiBoYW5kbGUoZW50cnkuZmluYWxseUxvYyk7XG4gICAgICAgICAgICB9XG5cbiAgICAgICAgICB9IGVsc2Uge1xuICAgICAgICAgICAgdGhyb3cgbmV3IEVycm9yKFwidHJ5IHN0YXRlbWVudCB3aXRob3V0IGNhdGNoIG9yIGZpbmFsbHlcIik7XG4gICAgICAgICAgfVxuICAgICAgICB9XG4gICAgICB9XG4gICAgfSxcblxuICAgIGFicnVwdDogZnVuY3Rpb24odHlwZSwgYXJnKSB7XG4gICAgICBmb3IgKHZhciBpID0gdGhpcy50cnlFbnRyaWVzLmxlbmd0aCAtIDE7IGkgPj0gMDsgLS1pKSB7XG4gICAgICAgIHZhciBlbnRyeSA9IHRoaXMudHJ5RW50cmllc1tpXTtcbiAgICAgICAgaWYgKGVudHJ5LnRyeUxvYyA8PSB0aGlzLnByZXYgJiZcbiAgICAgICAgICAgIGhhc093bi5jYWxsKGVudHJ5LCBcImZpbmFsbHlMb2NcIikgJiZcbiAgICAgICAgICAgIHRoaXMucHJldiA8IGVudHJ5LmZpbmFsbHlMb2MpIHtcbiAgICAgICAgICB2YXIgZmluYWxseUVudHJ5ID0gZW50cnk7XG4gICAgICAgICAgYnJlYWs7XG4gICAgICAgIH1cbiAgICAgIH1cblxuICAgICAgaWYgKGZpbmFsbHlFbnRyeSAmJlxuICAgICAgICAgICh0eXBlID09PSBcImJyZWFrXCIgfHxcbiAgICAgICAgICAgdHlwZSA9PT0gXCJjb250aW51ZVwiKSAmJlxuICAgICAgICAgIGZpbmFsbHlFbnRyeS50cnlMb2MgPD0gYXJnICYmXG4gICAgICAgICAgYXJnIDwgZmluYWxseUVudHJ5LmZpbmFsbHlMb2MpIHtcbiAgICAgICAgLy8gSWdub3JlIHRoZSBmaW5hbGx5IGVudHJ5IGlmIGNvbnRyb2wgaXMgbm90IGp1bXBpbmcgdG8gYVxuICAgICAgICAvLyBsb2NhdGlvbiBvdXRzaWRlIHRoZSB0cnkvY2F0Y2ggYmxvY2suXG4gICAgICAgIGZpbmFsbHlFbnRyeSA9IG51bGw7XG4gICAgICB9XG5cbiAgICAgIHZhciByZWNvcmQgPSBmaW5hbGx5RW50cnkgPyBmaW5hbGx5RW50cnkuY29tcGxldGlvbiA6IHt9O1xuICAgICAgcmVjb3JkLnR5cGUgPSB0eXBlO1xuICAgICAgcmVjb3JkLmFyZyA9IGFyZztcblxuICAgICAgaWYgKGZpbmFsbHlFbnRyeSkge1xuICAgICAgICB0aGlzLm5leHQgPSBmaW5hbGx5RW50cnkuZmluYWxseUxvYztcbiAgICAgIH0gZWxzZSB7XG4gICAgICAgIHRoaXMuY29tcGxldGUocmVjb3JkKTtcbiAgICAgIH1cblxuICAgICAgcmV0dXJuIENvbnRpbnVlU2VudGluZWw7XG4gICAgfSxcblxuICAgIGNvbXBsZXRlOiBmdW5jdGlvbihyZWNvcmQsIGFmdGVyTG9jKSB7XG4gICAgICBpZiAocmVjb3JkLnR5cGUgPT09IFwidGhyb3dcIikge1xuICAgICAgICB0aHJvdyByZWNvcmQuYXJnO1xuICAgICAgfVxuXG4gICAgICBpZiAocmVjb3JkLnR5cGUgPT09IFwiYnJlYWtcIiB8fFxuICAgICAgICAgIHJlY29yZC50eXBlID09PSBcImNvbnRpbnVlXCIpIHtcbiAgICAgICAgdGhpcy5uZXh0ID0gcmVjb3JkLmFyZztcbiAgICAgIH0gZWxzZSBpZiAocmVjb3JkLnR5cGUgPT09IFwicmV0dXJuXCIpIHtcbiAgICAgICAgdGhpcy5ydmFsID0gcmVjb3JkLmFyZztcbiAgICAgICAgdGhpcy5uZXh0ID0gXCJlbmRcIjtcbiAgICAgIH0gZWxzZSBpZiAocmVjb3JkLnR5cGUgPT09IFwibm9ybWFsXCIgJiYgYWZ0ZXJMb2MpIHtcbiAgICAgICAgdGhpcy5uZXh0ID0gYWZ0ZXJMb2M7XG4gICAgICB9XG5cbiAgICAgIHJldHVybiBDb250aW51ZVNlbnRpbmVsO1xuICAgIH0sXG5cbiAgICBmaW5pc2g6IGZ1bmN0aW9uKGZpbmFsbHlMb2MpIHtcbiAgICAgIGZvciAodmFyIGkgPSB0aGlzLnRyeUVudHJpZXMubGVuZ3RoIC0gMTsgaSA+PSAwOyAtLWkpIHtcbiAgICAgICAgdmFyIGVudHJ5ID0gdGhpcy50cnlFbnRyaWVzW2ldO1xuICAgICAgICBpZiAoZW50cnkuZmluYWxseUxvYyA9PT0gZmluYWxseUxvYykge1xuICAgICAgICAgIHJldHVybiB0aGlzLmNvbXBsZXRlKGVudHJ5LmNvbXBsZXRpb24sIGVudHJ5LmFmdGVyTG9jKTtcbiAgICAgICAgfVxuICAgICAgfVxuICAgIH0sXG5cbiAgICBcImNhdGNoXCI6IGZ1bmN0aW9uKHRyeUxvYykge1xuICAgICAgZm9yICh2YXIgaSA9IHRoaXMudHJ5RW50cmllcy5sZW5ndGggLSAxOyBpID49IDA7IC0taSkge1xuICAgICAgICB2YXIgZW50cnkgPSB0aGlzLnRyeUVudHJpZXNbaV07XG4gICAgICAgIGlmIChlbnRyeS50cnlMb2MgPT09IHRyeUxvYykge1xuICAgICAgICAgIHZhciByZWNvcmQgPSBlbnRyeS5jb21wbGV0aW9uO1xuICAgICAgICAgIGlmIChyZWNvcmQudHlwZSA9PT0gXCJ0aHJvd1wiKSB7XG4gICAgICAgICAgICB2YXIgdGhyb3duID0gcmVjb3JkLmFyZztcbiAgICAgICAgICAgIHJlc2V0VHJ5RW50cnkoZW50cnkpO1xuICAgICAgICAgIH1cbiAgICAgICAgICByZXR1cm4gdGhyb3duO1xuICAgICAgICB9XG4gICAgICB9XG5cbiAgICAgIC8vIFRoZSBjb250ZXh0LmNhdGNoIG1ldGhvZCBtdXN0IG9ubHkgYmUgY2FsbGVkIHdpdGggYSBsb2NhdGlvblxuICAgICAgLy8gYXJndW1lbnQgdGhhdCBjb3JyZXNwb25kcyB0byBhIGtub3duIGNhdGNoIGJsb2NrLlxuICAgICAgdGhyb3cgbmV3IEVycm9yKFwiaWxsZWdhbCBjYXRjaCBhdHRlbXB0XCIpO1xuICAgIH0sXG5cbiAgICBkZWxlZ2F0ZVlpZWxkOiBmdW5jdGlvbihpdGVyYWJsZSwgcmVzdWx0TmFtZSwgbmV4dExvYykge1xuICAgICAgdGhpcy5kZWxlZ2F0ZSA9IHtcbiAgICAgICAgaXRlcmF0b3I6IHZhbHVlcyhpdGVyYWJsZSksXG4gICAgICAgIHJlc3VsdE5hbWU6IHJlc3VsdE5hbWUsXG4gICAgICAgIG5leHRMb2M6IG5leHRMb2NcbiAgICAgIH07XG5cbiAgICAgIHJldHVybiBDb250aW51ZVNlbnRpbmVsO1xuICAgIH1cbiAgfTtcbn0pKFxuICAvLyBBbW9uZyB0aGUgdmFyaW91cyB0cmlja3MgZm9yIG9idGFpbmluZyBhIHJlZmVyZW5jZSB0byB0aGUgZ2xvYmFsXG4gIC8vIG9iamVjdCwgdGhpcyBzZWVtcyB0byBiZSB0aGUgbW9zdCByZWxpYWJsZSB0ZWNobmlxdWUgdGhhdCBkb2VzIG5vdFxuICAvLyB1c2UgaW5kaXJlY3QgZXZhbCAod2hpY2ggdmlvbGF0ZXMgQ29udGVudCBTZWN1cml0eSBQb2xpY3kpLlxuICB0eXBlb2YgZ2xvYmFsID09PSBcIm9iamVjdFwiID8gZ2xvYmFsIDpcbiAgdHlwZW9mIHdpbmRvdyA9PT0gXCJvYmplY3RcIiA/IHdpbmRvdyA6IHRoaXNcbik7XG5cbn0pLmNhbGwodGhpcyx0eXBlb2YgZ2xvYmFsICE9PSBcInVuZGVmaW5lZFwiID8gZ2xvYmFsIDogdHlwZW9mIHNlbGYgIT09IFwidW5kZWZpbmVkXCIgPyBzZWxmIDogdHlwZW9mIHdpbmRvdyAhPT0gXCJ1bmRlZmluZWRcIiA/IHdpbmRvdyA6IHt9KVxuLy8jIHNvdXJjZU1hcHBpbmdVUkw9ZGF0YTphcHBsaWNhdGlvbi9qc29uO2NoYXJzZXQ6dXRmLTg7YmFzZTY0LGV5SjJaWEp6YVc5dUlqb3pMQ0p6YjNWeVkyVnpJanBiSWk0dUwyNXZaR1ZmYlc5a2RXeGxjeTlpWVdKbGJDOXViMlJsWDIxdlpIVnNaWE12WW1GaVpXd3RZMjl5WlM5dWIyUmxYMjF2WkhWc1pYTXZjbVZuWlc1bGNtRjBiM0l0WW1GaVpXd3ZjblZ1ZEdsdFpTNXFjeUpkTENKdVlXMWxjeUk2VzEwc0ltMWhjSEJwYm1keklqb2lPMEZCUVVFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRTdRVUZEUVR0QlFVTkJPMEZCUTBFN1FVRkRRVHRCUVVOQk8wRkJRMEU3UVVGRFFUdEJRVU5CTzBGQlEwRWlMQ0ptYVd4bElqb2laMlZ1WlhKaGRHVmtMbXB6SWl3aWMyOTFjbU5sVW05dmRDSTZJaUlzSW5OdmRYSmpaWE5EYjI1MFpXNTBJanBiSWk4cUtseHVJQ29nUTI5d2VYSnBaMmgwSUNoaktTQXlNREUwTENCR1lXTmxZbTl2YXl3Z1NXNWpMbHh1SUNvZ1FXeHNJSEpwWjJoMGN5QnlaWE5sY25abFpDNWNiaUFxWEc0Z0tpQlVhR2x6SUhOdmRYSmpaU0JqYjJSbElHbHpJR3hwWTJWdWMyVmtJSFZ1WkdWeUlIUm9aU0JDVTBRdGMzUjViR1VnYkdsalpXNXpaU0JtYjNWdVpDQnBiaUIwYUdWY2JpQXFJR2gwZEhCek9pOHZjbUYzTG1kcGRHaDFZaTVqYjIwdlptRmpaV0p2YjJzdmNtVm5aVzVsY21GMGIzSXZiV0Z6ZEdWeUwweEpRMFZPVTBVZ1ptbHNaUzRnUVc1Y2JpQXFJR0ZrWkdsMGFXOXVZV3dnWjNKaGJuUWdiMllnY0dGMFpXNTBJSEpwWjJoMGN5QmpZVzRnWW1VZ1ptOTFibVFnYVc0Z2RHaGxJRkJCVkVWT1ZGTWdabWxzWlNCcGJseHVJQ29nZEdobElITmhiV1VnWkdseVpXTjBiM0o1TGx4dUlDb3ZYRzVjYmlFb1puVnVZM1JwYjI0b1oyeHZZbUZzS1NCN1hHNGdJRndpZFhObElITjBjbWxqZEZ3aU8xeHVYRzRnSUhaaGNpQm9ZWE5QZDI0Z1BTQlBZbXBsWTNRdWNISnZkRzkwZVhCbExtaGhjMDkzYmxCeWIzQmxjblI1TzF4dUlDQjJZWElnZFc1a1pXWnBibVZrT3lBdkx5Qk5iM0psSUdOdmJYQnlaWE56YVdKc1pTQjBhR0Z1SUhadmFXUWdNQzVjYmlBZ2RtRnlJR2wwWlhKaGRHOXlVM2x0WW05c0lEMWNiaUFnSUNCMGVYQmxiMllnVTNsdFltOXNJRDA5UFNCY0ltWjFibU4wYVc5dVhDSWdKaVlnVTNsdFltOXNMbWwwWlhKaGRHOXlJSHg4SUZ3aVFFQnBkR1Z5WVhSdmNsd2lPMXh1WEc0Z0lIWmhjaUJwYmsxdlpIVnNaU0E5SUhSNWNHVnZaaUJ0YjJSMWJHVWdQVDA5SUZ3aWIySnFaV04wWENJN1hHNGdJSFpoY2lCeWRXNTBhVzFsSUQwZ1oyeHZZbUZzTG5KbFoyVnVaWEpoZEc5eVVuVnVkR2x0WlR0Y2JpQWdhV1lnS0hKMWJuUnBiV1VwSUh0Y2JpQWdJQ0JwWmlBb2FXNU5iMlIxYkdVcElIdGNiaUFnSUNBZ0lDOHZJRWxtSUhKbFoyVnVaWEpoZEc5eVVuVnVkR2x0WlNCcGN5QmtaV1pwYm1Wa0lHZHNiMkpoYkd4NUlHRnVaQ0IzWlNkeVpTQnBiaUJoSUcxdlpIVnNaU3hjYmlBZ0lDQWdJQzh2SUcxaGEyVWdkR2hsSUdWNGNHOXlkSE1nYjJKcVpXTjBJR2xrWlc1MGFXTmhiQ0IwYnlCeVpXZGxibVZ5WVhSdmNsSjFiblJwYldVdVhHNGdJQ0FnSUNCdGIyUjFiR1V1Wlhod2IzSjBjeUE5SUhKMWJuUnBiV1U3WEc0Z0lDQWdmVnh1SUNBZ0lDOHZJRVJ2YmlkMElHSnZkR2hsY2lCbGRtRnNkV0YwYVc1bklIUm9aU0J5WlhOMElHOW1JSFJvYVhNZ1ptbHNaU0JwWmlCMGFHVWdjblZ1ZEdsdFpTQjNZWE5jYmlBZ0lDQXZMeUJoYkhKbFlXUjVJR1JsWm1sdVpXUWdaMnh2WW1Gc2JIa3VYRzRnSUNBZ2NtVjBkWEp1TzF4dUlDQjlYRzVjYmlBZ0x5OGdSR1ZtYVc1bElIUm9aU0J5ZFc1MGFXMWxJR2RzYjJKaGJHeDVJQ2hoY3lCbGVIQmxZM1JsWkNCaWVTQm5aVzVsY21GMFpXUWdZMjlrWlNrZ1lYTWdaV2wwYUdWeVhHNGdJQzh2SUcxdlpIVnNaUzVsZUhCdmNuUnpJQ2hwWmlCM1pTZHlaU0JwYmlCaElHMXZaSFZzWlNrZ2IzSWdZU0J1Wlhjc0lHVnRjSFI1SUc5aWFtVmpkQzVjYmlBZ2NuVnVkR2x0WlNBOUlHZHNiMkpoYkM1eVpXZGxibVZ5WVhSdmNsSjFiblJwYldVZ1BTQnBiazF2WkhWc1pTQS9JRzF2WkhWc1pTNWxlSEJ2Y25SeklEb2dlMzA3WEc1Y2JpQWdablZ1WTNScGIyNGdkM0poY0NocGJtNWxja1p1TENCdmRYUmxja1p1TENCelpXeG1MQ0IwY25sTWIyTnpUR2x6ZENrZ2UxeHVJQ0FnSUhKbGRIVnliaUJ1WlhjZ1IyVnVaWEpoZEc5eUtHbHVibVZ5Um00c0lHOTFkR1Z5Um00c0lITmxiR1lnZkh3Z2JuVnNiQ3dnZEhKNVRHOWpjMHhwYzNRZ2ZId2dXMTBwTzF4dUlDQjlYRzRnSUhKMWJuUnBiV1V1ZDNKaGNDQTlJSGR5WVhBN1hHNWNiaUFnTHk4Z1ZISjVMMk5oZEdOb0lHaGxiSEJsY2lCMGJ5QnRhVzVwYldsNlpTQmtaVzl3ZEdsdGFYcGhkR2x2Ym5NdUlGSmxkSFZ5Ym5NZ1lTQmpiMjF3YkdWMGFXOXVYRzRnSUM4dklISmxZMjl5WkNCc2FXdGxJR052Ym5SbGVIUXVkSEo1Ulc1MGNtbGxjMXRwWFM1amIyMXdiR1YwYVc5dUxpQlVhR2x6SUdsdWRHVnlabUZqWlNCamIzVnNaRnh1SUNBdkx5Qm9ZWFpsSUdKbFpXNGdLR0Z1WkNCM1lYTWdjSEpsZG1sdmRYTnNlU2tnWkdWemFXZHVaV1FnZEc4Z2RHRnJaU0JoSUdOc2IzTjFjbVVnZEc4Z1ltVmNiaUFnTHk4Z2FXNTJiMnRsWkNCM2FYUm9iM1YwSUdGeVozVnRaVzUwY3l3Z1luVjBJR2x1SUdGc2JDQjBhR1VnWTJGelpYTWdkMlVnWTJGeVpTQmhZbTkxZENCM1pWeHVJQ0F2THlCaGJISmxZV1I1SUdoaGRtVWdZVzRnWlhocGMzUnBibWNnYldWMGFHOWtJSGRsSUhkaGJuUWdkRzhnWTJGc2JDd2djMjhnZEdobGNtVW5jeUJ1YnlCdVpXVmtYRzRnSUM4dklIUnZJR055WldGMFpTQmhJRzVsZHlCbWRXNWpkR2x2YmlCdlltcGxZM1F1SUZkbElHTmhiaUJsZG1WdUlHZGxkQ0JoZDJGNUlIZHBkR2dnWVhOemRXMXBibWRjYmlBZ0x5OGdkR2hsSUcxbGRHaHZaQ0IwWVd0bGN5QmxlR0ZqZEd4NUlHOXVaU0JoY21kMWJXVnVkQ3dnYzJsdVkyVWdkR2hoZENCb1lYQndaVzV6SUhSdklHSmxJSFJ5ZFdWY2JpQWdMeThnYVc0Z1pYWmxjbmtnWTJGelpTd2djMjhnZDJVZ1pHOXVKM1FnYUdGMlpTQjBieUIwYjNWamFDQjBhR1VnWVhKbmRXMWxiblJ6SUc5aWFtVmpkQzRnVkdobFhHNGdJQzh2SUc5dWJIa2dZV1JrYVhScGIyNWhiQ0JoYkd4dlkyRjBhVzl1SUhKbGNYVnBjbVZrSUdseklIUm9aU0JqYjIxd2JHVjBhVzl1SUhKbFkyOXlaQ3dnZDJocFkyaGNiaUFnTHk4Z2FHRnpJR0VnYzNSaFlteGxJSE5vWVhCbElHRnVaQ0J6YnlCb2IzQmxablZzYkhrZ2MyaHZkV3hrSUdKbElHTm9aV0Z3SUhSdklHRnNiRzlqWVhSbExseHVJQ0JtZFc1amRHbHZiaUIwY25sRFlYUmphQ2htYml3Z2IySnFMQ0JoY21jcElIdGNiaUFnSUNCMGNua2dlMXh1SUNBZ0lDQWdjbVYwZFhKdUlIc2dkSGx3WlRvZ1hDSnViM0p0WVd4Y0lpd2dZWEpuT2lCbWJpNWpZV3hzS0c5aWFpd2dZWEpuS1NCOU8xeHVJQ0FnSUgwZ1kyRjBZMmdnS0dWeWNpa2dlMXh1SUNBZ0lDQWdjbVYwZFhKdUlIc2dkSGx3WlRvZ1hDSjBhSEp2ZDF3aUxDQmhjbWM2SUdWeWNpQjlPMXh1SUNBZ0lIMWNiaUFnZlZ4dVhHNGdJSFpoY2lCSFpXNVRkR0YwWlZOMWMzQmxibVJsWkZOMFlYSjBJRDBnWENKemRYTndaVzVrWldSVGRHRnlkRndpTzF4dUlDQjJZWElnUjJWdVUzUmhkR1ZUZFhOd1pXNWtaV1JaYVdWc1pDQTlJRndpYzNWemNHVnVaR1ZrV1dsbGJHUmNJanRjYmlBZ2RtRnlJRWRsYmxOMFlYUmxSWGhsWTNWMGFXNW5JRDBnWENKbGVHVmpkWFJwYm1kY0lqdGNiaUFnZG1GeUlFZGxibE4wWVhSbFEyOXRjR3hsZEdWa0lEMGdYQ0pqYjIxd2JHVjBaV1JjSWp0Y2JseHVJQ0F2THlCU1pYUjFjbTVwYm1jZ2RHaHBjeUJ2WW1wbFkzUWdabkp2YlNCMGFHVWdhVzV1WlhKR2JpQm9ZWE1nZEdobElITmhiV1VnWldabVpXTjBJR0Z6WEc0Z0lDOHZJR0p5WldGcmFXNW5JRzkxZENCdlppQjBhR1VnWkdsemNHRjBZMmdnYzNkcGRHTm9JSE4wWVhSbGJXVnVkQzVjYmlBZ2RtRnlJRU52Ym5ScGJuVmxVMlZ1ZEdsdVpXd2dQU0I3ZlR0Y2JseHVJQ0F2THlCRWRXMXRlU0JqYjI1emRISjFZM1J2Y2lCbWRXNWpkR2x2Ym5NZ2RHaGhkQ0IzWlNCMWMyVWdZWE1nZEdobElDNWpiMjV6ZEhKMVkzUnZjaUJoYm1SY2JpQWdMeThnTG1OdmJuTjBjblZqZEc5eUxuQnliM1J2ZEhsd1pTQndjbTl3WlhKMGFXVnpJR1p2Y2lCbWRXNWpkR2x2Ym5NZ2RHaGhkQ0J5WlhSMWNtNGdSMlZ1WlhKaGRHOXlYRzRnSUM4dklHOWlhbVZqZEhNdUlFWnZjaUJtZFd4c0lITndaV01nWTI5dGNHeHBZVzVqWlN3Z2VXOTFJRzFoZVNCM2FYTm9JSFJ2SUdOdmJtWnBaM1Z5WlNCNWIzVnlYRzRnSUM4dklHMXBibWxtYVdWeUlHNXZkQ0IwYnlCdFlXNW5iR1VnZEdobElHNWhiV1Z6SUc5bUlIUm9aWE5sSUhSM2J5Qm1kVzVqZEdsdmJuTXVYRzRnSUdaMWJtTjBhVzl1SUVkbGJtVnlZWFJ2Y2taMWJtTjBhVzl1S0NrZ2UzMWNiaUFnWm5WdVkzUnBiMjRnUjJWdVpYSmhkRzl5Um5WdVkzUnBiMjVRY205MGIzUjVjR1VvS1NCN2ZWeHVYRzRnSUhaaGNpQkhjQ0E5SUVkbGJtVnlZWFJ2Y2taMWJtTjBhVzl1VUhKdmRHOTBlWEJsTG5CeWIzUnZkSGx3WlNBOUlFZGxibVZ5WVhSdmNpNXdjbTkwYjNSNWNHVTdYRzRnSUVkbGJtVnlZWFJ2Y2taMWJtTjBhVzl1TG5CeWIzUnZkSGx3WlNBOUlFZHdMbU52Ym5OMGNuVmpkRzl5SUQwZ1IyVnVaWEpoZEc5eVJuVnVZM1JwYjI1UWNtOTBiM1I1Y0dVN1hHNGdJRWRsYm1WeVlYUnZja1oxYm1OMGFXOXVVSEp2ZEc5MGVYQmxMbU52Ym5OMGNuVmpkRzl5SUQwZ1IyVnVaWEpoZEc5eVJuVnVZM1JwYjI0N1hHNGdJRWRsYm1WeVlYUnZja1oxYm1OMGFXOXVMbVJwYzNCc1lYbE9ZVzFsSUQwZ1hDSkhaVzVsY21GMGIzSkdkVzVqZEdsdmJsd2lPMXh1WEc0Z0lISjFiblJwYldVdWFYTkhaVzVsY21GMGIzSkdkVzVqZEdsdmJpQTlJR1oxYm1OMGFXOXVLR2RsYmtaMWJpa2dlMXh1SUNBZ0lIWmhjaUJqZEc5eUlEMGdkSGx3Wlc5bUlHZGxia1oxYmlBOVBUMGdYQ0ptZFc1amRHbHZibHdpSUNZbUlHZGxia1oxYmk1amIyNXpkSEoxWTNSdmNqdGNiaUFnSUNCeVpYUjFjbTRnWTNSdmNseHVJQ0FnSUNBZ1B5QmpkRzl5SUQwOVBTQkhaVzVsY21GMGIzSkdkVzVqZEdsdmJpQjhmRnh1SUNBZ0lDQWdJQ0F2THlCR2IzSWdkR2hsSUc1aGRHbDJaU0JIWlc1bGNtRjBiM0pHZFc1amRHbHZiaUJqYjI1emRISjFZM1J2Y2l3Z2RHaGxJR0psYzNRZ2QyVWdZMkZ1WEc0Z0lDQWdJQ0FnSUM4dklHUnZJR2x6SUhSdklHTm9aV05ySUdsMGN5QXVibUZ0WlNCd2NtOXdaWEowZVM1Y2JpQWdJQ0FnSUNBZ0tHTjBiM0l1WkdsemNHeGhlVTVoYldVZ2ZId2dZM1J2Y2k1dVlXMWxLU0E5UFQwZ1hDSkhaVzVsY21GMGIzSkdkVzVqZEdsdmJsd2lYRzRnSUNBZ0lDQTZJR1poYkhObE8xeHVJQ0I5TzF4dVhHNGdJSEoxYm5ScGJXVXViV0Z5YXlBOUlHWjFibU4wYVc5dUtHZGxia1oxYmlrZ2UxeHVJQ0FnSUdkbGJrWjFiaTVmWDNCeWIzUnZYMThnUFNCSFpXNWxjbUYwYjNKR2RXNWpkR2x2YmxCeWIzUnZkSGx3WlR0Y2JpQWdJQ0JuWlc1R2RXNHVjSEp2ZEc5MGVYQmxJRDBnVDJKcVpXTjBMbU55WldGMFpTaEhjQ2s3WEc0Z0lDQWdjbVYwZFhKdUlHZGxia1oxYmp0Y2JpQWdmVHRjYmx4dUlDQnlkVzUwYVcxbExtRnplVzVqSUQwZ1puVnVZM1JwYjI0b2FXNXVaWEpHYml3Z2IzVjBaWEpHYml3Z2MyVnNaaXdnZEhKNVRHOWpjMHhwYzNRcElIdGNiaUFnSUNCeVpYUjFjbTRnYm1WM0lGQnliMjFwYzJVb1puVnVZM1JwYjI0b2NtVnpiMngyWlN3Z2NtVnFaV04wS1NCN1hHNGdJQ0FnSUNCMllYSWdaMlZ1WlhKaGRHOXlJRDBnZDNKaGNDaHBibTVsY2tadUxDQnZkWFJsY2tadUxDQnpaV3htTENCMGNubE1iMk56VEdsemRDazdYRzRnSUNBZ0lDQjJZWElnWTJGc2JFNWxlSFFnUFNCemRHVndMbUpwYm1Rb1oyVnVaWEpoZEc5eUxtNWxlSFFwTzF4dUlDQWdJQ0FnZG1GeUlHTmhiR3hVYUhKdmR5QTlJSE4wWlhBdVltbHVaQ2huWlc1bGNtRjBiM0piWENKMGFISnZkMXdpWFNrN1hHNWNiaUFnSUNBZ0lHWjFibU4wYVc5dUlITjBaWEFvWVhKbktTQjdYRzRnSUNBZ0lDQWdJSFpoY2lCeVpXTnZjbVFnUFNCMGNubERZWFJqYUNoMGFHbHpMQ0J1ZFd4c0xDQmhjbWNwTzF4dUlDQWdJQ0FnSUNCcFppQW9jbVZqYjNKa0xuUjVjR1VnUFQwOUlGd2lkR2h5YjNkY0lpa2dlMXh1SUNBZ0lDQWdJQ0FnSUhKbGFtVmpkQ2h5WldOdmNtUXVZWEpuS1R0Y2JpQWdJQ0FnSUNBZ0lDQnlaWFIxY200N1hHNGdJQ0FnSUNBZ0lIMWNibHh1SUNBZ0lDQWdJQ0IyWVhJZ2FXNW1ieUE5SUhKbFkyOXlaQzVoY21jN1hHNGdJQ0FnSUNBZ0lHbG1JQ2hwYm1adkxtUnZibVVwSUh0Y2JpQWdJQ0FnSUNBZ0lDQnlaWE52YkhabEtHbHVabTh1ZG1Gc2RXVXBPMXh1SUNBZ0lDQWdJQ0I5SUdWc2MyVWdlMXh1SUNBZ0lDQWdJQ0FnSUZCeWIyMXBjMlV1Y21WemIyeDJaU2hwYm1adkxuWmhiSFZsS1M1MGFHVnVLR05oYkd4T1pYaDBMQ0JqWVd4c1ZHaHliM2NwTzF4dUlDQWdJQ0FnSUNCOVhHNGdJQ0FnSUNCOVhHNWNiaUFnSUNBZ0lHTmhiR3hPWlhoMEtDazdYRzRnSUNBZ2ZTazdYRzRnSUgwN1hHNWNiaUFnWm5WdVkzUnBiMjRnUjJWdVpYSmhkRzl5S0dsdWJtVnlSbTRzSUc5MWRHVnlSbTRzSUhObGJHWXNJSFJ5ZVV4dlkzTk1hWE4wS1NCN1hHNGdJQ0FnZG1GeUlHZGxibVZ5WVhSdmNpQTlJRzkxZEdWeVJtNGdQeUJQWW1wbFkzUXVZM0psWVhSbEtHOTFkR1Z5Um00dWNISnZkRzkwZVhCbEtTQTZJSFJvYVhNN1hHNGdJQ0FnZG1GeUlHTnZiblJsZUhRZ1BTQnVaWGNnUTI5dWRHVjRkQ2gwY25sTWIyTnpUR2x6ZENrN1hHNGdJQ0FnZG1GeUlITjBZWFJsSUQwZ1IyVnVVM1JoZEdWVGRYTndaVzVrWldSVGRHRnlkRHRjYmx4dUlDQWdJR1oxYm1OMGFXOXVJR2x1ZG05clpTaHRaWFJvYjJRc0lHRnlaeWtnZTF4dUlDQWdJQ0FnYVdZZ0tITjBZWFJsSUQwOVBTQkhaVzVUZEdGMFpVVjRaV04xZEdsdVp5a2dlMXh1SUNBZ0lDQWdJQ0IwYUhKdmR5QnVaWGNnUlhKeWIzSW9YQ0pIWlc1bGNtRjBiM0lnYVhNZ1lXeHlaV0ZrZVNCeWRXNXVhVzVuWENJcE8xeHVJQ0FnSUNBZ2ZWeHVYRzRnSUNBZ0lDQnBaaUFvYzNSaGRHVWdQVDA5SUVkbGJsTjBZWFJsUTI5dGNHeGxkR1ZrS1NCN1hHNGdJQ0FnSUNBZ0lDOHZJRUpsSUdadmNtZHBkbWx1Wnl3Z2NHVnlJREkxTGpNdU15NHpMak1nYjJZZ2RHaGxJSE53WldNNlhHNGdJQ0FnSUNBZ0lDOHZJR2gwZEhCek9pOHZjR1Z2Y0d4bExtMXZlbWxzYkdFdWIzSm5MMzVxYjNKbGJtUnZjbVptTDJWek5pMWtjbUZtZEM1b2RHMXNJM05sWXkxblpXNWxjbUYwYjNKeVpYTjFiV1ZjYmlBZ0lDQWdJQ0FnY21WMGRYSnVJR1J2Ym1WU1pYTjFiSFFvS1R0Y2JpQWdJQ0FnSUgxY2JseHVJQ0FnSUNBZ2QyaHBiR1VnS0hSeWRXVXBJSHRjYmlBZ0lDQWdJQ0FnZG1GeUlHUmxiR1ZuWVhSbElEMGdZMjl1ZEdWNGRDNWtaV3hsWjJGMFpUdGNiaUFnSUNBZ0lDQWdhV1lnS0dSbGJHVm5ZWFJsS1NCN1hHNGdJQ0FnSUNBZ0lDQWdkbUZ5SUhKbFkyOXlaQ0E5SUhSeWVVTmhkR05vS0Z4dUlDQWdJQ0FnSUNBZ0lDQWdaR1ZzWldkaGRHVXVhWFJsY21GMGIzSmJiV1YwYUc5a1hTeGNiaUFnSUNBZ0lDQWdJQ0FnSUdSbGJHVm5ZWFJsTG1sMFpYSmhkRzl5TEZ4dUlDQWdJQ0FnSUNBZ0lDQWdZWEpuWEc0Z0lDQWdJQ0FnSUNBZ0tUdGNibHh1SUNBZ0lDQWdJQ0FnSUdsbUlDaHlaV052Y21RdWRIbHdaU0E5UFQwZ1hDSjBhSEp2ZDF3aUtTQjdYRzRnSUNBZ0lDQWdJQ0FnSUNCamIyNTBaWGgwTG1SbGJHVm5ZWFJsSUQwZ2JuVnNiRHRjYmx4dUlDQWdJQ0FnSUNBZ0lDQWdMeThnVEdsclpTQnlaWFIxY201cGJtY2daMlZ1WlhKaGRHOXlMblJvY205M0tIVnVZMkYxWjJoMEtTd2dZblYwSUhkcGRHaHZkWFFnZEdobFhHNGdJQ0FnSUNBZ0lDQWdJQ0F2THlCdmRtVnlhR1ZoWkNCdlppQmhiaUJsZUhSeVlTQm1kVzVqZEdsdmJpQmpZV3hzTGx4dUlDQWdJQ0FnSUNBZ0lDQWdiV1YwYUc5a0lEMGdYQ0owYUhKdmQxd2lPMXh1SUNBZ0lDQWdJQ0FnSUNBZ1lYSm5JRDBnY21WamIzSmtMbUZ5Wnp0Y2JseHVJQ0FnSUNBZ0lDQWdJQ0FnWTI5dWRHbHVkV1U3WEc0Z0lDQWdJQ0FnSUNBZ2ZWeHVYRzRnSUNBZ0lDQWdJQ0FnTHk4Z1JHVnNaV2RoZEdVZ1oyVnVaWEpoZEc5eUlISmhiaUJoYm1RZ2FHRnVaR3hsWkNCcGRITWdiM2R1SUdWNFkyVndkR2x2Ym5NZ2MyOWNiaUFnSUNBZ0lDQWdJQ0F2THlCeVpXZGhjbVJzWlhOeklHOW1JSGRvWVhRZ2RHaGxJRzFsZEdodlpDQjNZWE1zSUhkbElHTnZiblJwYm5WbElHRnpJR2xtSUdsMElHbHpYRzRnSUNBZ0lDQWdJQ0FnTHk4Z1hDSnVaWGgwWENJZ2QybDBhQ0JoYmlCMWJtUmxabWx1WldRZ1lYSm5MbHh1SUNBZ0lDQWdJQ0FnSUcxbGRHaHZaQ0E5SUZ3aWJtVjRkRndpTzF4dUlDQWdJQ0FnSUNBZ0lHRnlaeUE5SUhWdVpHVm1hVzVsWkR0Y2JseHVJQ0FnSUNBZ0lDQWdJSFpoY2lCcGJtWnZJRDBnY21WamIzSmtMbUZ5Wnp0Y2JpQWdJQ0FnSUNBZ0lDQnBaaUFvYVc1bWJ5NWtiMjVsS1NCN1hHNGdJQ0FnSUNBZ0lDQWdJQ0JqYjI1MFpYaDBXMlJsYkdWbllYUmxMbkpsYzNWc2RFNWhiV1ZkSUQwZ2FXNW1ieTUyWVd4MVpUdGNiaUFnSUNBZ0lDQWdJQ0FnSUdOdmJuUmxlSFF1Ym1WNGRDQTlJR1JsYkdWbllYUmxMbTVsZUhSTWIyTTdYRzRnSUNBZ0lDQWdJQ0FnZlNCbGJITmxJSHRjYmlBZ0lDQWdJQ0FnSUNBZ0lITjBZWFJsSUQwZ1IyVnVVM1JoZEdWVGRYTndaVzVrWldSWmFXVnNaRHRjYmlBZ0lDQWdJQ0FnSUNBZ0lISmxkSFZ5YmlCcGJtWnZPMXh1SUNBZ0lDQWdJQ0FnSUgxY2JseHVJQ0FnSUNBZ0lDQWdJR052Ym5SbGVIUXVaR1ZzWldkaGRHVWdQU0J1ZFd4c08xeHVJQ0FnSUNBZ0lDQjlYRzVjYmlBZ0lDQWdJQ0FnYVdZZ0tHMWxkR2h2WkNBOVBUMGdYQ0p1WlhoMFhDSXBJSHRjYmlBZ0lDQWdJQ0FnSUNCcFppQW9jM1JoZEdVZ1BUMDlJRWRsYmxOMFlYUmxVM1Z6Y0dWdVpHVmtVM1JoY25RZ0ppWmNiaUFnSUNBZ0lDQWdJQ0FnSUNBZ2RIbHdaVzltSUdGeVp5QWhQVDBnWENKMWJtUmxabWx1WldSY0lpa2dlMXh1SUNBZ0lDQWdJQ0FnSUNBZ0x5OGdhSFIwY0hNNkx5OXdaVzl3YkdVdWJXOTZhV3hzWVM1dmNtY3ZmbXB2Y21WdVpHOXlabVl2WlhNMkxXUnlZV1owTG1oMGJXd2pjMlZqTFdkbGJtVnlZWFJ2Y25KbGMzVnRaVnh1SUNBZ0lDQWdJQ0FnSUNBZ2RHaHliM2NnYm1WM0lGUjVjR1ZGY25KdmNpaGNiaUFnSUNBZ0lDQWdJQ0FnSUNBZ1hDSmhkSFJsYlhCMElIUnZJSE5sYm1RZ1hDSWdLeUJLVTA5T0xuTjBjbWx1WjJsbWVTaGhjbWNwSUNzZ1hDSWdkRzhnYm1WM1ltOXliaUJuWlc1bGNtRjBiM0pjSWx4dUlDQWdJQ0FnSUNBZ0lDQWdLVHRjYmlBZ0lDQWdJQ0FnSUNCOVhHNWNiaUFnSUNBZ0lDQWdJQ0JwWmlBb2MzUmhkR1VnUFQwOUlFZGxibE4wWVhSbFUzVnpjR1Z1WkdWa1dXbGxiR1FwSUh0Y2JpQWdJQ0FnSUNBZ0lDQWdJR052Ym5SbGVIUXVjMlZ1ZENBOUlHRnlaenRjYmlBZ0lDQWdJQ0FnSUNCOUlHVnNjMlVnZTF4dUlDQWdJQ0FnSUNBZ0lDQWdaR1ZzWlhSbElHTnZiblJsZUhRdWMyVnVkRHRjYmlBZ0lDQWdJQ0FnSUNCOVhHNWNiaUFnSUNBZ0lDQWdmU0JsYkhObElHbG1JQ2h0WlhSb2IyUWdQVDA5SUZ3aWRHaHliM2RjSWlrZ2UxeHVJQ0FnSUNBZ0lDQWdJR2xtSUNoemRHRjBaU0E5UFQwZ1IyVnVVM1JoZEdWVGRYTndaVzVrWldSVGRHRnlkQ2tnZTF4dUlDQWdJQ0FnSUNBZ0lDQWdjM1JoZEdVZ1BTQkhaVzVUZEdGMFpVTnZiWEJzWlhSbFpEdGNiaUFnSUNBZ0lDQWdJQ0FnSUhSb2NtOTNJR0Z5Wnp0Y2JpQWdJQ0FnSUNBZ0lDQjlYRzVjYmlBZ0lDQWdJQ0FnSUNCcFppQW9ZMjl1ZEdWNGRDNWthWE53WVhSamFFVjRZMlZ3ZEdsdmJpaGhjbWNwS1NCN1hHNGdJQ0FnSUNBZ0lDQWdJQ0F2THlCSlppQjBhR1VnWkdsemNHRjBZMmhsWkNCbGVHTmxjSFJwYjI0Z2QyRnpJR05oZFdkb2RDQmllU0JoSUdOaGRHTm9JR0pzYjJOckxGeHVJQ0FnSUNBZ0lDQWdJQ0FnTHk4Z2RHaGxiaUJzWlhRZ2RHaGhkQ0JqWVhSamFDQmliRzlqYXlCb1lXNWtiR1VnZEdobElHVjRZMlZ3ZEdsdmJpQnViM0p0WVd4c2VTNWNiaUFnSUNBZ0lDQWdJQ0FnSUcxbGRHaHZaQ0E5SUZ3aWJtVjRkRndpTzF4dUlDQWdJQ0FnSUNBZ0lDQWdZWEpuSUQwZ2RXNWtaV1pwYm1Wa08xeHVJQ0FnSUNBZ0lDQWdJSDFjYmx4dUlDQWdJQ0FnSUNCOUlHVnNjMlVnYVdZZ0tHMWxkR2h2WkNBOVBUMGdYQ0p5WlhSMWNtNWNJaWtnZTF4dUlDQWdJQ0FnSUNBZ0lHTnZiblJsZUhRdVlXSnlkWEIwS0Z3aWNtVjBkWEp1WENJc0lHRnlaeWs3WEc0Z0lDQWdJQ0FnSUgxY2JseHVJQ0FnSUNBZ0lDQnpkR0YwWlNBOUlFZGxibE4wWVhSbFJYaGxZM1YwYVc1bk8xeHVYRzRnSUNBZ0lDQWdJSFpoY2lCeVpXTnZjbVFnUFNCMGNubERZWFJqYUNocGJtNWxja1p1TENCelpXeG1MQ0JqYjI1MFpYaDBLVHRjYmlBZ0lDQWdJQ0FnYVdZZ0tISmxZMjl5WkM1MGVYQmxJRDA5UFNCY0ltNXZjbTFoYkZ3aUtTQjdYRzRnSUNBZ0lDQWdJQ0FnTHk4Z1NXWWdZVzRnWlhoalpYQjBhVzl1SUdseklIUm9jbTkzYmlCbWNtOXRJR2x1Ym1WeVJtNHNJSGRsSUd4bFlYWmxJSE4wWVhSbElEMDlQVnh1SUNBZ0lDQWdJQ0FnSUM4dklFZGxibE4wWVhSbFJYaGxZM1YwYVc1bklHRnVaQ0JzYjI5d0lHSmhZMnNnWm05eUlHRnViM1JvWlhJZ2FXNTJiMk5oZEdsdmJpNWNiaUFnSUNBZ0lDQWdJQ0J6ZEdGMFpTQTlJR052Ym5SbGVIUXVaRzl1WlZ4dUlDQWdJQ0FnSUNBZ0lDQWdQeUJIWlc1VGRHRjBaVU52YlhCc1pYUmxaRnh1SUNBZ0lDQWdJQ0FnSUNBZ09pQkhaVzVUZEdGMFpWTjFjM0JsYm1SbFpGbHBaV3hrTzF4dVhHNGdJQ0FnSUNBZ0lDQWdkbUZ5SUdsdVptOGdQU0I3WEc0Z0lDQWdJQ0FnSUNBZ0lDQjJZV3gxWlRvZ2NtVmpiM0prTG1GeVp5eGNiaUFnSUNBZ0lDQWdJQ0FnSUdSdmJtVTZJR052Ym5SbGVIUXVaRzl1WlZ4dUlDQWdJQ0FnSUNBZ0lIMDdYRzVjYmlBZ0lDQWdJQ0FnSUNCcFppQW9jbVZqYjNKa0xtRnlaeUE5UFQwZ1EyOXVkR2x1ZFdWVFpXNTBhVzVsYkNrZ2UxeHVJQ0FnSUNBZ0lDQWdJQ0FnYVdZZ0tHTnZiblJsZUhRdVpHVnNaV2RoZEdVZ0ppWWdiV1YwYUc5a0lEMDlQU0JjSW01bGVIUmNJaWtnZTF4dUlDQWdJQ0FnSUNBZ0lDQWdJQ0F2THlCRVpXeHBZbVZ5WVhSbGJIa2dabTl5WjJWMElIUm9aU0JzWVhOMElITmxiblFnZG1Gc2RXVWdjMjhnZEdoaGRDQjNaU0JrYjI0bmRGeHVJQ0FnSUNBZ0lDQWdJQ0FnSUNBdkx5QmhZMk5wWkdWdWRHRnNiSGtnY0dGemN5QnBkQ0J2YmlCMGJ5QjBhR1VnWkdWc1pXZGhkR1V1WEc0Z0lDQWdJQ0FnSUNBZ0lDQWdJR0Z5WnlBOUlIVnVaR1ZtYVc1bFpEdGNiaUFnSUNBZ0lDQWdJQ0FnSUgxY2JpQWdJQ0FnSUNBZ0lDQjlJR1ZzYzJVZ2UxeHVJQ0FnSUNBZ0lDQWdJQ0FnY21WMGRYSnVJR2x1Wm04N1hHNGdJQ0FnSUNBZ0lDQWdmVnh1WEc0Z0lDQWdJQ0FnSUgwZ1pXeHpaU0JwWmlBb2NtVmpiM0prTG5SNWNHVWdQVDA5SUZ3aWRHaHliM2RjSWlrZ2UxeHVJQ0FnSUNBZ0lDQWdJSE4wWVhSbElEMGdSMlZ1VTNSaGRHVkRiMjF3YkdWMFpXUTdYRzVjYmlBZ0lDQWdJQ0FnSUNCcFppQW9iV1YwYUc5a0lEMDlQU0JjSW01bGVIUmNJaWtnZTF4dUlDQWdJQ0FnSUNBZ0lDQWdZMjl1ZEdWNGRDNWthWE53WVhSamFFVjRZMlZ3ZEdsdmJpaHlaV052Y21RdVlYSm5LVHRjYmlBZ0lDQWdJQ0FnSUNCOUlHVnNjMlVnZTF4dUlDQWdJQ0FnSUNBZ0lDQWdZWEpuSUQwZ2NtVmpiM0prTG1GeVp6dGNiaUFnSUNBZ0lDQWdJQ0I5WEc0Z0lDQWdJQ0FnSUgxY2JpQWdJQ0FnSUgxY2JpQWdJQ0I5WEc1Y2JpQWdJQ0JuWlc1bGNtRjBiM0l1Ym1WNGRDQTlJR2x1ZG05clpTNWlhVzVrS0dkbGJtVnlZWFJ2Y2l3Z1hDSnVaWGgwWENJcE8xeHVJQ0FnSUdkbGJtVnlZWFJ2Y2x0Y0luUm9jbTkzWENKZElEMGdhVzUyYjJ0bExtSnBibVFvWjJWdVpYSmhkRzl5TENCY0luUm9jbTkzWENJcE8xeHVJQ0FnSUdkbGJtVnlZWFJ2Y2x0Y0luSmxkSFZ5Ymx3aVhTQTlJR2x1ZG05clpTNWlhVzVrS0dkbGJtVnlZWFJ2Y2l3Z1hDSnlaWFIxY201Y0lpazdYRzVjYmlBZ0lDQnlaWFIxY200Z1oyVnVaWEpoZEc5eU8xeHVJQ0I5WEc1Y2JpQWdSM0JiYVhSbGNtRjBiM0pUZVcxaWIyeGRJRDBnWm5WdVkzUnBiMjRvS1NCN1hHNGdJQ0FnY21WMGRYSnVJSFJvYVhNN1hHNGdJSDA3WEc1Y2JpQWdSM0F1ZEc5VGRISnBibWNnUFNCbWRXNWpkR2x2YmlncElIdGNiaUFnSUNCeVpYUjFjbTRnWENKYmIySnFaV04wSUVkbGJtVnlZWFJ2Y2wxY0lqdGNiaUFnZlR0Y2JseHVJQ0JtZFc1amRHbHZiaUJ3ZFhOb1ZISjVSVzUwY25rb2JHOWpjeWtnZTF4dUlDQWdJSFpoY2lCbGJuUnllU0E5SUhzZ2RISjVURzlqT2lCc2IyTnpXekJkSUgwN1hHNWNiaUFnSUNCcFppQW9NU0JwYmlCc2IyTnpLU0I3WEc0Z0lDQWdJQ0JsYm5SeWVTNWpZWFJqYUV4dll5QTlJR3h2WTNOYk1WMDdYRzRnSUNBZ2ZWeHVYRzRnSUNBZ2FXWWdLRElnYVc0Z2JHOWpjeWtnZTF4dUlDQWdJQ0FnWlc1MGNua3VabWx1WVd4c2VVeHZZeUE5SUd4dlkzTmJNbDA3WEc0Z0lDQWdJQ0JsYm5SeWVTNWhablJsY2t4dll5QTlJR3h2WTNOYk0xMDdYRzRnSUNBZ2ZWeHVYRzRnSUNBZ2RHaHBjeTUwY25sRmJuUnlhV1Z6TG5CMWMyZ29aVzUwY25rcE8xeHVJQ0I5WEc1Y2JpQWdablZ1WTNScGIyNGdjbVZ6WlhSVWNubEZiblJ5ZVNobGJuUnllU2tnZTF4dUlDQWdJSFpoY2lCeVpXTnZjbVFnUFNCbGJuUnllUzVqYjIxd2JHVjBhVzl1SUh4OElIdDlPMXh1SUNBZ0lISmxZMjl5WkM1MGVYQmxJRDBnWENKdWIzSnRZV3hjSWp0Y2JpQWdJQ0JrWld4bGRHVWdjbVZqYjNKa0xtRnlaenRjYmlBZ0lDQmxiblJ5ZVM1amIyMXdiR1YwYVc5dUlEMGdjbVZqYjNKa08xeHVJQ0I5WEc1Y2JpQWdablZ1WTNScGIyNGdRMjl1ZEdWNGRDaDBjbmxNYjJOelRHbHpkQ2tnZTF4dUlDQWdJQzh2SUZSb1pTQnliMjkwSUdWdWRISjVJRzlpYW1WamRDQW9aV1ptWldOMGFYWmxiSGtnWVNCMGNua2djM1JoZEdWdFpXNTBJSGRwZEdodmRYUWdZU0JqWVhSamFGeHVJQ0FnSUM4dklHOXlJR0VnWm1sdVlXeHNlU0JpYkc5amF5a2daMmwyWlhNZ2RYTWdZU0J3YkdGalpTQjBieUJ6ZEc5eVpTQjJZV3gxWlhNZ2RHaHliM2R1SUdaeWIyMWNiaUFnSUNBdkx5QnNiMk5oZEdsdmJuTWdkMmhsY21VZ2RHaGxjbVVnYVhNZ2JtOGdaVzVqYkc5emFXNW5JSFJ5ZVNCemRHRjBaVzFsYm5RdVhHNGdJQ0FnZEdocGN5NTBjbmxGYm5SeWFXVnpJRDBnVzNzZ2RISjVURzlqT2lCY0luSnZiM1JjSWlCOVhUdGNiaUFnSUNCMGNubE1iMk56VEdsemRDNW1iM0pGWVdOb0tIQjFjMmhVY25sRmJuUnllU3dnZEdocGN5azdYRzRnSUNBZ2RHaHBjeTV5WlhObGRDZ3BPMXh1SUNCOVhHNWNiaUFnY25WdWRHbHRaUzVyWlhseklEMGdablZ1WTNScGIyNG9iMkpxWldOMEtTQjdYRzRnSUNBZ2RtRnlJR3RsZVhNZ1BTQmJYVHRjYmlBZ0lDQm1iM0lnS0haaGNpQnJaWGtnYVc0Z2IySnFaV04wS1NCN1hHNGdJQ0FnSUNCclpYbHpMbkIxYzJnb2EyVjVLVHRjYmlBZ0lDQjlYRzRnSUNBZ2EyVjVjeTV5WlhabGNuTmxLQ2s3WEc1Y2JpQWdJQ0F2THlCU1lYUm9aWElnZEdoaGJpQnlaWFIxY201cGJtY2dZVzRnYjJKcVpXTjBJSGRwZEdnZ1lTQnVaWGgwSUcxbGRHaHZaQ3dnZDJVZ2EyVmxjRnh1SUNBZ0lDOHZJSFJvYVc1bmN5QnphVzF3YkdVZ1lXNWtJSEpsZEhWeWJpQjBhR1VnYm1WNGRDQm1kVzVqZEdsdmJpQnBkSE5sYkdZdVhHNGdJQ0FnY21WMGRYSnVJR1oxYm1OMGFXOXVJRzVsZUhRb0tTQjdYRzRnSUNBZ0lDQjNhR2xzWlNBb2EyVjVjeTVzWlc1bmRHZ3BJSHRjYmlBZ0lDQWdJQ0FnZG1GeUlHdGxlU0E5SUd0bGVYTXVjRzl3S0NrN1hHNGdJQ0FnSUNBZ0lHbG1JQ2hyWlhrZ2FXNGdiMkpxWldOMEtTQjdYRzRnSUNBZ0lDQWdJQ0FnYm1WNGRDNTJZV3gxWlNBOUlHdGxlVHRjYmlBZ0lDQWdJQ0FnSUNCdVpYaDBMbVJ2Ym1VZ1BTQm1ZV3h6WlR0Y2JpQWdJQ0FnSUNBZ0lDQnlaWFIxY200Z2JtVjRkRHRjYmlBZ0lDQWdJQ0FnZlZ4dUlDQWdJQ0FnZlZ4dVhHNGdJQ0FnSUNBdkx5QlVieUJoZG05cFpDQmpjbVZoZEdsdVp5QmhiaUJoWkdScGRHbHZibUZzSUc5aWFtVmpkQ3dnZDJVZ2FuVnpkQ0JvWVc1bklIUm9aU0F1ZG1Gc2RXVmNiaUFnSUNBZ0lDOHZJR0Z1WkNBdVpHOXVaU0J3Y205d1pYSjBhV1Z6SUc5bVppQjBhR1VnYm1WNGRDQm1kVzVqZEdsdmJpQnZZbXBsWTNRZ2FYUnpaV3htTGlCVWFHbHpYRzRnSUNBZ0lDQXZMeUJoYkhOdklHVnVjM1Z5WlhNZ2RHaGhkQ0IwYUdVZ2JXbHVhV1pwWlhJZ2QybHNiQ0J1YjNRZ1lXNXZibmx0YVhwbElIUm9aU0JtZFc1amRHbHZiaTVjYmlBZ0lDQWdJRzVsZUhRdVpHOXVaU0E5SUhSeWRXVTdYRzRnSUNBZ0lDQnlaWFIxY200Z2JtVjRkRHRjYmlBZ0lDQjlPMXh1SUNCOU8xeHVYRzRnSUdaMWJtTjBhVzl1SUhaaGJIVmxjeWhwZEdWeVlXSnNaU2tnZTF4dUlDQWdJR2xtSUNocGRHVnlZV0pzWlNrZ2UxeHVJQ0FnSUNBZ2RtRnlJR2wwWlhKaGRHOXlUV1YwYUc5a0lEMGdhWFJsY21GaWJHVmJhWFJsY21GMGIzSlRlVzFpYjJ4ZE8xeHVJQ0FnSUNBZ2FXWWdLR2wwWlhKaGRHOXlUV1YwYUc5a0tTQjdYRzRnSUNBZ0lDQWdJSEpsZEhWeWJpQnBkR1Z5WVhSdmNrMWxkR2h2WkM1allXeHNLR2wwWlhKaFlteGxLVHRjYmlBZ0lDQWdJSDFjYmx4dUlDQWdJQ0FnYVdZZ0tIUjVjR1Z2WmlCcGRHVnlZV0pzWlM1dVpYaDBJRDA5UFNCY0ltWjFibU4wYVc5dVhDSXBJSHRjYmlBZ0lDQWdJQ0FnY21WMGRYSnVJR2wwWlhKaFlteGxPMXh1SUNBZ0lDQWdmVnh1WEc0Z0lDQWdJQ0JwWmlBb0lXbHpUbUZPS0dsMFpYSmhZbXhsTG14bGJtZDBhQ2twSUh0Y2JpQWdJQ0FnSUNBZ2RtRnlJR2tnUFNBdE1Td2dibVY0ZENBOUlHWjFibU4wYVc5dUlHNWxlSFFvS1NCN1hHNGdJQ0FnSUNBZ0lDQWdkMmhwYkdVZ0tDc3JhU0E4SUdsMFpYSmhZbXhsTG14bGJtZDBhQ2tnZTF4dUlDQWdJQ0FnSUNBZ0lDQWdhV1lnS0doaGMwOTNiaTVqWVd4c0tHbDBaWEpoWW14bExDQnBLU2tnZTF4dUlDQWdJQ0FnSUNBZ0lDQWdJQ0J1WlhoMExuWmhiSFZsSUQwZ2FYUmxjbUZpYkdWYmFWMDdYRzRnSUNBZ0lDQWdJQ0FnSUNBZ0lHNWxlSFF1Wkc5dVpTQTlJR1poYkhObE8xeHVJQ0FnSUNBZ0lDQWdJQ0FnSUNCeVpYUjFjbTRnYm1WNGREdGNiaUFnSUNBZ0lDQWdJQ0FnSUgxY2JpQWdJQ0FnSUNBZ0lDQjlYRzVjYmlBZ0lDQWdJQ0FnSUNCdVpYaDBMblpoYkhWbElEMGdkVzVrWldacGJtVmtPMXh1SUNBZ0lDQWdJQ0FnSUc1bGVIUXVaRzl1WlNBOUlIUnlkV1U3WEc1Y2JpQWdJQ0FnSUNBZ0lDQnlaWFIxY200Z2JtVjRkRHRjYmlBZ0lDQWdJQ0FnZlR0Y2JseHVJQ0FnSUNBZ0lDQnlaWFIxY200Z2JtVjRkQzV1WlhoMElEMGdibVY0ZER0Y2JpQWdJQ0FnSUgxY2JpQWdJQ0I5WEc1Y2JpQWdJQ0F2THlCU1pYUjFjbTRnWVc0Z2FYUmxjbUYwYjNJZ2QybDBhQ0J1YnlCMllXeDFaWE11WEc0Z0lDQWdjbVYwZFhKdUlIc2dibVY0ZERvZ1pHOXVaVkpsYzNWc2RDQjlPMXh1SUNCOVhHNGdJSEoxYm5ScGJXVXVkbUZzZFdWeklEMGdkbUZzZFdWek8xeHVYRzRnSUdaMWJtTjBhVzl1SUdSdmJtVlNaWE4xYkhRb0tTQjdYRzRnSUNBZ2NtVjBkWEp1SUhzZ2RtRnNkV1U2SUhWdVpHVm1hVzVsWkN3Z1pHOXVaVG9nZEhKMVpTQjlPMXh1SUNCOVhHNWNiaUFnUTI5dWRHVjRkQzV3Y205MGIzUjVjR1VnUFNCN1hHNGdJQ0FnWTI5dWMzUnlkV04wYjNJNklFTnZiblJsZUhRc1hHNWNiaUFnSUNCeVpYTmxkRG9nWm5WdVkzUnBiMjRvS1NCN1hHNGdJQ0FnSUNCMGFHbHpMbkJ5WlhZZ1BTQXdPMXh1SUNBZ0lDQWdkR2hwY3k1dVpYaDBJRDBnTUR0Y2JpQWdJQ0FnSUhSb2FYTXVjMlZ1ZENBOUlIVnVaR1ZtYVc1bFpEdGNiaUFnSUNBZ0lIUm9hWE11Wkc5dVpTQTlJR1poYkhObE8xeHVJQ0FnSUNBZ2RHaHBjeTVrWld4bFoyRjBaU0E5SUc1MWJHdzdYRzVjYmlBZ0lDQWdJSFJvYVhNdWRISjVSVzUwY21sbGN5NW1iM0pGWVdOb0tISmxjMlYwVkhKNVJXNTBjbmtwTzF4dVhHNGdJQ0FnSUNBdkx5QlFjbVV0YVc1cGRHbGhiR2w2WlNCaGRDQnNaV0Z6ZENBeU1DQjBaVzF3YjNKaGNua2dkbUZ5YVdGaWJHVnpJSFJ2SUdWdVlXSnNaU0JvYVdSa1pXNWNiaUFnSUNBZ0lDOHZJR05zWVhOeklHOXdkR2x0YVhwaGRHbHZibk1nWm05eUlITnBiWEJzWlNCblpXNWxjbUYwYjNKekxseHVJQ0FnSUNBZ1ptOXlJQ2gyWVhJZ2RHVnRjRWx1WkdWNElEMGdNQ3dnZEdWdGNFNWhiV1U3WEc0Z0lDQWdJQ0FnSUNBZ0lHaGhjMDkzYmk1allXeHNLSFJvYVhNc0lIUmxiWEJPWVcxbElEMGdYQ0owWENJZ0t5QjBaVzF3U1c1a1pYZ3BJSHg4SUhSbGJYQkpibVJsZUNBOElESXdPMXh1SUNBZ0lDQWdJQ0FnSUNBckszUmxiWEJKYm1SbGVDa2dlMXh1SUNBZ0lDQWdJQ0IwYUdselczUmxiWEJPWVcxbFhTQTlJRzUxYkd3N1hHNGdJQ0FnSUNCOVhHNGdJQ0FnZlN4Y2JseHVJQ0FnSUhOMGIzQTZJR1oxYm1OMGFXOXVLQ2tnZTF4dUlDQWdJQ0FnZEdocGN5NWtiMjVsSUQwZ2RISjFaVHRjYmx4dUlDQWdJQ0FnZG1GeUlISnZiM1JGYm5SeWVTQTlJSFJvYVhNdWRISjVSVzUwY21sbGMxc3dYVHRjYmlBZ0lDQWdJSFpoY2lCeWIyOTBVbVZqYjNKa0lEMGdjbTl2ZEVWdWRISjVMbU52YlhCc1pYUnBiMjQ3WEc0Z0lDQWdJQ0JwWmlBb2NtOXZkRkpsWTI5eVpDNTBlWEJsSUQwOVBTQmNJblJvY205M1hDSXBJSHRjYmlBZ0lDQWdJQ0FnZEdoeWIzY2djbTl2ZEZKbFkyOXlaQzVoY21jN1hHNGdJQ0FnSUNCOVhHNWNiaUFnSUNBZ0lISmxkSFZ5YmlCMGFHbHpMbkoyWVd3N1hHNGdJQ0FnZlN4Y2JseHVJQ0FnSUdScGMzQmhkR05vUlhoalpYQjBhVzl1T2lCbWRXNWpkR2x2YmlobGVHTmxjSFJwYjI0cElIdGNiaUFnSUNBZ0lHbG1JQ2gwYUdsekxtUnZibVVwSUh0Y2JpQWdJQ0FnSUNBZ2RHaHliM2NnWlhoalpYQjBhVzl1TzF4dUlDQWdJQ0FnZlZ4dVhHNGdJQ0FnSUNCMllYSWdZMjl1ZEdWNGRDQTlJSFJvYVhNN1hHNGdJQ0FnSUNCbWRXNWpkR2x2YmlCb1lXNWtiR1VvYkc5akxDQmpZWFZuYUhRcElIdGNiaUFnSUNBZ0lDQWdjbVZqYjNKa0xuUjVjR1VnUFNCY0luUm9jbTkzWENJN1hHNGdJQ0FnSUNBZ0lISmxZMjl5WkM1aGNtY2dQU0JsZUdObGNIUnBiMjQ3WEc0Z0lDQWdJQ0FnSUdOdmJuUmxlSFF1Ym1WNGRDQTlJR3h2WXp0Y2JpQWdJQ0FnSUNBZ2NtVjBkWEp1SUNFaFkyRjFaMmgwTzF4dUlDQWdJQ0FnZlZ4dVhHNGdJQ0FnSUNCbWIzSWdLSFpoY2lCcElEMGdkR2hwY3k1MGNubEZiblJ5YVdWekxteGxibWQwYUNBdElERTdJR2tnUGowZ01Ec2dMUzFwS1NCN1hHNGdJQ0FnSUNBZ0lIWmhjaUJsYm5SeWVTQTlJSFJvYVhNdWRISjVSVzUwY21sbGMxdHBYVHRjYmlBZ0lDQWdJQ0FnZG1GeUlISmxZMjl5WkNBOUlHVnVkSEo1TG1OdmJYQnNaWFJwYjI0N1hHNWNiaUFnSUNBZ0lDQWdhV1lnS0dWdWRISjVMblJ5ZVV4dll5QTlQVDBnWENKeWIyOTBYQ0lwSUh0Y2JpQWdJQ0FnSUNBZ0lDQXZMeUJGZUdObGNIUnBiMjRnZEdoeWIzZHVJRzkxZEhOcFpHVWdiMllnWVc1NUlIUnllU0JpYkc5amF5QjBhR0YwSUdOdmRXeGtJR2hoYm1Sc1pWeHVJQ0FnSUNBZ0lDQWdJQzh2SUdsMExDQnpieUJ6WlhRZ2RHaGxJR052YlhCc1pYUnBiMjRnZG1Gc2RXVWdiMllnZEdobElHVnVkR2x5WlNCbWRXNWpkR2x2YmlCMGIxeHVJQ0FnSUNBZ0lDQWdJQzh2SUhSb2NtOTNJSFJvWlNCbGVHTmxjSFJwYjI0dVhHNGdJQ0FnSUNBZ0lDQWdjbVYwZFhKdUlHaGhibVJzWlNoY0ltVnVaRndpS1R0Y2JpQWdJQ0FnSUNBZ2ZWeHVYRzRnSUNBZ0lDQWdJR2xtSUNobGJuUnllUzUwY25sTWIyTWdQRDBnZEdocGN5NXdjbVYyS1NCN1hHNGdJQ0FnSUNBZ0lDQWdkbUZ5SUdoaGMwTmhkR05vSUQwZ2FHRnpUM2R1TG1OaGJHd29aVzUwY25rc0lGd2lZMkYwWTJoTWIyTmNJaWs3WEc0Z0lDQWdJQ0FnSUNBZ2RtRnlJR2hoYzBacGJtRnNiSGtnUFNCb1lYTlBkMjR1WTJGc2JDaGxiblJ5ZVN3Z1hDSm1hVzVoYkd4NVRHOWpYQ0lwTzF4dVhHNGdJQ0FnSUNBZ0lDQWdhV1lnS0doaGMwTmhkR05vSUNZbUlHaGhjMFpwYm1Gc2JIa3BJSHRjYmlBZ0lDQWdJQ0FnSUNBZ0lHbG1JQ2gwYUdsekxuQnlaWFlnUENCbGJuUnllUzVqWVhSamFFeHZZeWtnZTF4dUlDQWdJQ0FnSUNBZ0lDQWdJQ0J5WlhSMWNtNGdhR0Z1Wkd4bEtHVnVkSEo1TG1OaGRHTm9URzlqTENCMGNuVmxLVHRjYmlBZ0lDQWdJQ0FnSUNBZ0lIMGdaV3h6WlNCcFppQW9kR2hwY3k1d2NtVjJJRHdnWlc1MGNua3VabWx1WVd4c2VVeHZZeWtnZTF4dUlDQWdJQ0FnSUNBZ0lDQWdJQ0J5WlhSMWNtNGdhR0Z1Wkd4bEtHVnVkSEo1TG1acGJtRnNiSGxNYjJNcE8xeHVJQ0FnSUNBZ0lDQWdJQ0FnZlZ4dVhHNGdJQ0FnSUNBZ0lDQWdmU0JsYkhObElHbG1JQ2hvWVhORFlYUmphQ2tnZTF4dUlDQWdJQ0FnSUNBZ0lDQWdhV1lnS0hSb2FYTXVjSEpsZGlBOElHVnVkSEo1TG1OaGRHTm9URzlqS1NCN1hHNGdJQ0FnSUNBZ0lDQWdJQ0FnSUhKbGRIVnliaUJvWVc1a2JHVW9aVzUwY25rdVkyRjBZMmhNYjJNc0lIUnlkV1VwTzF4dUlDQWdJQ0FnSUNBZ0lDQWdmVnh1WEc0Z0lDQWdJQ0FnSUNBZ2ZTQmxiSE5sSUdsbUlDaG9ZWE5HYVc1aGJHeDVLU0I3WEc0Z0lDQWdJQ0FnSUNBZ0lDQnBaaUFvZEdocGN5NXdjbVYySUR3Z1pXNTBjbmt1Wm1sdVlXeHNlVXh2WXlrZ2UxeHVJQ0FnSUNBZ0lDQWdJQ0FnSUNCeVpYUjFjbTRnYUdGdVpHeGxLR1Z1ZEhKNUxtWnBibUZzYkhsTWIyTXBPMXh1SUNBZ0lDQWdJQ0FnSUNBZ2ZWeHVYRzRnSUNBZ0lDQWdJQ0FnZlNCbGJITmxJSHRjYmlBZ0lDQWdJQ0FnSUNBZ0lIUm9jbTkzSUc1bGR5QkZjbkp2Y2loY0luUnllU0J6ZEdGMFpXMWxiblFnZDJsMGFHOTFkQ0JqWVhSamFDQnZjaUJtYVc1aGJHeDVYQ0lwTzF4dUlDQWdJQ0FnSUNBZ0lIMWNiaUFnSUNBZ0lDQWdmVnh1SUNBZ0lDQWdmVnh1SUNBZ0lIMHNYRzVjYmlBZ0lDQmhZbkoxY0hRNklHWjFibU4wYVc5dUtIUjVjR1VzSUdGeVp5a2dlMXh1SUNBZ0lDQWdabTl5SUNoMllYSWdhU0E5SUhSb2FYTXVkSEo1Ulc1MGNtbGxjeTVzWlc1bmRHZ2dMU0F4T3lCcElENDlJREE3SUMwdGFTa2dlMXh1SUNBZ0lDQWdJQ0IyWVhJZ1pXNTBjbmtnUFNCMGFHbHpMblJ5ZVVWdWRISnBaWE5iYVYwN1hHNGdJQ0FnSUNBZ0lHbG1JQ2hsYm5SeWVTNTBjbmxNYjJNZ1BEMGdkR2hwY3k1d2NtVjJJQ1ltWEc0Z0lDQWdJQ0FnSUNBZ0lDQm9ZWE5QZDI0dVkyRnNiQ2hsYm5SeWVTd2dYQ0ptYVc1aGJHeDVURzlqWENJcElDWW1YRzRnSUNBZ0lDQWdJQ0FnSUNCMGFHbHpMbkJ5WlhZZ1BDQmxiblJ5ZVM1bWFXNWhiR3g1VEc5aktTQjdYRzRnSUNBZ0lDQWdJQ0FnZG1GeUlHWnBibUZzYkhsRmJuUnllU0E5SUdWdWRISjVPMXh1SUNBZ0lDQWdJQ0FnSUdKeVpXRnJPMXh1SUNBZ0lDQWdJQ0I5WEc0Z0lDQWdJQ0I5WEc1Y2JpQWdJQ0FnSUdsbUlDaG1hVzVoYkd4NVJXNTBjbmtnSmlaY2JpQWdJQ0FnSUNBZ0lDQW9kSGx3WlNBOVBUMGdYQ0ppY21WaGExd2lJSHg4WEc0Z0lDQWdJQ0FnSUNBZ0lIUjVjR1VnUFQwOUlGd2lZMjl1ZEdsdWRXVmNJaWtnSmlaY2JpQWdJQ0FnSUNBZ0lDQm1hVzVoYkd4NVJXNTBjbmt1ZEhKNVRHOWpJRHc5SUdGeVp5QW1KbHh1SUNBZ0lDQWdJQ0FnSUdGeVp5QThJR1pwYm1Gc2JIbEZiblJ5ZVM1bWFXNWhiR3g1VEc5aktTQjdYRzRnSUNBZ0lDQWdJQzh2SUVsbmJtOXlaU0IwYUdVZ1ptbHVZV3hzZVNCbGJuUnllU0JwWmlCamIyNTBjbTlzSUdseklHNXZkQ0JxZFcxd2FXNW5JSFJ2SUdGY2JpQWdJQ0FnSUNBZ0x5OGdiRzlqWVhScGIyNGdiM1YwYzJsa1pTQjBhR1VnZEhKNUwyTmhkR05vSUdKc2IyTnJMbHh1SUNBZ0lDQWdJQ0JtYVc1aGJHeDVSVzUwY25rZ1BTQnVkV3hzTzF4dUlDQWdJQ0FnZlZ4dVhHNGdJQ0FnSUNCMllYSWdjbVZqYjNKa0lEMGdabWx1WVd4c2VVVnVkSEo1SUQ4Z1ptbHVZV3hzZVVWdWRISjVMbU52YlhCc1pYUnBiMjRnT2lCN2ZUdGNiaUFnSUNBZ0lISmxZMjl5WkM1MGVYQmxJRDBnZEhsd1pUdGNiaUFnSUNBZ0lISmxZMjl5WkM1aGNtY2dQU0JoY21jN1hHNWNiaUFnSUNBZ0lHbG1JQ2htYVc1aGJHeDVSVzUwY25rcElIdGNiaUFnSUNBZ0lDQWdkR2hwY3k1dVpYaDBJRDBnWm1sdVlXeHNlVVZ1ZEhKNUxtWnBibUZzYkhsTWIyTTdYRzRnSUNBZ0lDQjlJR1ZzYzJVZ2UxeHVJQ0FnSUNBZ0lDQjBhR2x6TG1OdmJYQnNaWFJsS0hKbFkyOXlaQ2s3WEc0Z0lDQWdJQ0I5WEc1Y2JpQWdJQ0FnSUhKbGRIVnliaUJEYjI1MGFXNTFaVk5sYm5ScGJtVnNPMXh1SUNBZ0lIMHNYRzVjYmlBZ0lDQmpiMjF3YkdWMFpUb2dablZ1WTNScGIyNG9jbVZqYjNKa0xDQmhablJsY2t4dll5a2dlMXh1SUNBZ0lDQWdhV1lnS0hKbFkyOXlaQzUwZVhCbElEMDlQU0JjSW5Sb2NtOTNYQ0lwSUh0Y2JpQWdJQ0FnSUNBZ2RHaHliM2NnY21WamIzSmtMbUZ5Wnp0Y2JpQWdJQ0FnSUgxY2JseHVJQ0FnSUNBZ2FXWWdLSEpsWTI5eVpDNTBlWEJsSUQwOVBTQmNJbUp5WldGclhDSWdmSHhjYmlBZ0lDQWdJQ0FnSUNCeVpXTnZjbVF1ZEhsd1pTQTlQVDBnWENKamIyNTBhVzUxWlZ3aUtTQjdYRzRnSUNBZ0lDQWdJSFJvYVhNdWJtVjRkQ0E5SUhKbFkyOXlaQzVoY21jN1hHNGdJQ0FnSUNCOUlHVnNjMlVnYVdZZ0tISmxZMjl5WkM1MGVYQmxJRDA5UFNCY0luSmxkSFZ5Ymx3aUtTQjdYRzRnSUNBZ0lDQWdJSFJvYVhNdWNuWmhiQ0E5SUhKbFkyOXlaQzVoY21jN1hHNGdJQ0FnSUNBZ0lIUm9hWE11Ym1WNGRDQTlJRndpWlc1a1hDSTdYRzRnSUNBZ0lDQjlJR1ZzYzJVZ2FXWWdLSEpsWTI5eVpDNTBlWEJsSUQwOVBTQmNJbTV2Y20xaGJGd2lJQ1ltSUdGbWRHVnlURzlqS1NCN1hHNGdJQ0FnSUNBZ0lIUm9hWE11Ym1WNGRDQTlJR0ZtZEdWeVRHOWpPMXh1SUNBZ0lDQWdmVnh1WEc0Z0lDQWdJQ0J5WlhSMWNtNGdRMjl1ZEdsdWRXVlRaVzUwYVc1bGJEdGNiaUFnSUNCOUxGeHVYRzRnSUNBZ1ptbHVhWE5vT2lCbWRXNWpkR2x2YmlobWFXNWhiR3g1VEc5aktTQjdYRzRnSUNBZ0lDQm1iM0lnS0haaGNpQnBJRDBnZEdocGN5NTBjbmxGYm5SeWFXVnpMbXhsYm1kMGFDQXRJREU3SUdrZ1BqMGdNRHNnTFMxcEtTQjdYRzRnSUNBZ0lDQWdJSFpoY2lCbGJuUnllU0E5SUhSb2FYTXVkSEo1Ulc1MGNtbGxjMXRwWFR0Y2JpQWdJQ0FnSUNBZ2FXWWdLR1Z1ZEhKNUxtWnBibUZzYkhsTWIyTWdQVDA5SUdacGJtRnNiSGxNYjJNcElIdGNiaUFnSUNBZ0lDQWdJQ0J5WlhSMWNtNGdkR2hwY3k1amIyMXdiR1YwWlNobGJuUnllUzVqYjIxd2JHVjBhVzl1TENCbGJuUnllUzVoWm5SbGNreHZZeWs3WEc0Z0lDQWdJQ0FnSUgxY2JpQWdJQ0FnSUgxY2JpQWdJQ0I5TEZ4dVhHNGdJQ0FnWENKallYUmphRndpT2lCbWRXNWpkR2x2YmloMGNubE1iMk1wSUh0Y2JpQWdJQ0FnSUdadmNpQW9kbUZ5SUdrZ1BTQjBhR2x6TG5SeWVVVnVkSEpwWlhNdWJHVnVaM1JvSUMwZ01Uc2dhU0ErUFNBd095QXRMV2twSUh0Y2JpQWdJQ0FnSUNBZ2RtRnlJR1Z1ZEhKNUlEMGdkR2hwY3k1MGNubEZiblJ5YVdWelcybGRPMXh1SUNBZ0lDQWdJQ0JwWmlBb1pXNTBjbmt1ZEhKNVRHOWpJRDA5UFNCMGNubE1iMk1wSUh0Y2JpQWdJQ0FnSUNBZ0lDQjJZWElnY21WamIzSmtJRDBnWlc1MGNua3VZMjl0Y0d4bGRHbHZianRjYmlBZ0lDQWdJQ0FnSUNCcFppQW9jbVZqYjNKa0xuUjVjR1VnUFQwOUlGd2lkR2h5YjNkY0lpa2dlMXh1SUNBZ0lDQWdJQ0FnSUNBZ2RtRnlJSFJvY205M2JpQTlJSEpsWTI5eVpDNWhjbWM3WEc0Z0lDQWdJQ0FnSUNBZ0lDQnlaWE5sZEZSeWVVVnVkSEo1S0dWdWRISjVLVHRjYmlBZ0lDQWdJQ0FnSUNCOVhHNGdJQ0FnSUNBZ0lDQWdjbVYwZFhKdUlIUm9jbTkzYmp0Y2JpQWdJQ0FnSUNBZ2ZWeHVJQ0FnSUNBZ2ZWeHVYRzRnSUNBZ0lDQXZMeUJVYUdVZ1kyOXVkR1Y0ZEM1allYUmphQ0J0WlhSb2IyUWdiWFZ6ZENCdmJteDVJR0psSUdOaGJHeGxaQ0IzYVhSb0lHRWdiRzlqWVhScGIyNWNiaUFnSUNBZ0lDOHZJR0Z5WjNWdFpXNTBJSFJvWVhRZ1kyOXljbVZ6Y0c5dVpITWdkRzhnWVNCcmJtOTNiaUJqWVhSamFDQmliRzlqYXk1Y2JpQWdJQ0FnSUhSb2NtOTNJRzVsZHlCRmNuSnZjaWhjSW1sc2JHVm5ZV3dnWTJGMFkyZ2dZWFIwWlcxd2RGd2lLVHRjYmlBZ0lDQjlMRnh1WEc0Z0lDQWdaR1ZzWldkaGRHVlphV1ZzWkRvZ1puVnVZM1JwYjI0b2FYUmxjbUZpYkdVc0lISmxjM1ZzZEU1aGJXVXNJRzVsZUhSTWIyTXBJSHRjYmlBZ0lDQWdJSFJvYVhNdVpHVnNaV2RoZEdVZ1BTQjdYRzRnSUNBZ0lDQWdJR2wwWlhKaGRHOXlPaUIyWVd4MVpYTW9hWFJsY21GaWJHVXBMRnh1SUNBZ0lDQWdJQ0J5WlhOMWJIUk9ZVzFsT2lCeVpYTjFiSFJPWVcxbExGeHVJQ0FnSUNBZ0lDQnVaWGgwVEc5ak9pQnVaWGgwVEc5alhHNGdJQ0FnSUNCOU8xeHVYRzRnSUNBZ0lDQnlaWFIxY200Z1EyOXVkR2x1ZFdWVFpXNTBhVzVsYkR0Y2JpQWdJQ0I5WEc0Z0lIMDdYRzU5S1NoY2JpQWdMeThnUVcxdmJtY2dkR2hsSUhaaGNtbHZkWE1nZEhKcFkydHpJR1p2Y2lCdlluUmhhVzVwYm1jZ1lTQnlaV1psY21WdVkyVWdkRzhnZEdobElHZHNiMkpoYkZ4dUlDQXZMeUJ2WW1wbFkzUXNJSFJvYVhNZ2MyVmxiWE1nZEc4Z1ltVWdkR2hsSUcxdmMzUWdjbVZzYVdGaWJHVWdkR1ZqYUc1cGNYVmxJSFJvWVhRZ1pHOWxjeUJ1YjNSY2JpQWdMeThnZFhObElHbHVaR2x5WldOMElHVjJZV3dnS0hkb2FXTm9JSFpwYjJ4aGRHVnpJRU52Ym5SbGJuUWdVMlZqZFhKcGRIa2dVRzlzYVdONUtTNWNiaUFnZEhsd1pXOW1JR2RzYjJKaGJDQTlQVDBnWENKdlltcGxZM1JjSWlBL0lHZHNiMkpoYkNBNlhHNGdJSFI1Y0dWdlppQjNhVzVrYjNjZ1BUMDlJRndpYjJKcVpXTjBYQ0lnUHlCM2FXNWtiM2NnT2lCMGFHbHpYRzRwTzF4dUlsMTkiLCJtb2R1bGUuZXhwb3J0cyA9IHJlcXVpcmUoXCIuL2xpYi9iYWJlbC9wb2x5ZmlsbFwiKTtcbiIsIm1vZHVsZS5leHBvcnRzID0gcmVxdWlyZShcImJhYmVsLWNvcmUvcG9seWZpbGxcIik7XG4iXX0=
