"use strict";

import $ from "jquery";

class Autoslug {
    static setup() {
        // set up auto slug
        $('[data-slug-from]').each((index, elem) => {
            var slugFrom = $(elem).attr('data-slug-from');
            $('[name="' + slugFrom + '"]').slugIt({
                output: $(elem),
                map: {'\'': ''}
            });
        });
    }
}

export default Autoslug;
