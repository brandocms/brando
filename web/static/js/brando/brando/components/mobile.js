"use strict";

import $ from "jquery";

class Mobile {
    static setup() {
        // set up mobile menu
        $(document).on('click', '#mobile-nav', function() {
            $('#menu').toggle();
        });
    }
}

export default Mobile;