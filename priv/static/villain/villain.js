(function($, _) {
    var that = this,
               Villain;
    Villain = that.Villain = {};
    Villain.EventBus = Villain.EventBus || _.extend({}, Backbone.Events);
    Villain.Blocks = Villain.Blocks || {};
    Villain.Editor = Villain.Editor || {};
    Villain.options = Villain.options || [];

    Villain.defaults = {
        textArea: '#textarea',
        browseURL: 'villain/browse/',
        uploadURL: 'villain/upload/',
        imageseriesURL: 'villain/imageseries/'
    };

    function $element(el) {
        return el instanceof $ ? el : $(el);
    }

    /* Mixins */
    var url_regex = /^(?:([A-Za-z]+):)?(\/{0,3})([0-9.\-A-Za-z]+)(?::(\d+))?(?:\/([^?#]*))?(?:\?([^#]*))?(?:#(.*))?$/;
    
    _.mixin({
        isURI : function(string) {
            return (url_regex.test(string));
        },
    
        titleize: function(str) {
            if (str === null) {
                return '';
            }
            str  = String(str).toLowerCase();
            return str.replace(/(?:^|\s|-)\S/g, function(c) { return c.toUpperCase(); });
        },
    
        classify: function(str) {
            return _.titleize(String(str).replace(/[\W_]/g, ' ')).replace(/\s/g, '');
        },
    
        classifyList: function(a) {
            return _.map(a, function(i) { return _.classify(i); });
        },
    
        capitalize : function(string) {
            return string.charAt(0).toUpperCase() + string.substring(1).toLowerCase();
        },
    
        underscored: function(str) {
            return _.trim(str).replace(/([a-z\d])([A-Z]+)/g, '$1_$2')
            .replace(/[-\s]+/g, '_').toLowerCase();
        },
    
        trim : function(string) {
            return string.replace(/^\s\s*/, '').replace(/\s\s*$/, '');
        },
    
        reverse: function(str) {
            return str.split('').reverse().join('');
        },
    
        flattern: function(obj) {
            var x = {};
            _.each(obj, function(a,b) {
              x[(_.isArray(obj)) ? a : b] = true;
          });
            return x;
        },
    
        to_slug: function(str) {
            return str
            .toLowerCase()
            .replace(/[^\w ]+/g,'')
            .replace(/ +/g,'-');
        }
    });
    
    $.fn.visible = function() {
        return this.css('visibility', 'visible');
    };
    
    $.fn.invisible = function() {
        return this.css('visibility', 'hidden');
    };
    
    $.fn.visibilityToggle = function() {
        return this.css('visibility', function(i, visibility) {
            return (visibility == 'visible') ? 'hidden' : 'visible';
        });
    };
    
    $.fn.caretToEnd = function() {
        var range, selection;
    
        range = document.createRange();
        range.selectNodeContents(this[0]);
        range.collapse(false);
    
        selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
    
        return this;
    };
    
    // Extend jquery with flashing for elements
    $.fn.flash = function(duration, iterations) {
        duration = duration || 1000; // Default to 1 second
        iterations = iterations || 2; // Default to 1 iteration
        var iterationDuration = Math.floor(duration / iterations);
    
        originalColor = this.css('background-color');
        this.css('background-color','#ffffdd');
        for (var i = 0; i < iterations; i++) {
            this.fadeOut(iterationDuration).fadeIn(iterationDuration, function() {
                this.css('background-color', '#ffffff');
            });
        }
        //this.css('background-color',originalColor);
        return this;
    };
    
    $.fn.shake = function(shakes, distance, duration) {
        shakes = shakes || 3;
        distance = distance || 10;
        duration = duration || 300;
        this.each(function() {
            $(this).css('position', 'relative');
            for (var x = 1; x <= shakes; x++) {
                $(this).animate({left: (distance * -1)}, (((duration / shakes) / 4)))
                       .animate({left: distance}, ((duration / shakes) / 2))
                       .animate({left: 0}, (((duration / shakes) / 4)));
            }
        });
        return this;
    };
    
    /*! Loading Overlay - v1.0.2 - 2014-02-19
    * http://jgerigmeyer.github.io/jquery-loading-overlay/
    * Copyright (c) 2014 Jonny Gerig Meyer; Licensed MIT */
    (function($) {
    
      'use strict';
    
      var methods = {
        init: function(options) {
          var opts = $.extend({}, $.fn.loadingOverlay.defaults, options),
              target = $(this).addClass(opts.loadingClass),
              overlay = '<div class="' + opts.overlayClass + '">' +
            '<p class="' + opts.spinnerClass + '">' +
            '<span class="' + opts.iconClass + '"></span>' +
            '<span class="' + opts.textClass + '">' + opts.loadingText + '</span>' +
            '</p></div>';
          // Don't add duplicate loading-overlay
          if (!target.data('loading-overlay')) {
            target.prepend($(overlay)).data('loading-overlay', true);
          }
          return target;
        },
    
        remove: function(options) {
          var opts = $.extend({}, $.fn.loadingOverlay.defaults, options),
              target = $(this).data('loading-overlay', false);
          target.find('.' + opts.overlayClass).detach();
          if (target.hasClass(opts.loadingClass)) {
            target.removeClass(opts.loadingClass);
          } else {
            target.find('.' + opts.loadingClass).removeClass(opts.loadingClass);
          }
          return target;
        },
    
        // Expose internal methods to allow stubbing in tests
        exposeMethods: function() {
          return methods;
        }
      };
    
      $.fn.loadingOverlay = function(method) {
        if (methods[method]) {
          return methods[method].apply(
            this,
            Array.prototype.slice.call(arguments, 1)
          );
        } else if (typeof method === 'object' || !method) {
          return methods.init.apply(this, arguments);
        } else {
          $.error('Method ' + method + ' does not exist on jQuery.loadingOverlay');
        }
      };
    
      /* Setup plugin defaults */
      $.fn.loadingOverlay.defaults = {
        loadingClass: 'loading',          // Class added to target while loading
        overlayClass: 'loading-overlay',  // Class added to overlay (style with CSS)
        spinnerClass: 'loading-spinner',  // Class added to loading overlay spinner
        iconClass: 'loading-icon fa fa-circle-o-notch fa-spin',        // Class added to loading overlay spinner
        textClass: 'loading-text',        // Class added to loading overlay spinner
        loadingText: ''            // Text within loading overlay
      };
    }(jQuery));

    /* Plus */
    Villain.Plus = Backbone.View.extend({
        tagName: 'div',
        className: 'villain-add-block villain-droppable',
        blockSelectionTemplate: _.template(
            '<div class="villain-block-selection"><%= content %></div>'
        ),
        events: {
            'click .villain-add-block-button': 'onClickAddBlock',
            'click .villain-block-button': 'onClickBlockButton'
        },
    
        initialize: function(store) {
            this.store = store;
            this.$el.attr('data-blockstore', store);
            this.$el.attr('id', _.uniqueId('villain-plus-'));
            this.render();
        },
    
        render: function() {
            this.$el.append('<button class="villain-add-block-button">+</button>');
            return this;
        },
    
        onClickBlockButton: function(e) {
            /* clicked a button in the add new block container */
            e.preventDefault();
    
            $button = $(e.currentTarget);
    
            blockType = $button.data('type');
            blockStore = this.store;
            BlockClass = Villain.BlockRegistry.getBlockClassByType(blockType);
    
            // get a new block with no data, and the specified blockStore
            block = new BlockClass(false, blockStore);
            block.$el.insertAfter($button.parent().parent());
            block.$el.after(block.renderPlus().$el);
            // if the block has a textblock, set the caret to the end
            if (block.hasTextBlock()) {
                block.setCaret();
            }
            // scroll to element position
            block.scrollTo();
            // show the plus
            $button.parent().prev().show();
            // hide the buttons
            $button.parent().remove();
        },
    
        onClickAddBlock: function(e) {
            // in case it tries to submit.
            e.preventDefault();
            $addBlockButton = $(e.currentTarget);
            $addBlockButton.hide();
            blockId = $addBlockButton.parent().data('after-block-id');
            blockSelection = this.blockSelectionTemplate({content: this.getButtons(blockId)});
            $addBlockButton.parent().append(blockSelection);
        },
    
        getButtons: function(id) {
            // iterate through block types in the block registry
            // and get buttons for each type.
            html = '';
            for (i = 0; i < Villain.BlockRegistry.Map.length; ++i) {
                blockName = Villain.BlockRegistry.Map[i];
                b = Villain.BlockRegistry.getBlockClassByType(blockName);
                if (_.isUndefined(b)) {
                    console.error("Villain: Undefined block ", blockName);
                    continue;
                }
                if (b.hasOwnProperty('getButton')) {
                    html += b.getButton(id);
                } else {
                    console.log("// No button found for " + blockName);
                }
            }
            return html;
        }
    });

    /* Blocks */
    /**
     * blockstore.js
     * This is where we store the blocks. There are multiple stores to deal
     * with columns/superblocks. The columns blocks have their own store
     * named after their id.
     */
    
    Villain.BlockStore = [];
    Villain.BlockStore.stores = [];
    Villain.BlockStore.count = 1;
    
    // Don't need storeName here, since we never want two equal ids
    Villain.BlockStore.getId = function() {
        id = Villain.BlockStore.count;
        Villain.BlockStore.count++;
        return id;
    };
    
    Villain.BlockStore.getBlockById = function(storeName, id) {
        block = _.find(Villain.BlockStore[storeName], function(b) {
            return b.id == id;
        });
        if (!block) {
            return false;
        }
        if (!block.hasOwnProperty('object')) {
            return false;
        }
        return block.object;
    };
    
    Villain.BlockStore.add = function(store, id, blockObject) {
        Villain.BlockStore[store].push({
            id: id,
            object: blockObject
        });
    };
    
    Villain.BlockStore.del = function(store, id) {
        Villain.BlockStore[store] = _.filter(Villain.BlockStore[store], function(block) {
            return parseInt(block.id) !== parseInt(id);
        });
    };
    
    Villain.BlockStore.delStore = function(store) {
        // iterate all blocks
        _.each(Villain.BlockStore[store], function(element, index) {
            element.object.destroy();
        });
        Villain.BlockStore[store] = [];
        var index = Villain.BlockStore.stores.indexOf(store);
        Villain.BlockStore.stores.splice(index, 1);
    };
    
    Villain.BlockStore.create = function(name) {
        Villain.BlockStore[name] = [];
        Villain.BlockStore.stores.push(name);
    };
    
    Villain.BlockStore.listAll = function() {
        for (var i = 0; i < Villain.BlockStore.stores.length; i++) {
            console.log(Villain.BlockStore.stores[i]);
            console.log(Villain.BlockStore[Villain.BlockStore.stores[i]]);
        }
    };
    Villain.Block = Backbone.View.extend({
        tagName: 'div',
        className: 'villain-block-wrapper',
        type: 'base',
        template: _.template('base'),
        store: 'main',
    
        wrapperTemplate: _.template([
            '<div class="villain-block-inner"><%= content %><%= actions %></div>'
        ].join('\n')),
    
        actionsTemplate: _.template([
            '<div class="villain-actions">',
            '  <div class="villain-action-button villain-action-button-setup">',
            '    <i class="fa fa-cogs"></i>',
            '  </div>',
            '  <div class="villain-action-button villain-action-button-del">',
            '    <i class="fa fa-trash"></i>',
            '  </div>',
            '  <div class="villain-action-button villain-action-button-move" draggable="true">',
            '    <i class="fa fa-arrows-alt"></i>',
            '  </div>',
            '</div>'
        ].join('\n')),
    
        setupTemplate: _.template(
            '<div class="villain-setup-block" />'
        ),
    
        events: {
            'dragstart .villain-action-button-move': 'onDragStart',
            'click .villain-action-button-move': 'onClickMove',
            'click .villain-action-button-del': 'onClickDelete',
            'mouseover .villain-block-inner': 'onMouseOver',
            'mouseout .villain-block-inner': 'onMouseOut',
            'paste .villain-text-block': 'onPaste',
            'mouseup .villain-text-block': 'onMouseUp',
            'keyup .villain-text-block': 'onKeyUp',
            'click .villain-text-block': 'onClick',
            'click .villain-action-button-setup': 'onSetupClick'
        },
    
        initialize: function(json, store) {
            this.data = json || null;
            this.dataId = this.getIdFromBlockStore();
            this.$el.attr('data-block-id', this.dataId);
            this.$el.attr('data-block-type', this.type);
            this.$el.attr('id', 'villain-block-' + this.dataId);
            if (store) {
                this.store = store;
            }
            this.$el.attr('data-blockstore', this.store);
            this.id = 'villain-block-' + this.dataId;
            this.addToBlockStore(store);
            this.render();
        },
    
        render: function() {
            if (this.hasData()) {
                // we got passed data. render editorhtm
                html = this.renderEditorHtml();
            } else {
                // no data, probably want a blank block
                html = this.renderEmpty();
            }
            this.el.innerHTML = html;
            this.setSections();
            this.addSetup();
            return this;
        },
    
        onClick: function(e) {
            var text = this.getSelectedText();
            if (text === '') {
                Villain.EventBus.trigger('formatpopup:hide');
            }
        },
    
        onSetupClick: function(e) {
            e.stopPropagation();
            // is it active now?
            $button = this.$('.villain-action-button-setup');
            if ($button.hasClass('active')) {
                // hide the setup
                $button.removeClass('active');
                this.hideSetup();
            } else {
                $button.addClass('active');
                this.showSetup();
            }
        },
    
        onKeyUp: function(e) {
            // check if there's text selected
            var text = this.getSelectedText();
    
            if (text !== '') {
                Villain.EventBus.trigger('formatpopup:show', this);
            } else {
                Villain.EventBus.trigger('formatpopup:hide');
            }
        },
    
        onMouseUp: function(e) {
            // check if there's text selected
            var text = this.getSelectedText();
    
            if (text !== '') {
                Villain.EventBus.trigger('formatpopup:show', this);
            } else {
                Villain.EventBus.trigger('formatpopup:hide');
            }
        },
    
        getSelectedText: function() {
            var text = '';
    
            if (window.getSelection) {
              text = window.getSelection();
            } else if (document.getSelection) {
              text = document.getSelection();
            } else if (document.selection) {
              text = document.selection.createRange().text;
            }
            return text.toString();
        },
    
        deleteBlock: function() {
            Villain.BlockStore.del(this.store, this.dataId);
            this.destroy();
        },
    
        loading: function() {
            this.$el.loadingOverlay();
        },
    
        done: function() {
            this.$el.loadingOverlay('remove');
        },
    
        addToPathName: function(relativeUrl) {
            if (relativeUrl.charAt(0) === "/") {
                return relativeUrl;
            } else {
                var divider = (window.location.pathname.slice(-1) == "/") ? "" : "/";
                var fullPath = window.location.pathname + divider + relativeUrl;
            }
            return fullPath;
        },
    
        destroy: function() {
            // delete the plus after
            this.$el.next('.villain-add-block').remove();
            // TODO: find the plus object and delete it...
            // COMPLETELY UNBIND THE VIEW
            this.undelegateEvents();
            this.$el.removeData().unbind();
            // Remove view from DOM
            this.remove();
            Backbone.View.prototype.remove.call(this);
        },
    
        onClickDelete: function(e) {
            this.deleteBlock();
            e.stopPropagation();
        },
    
        onClickMove: function(e) {
            e.stopPropagation();
        },
    
        onDragStart: function(e) {
            e.originalEvent.dataTransfer.setDragImage(this.$el.get(0), this.$el.width(), this.$el.height());
            e.originalEvent.dataTransfer.setData('Text', this.dataId);
            e.stopPropagation();
        },
    
        onMouseOver: function(e) {
            event.stopPropagation();
            this.$inner.addClass('hover');
            this.$inner.children('.villain-actions').visible();
        },
    
        onMouseOut: function(e) {
            this.$inner.removeClass('hover');
            this.$inner.children('.villain-actions').invisible();
        },
    
        onPaste: function(e) {
            var clipboard = false;
            if (e && e.originalEvent.clipboardData && e.originalEvent.clipboardData.getData) {
                var types = '',
                    clipboard_types = e.originalEvent.clipboardData.types;
    
                if ($.isArray(clipboard_types)) {
                    for (var i = 0 ; i < clipboard_types.length; i++) {
                        types += clipboard_types[i] + ';';
                    }
                } else {
                    types = clipboard_types;
                }
    
                if (/text\/html/.test(types)) {
                    // HTML.
                    clipboardHTML = e.originalEvent.clipboardData.getData('text/html');
                } else if (/text\/rtf/.test(types) && Villain.browser.safari) {
                    // Safari HTML.
                    clipboardHTML = e.originalEvent.clipboardData.getData('text/rtf');
                } else if (/text\/plain/.test(types) && !Villain.browser.mozilla) {
                    clipboardHTML = e.originalEvent.clipboardData.getData('text/plain').replace(/\n/g, '<br/>');
                }
    
                if (this.clipboardHTML !== '') {
                    clipboard = true;
                } else {
                    this.clipboardHTML = null;
                }
    
                if (clipboard) {
                    cleanHtml = Villain.Editor.processPaste(clipboardHTML);
                    e.stopPropagation();
                    e.preventDefault();
                    Villain.Editor.pasteHtmlAtCaret(cleanHtml);
                    return false;
                }
            }
        },
    
        getIdFromBlockStore: function() {
            return Villain.BlockStore.getId();
        },
    
        doRenderCallback: function() {
    
        },
    
        hasTextBlock: function() {
            // check if the block has its own textblock
            return this.$('.villain-text-block').length === 0 ? false : true;
        },
    
        setCaret: function() {
            var range, selection;
    
            range = document.createRange();
            range.selectNodeContents(this.getTextBlock()[0]);
            range.collapse(false);
    
            selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
        },
    
        scrollTo: function() {
            $('html, body').animate({
                scrollTop: this.$el.offset().top - 75
            }, 300, 'linear');
        },
    
        flash: function(color, duration) {
    
        },
    
        getJSON: function() {
            return [];
        },
    
        addToBlockStore: function(store) {
            Villain.BlockStore.add(store ? store : 'main', this.dataId, this);
        },
    
        setData: function(json) {
            this.data = json;
        },
    
        getData: function() {
            return this.data;
        },
    
        setDataProperty: function(prop, value) {
            data = this.getData();
            data[prop] = value;
            this.setData(data);
        },
    
        hasData: function() {
            return this.data ? !_.isEmpty(this.data) : false;
        },
    
        refreshBlock: function() {
            html = this.renderEditorHtml();
            this.el.innerHTML = html;
            this.addSetup();
            return this;
        },
    
        refreshContentBlock: function(hidden) {
            block = this.renderContentBlockHtml();
            this.$content.html($(block).html());
            return this.$content;
        },
    
        setSections: function() {
            this.$inner = this.$('.villain-block-inner');
            this.$content = this.$('.villain-content');
        },
    
        addSetup: function() {
            if (this.setup) {
                // the block has a setup method - add the setupTemplate
                // and call setup()
                this.$inner.prepend(this.setupTemplate());
                this.$setup = this.$('.villain-setup-block');
                // show the setup button
                this.$('.villain-action-button-setup').show();
                this.setup();
            } else {
                this.$('.villain-action-button-setup').hide();
            }
        },
    
        clearSetup: function() {
            this.$setup.empty();
        },
    
        getTextBlock: function() {
            this.$textBlock = this.$('.villain-text-block');
            return this.$textBlock;
        },
    
        getTextBlockInner: function() {
            tb = this.getTextBlock();
            return tb.html();
        },
    
        clearInsertedStyles: function(e) {
            var target = e.target;
            target.removeAttribute('style'); // Hacky fix for Chrome.
        },
    
        renderEditorHtml: function() {},
    
        renderEmpty: function() {},
    
        renderPlus: function() {
            addblock = new Villain.Plus(this.store);
            return addblock;
        },
    
        showSetup: function() {
            innerHeight = this.$inner.height();
            this.$content.hide();
            $button = this.$('.villain-action-button-setup');
            $button.addClass('active');
            this.$setup.show();
            if (this.$setup.height() < innerHeight) {
                this.$setup.height(innerHeight);
            }
        },
    
        hideSetup: function() {
            this.$setup.hide();
            this.$setup.height("");
            $button = this.$('.villain-action-button-setup');
            $button.removeClass('active');
            this.$content.show();
        }
    });

    /* Blocktypes */
    Villain.Blocks.Text = Villain.Block.extend({
        type: 'text',
        template: _.template(
            '<div class="villain-text-block villain-content" contenteditable="true" data-text-type="<%= type %>"><%= content %></div>'
        ),
    
        renderEditorHtml: function() {
            blockTemplate = this.renderContentBlockHtml();
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        renderContentBlockHtml: function() {
            text = this.getTextBlockInner() ? this.getTextBlockInner() : this.data.text;
            return this.template({content: Villain.toHTML(text), type: this.data.type});
        },
    
        renderEmpty: function() {
            blockTemplate = this.template({content: 'Text', type: "paragraph"});
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        getJSON: function() {
            textNode = Villain.toMD(this.getTextBlockInner());
            data = this.getData();
            json = {
                type: this.type,
                data: {
                    text: textNode,
                    type: data.type
                }
            };
            return json;
        },
    
        getHTML: function() {
            textNode = this.getTextBlock().html();
            return markdown.toHTML(textNode);
        },
    
        setup: function() {
            data = this.getData();
            if (!data.hasOwnProperty('type')) {
                this.setDataProperty('type', 'paragraph');
            }
            type = this.data.type;
            this.$setup.hide();
            var radios = "";
            types = ['paragraph', 'lead'];
            for (i in types) {
                selected = "";
                if (type === types[i]) {
                    selected = ' checked="checked"';
                }
                radios += '<label><input type="radio" name="text-type" value="'
                        + types[i] + '"' + selected + '>' + types[i] + '</label>';
            }
    
            this.$setup.append($([
                '<label>Type</label>',
                radios
            ].join('\n')));
    
            this.$setup.find('input[type=radio]').on('change', $.proxy(function(e) {
                this.setDataProperty('type', $(e.target).val());
                this.refreshContentBlock();
                this.$content.attr('data-text-type', $(e.target).val());
            }, this));
        },
    },
    {
        /* static methods */
        getButton: function(afterId) {
            var blockType = 'text';
            t = _.template([
                '<button class="villain-block-button" data-type="<%= type %>" data-after-block-id="<%= id %>">',
                '<i class="fa fa-paragraph"></i>',
                '<p>text</p>',
                '</button>'].join('\n'));
            return t({id: afterId, type: blockType});
        }
    });
    Villain.Blocks.Blockquote = Villain.Block.extend({
        type: 'blockquote',
        template: _.template(
            '<div class="villain-quote-block villain-content"><blockquote contenteditable="true"><%= content %></blockquote><cite contenteditable="true"><%= cite %></cite></div>'
        ),
    
        renderEditorHtml: function() {
            blockTemplate = this.renderContentBlockHtml();
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        renderContentBlockHtml: function() {
            text = this.getTextBlockInner() ? this.getTextBlockInner() : this.data.text;
            return this.template({content: Villain.toHTML(text), cite: this.data.cite});
        },
    
        renderEmpty: function() {
            blockTemplate = this.template({content: 'quote', cite: 'author'});
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        getJSON: function() {
            quote = this.$content.find('blockquote')[0].outerHTML;
            cite = $('cite', this.$content).html();
            textNode = Villain.toMD(quote);
            data = this.getData();
            json = {
                type: this.type,
                data: {
                    text: textNode,
                    cite: cite
                }
            };
            return json;
        },
    
        getHTML: function() {
            textNode = this.getTextBlock().html();
            return markdown.toHTML(textNode);
        }
    },
    {
        /* static methods */
        getButton: function(afterId) {
            var blockType = 'blockquote';
            t = _.template([
                '<button class="villain-block-button" data-type="<%= type %>" data-after-block-id="<%= id %>">',
                '<i class="fa fa-quote-right"></i>',
                '<p>quote</p>',
                '</button>'].join('\n'));
            return t({id: afterId, type: blockType});
        }
    });

    Villain.Blocks.Divider = Villain.Block.extend({
        type: 'divider',
        template: _.template('<div class="villain-divider-block villain-content"><hr></div>'),
    
        renderEditorHtml: function() {
            blockTemplate = this.template();
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        renderEmpty: function() {
            blockTemplate = this.template();
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        getJSON: function() {
            json = {
                type: this.type,
                data: {
                    text: '--------------------'
                }
            };
            return json;
        },
    
        getHTML: function() {
            return '<hr>';
        }
    }, {
        /* static methods */
        getButton: function(afterId) {
            var blockType = 'divider';
            t = _.template([
                '<button class="villain-block-button" data-type="<%= type %>" data-after-block-id="<%= id %>">',
                '<i class="fa fa-minus"></i>',
                '<p>hr</p>',
                '</button>'].join('\n'));
            return t({id: afterId, type: blockType});
        }
    });
    Villain.Blocks.Header = Villain.Block.extend({
        type: 'header',
        template: _.template([
            '<div class="villain-text-block villain-text-block-header villain-content" data-header-level="<%= level %>" contenteditable="true">',
              '<%= content %>',
            '</div>'
        ].join('\n')),
    
        renderEditorHtml: function() {
            blockTemplate = this.renderContentBlockHtml();
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        renderContentBlockHtml: function() {
            return this.template({content: this.data.text, level: this.data.level});
        },
    
        renderEmpty: function() {
            blockTemplate = this.template({content: 'Header', level: 1});
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        setup: function() {
            data = this.getData();
            if (!data.hasOwnProperty('level')) {
                this.setDataProperty('level', 1);
            }
            level = data['level'];
            this.$setup.hide();
            var radios = "";
            levels = [1, 2, 3, 4, 5];
            for (i in levels) {
                selected = "";
                if (parseInt(level) === parseInt(levels[i])) {
                    selected = ' checked="checked"';
                }
                radios += '<label><input type="radio" name="header-size" value="' + levels[i] + '"' + selected + '>H' + levels[i] + '</label>';
            }
            this.$setup.append($([
                '<label>Størrelse</label>',
                radios
            ].join('\n')));
    
            this.$setup.find('input[type=radio]').on('change', $.proxy(function(e) {
                this.setDataProperty('level', $(e.target).val());
                this.refreshContentBlock();
                this.$content.attr('data-header-level', $(e.target).val());
            }, this));
        },
    
        getData: function() {
            data = this.data;
            data.text = Villain.toMD(this.getTextBlock().html()).trim();
            return data;
        },
    
        getJSON: function() {
            // strip newlines
            json = {
                type: this.type,
                data: this.getData()
            };
            return json;
        },
    
        getHTML: function() {
            textNode = this.getTextBlock().html();
            return '<h3>' + markdown.toHTML(textNode) + '</h3>';
        }
    },
    {
        /* static methods */
        getButton: function(afterId) {
            var blockType = 'header';
            t = _.template([
                '<button class="villain-block-button" data-type="<%= type %>" data-after-block-id="<%= id %>">',
                '<i class="fa fa-header"></i>',
                '<p>h1-6</p>',
                '</button>'].join('\n'));
            return t({
                id: afterId,
                type: blockType
            });
        }
    });
    Villain.Blocks.List = Villain.Block.extend({
        type: 'list',
        template: _.template([
            '<div class="villain-text-block villain-text-block-list villain-content" contenteditable="true">',
              '<%= content %>',
            '</div>'].join('\n')
        ),
    
        events: {
            'keyup .villain-content': 'onKeyUp'
        },
    
        onKeyUp: function(e) {
            console.log(e.currentTarget.innerHTML);
            if (e.currentTarget.innerText == "" || e.currentTarget.innerText == "\n") {
                console.log("empty!");
                e.currentTarget.innerHTML = "<ul><li><br></li></ul>";
            }
        },
    
        renderEditorHtml: function() {
            blockTemplate = this.template({content: markdown.toHTML(this.data.text)});
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        renderEmpty: function() {
            blockTemplate = this.template({content: '<ul><li>list</li></ul>'});
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        getJSON: function() {
            textNode = this.getTextBlock().html().replace(/<\/li>/mg,'\n')
                                                 .replace(/<\/?[^>]+(>|$)/g, '')
                                                 .replace(/^(.+)$/mg,' - $1');
            json = {
                type: this.type,
                data: {
                    text: textNode
                }
            };
            return json;
        },
    
        getHTML: function() {
            textNode = this.getTextBlock().html();
            return '<h3>' + markdown.toHTML(textNode) + '</h3>';
        },
    
        toMarkdown: function(markdown) {
          return markdown.replace(/<\/li>/mg,'\n')
                         .replace(/<\/?[^>]+(>|$)/g, '')
                         .replace(/^(.+)$/mg,' - $1');
        }
        /*
        onBlockRender: function() {
          this.checkForList = _.bind(this.checkForList, this);
          this.getTextBlock().on('click keyup', this.checkForList);
        },
        */
    
    },
    {
        /* static methods */
        getButton: function(afterId) {
            var blockType = 'list';
            t = _.template([
                '<button class="villain-block-button" ',
                '        data-type="<%= type %>" ',
                '        data-after-block-id="<%= id %>"',
                '>',
                '   <i class="fa fa-list-ul"></i>',
                '<p>list</p>',
                '</button>'].join('\n'));
            return t({
                id: afterId,
                type: blockType
            });
        }
    });

    Villain.Blocks.Image = Villain.Block.extend({
        type: 'image',
        template: _.template(
            '<div class="villain-image-block villain-content"><img class="img-responsive" src="<%= url %>" /></div>'
        ),
    
        events: {
            'drop .villain-image-dropper i': 'onDropImage',
            'dragenter .villain-image-dropper i': 'onDragEnter',
            'dragleave .villain-image-dropper i': 'onDragLeave',
            'dragover .villain-image-dropper i': 'onDragOver',
            'click .villain-image-dropper-upload': 'onUploadClickAfterDrop'
        },
    
        initialize: function(json, store) {
            Villain.Block.prototype.initialize.apply(this, [json, store]);
            _.extend(this.events, Villain.Block.prototype.events);
        },
    
        renderEditorHtml: function() {
            blockTemplate = this.renderContentBlockHtml();
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        renderContentBlockHtml: function() {
            return this.template({url: this.data.url});
        },
    
        renderEmpty: function() {
            blockTemplate = this.template({url: 'http://placehold.it/1150x400'});
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        onUploadClickAfterDrop: function(e) {
            var uid  = [this.dataId, (new Date()).getTime(), 'raw'].join('-');
            var data = new FormData();
    
            e.preventDefault();
            this.loading();
            img = this.$setup.find('.villain-image-dropper img');
            if (!this.file) {
                this.done();
                return false;
            }
            data.append('name', this.file.name);
            data.append('image', this.file);
            data.append('uid', uid);
    
            that = this;
    
            $.ajax({
                type: 'post',
                dataType: 'json',
                accepts: {
                    json: 'text/json'
                },
                url: this.addToPathName(Villain.options['uploadURL']),
                data: data,
                cache: false,
                contentType: false,
                processData: false,
                // Custom XMLHttpRequest
                xhr: function() {
                    var customXhr = $.ajaxSettings.xhr();
                    // Check if upload property exists
                    if (customXhr.upload) {
                        customXhr.upload.addEventListener('progress', that.progressHandlingFunction, false);
                    }
                    return customXhr;
                }
            }).done($.proxy(function(data) {
                /**
                 * Callback after confirming upload
                 */
                if (data.status == '200') {
                    // image uploaded successfully
                    this.$setup.append('<div class="villain-message success">Bildet er lastet opp</div>');
                    // remove upload button
                    this.$setup.find('.villain-image-dropper-upload').remove();
                    this.$setup.find('.villain-image-dropper').remove();
    
                    if (data.hasOwnProperty('image')) {
                        imageData = data.image;
                        $image = $('<img src="' + imageData.src + '" />');
                        this.$setup.append($image);
    
                        // set the image src as data
                        json = {
                            url: imageData.src,
                            sizes: imageData.sizes
                        };
                        this.setData(json);
                    }
    
                    if (data.hasOwnProperty('uid')) {
                        uid = data.uid;
                    }
    
                    if (data.hasOwnProperty('form')) {
                        var inputsHtml = '';
                        inputTemplate = _.template([
                            '<label><%= label %></label>',
                            '<input type="<%= type %>" ',
                            '       value="<%= value %>" ',
                            '       name="<%= name %>"',
                            '/>'
                        ].join('\n'));
                        for (var i = 0; i < data.form.fields.length; i++) {
                            field = data.form.fields[i];
                            inputsHtml += inputTemplate({
                                label: field.label,
                                type: field.type,
                                value: field.value,
                                name: field.name
                            });
                        }
                        formTemplate = _.template([
                            '<form method="<%= method %>" ',
                            '      action="<%= action %>" ',
                            '      class="villain-form" ',
                            '      name="<%= name %>"',
                            '>',
                            '<%= inputs %>',
                            '</form>'
                        ].join('\n'));
                        form = formTemplate({
                            method: data.form.method,
                            action: that.addToPathName(data.form.action),
                            name: data.form.name,
                            inputs: inputsHtml
                        });
                        $form = $(form);
                        $submitButton = $('<input type="submit" name="' + data.form.name + '-submit" value="Lagre" />');
    
                        $submitButton.on('click', function(e) {
                            e.preventDefault();
    
                            serializedForm = $form.serialize();
                            imagedata = new FormData();
                            imagedata.append('form', serializedForm);
                            imagedata.append('uid', uid);
    
                            $.ajax({
                                type: 'post',
                                url: that.addToPathName(data.form.action),
                                data: imagedata,
                                cache: false,
                                contentType: false,
                                processData: false,
                                dataType: 'json'
                            }).done($.proxy(function(data) {
                                if (data.status == 200) {
                                    // set the image title and credits as data
                                    json = that.getData();
                                    json.title = data.title;
                                    json.credits = data.credits;
                                    json.link = "";
                                    that.setData(json);
                                    that.refreshContentBlock();
                                    that.hideSetup();
                                    that.setup();
                                }
                            }, this));
                        });
                        $form.append($submitButton);
                        this.$setup.append($form);
                    }
                }
            }, this)).fail($.proxy(function() {
                // Failed during upload.
                alert('Feil fra server under opplasting.');
            }, this)).always($.proxy(function() {
                // block.removeQueuedItem, block, uid
            }));
            // block.addQueuedItem(uid, xhr); ?
            this.done();
        },
    
        progressHandlingFunction: function(e) {
            if (e.lengthComputable) {
                // value
                //$('progress').attr({value:e.loaded, max:e.total});
            }
        },
    
        onDragEnter: function(e) {
            this.$('.villain-image-dropper i').addClass('drop-hover');
            e.preventDefault();
        },
    
        onDragLeave: function(e) {
            this.$('.villain-image-dropper i').removeClass('drop-hover');
            e.preventDefault();
        },
    
        onDragOver: function(e) {
            e.preventDefault();
        },
    
        onDropImage: function(e) {
            e.preventDefault();
            this.$('.villain-image-dropper i').removeClass('drop-hover');
            dataTransfer = e.originalEvent.dataTransfer;
            var file = dataTransfer.files[0],
                urlAPI = (typeof URL !== 'undefined') ? URL : (typeof webkitURL !== 'undefined') ? webkitURL : null;
    
            // Handle one upload at a time
            if (/image/.test(file.type)) {
                // Show this image on here
                this.$('.villain-image-dropper').html($('<img>', {src: urlAPI.createObjectURL(file)}));
                $form = $([
                    '<form enctype="multipart/form-data" ',
                          'encoding="multipart/form-data" action="upload/image" ',
                          'method="post" id="villain-upload-form-' + this.dataId + '">',
                        '<input id="villain-upload-file-' + this.dataId + '" ',
                               'type="file" ',
                               'name="villain-upload-file-' + this.dataId + '" ',
                               'accept="image/*">',
                    '</form>'].join('\n'));
    
                this.$setup.append('<hr>');
                this.$setup.append(
                    '<button class="villain-image-dropper-upload">Last opp og lagre</button>'
                );
                this.file = file;
            }
        },
    
        getJSON: function() {
            data = this.getData();
            json = {
                type: this.type,
                data: {
                    url: data.url,
                    sizes: data.sizes,
                    title: data.title || "",
                    credits: data.credits || "",
                    link: data.link || ""
                }
            };
            return json;
        },
    
        getHTML: function() {
            url = this.$('img').attr('src');
            return this.template({url: url});
        },
    
        setup: function() {
            // check if this block has data. if not, show the setup div
            that = this;
            if (!this.hasData()) {
                this.$('.villain-image-block').hide();
                $imageDropper = $([
                    '<div class="villain-image-dropper"><i class="fa fa-image"></i>',
                        '<div>Dra bildet du vil laste opp hit</div>',
                        '<div><hr></div>',
                        '<div>',
                            '<button class="villain-image-browse-button">Hent bilde fra server</button>',
                        '</div>',
                    '</div>'
                ].join('\n'));
                $imageDropper.find('.villain-image-browse-button').on('click', $.proxy(this.onImageBrowseButton, this));
                this.$setup.append($imageDropper);
                this.$setup.show();
            } else {
                this.clearSetup();
                data = this.getData();
                $meta = $([
                    '<label for="title">Tittel</label><input value="' + data.title + '" type="text" name="title" />',
                    '<label for="credits">Kreditering</label><input value="' + data.credits + '" type="text" name="credits" />',
                    '<label for="link">URL</label><input value="' + data.link + '" type="text" name="link" />'
                ].join('\n'));
                this.$setup.append($meta);
                this.$setup.find('input[name="title"]').on('keyup', _.debounce(function (e) {
                    that.setDataProperty('title', $(this).val());
                }, 700, false));
                this.$setup.find('input[name="credits"]').on('keyup', _.debounce(function (e) {
                    that.setDataProperty('credits', $(this).val());
                }, 700, false));
                this.$setup.find('input[name="link"]').on('keyup', _.debounce(function (e) {
                    that.setDataProperty('link', $(this).val());
                }, 700, false));
    
                this.$setup.append($('<label>Størrelse</label>'));
    
                /* create sizes overview */
                for (var key in data.sizes) {
                    if (data.sizes.hasOwnProperty(key)) {
                        checked = '';
                        if (data.sizes[key] == data.url) {
                            checked = ' checked="checked"';
                        }
                        $radio = $('<label for="' + key +'">'
                               + '<input type="radio" name="' + 'imagesize'
                               + '" value="' + data.sizes[key] + '"'
                               + checked + ' />' + key + '</label>');
                        this.$setup.append($radio);
                    }
                }
                this.$setup.find('input[type=radio]').on('change', $.proxy(function(e) {
                    this.setUrl($(e.target).val());
                }, this));
                this.hideSetup();
            }
        },
    
        setUrl: function(url) {
            this.setDataProperty('url', url);
            this.refreshContentBlock();
        },
    
        onImageBrowseButton: function(e) {
            e.preventDefault();
            this.loading();
            $.ajax({
                type: 'get',
                url: this.addToPathName(Villain.options['browseURL']),
                cache: false,
                contentType: false,
                processData: false,
                dataType: 'json'
            }).done($.proxy(function(data) {
                /**
                 * Data returned from image browse.
                 */
                if (data.status != 200) {
                    alert('Ingen bilder fantes.');
                    this.done();
                    return false;
                }
                if (!data.hasOwnProperty('images')) {
                    return false;
                }
                $images = $('<div />');
                for (var i = 0; i < data.images.length; i++) {
                    img = data.images[i];
                    $store_img = $('<img src="' + img.thumb + '" />');
                    $store_img.data('sizes', img.sizes)
                              .data('large', img.src)
                              .data('title', img.title)
                              .data('credits', img.credits);
                    $images.append($store_img);
                }
                $images.on('click', 'img', $.proxy(function(e) {
                    this.setData({
                        url: $(e.target).data('large'),
                        title: $(e.target).data('title'),
                        credits: $(e.target).data('credits'),
                        sizes: $(e.target).data('sizes')
                    });
                    data = this.getData();
                    this.refreshContentBlock();
                    this.hideSetup();
                    this.setup();
                }, this));
    
                this.$setup.html('');
                this.$setup.append('<div class="villain-message success">Klikk på bildet du vil sette inn</div>');
                this.$setup.append($images);
                this.done();
            }, this));
        },
    
        onUploadImagesButton: function(e) {
            var files = e.target.files,
                urlAPI = (typeof URL !== 'undefined') ? URL : (typeof webkitURL !== 'undefined') ? webkitURL : null;
            fileList = [];
            for (var i = 0; i < files.length; i++) {
                var f = files[i];
                fileList.push([
                    '<div class="three">',
                    '<div class="center-cropped" style="background-image: url(', urlAPI.createObjectURL(f), ');"></div>',
                    '</div>'].join('\n')
                );
            }
            listHTML = '<div style="margin-top: 10px;" class="wrapper"><div class="row">';
            for (var x = 0; x < fileList.length; x++) {
                if (x && (x  % 4) === 0) {
                    // add row
                    listHTML += '</div><div style="margin-top: 15px" class="row">' + fileList[x];
                } else {
                    listHTML += fileList[x];
                }
            }
            listHTML += '</div></div>';
            this.$setup.append(listHTML);
        }
    },
    {
        /* static methods */
        getButton: function(afterId) {
            var blockType = 'image';
            t = _.template([
                '<button class="villain-block-button" data-type="<%= type %>" data-after-block-id="<%= id %>">',
                '<i class="fa fa-file-image-o"></i>',
                '<p>img</p>',
                '</button>'].join('\n'));
            return t({id: afterId, type: blockType});
        }
    });
    Villain.Blocks.Slideshow = Villain.Block.extend({
        type: 'slideshow',
        template: _.template([
            '<div class="villain-slideshow-block villain-content" contenteditable="false">',
              '<h4>Slideshow</h4>',
              '<%= content %>',
            '</div>'
        ].join('\n')),
    
        renderEditorHtml: function() {
            blockTemplate = this.renderContentBlockHtml();
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        renderContentBlockHtml: function() {
            images = this.renderDataImages();
            return this.template({content: images});
        },
    
        renderDataImages: function() {
            var data = this.getData();
            if (_.isUndefined(data.images)) {
                return "";
            } else {
                var html = "";
                for (var i = 0; i < data.images.length; i++) {
                    img = data.images[i];
                    html += '<img src="' + data.media_url + '/' + img.sizes.thumb + '" />';
                }
                return html;
            }
        },
    
        renderEmpty: function() {
            blockTemplate = this.template({content: '<i class="fa fa-th"></i>'});
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        getAllImageseries: function() {
            that = this;
            $select = this.$setup.find('.imageserie-select');
            $.ajax({
                type: 'get',
                dataType: 'json',
                accepts: {
                    json: 'text/json'
                },
                url: this.addToPathName(Villain.options['imageseriesURL']),
                cache: false,
                contentType: false,
                processData: false,
                // Custom XMLHttpRequest
                xhr: function() {
                    var customXhr = $.ajaxSettings.xhr();
                    // Check if upload property exists
                    if (customXhr.upload) {
                        customXhr.upload.addEventListener('progress', that.progressHandlingFunction, false);
                    }
                    return customXhr;
                }
            }).done($.proxy(function(data) {
                /**
                 * Callback after confirming upload
                 */
                if (data.status == '200') {
                    $select.append(that.buildOptions(data.series, true));
                    if (!_.isUndefined(that.data.imageseries)) {
                        $select.val(that.data.imageseries).change();
                    }
                }
            }));
        },
    
        getImageseries: function(series) {
            $.ajax({
                type: 'get',
                dataType: 'json',
                accepts: {json: 'text/json'},
                url: this.addToPathName(Villain.options['imageseriesURL']),
                data: {series: series},
                cache: false,
                contentType: false,
                // Custom XMLHttpRequest
                xhr: function() {
                    var customXhr = $.ajaxSettings.xhr();
                    // Check if upload property exists
                    if (customXhr.upload) {
                        customXhr.upload.addEventListener('progress', that.progressHandlingFunction, false);
                    }
                    return customXhr;
                }
            }).done($.proxy(function(data) {
                /**
                 * Callback after confirming upload
                 */
                if (data.status == '200') {
                    var json = {};
    
                    json.imageseries = data.series;
                    json.media_url = data.media_url;
                    json.images = data.images;
    
                    if (that.$setup.find('.imageserie-size-select').length > 0) {
                        // we already have the size select
                    } else {
                        // add size dropdown
                        var sizeSelect = '<label for="imageserie-size">Str:</label>' +
                                         '<select class="imageserie-size-select" ' +
                                         '        name="imageserie-size"></select>';
                        that.$setup.append(sizeSelect);
                    }
    
                    var $sizeSelect = that.$setup.find('.imageserie-size-select');
                    $sizeSelect.html('');
                    $sizeSelect.append(that.buildOptions(data.sizes, true));
                    if (!_.isUndefined(that.data.size)) {
                        $sizeSelect.val(that.data.size).change();
                        json.size = that.data.size;
                    }
                    $sizeSelect.on('change', function(e) {
                        json.size = $(this).val();
                        that.hideSetup();
                    });
                    that.setData(json);
                    that.refreshContentBlock();
                }
            }));
        },
    
        buildOptions: function(values, placeholder) {
            if (placeholder) {
                html = '<option disabled="disabled" selected="selected">---</option>';
            } else {
                html = '';
            }
            for (var i = 0; i < values.length; i++) {
                val = values[i];
                html += '<option value="' + val + '">' + val + '</option>';
            }
            return html;
        },
    
        setup: function() {
            if (!this.hasData()) {
                this.$content.hide();
    
                that = this;
                data = this.getData();
                //this.$setup.hide();
                var select = '<select class="imageserie-select" name="imageserie"></select>';
                this.$setup.append($([
                    '<label for="imageserie">Bildeserie</label>',
                    select
                ].join('\n')));
    
                $select = this.$setup.find('.imageserie-select');
                $select.on('change', function(e) {
                    that.getImageseries($(this).val());
                });
    
                this.getAllImageseries();
            } else {
                this.$setup.hide();
                var select = '<select class="imageserie-select" name="imageserie"></select>';
                this.$setup.append($([
                    '<label for="imageserie">Bildeserie</label>',
                    select
                ].join('\n')));
    
                $select = this.$setup.find('.imageserie-select');
                $select.on('change', function(e) {
                    that.getImageseries($(this).val());
                });
                this.getAllImageseries();
            }
        },
    
        getData: function() {
            data = this.data;
            return data;
        },
    
        getJSON: function() {
            var data = this.getData();
            // strip out images, we don't need to store them since they are
            // already in the DB.
            delete data.images;
            delete data.media_url;
            json = {
                type: this.type,
                data: data
            };
            return json;
        },
    
        getHTML: function() {
            textNode = this.getTextBlock().html();
            return '<h3>' + markdown.toHTML(textNode) + '</h3>';
        }
    },
    {
        /* static methods */
        getButton: function(afterId) {
            var blockType = 'slideshow';
            t = _.template([
                '<button class="villain-block-button" data-type="<%= type %>" data-after-block-id="<%= id %>">',
                '<i class="fa fa-th"></i>',
                '<p>slides</p>',
                '</button>'].join('\n'));
            return t({
                id: afterId,
                type: blockType
            });
        }
    });
    Villain.Blocks.Video = Villain.Block.extend({
        type: 'video',
    
        providers: {
            vimeo: {
                regex: /(?:http[s]?:\/\/)?(?:www.)?vimeo.com\/(.+)/,
                html: ['<iframe src=\"{{protocol}}//player.vimeo.com/video/{{remote_id}}?title=0&byline=0\" ',
                       'width=\"580\" height=\"320\" frameborder=\"0\"></iframe>'].join('\n')
            },
            youtube: {
                regex: /(?:http[s]?:\/\/)?(?:www.)?(?:(?:youtube.com\/watch\?(?:.*)(?:v=))|(?:youtu.be\/))([^&].+)/,
                html: ['<iframe src=\"{{protocol}}//www.youtube.com/embed/{{remote_id}}\" ',
                       'width=\"580\" height=\"320\" frameborder=\"0\" allowfullscreen></iframe>'].join('\n')
            }
        },
    
        template: _.template(
            '<div class="villain-video-block villain-content"><%= content %></div>'
        ),
    
        events: {
            'click .villain-setup-block button': 'onClick'
        },
    
        onClick: function(e) {
            e.preventDefault();
            videoUrl = this.$('.villain-video-setup-url').val();
            // parse the url
            if (!_.isURI(videoUrl)) {
                return;
            }
    
            embedString = this.buildString(videoUrl);
    
            this.$content.html(embedString);
            this.hideSetup();
        },
    
        buildString: function(videoUrl) {
            var match, data;
    
            _.each(this.providers, function(provider, index) {
                match = provider.regex.exec(videoUrl);
    
                if (match !== null && !_.isUndefined(match[1])) {
                    data = {
                        source: index,
                        remote_id: match[1]
                    };
                    this.setData(data);
                }
            }, this);
    
            if (!this.providers.hasOwnProperty(data.source)) {
                return;
            }
    
            var embedString = this.providers[data.source].html
                .replace('{{protocol}}', window.location.protocol)
                .replace('{{remote_id}}', data.remote_id)
                .replace('{{width}}', '100%'); // for videos that can't resize automatically like vine
    
            return embedString;
        },
    
        initialize: function(json, store) {
            Villain.Block.prototype.initialize.apply(this, [json, store]);
            _.extend(this.events, Villain.Block.prototype.events);
        },
    
        renderEditorHtml: function() {
            if (!this.providers.hasOwnProperty(this.data.source)) {
                return;
            }
    
            var embedString = this.providers[this.data.source].html
                .replace('{{protocol}}', window.location.protocol)
                .replace('{{remote_id}}', this.data.remote_id)
                .replace('{{width}}', '100%'); // for videos that can't resize automatically like vine
    
            blockTemplate = this.template({content: embedString});
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        renderEmpty: function() {
            blockTemplate = this.template({content: ''});
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return wrapperTemplate;
        },
    
        getJSON: function() {
            url = this.$('img').attr('src');
            json = {
                type: this.type,
                data: this.data
            };
            return json;
        },
    
        getHTML: function() {
            url = this.$('img').attr('src');
            return this.template({url: url});
        },
    
        setup: function() {
            // check if this block has data
            // if not, show the setup div
            if (!this.hasData()) {
                this.$('.villain-video-block').hide();
                videoSetup = $([
                    '<div class="villain-video-setup-icon">',
                        '<i class="fa fa-video-camera"></i>',
                        '<div>Lim inn link til youtube eller vimeo, f.eks http://www.youtube.com/watch?v=jlbunmCbTBA</div>',
                    '</div>',
                    '<div class="villain-video-setup-input-wrapper">',
                        '<input type="text" name="villain-video-setup-url" class="villain-video-setup-url" />',
                    '</div>',
                    '<div><hr></div>',
                    '<div style="text-align: center;"><button>Hent video</button></div>',
                ].join('\n'));
                this.$setup.append(videoSetup);
                this.$setup.show();
            }
        }
    },
    {
        /* static methods */
        getButton: function(afterId) {
            var blockType = 'video';
            t = _.template([
                '<button class="villain-block-button" data-type="<%= type %>" data-after-block-id="<%= id %>">',
                '<i class="fa fa-video-camera"></i>',
                '<p>video</p>',
                '</button>'].join('\n'));
            return t({
                id: afterId,
                type: blockType
            });
        }
    });

    /* Columns */
    
    Villain.Blocks.Columns = Villain.Block.extend({
        type: 'columns',
        template: _.template('<div class="row"></div>'),
        columnTemplate: _.template('<div class="<%= columnClass %>"></div>'),
    
        events: {
            'keyup input[name="villain-columns-number"]': '_updateColumnCount',
            'click button.villain-columns-apply': '_applyColumnCount'
        },
    
        initialize: function(json, store) {
            Villain.Block.prototype.initialize.apply(this, [json, store]);
            _.extend(this.events, Villain.Block.prototype.events);
        },
    
        deleteBlock: function() {
            // delete the store containing all the child blocks
            if (Villain.BlockStore.hasOwnProperty(this.store)) {
                Villain.BlockStore.delStore(this.store);
            }
            // delete the block from mainstore
            Villain.BlockStore.del('main', this.dataId);
            // destroy block
            this.destroy();
        },
    
        renderBlock: function(block) {
            // overrides the editors renderer, since we want the blocks to
            // render inside the column view.
            // But only if we're the parent!
            if (!block.$parent) {
                return false;
            }
            if (block.$parent.attr('id') === this.$el.attr('id')) {
                this.$el.append(block.el);
            }
        },
    
        // override render
        render: function() {
            // create a blockstore for these columns
            Villain.BlockStore.create(this.id);
            this.store = this.id;
            this.$el.attr('data-blockstore', this.store);
    
            blockTemplate = this.template({content: this.data});
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            this.el.innerHTML = wrapperTemplate;
    
            this.$inner = this.$('.villain-block-inner');
            this.$content = this.$('.row');
    
            if (this.data) {
                // we got passed data. render editorhtml
                this.renderEditorHtml();
            } else {
                // no data, probably want a blank block
                this.renderEmpty();
            }
    
            if (this.setup) {
                // the block has a setup method - add the setupTemplate
                // and call setup()
                this.$inner.prepend(this.setupTemplate());
                this.$setup = this.$('.villain-setup-block');
                this.setup();
            }
    
            return this;
        },
    
        renderEditorHtml: function() {
            this.parseRow();
            blockTemplate = this.template({content: this.data});
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return this;
        },
    
        renderEmpty: function() {
            blockTemplate = this.template({content: this.data});
            actionsTemplate = this.actionsTemplate();
            wrapperTemplate = this.wrapperTemplate({content: blockTemplate, actions: actionsTemplate});
            return this;
        },
    
        getRow: function() {
            if (this.$row) {
                return this.$row;
            }
            this.$row = this.$('.row');
            return this.$row;
        },
    
        getColumns: function(filter) {
          return this.getRow().children(filter);
        },
    
        getColumn: function(index) {
          return this.getRow().children(':eq(' + index + ')');
        },
    
        parseRow: function() {
            // create the columns
            $row = this.getRow();
            for (var i = 0; i <= this.data.length - 1; i++) {
                columnClass = this.data[i].class;
                columnData = this.data[i].data;
                $column = $('<div class="' + columnClass + '"></div>');
                $row.append($column);
                $column = this.getColumn(i);
                addblock = new Villain.Plus(this.store);
                $column.append(addblock.$el);
                for (var j = 0; j < columnData.length; j++) {
                    if ((BlockClass = Villain.BlockRegistry.getBlockClassByType(columnData[j].type)) !== false) {
                        block = new BlockClass(columnData[j].data, this.store);
                        $column.append(block.$el);
                        addblock = new Villain.Plus(this.store);
                        $column.append(addblock.$el);
                    }
                }
            }
        },
    
        getJSON: function() {
            var json = {
                type: this.type,
                data: []
            };
            this.getColumns().each(function(i) {
                var blocksData = [];
                $(this).children('.villain-block-wrapper').each(function() {
                    var block = Villain.BlockStore.getBlockById(
                        $(this).attr('data-blockstore'), $(this).attr('data-block-id'));
                    blocksData.push(block.getJSON());
                });
                json.data.push({'class': $(this).attr('class'), data: blocksData});
            });
    
            return json;
        },
    
        setup: function() {
            // check if this block has data
            // if not, show the setup div
            if (!this.hasData()) {
                this.getRow().hide();
                this.$setup.append([
                    '<label for="villain-columns-number">Antall kolonner</label>',
                    '<input type="text" class="villain-columns-number" name="villain-columns-number" />'
                ].join('\n'));
                this.$setup.show();
                this.$('.villain-columns-number').attr('autofocus', 'autofocus');
            } else {
                this.$setup.hide();
            }
        },
    
        _updateColumnCount: function(e) {
            var columnCount = $(e.target).val();
            this.$('.villain-column-widths').remove();
            columnCountWrapper = $('<div class="villain-column-widths" />');
            for (var i = 1; i < (parseInt(columnCount) + 1); i++) {
                columnCountWrapper.append([
                    '<label for="villain-column-width-' + i + '">' +
                    'Kolonne ' + i + ' klassenavn (one, two, three ...)</label>',
                    '<input type="text" name="villain-column-width-' + i + '" class="villain-column-width" />'
                ].join('\n'));
            }
            columnCountWrapper.append('<button class="villain-columns-apply">Sett opp kolonner</button>');
            this.$setup.append(columnCountWrapper);
    
        },
    
        _applyColumnCount: function(e) {
            e.preventDefault();
            columnCount = this.$('input[name="villain-columns-number"]').val();
            for (var i = 1; i < (parseInt(columnCount) + 1); i++) {
                columnClass = this.$('input[name="villain-column-width-' + i + '"]').val();
                this.getRow().append(this.columnTemplate({columnClass: columnClass}));
                addblock = new Villain.Plus(this.store);
                this.getColumn(i - 1).append(addblock.$el);
            }
            // hide the setup
            this.$setup.hide();
            // show the row
            this.getRow().show();
        },
    
        onSetupClick: function(e) {
            e.stopPropagation();
            // is it active now?
            $button = this.$('.villain-action-button-setup');
            if ($button.hasClass('active')) {
                // hide the setup
                $button.removeClass('active');
                this.hideSetup();
            } else {
                $button.addClass('active');
                this.showSetup();
            }
        },
    
        renderPlus: function() {
            addblock = new Villain.Plus('main');
            return addblock;
        }
    },
    {
        /* Static methods */
        getButton: function(afterId) {
            var blockType = 'columns';
            t = _.template([
                '<button class="villain-block-button" data-type="<%= type %>" data-after-block-id="<%= id %>">',
                '<i class="fa fa-columns"></i>',
                '<p>cols</p>',
                '</button>'
            ].join('\n'));
    
            return t({id: afterId, type: blockType});
        }
    });

    var blocks = [];

    Villain.Editor = Backbone.View.extend({
        el: '#villain',
        textArea: '#id_body',
        data: {},
        blocks: {},
    
        events: {
            'submit form': 'clickSubmit',
            'dragover .villain-droppable': 'onDragOverDroppable',
            'dragenter .villain-droppable': 'onDragEnterDroppable',
            'dragleave .villain-droppable': 'onDragLeaveDroppable',
            'drop .villain-droppable': 'onDropDroppable',
            'drop .villain-text-block': 'onDropTextblock'
        },
    
        initialize: function(options) {
            _this = this;
            this.$textArea = $(options.textArea) || this.textArea;
            $('<div id="villain"></div>').insertAfter(this.$textArea);
            this.el = "#villain";
            this.$el = $(this.el);
    
            this.$textArea.hide();
            this.isDirty = false;
            try {
                this.data = JSON.parse(this.$textArea.val());
            } catch (e) {
                this.data = null;
            }
            // inject json to textarea before submitting.
            $('form').submit(function( event ) {
                _this.$textArea.val(_this.getJSON());
            });
            // create a blockstore
            Villain.BlockStore.create('main');
            Villain.setOptions(options);
            // initialize registry with optional extra blocks
            Villain.BlockRegistry.initialize(options.extraBlocks);
            this.render();
        },
    
        render: function() {
            // add + block
            addblock = new Villain.Plus('main');
            this.$el.append(addblock.$el);
            // add format popup
            formatPopUp = new Villain.FormatPopUp();
            this.$el.append(formatPopUp.$el);
            // parse json
            if (!this.data) {
                return false;
            }
            for (var i = 0; i <= this.data.length - 1; i++) {
                blockJson = this.data[i];
                if ((BlockClass = Villain.BlockRegistry.getBlockClassByType(blockJson.type)) !== false) {
                    block = new BlockClass(blockJson.data);
                    this.$el.append(block.$el);
                    this.$el.append(block.renderPlus().$el);
                } else {
                    console.error('Villain: No class found for type: ' + blockJson.type);
                }
            }
        },
    
        organizeMode: function() {
            $('.villain-block-wrapper').toggleClass('organize');
            $('.villain-block-wrapper[data-block-type="columns"]').removeClass('organize');
            $('.organize .villain-content').hide();
        },
    
        getJSON: function() {
            var json = [];
            this.$('.villain-block-wrapper').each(function() {
                // check the main block store for the id. if it's not there
                // it probably belongs to a superblock
                if ((block = Villain.BlockStore.getBlockById('main', $(this).data('block-id'))) !== false) {
                    blockJson = block.getJSON();
                    json.push(blockJson);
                }
            });
            ret = JSON.stringify(json);
            return ret != "[]" ? ret : "";
        },
    
       onDragEnterDroppable: function(e) {
            $('.villain-add-block-button', e.currentTarget).addClass('drop-hover');
            e.preventDefault();
            e.stopPropagation();
        },
    
        onDragLeaveDroppable: function(e) {
            $('.villain-add-block-button', e.currentTarget).removeClass('drop-hover');
            e.preventDefault();
            e.stopPropagation();
        },
    
        onDragOverDroppable: function(e) {
            e.preventDefault();
            e.stopPropagation();
        },
    
        onDropDroppable: function(e) {
            //do something
            target = e.currentTarget;
            if ($(target).hasClass('villain-droppable') !== true) {
                e.preventDefault();
                e.stopPropagation();
                return false;
            }
            $('.villain-add-block-button', target).removeClass('drop-hover');
            sourceId = e.originalEvent.dataTransfer.getData('text/plain');
            $source = $('[data-block-id=' + sourceId + ']');
            $sourceAdd = $source.next();
            $source.detach();
            $sourceAdd.detach();
    
            // move the block
            // we have to remove it from its current blockstore,
            // and add it to the new blockstore!
            $source.insertAfter($(target));
            oldBlockStore = $source.attr('data-blockstore');
            newBlockStore = $(target).attr('data-blockstore');
            // get the block from old blockstore
            block = Villain.BlockStore.getBlockById(oldBlockStore, sourceId);
            block.store = newBlockStore;
            Villain.BlockStore.del(oldBlockStore, sourceId);
            Villain.BlockStore.add(newBlockStore, sourceId, block);
            $source.attr('data-blockstore', newBlockStore);
            $sourceAdd.insertAfter($source);
            $sourceAdd.attr('data-blockstore', newBlockStore);
            // get the block store
        },
    
        onDropTextblock: function(e) {
            $target = $(e.currentTarget).closest('.villain-block-wrapper').shake();
            e.preventDefault();
            e.stopPropagation();
            return false;
        },
    
        clickSubmit: function(e) {
            Villain.EventBus.trigger('posts:submit', e);
            form = this.checkForm();
            if (form.valid === false) {
                e.preventDefault();
            }
            window.onbeforeunload = $.noop();
        },
    
        checkForm: function() {
            var form = {
                valid: true,
                errors: []
            };
            if ($titleEl.val() === '') {
                form.errors.push('Overskrift kan ikke være blank.');
                form.valid = false;
                $titleEl.parent().parent().addClass('error');
                $titleEl.parent().parent().append(
                    '<span class="help-inline"><strong><i class="icon-hand-up"></i> Feltet er påkrevet.</strong></span>'
                );
                $('html, body').animate({
                    scrollTop: 0
                }, 5);
            }
            // clean body text here?
            return form;
        },
    
        markDirty: function() {
            this.isDirty = true;
        },
    });

    Villain.FormatPopUp = Backbone.View.extend({
        tagName: 'div',
        className: 'villain-format-popup',
    
        events: {
            'click .villain-format-bold': 'onClickBold',
            'click .villain-format-italic': 'onClickItalic',
            'click .villain-format-link': 'onClickLink',
            'click .villain-format-unlink': 'onClickUnlink'
        },
    
        onClickBold: function(e) {
            e.preventDefault();
            document.execCommand('bold', false, false);
            this.activateButton('.villain-format-bold');
        },
    
        onClickItalic: function(e) {
            e.preventDefault();
            document.execCommand('italic', false, false);
            this.activateButton('.villain-format-italic');
        },
    
        onClickLink: function(e) {
            e.preventDefault();
            var link = prompt('Sett inn link:'),
                link_regex = /((ftp|http|https):\/\/.)|mailto(?=\:[-\.\w]+@)/;
    
            if (link && link.length > 0) {
                if (!link_regex.test(link)) {
                    link = 'http://' + link;
                }
                document.execCommand('CreateLink', false, link);
            }
            this.activateButton('.villain-format-link');
        },
    
        onClickUnlink: function(e) {
            e.preventDefault();
            document.execCommand('unlink', false, false);
        },
    
        initialize: function() {
            this.render();
            // listen to events
            Villain.EventBus.on('formatpopup:show', this.showPopUp, this);
            Villain.EventBus.on('formatpopup:hide', this.hidePopUp, this);
        },
    
        render: function() {
            // add buttons
            this.$el.append('<button class="popup-button villain-format-bold"><i class="fa fa-bold"></i></button>');
            this.$el.append('<button class="popup-button villain-format-italic"><i class="fa fa-italic"></i></button>');
            this.$el.append('<button class="popup-button villain-format-link"><i class="fa fa-link"></i></button>');
            this.$el.append('<button class="popup-button villain-format-unlink"><i class="fa fa-unlink"></i></button>');
            return this;
        },
    
        showPopUp: function(view) {
            $el = view.$el;
            var selection = window.getSelection(),
                range = selection.getRangeAt(0),
                boundary = range.getBoundingClientRect(),
                offset = $el.offset(),
                coords = {};
                mainContent = $('section#maincontent');
    
            coords.top = boundary.top + mainContent.scrollTop();
            // 12 is padding for text-block
            coords.left = ((boundary.left + boundary.right) / 2) - (this.$el.width() / 2) - offset.left + 12;
            if (parseInt(coords.left) < 0) {
                coords.left = '0';
            }
            coords.left = coords.left  + 'px';
    
            this.deactivateButtons();
            this.activeButtons();
            this.$el.addClass('show-popup');
            this.$el.css(coords);
        },
    
        hidePopUp: function() {
            this.$el.removeClass('show-popup');
        },
    
        activeButtons: function() {
            var selection = window.getSelection(),
                node;
    
            if (selection.rangeCount > 0) {
                node = selection.getRangeAt(0)
                              .startContainer
                              .parentNode;
            }
    
            // link
            if (node && node.nodeName == 'A') {
                this.activateButton('.villain-format-link');
            }
            if (document.queryCommandState('bold')) {
                this.activateButton('.villain-format-bold');
            }
            if (document.queryCommandState('italic')) {
                this.activateButton('.villain-format-italic');
            }
        },
    
        activateButton: function(className) {
            this.$(className).addClass('active');
        },
    
        deactivateButtons: function() {
            this.$('.popup-button').removeClass('active');
        }
    });

    Villain.Editor.HTML = Villain.Editor.HTML || {};
    Villain.Editor.EditorHTML = Villain.Editor.EditorHTML || {};

    Villain.toMD = function toMD(html) {
        var html = toMarkdown(html);
        html = html.replace(/&nbsp;/g,' ');
        // Divitis style line breaks (handle the first line)
        html = html.replace(/([^<>]+)(<div>)/g,'$1\n$2')
                    // (double opening divs with one close from Chrome)
                    .replace(/<div><div>/g,'\n<div>')
                    .replace(/<div><br \/><\/div>/g, '\n\n')
                    .replace(/(?:<div>)([^<>]+)(?:<div>)/g,'$1\n')
                    // ^ (handle nested divs that start with content)
                    .replace(/(?:<div>)(?:<br>)?([^<>]+)(?:<br>)?(?:<\/div>)/g,'$1\n')
                    // ^ (handle content inside divs)
                    .replace(/<\/p>/g,'\n\n')
                    // P tags as line breaks
                    .replace(/<(.)?br(.)?>/g,'\n')
                    // Convert normal line breaks
                    .replace(/&lt;/g,'<').replace(/&gt;/g,'>');
                    // Encoding

        // strip whatever might be left.
        aggressiveStrip = true;
        if (aggressiveStrip) {
            html = html.replace(/<\/?[^>]+(>|$)/g, '');
        } else {
            // strip rest of the tags
            html = html.replace(/<(?=\S)\/?[^>]+(>|$)/ig, '');
        }
        return html;
    };

    Villain.toHTML = function toHTML(markdown, type) {
        // MD -> HTML
        if (_.isUndefined(markdown)) {
            return "";
        }

        type = _.classify(type);

        var html = markdown,
            shouldWrap = type === 'Text';

        if (_.isUndefined(shouldWrap)) { shouldWrap = false; }

        if (shouldWrap) {
            html = '<div>' + html;
        }

        html = html.replace(/\[([^\]]+)\]\(([^\)]+)\)/gm, function(match, p1, p2) {
            return '<a href="' + p2 + '">' + p1.replace(/\r?\n/g, '') + '</a>';
        });

        // This may seem crazy, but because JS doesn't have a look behind,
        // we reverse the string to regex out the italic items (and bold)
        // and look for something that doesn't start (or end in the reversed strings case)
        // with a slash.
        html = _.reverse(
            _.reverse(html)
            .replace(/_(?!\\)((_\\|[^_])*)_(?=$|[^\\])/gm, function(match, p1) {
                return '>i/<' + p1.replace(/\r?\n/g, '').replace(/[\s]+$/,'') + '>i<';
            })
            .replace(/\*\*(?!\\)((\*\*\\|[^\*\*])*)\*\*(?=$|[^\\])/gm, function(match, p1) {
                return '>b/<' + p1.replace(/\r?\n/g, '').replace(/[\s]+$/,'') + '>b<';
            })
        );

        html =  html.replace(/^\> (.+)$/mg,'$1');

        // Use custom formatters toHTML functions (if any exist)
        var formatName, format;
        for (formatName in Villain.Formatters) {
            if (Villain.Formatters.hasOwnProperty(formatName)) {
                format = Villain.Formatters[formatName];
                // Do we have a toHTML function?
                if (!_.isUndefined(format.toHTML) && _.isFunction(format.toHTML)) {
                    html = format.toHTML(html);
                }
            }
        }

        if (shouldWrap) {
            html = html.replace(/\r?\n\r?\n/gm, '</div><div><br></div><div>')
                       .replace(/\r?\n/gm, '</div><div>');
        }

        html = html.replace(/\t/g, '&nbsp;&nbsp;&nbsp;&nbsp;')
                   .replace(/\r?\n/g, '<br>')
                   .replace(/\*\*/, '')
                   .replace(/__/, '');  // Cleanup any markdown characters left

        // Replace escaped
        html = html.replace(/\\\*/g, '*')
                   .replace(/\\\[/g, '[')
                   .replace(/\\\]/g, ']')
                   .replace(/\\\_/g, '_')
                   .replace(/\\\(/g, '(')
                   .replace(/\\\)/g, ')')
                   .replace(/\\\-/g, '-');

        if (shouldWrap) {
            html += '</div>';
        }

        return html;
    };

    Villain.setOptions = function setOptions(options) {
        if (_.isUndefined(options.imageSeries) || _.isUndefined(options.baseURL)) {
            console.error("Villain: baseURL and imageSeries MUST be set on initialization.");
        }
        Villain.defaults.browseURL = options.baseURL + Villain.defaults.browseURL + options.imageSeries;
        Villain.defaults.uploadURL = options.baseURL + Villain.defaults.uploadURL + options.imageSeries;
        Villain.defaults.imageseriesURL = options.baseURL + Villain.defaults.imageseriesURL;
        Villain.options = $.extend({}, Villain.defaults, options);
    };

    Villain.browser = function browser() {
        var browser = {};

        if (this.getIEversion() > 0) {
            browser.msie = true;
        } else {
            var ua = navigator.userAgent.toLowerCase(),
            match = /(chrome)[ \/]([\w.]+)/.exec(ua) ||
                    /(webkit)[ \/]([\w.]+)/.exec(ua) ||
                    /(opera)(?:.*version|)[ \/]([\w.]+)/.exec(ua) ||
                    /(msie) ([\w.]+)/.exec(ua) ||
                    ua.indexOf('compatible') < 0 && /(mozilla)(?:.*? rv:([\w.]+)|)/.exec(ua) ||
                    [],

            matched = {
                browser: match[1] || '',
                version: match[2] || '0'
            };

            if (match[1]) {
                browser[matched.browser] = true;
            }
            if (parseInt(matched.version, 10) < 9 && browser.msie) {
                browser.oldMsie = true;
            }

            // Chrome is Webkit, but Webkit is also Safari.
            if (browser.chrome) {
                browser.webkit = true;
            } else if (browser.webkit) {
                browser.safari = true;
            }
        }
        return browser;
    };

    Villain.Editor.processPaste = function processPaste(pastedFrag) {
        var cleanHtml;
        if (pastedFrag.match(/(class=\"?Mso|style=\"[^\"]*\bmso\-|w:WordDocument)/gi)) {
            cleanHtml = Villain.Editor.wordClean(pastedFrag);
            cleanHtml = Villain.Editor.clean($('<div>').append(cleanHtml).html(), false, true);
            cleanHtml = Villain.Editor.removeEmptyTags(cleanHtml);
        } else {
            // Paste.
            cleanHtml = Villain.Editor.clean(pastedFrag, false, true);
            cleanHtml = Villain.Editor.removeEmptyTags(cleanHtml);
        }

        cleanHtml = Villain.Editor.plainPasteClean(cleanHtml);

        // Check if there is anything to clean.
        if (cleanHtml !== '') {
            // Insert HTML.
            return cleanHtml;
        }
    };

    Villain.Editor.wordClean = function wordClean(html) {
        // Keep only body.
        if (html.indexOf('<body') >= 0) {
            html = html.replace(/[.\s\S\w\W<>]*<body[^>]*>([.\s\S\w\W<>]*)<\/body>[.\s\S\w\W<>]*/g, '$1');
        }

        // Single item list.
        html = html.replace(
            /<p(.*?)class="?'?MsoListParagraph"?'?([\s\S]*?)>([\s\S]*?)<\/p>/gi,
            '<ul><li><p>$3</p></li></ul>'
        );

        // List start.
        html = html.replace(
            /<p(.*?)class="?'?MsoListParagraphCxSpFirst"?'?([\s\S]*?)>([\s\S]*?)<\/p>/gi,
            '<ul><li><p>$3</p></li>'
        );

        // List middle.
        html = html.replace(
            /<p(.*?)class="?'?MsoListParagraphCxSpMiddle"?'?([\s\S]*?)>([\s\S]*?)<\/p>/gi,
            '<li><p>$3</p></li>'
        );

        // List end.
        html = html.replace(/<p(.*?)class="?'?MsoListParagraphCxSpLast"?'?([\s\S]*?)>([\s\S]*?)<\/p>/gi,
                '<li><p>$3</p></li></ul>');

        // Clean list bullets.
        html = html.replace(/<span([^<]*?)style="?'?mso-list:Ignore"?'?([\s\S]*?)>([\s\S]*?)<span/gi, '<span><span');

        // Webkit clean list bullets.
        html = html.replace(/<!--\[if \!supportLists\]-->([\s\S]*?)<!--\[endif\]-->/gi, '');

        // Remove mso classes.
        html = html.replace(/(\n|\r| class=(")?Mso[a-zA-Z]+(")?)/gi, ' ');

        // Remove comments.
        html = html.replace(/<!--[\s\S]*?-->/gi, '');

        // Remove tags but keep content.
        html = html.replace(/<(\/)*(meta|link|span|\\?xml:|st1:|o:|font)(.*?)>/gi, '');

        // Remove no needed tags.
        var word_tags = ['style', 'script', 'applet', 'embed', 'noframes', 'noscript'];
        for (var i = 0; i < word_tags.length; i++) {
            var regex = new RegExp('<' + word_tags[i] + '.*?' + word_tags[i] + '(.*?)>', 'gi');
            html = html.replace(regex, '');
        }

        // Remove attributes.
        html = html.replace(/([\w\-]*)=("[^<>"]*"|'[^<>']*'|\w+)/gi, '');

        // Remove spaces.
        html = html.replace(/&nbsp;/gi, '');

        // Remove empty tags.
        var oldHTML;
        do {
            oldHTML = html;
            html = html.replace(/<[^\/>][^>]*><\/[^>]+>/gi, '');
        } while (html != oldHTML);

        html = Villain.Editor.clean(html);

        return html;
    };

    Villain.Editor.clean = function clean(html, allow_id, clean_style, allowed_tags, allowed_attrs) {
        // List of allowed attributes.
        allowed_attrs = [
            'accept', 'accept-charset', 'accesskey', 'action', 'align',
            'alt', 'async', 'autocomplete', 'autofocus', 'autoplay',
            'autosave', 'background', 'bgcolor', 'border', 'charset',
            'cellpadding', 'cellspacing', 'checked', 'cite', 'class',
            'color', 'cols', 'colspan', 'contenteditable', 'contextmenu',
            'controls', 'coords', 'data', 'data-.*', 'datetime',
            'default', 'defer', 'dir', 'dirname', 'disabled',
            'download', 'draggable', 'dropzone', 'enctype', 'for',
            'form', 'formaction', 'headers', 'height', 'hidden', 'high',
            'href', 'hreflang', 'icon', 'id', 'ismap', 'itemprop',
            'keytype', 'kind', 'label', 'lang', 'language', 'list',
            'loop', 'low', 'max', 'maxlength', 'media', 'method',
            'min', 'multiple', 'name', 'novalidate', 'open', 'optimum',
            'pattern', 'ping', 'placeholder', 'poster', 'preload',
            'pubdate', 'radiogroup', 'readonly', 'rel', 'required',
            'reversed', 'rows', 'rowspan', 'sandbox', 'scope', 'scoped',
            'scrolling', 'seamless', 'selected', 'shape', 'size', 'sizes',
            'span', 'src', 'srcdoc', 'srclang', 'srcset', 'start', 'step',
            'summary', 'spellcheck', 'style', 'tabindex', 'target', 'title',
            'type', 'translate', 'usemap', 'value', 'valign', 'width', 'wrap'
        ];
        allowed_tags = [
            '!--', 'a', 'abbr', 'address', 'area', 'article', 'aside',
            'audio', 'b', 'base', 'bdi', 'bdo', 'blockquote', 'br',
            'button', 'canvas', 'caption', 'cite', 'code', 'col',
            'colgroup', 'datalist', 'dd', 'del', 'details', 'dfn',
            'dialog', 'div', 'dl', 'dt', 'em', 'embed', 'fieldset',
            'figcaption', 'figure', 'footer', 'form', 'h1', 'h2',
            'h3', 'h4', 'h5', 'h6', 'header', 'hgroup', 'hr', 'i',
            'iframe', 'img', 'input', 'ins', 'kbd', 'keygen', 'label',
            'legend', 'li', 'link', 'main', 'map', 'mark', 'menu',
            'menuitem', 'meter', 'nav', 'noscript', 'object', 'ol',
            'optgroup', 'option', 'output', 'p', 'param', 'pre',
            'progress', 'queue', 'rp', 'rt', 'ruby', 's', 'samp',
            'script', 'section', 'select', 'small', 'source',
            'span', 'strong', 'style', 'sub', 'summary', 'sup',
            'table', 'tbody', 'td', 'textarea', 'tfoot', 'th',
            'thead', 'time', 'title', 'tr', 'track', 'u', 'ul',
            'var', 'video', 'wbr'
        ];

        // Remove script tag.
        html = html.replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '');

        // Remove all tags not in allowed tags.
        var at_reg = new RegExp('<\\/?((?!(?:' + allowed_tags.join('|') + '))\\w+)[^>]*?>', 'gi');
        html = html.replace(at_reg, '');

        // Remove all attributes not in allowed attrs.
        var aa_reg = new RegExp(
            '( (?!(?:' + allowed_attrs.join('|') +
            '))[a-zA-Z0-9-_]+)=((?:.(?!\\s+(?:\\S+)=|[>]|(\\/>)))+.)', 'gi'
        );
        html = html.replace(aa_reg, '');

        // Clean style.
        var style_reg = new RegExp(
            'style=("[a-zA-Z0-9:;\\.\\s\\(\\)\\-\\,!\\/\'%]*"|' +
            '\'[a-zA-Z0-9:;\\.\\s\\(\\)\\-\\,!\\/"%]*\')', 'gi'
        );
        html = html.replace(style_reg, '');

        // Remove the class.
        var $div = $('<div>').append(html);
        $div.find('[class]:not([class^="fr-"])').each(function(index, el) {
            $(el).removeAttr('class');
        });

        html = $div.html();

        return html;
    };

    Villain.Editor.plainPasteClean = function plainPasteClean(html) {
        var $div = $('<div>').html(html);

        $div.find('h1, h2, h3, h4, h5, h6, pre, blockquote').each(function(i, el) {
            $(el).replaceWith('<p>' + $(el).html() + '</p>');
        });

        var replacePlain = function(i, el) {
            $(el).replaceWith($(el).html());
        };

        while ($div.find('strong, em, strike, b, u, i, sup, sub, span, a').length) {
            $div.find('strong, em, strike, b, u, i, sup, sub, span, a').each (replacePlain);
        }

        return $div.html();
    };

    Villain.Editor.removeEmptyTags = function removeEmptyTags(html) {
        var i,
            $div = $('<div>').html(html),
            empty_tags = $div.find('*:empty:not(br, img, td, th)');

        while (empty_tags.length) {
            for (i = 0; i < empty_tags.length; i++) {
                $(empty_tags[i]).remove();
            }

            empty_tags = $div.find('*:empty:not(br, img, td, th)');
        }

        // Workaround for Notepad paste.
        $div.find('> div').each(function(i, div) {
            $(div).replaceWith($(div).html() + '<br/>');
        });

        // Remove divs.
        var divs = $div.find('div');
        while (divs.length) {
            for (i = 0; i < divs.length; i++) {
                var $el = $(divs[i]),
                    text = $el.html().replace(/\u0009/gi, '').trim();

                $el.replaceWith(text);
            }

            divs = $div.find('div');
        }

        return $div.html();
    };

    Villain.Editor.pasteHtmlAtCaret = function pasteHtmlAtCaret(html) {
        var sel, range;
        if (window.getSelection) {
            // IE9 and non-IE
            sel = window.getSelection();
            if (sel.getRangeAt && sel.rangeCount) {
                range = sel.getRangeAt(0);
                range.deleteContents();

                // Range.createContextualFragment() would be useful here but is
                // only relatively recently standardized and is not supported in
                // some browsers (IE9, for one)
                var el = document.createElement('div');
                el.innerHTML = html;
                var frag = document.createDocumentFragment(), node, lastNode;
                while (node = el.firstChild) {
                    lastNode = frag.appendChild(node);
                }
                range.insertNode(frag);

                // Preserve the selection
                if (lastNode) {
                    range = range.cloneRange();
                    range.setStartAfter(lastNode);
                    range.collapse(true);
                    sel.removeAllRanges();
                    sel.addRange(range);
                }
            }
        } else if (document.selection && document.selection.type != 'Control') {
            // IE < 9
            document.selection.createRange().pasteHTML(html);
        }
    };

    /* Block Registry */
    
    Villain.BlockRegistry = {};
    
    Villain.BlockRegistry.initialize = function (extraBlocks) {
        // add defaults
        Villain.BlockRegistry.Map = [
            "Text",
            "Header",
            "Blockquote",
            "List",
            "Image",
            "Slideshow",
            "Video",
            "Divider",
            "Columns",
        ];
        if (!_.isUndefined(extraBlocks)) {
            Villain.BlockRegistry.addExtraBlocks(extraBlocks);
        }
        Villain.BlockRegistry.checkBlocks();
    };
    
    Villain.BlockRegistry.addExtraBlocks = function(extraBlocks) {
        Villain.BlockRegistry.Map = Villain.BlockRegistry.Map.concat(extraBlocks);
    };
    
    Villain.BlockRegistry.add = function(block) {
        Villain.BlockRegistry.Map.push(block);
    };
    
    Villain.BlockRegistry.checkBlocks = function() {
        for (i = 0; i < Villain.BlockRegistry.Map.length; ++i) {
            type = Villain.BlockRegistry.Map[i];
            if (_.isUndefined(Villain.Blocks[_(type).capitalize()])) {
                console.error("Villain: Missing block source for " + type + "! Please ensure it is included.");
            }
        }
    };
    
    Villain.BlockRegistry.getBlockClassByType = function(type) {
        if (Villain.BlockRegistry.Map.indexOf(_(type).capitalize()) !== -1) {
            return Villain.Blocks[_(type).capitalize()];
        }
        return false;
    };

}(jQuery, _));