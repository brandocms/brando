"use strict";

class Sequence {
    static setup() {
        if ($('#sequence').length != 0) {
            var el = document.getElementById('sequence');
            this.sortable = new Sortable(el, {
                animation: 150,
                ghostClass: "sequence-ghost",
                onUpdate: function (e) {
                    $('#sort-post').removeClass("btn-default", "btn-success")
                                   .addClass("btn-warning")
                                   .html("Lagre ny rekkefølge");
                },
            });
            this.sortListener();
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
                data: {order: _this.sortable.toArray()},
                success: _this.sortSuccess,
            });
        });
    }
}

export default Sequence;