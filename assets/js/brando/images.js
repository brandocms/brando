"use strict";
import Utils from "./utils.js";

var imagePool = [];
class Images {
    static setup() {
        if ($('body#images').length) {
            this.getHash();
            this.deleteListener();
            this.imageSelectionListener();
        }
    }
    static getHash() {
        let hash = document.location.hash
        if (hash) {
            // show the tab
            activate_tab("#tab-" + hash.slice(1));
        }
    }
    static imageSelectionListener() {
        var that = this;
        $('.image-selection-pool img').click(function(e) {
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
          that.checkButtonEnable();
        });
    }

    static checkButtonEnable() {
        let $btn = $('.delete-selected-images');
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
                message: 'Er du sikker på at du vil slette disse bildene?',
                callback: function(value) {
                    if (value) {
                        $(this).removeClass("btn-danger").addClass("btn-warning").html("Lagrer ...");
                        $.ajax({
                            headers: {Accept : "application/json; charset=utf-8"},
                            type: "POST",
                            url: Utils.addToPathName('slett-valgte-bilder'),
                            data: {ids: imagePool},
                            success: that.deleteSuccess,
                        });
                    }
                }
            });
        });
    }
    static deleteSuccess(data) {
        if (data.status == 200) {
            $(".delete-selected-images").removeClass("btn-warning").addClass("btn-danger").html("Slett valgte bilder");
            for (var i = 0; i < data.ids.length; i++) {
                $('.image-selection-pool img[data-id=' + data.ids[i] + ']').fadeOut();
            }
            imagePool = [];
        }
    }
}

export default Images;