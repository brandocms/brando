"use strict";

class Mobile {
    static setup() {
        // set up mobile menu
        console.log("setup mobile");
        $(document).on('click', '#mobile-nav', function(e) {
            console.log("toggle!");
            $('#menu').toggle();
        });
    }
}

export default Mobile;