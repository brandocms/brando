"use strict";

class Pages {
    static setup() {
        var _this = this;
        $('.expand-page-children').click(function(e) {
            _this.onClickExpandButton(e, this);
        });
    }

    static onClickExpandButton(e, elem) {
        e.preventDefault();
        $(elem).toggleClass('active');
        $('tr.child[data-parent-id=' + $(elem).attr('data-id') + ']').toggleClass('hidden');
    }
}

export default Pages;