"use strict";

class Mobile {
    static setup() {
        // set up mobile menu
        $(document).on('click', '#mobile-nav', function(e) {
            $('#menu').toggle();
        });
    }
}

export default Mobile;