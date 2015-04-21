"use strict";
import Utils from "./utils.js";

var imagePool = [];
class Images {
    static setup() {
        switch ($('body').attr('data-script')) {
            case "images-index":
                this.getHash();
                this.deleteListener();
                this.imageSelectionListener();
            return;
            case "images-sort":
                var el = document.getElementById('sortable');
                this.sortable = new Sortable(el, {
                    animation: 150,
                    ghostClass: "sortable-ghost",
                    onUpdate: function (e) {
                        $('#sort-post').removeClass("btn-default", "btn-success")
                                       .addClass("btn-warning")
                                       .html("Lagre ny rekkefølge");
                    },
                });
                this.sortListener();
            return;
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
    static sortSuccess(data) {
        if (data.status == 200) {
            $("#sort-post").removeClass("btn-warning").addClass("btn-success").html("Lagret rekkefølge!");
        }
    }

    static sortListener() {
        var _this = this;
        $('#sort-post').on('click', function(e) {
            e.preventDefault();
            $(this).removeClass("btn-default").addClass("btn-warning").html("Lagrer ...");
            $.ajax({
                headers: {Accept : "application/json; charset=utf-8"},
                type: "POST",
                url: "",
                data: {
                    order: _this.sortable.toArray()
                },
                success: _this.sortSuccess,
            });
        });
    }
}

export default Images;