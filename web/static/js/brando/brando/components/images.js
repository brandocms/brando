"use strict";

import $ from "jquery";

import {Accordion} from "./accordion";
import {Utils} from "./utils";
import {vex} from "./vex_brando";
import {bI18n} from "./i18n";

var imagePool = [];

class Images {
    static setup() {
        this.getHash();
        this.deleteListener();
        this.imageSelectionListener();
        this.imagePropertiesListener();
    }
    static getHash() {
        let hash = document.location.hash
        if (hash) {
            Accordion.activateTab("#tab-" + hash.slice(1));
        }
    }
    static imageSelectionListener() {
        var that = this;
        $('.image-selection-pool img').click(function() {
          if ($(this).hasClass('selected')) {
            // remove from selected pool
            var pos;
            for (var i = 0; i < imagePool.length; i++) {
              if ( imagePool[i] == $(this).attr('data-id')) {
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
          that.checkButtonEnable(this);
        });
    }

    static imagePropertiesListener() {
        var that = this;

        $(document).on({
            mouseenter: function(){
                $(this).find('.overlay').css('visibility', 'visible');
            },
            mouseleave: function(){
                $(this).find('.overlay').css('visibility', 'hidden');
            }
        }, '.image-wrapper');

        $(document).on('click', '.edit-properties', function(e) {
            e.preventDefault();

            var attrs,
                $content = $('<div>'),
                $img = $(this).parent().parent().find('img').clone();

            vex.dialog.open({
                message: '',
                input: function() {
                    attrs = that._buildAttrs($img.data());
                    $content.append($img).append(attrs);
                    return $content;
                },
                callback: function(form) {
                    if (form !== false) {
                        var id = form.id;
                        delete form.id;
                        var data = {
                            form: form,
                            id: id
                        }
                        that._submitProperties(data);
                    }
                }
            });
        });
    }

    static _submitProperties(data) {
        $.ajax({
            headers: {Accept : "application/json; charset=utf-8"},
            type: "POST",
            data: data,
            url: Utils.addToPathName('set-properties')
        }).done($.proxy(function(data) {
            /**
             * Callback after confirming.
             */
            if (data.status == '200') {
                // success
                var $img = $('.image-serie img[data-id=' + data.id + ']');
                $.each(data.attrs, function(attr, val) {
                    $img.attr('data-' + attr, val);
                });
            }
        }));
    }

    static _buildAttrs(data) {
        var that = this;
        var ret = '';
        $.each(data, function(attr, val) {
            if (attr == 'id') {
                ret += '<input name="id" type="hidden" value="' + val + '" />';
            } else {
                ret += '<div><label>' + that._capitalize(attr) + '</label>' +
                       '<input name="' + attr + '" type="text" value="' + val + '" /></div>'
            }
        });
        return ret;
    }

    static _capitalize(word) {
       return $.camelCase("-" + word);
    }

    static checkButtonEnable(scope) {
        let $scope = $(scope).parent().parent();
        let $btn = $('.delete-selected-images', $scope);
        if (imagePool.length > 0) {
            $btn.removeAttr('disabled');
        } else {
            $btn.attr('disabled', 'disabled');
        }
    }

    static deleteListener() {
        var that = this;
        $('.delete-selected-images').click(function(e) {
            e.preventDefault();
            vex.dialog.confirm({
                message: bI18n.t("images:delete_confirm"),
                callback: function(value) {
                    if (value) {
                        $(this).removeClass("btn-danger").addClass("btn-warning").html(bI18n.t("images:deleting"));
                        $.ajax({
                            headers: {Accept : "application/json; charset=utf-8"},
                            type: "POST",
                            url: Utils.addToPathName('delete-selected-images'),
                            data: {ids: imagePool},
                            success: that.deleteSuccess
                        });
                    }
                }
            });
        });
    }
    static deleteSuccess(data) {
        if (data.status == 200) {
            $(".delete-selected-images")
                .removeClass("btn-warning")
                .addClass("btn-danger")
                .html(bI18n.t("images:delete_images"))
                .attr('disabled', 'disabled');

            for (var i = 0; i < data.ids.length; i++) {
                $('.image-selection-pool img[data-id=' + data.ids[i] + ']').fadeOut();
            }
            imagePool = [];
        }
    }
}

export default Images;
