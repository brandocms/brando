"use strict";

import Autoslug from "./autoslug.js";
import Flash from "./flash.js";
import FilterTable from "./filter_table.js";
import Slideout from "./slideout.js";
import Utils from "./utils.js";
import Vex from "./vex.js";
import Images from "./images.js";
import Instagram from "./instagram.js";
import Sequence from "./sequence.js";
import Stats from "./stats.js";
import Tags from "./tags.js";
import Toolbar from "./toolbar.js";
import WS from "./ws.js";


$(() => {
    /* set up automated vendored js stuff */
    Vex.setup();
    Autoslug.setup();
    FilterTable.setup();
    Flash.setup();
    Slideout.setup();
    Sequence.setup();
    Toolbar.setup();
    Tags.setup();

    switch ($('body').attr('data-script')) {
        case "images-index":
            Images.setup();
            break;
        case "dashboard-system_info":
            Stats.setup();
            break;
        case "instagram-index":
            Instagram.setup();
            break;
    }
    /* set up ws */
    WS.setup();
});