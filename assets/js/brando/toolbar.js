"use strict";

class Toolbar {
    static setup() {
        var _this = this;
        $('.toolbar .logbutton').click(function(e) {
            _this.onClickLogButton(e, this);
        });
    }

    static onClickLogButton(e, elem) {
        $(elem).toggleClass('active');
        $('#log-wrapper').toggle();
    }
}

export default Toolbar;