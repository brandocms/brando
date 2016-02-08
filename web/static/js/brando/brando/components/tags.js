"use strict";

import $ from "jquery";

class Tags {
    static setup() {
        // set up tags
        $('[data-tags-input]').each((index, elem) => {
            $(elem).tagsInput({width: "100%", height: "35px", defaultText: "+"});
        });
    }
}

export default Tags;