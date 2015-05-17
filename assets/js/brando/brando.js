"use strict";

import Autoslug from "./autoslug.js";
import Flash from "./flash.js";
import Slideout from "./slideout.js";
import Utils from "./utils.js";
import Vex from "./vex.js";
import Images from "./images.js";
import Sequence from "./sequence.js";
import Stats from "./stats.js";
import Toolbar from "./toolbar.js";
import WS from "./ws.js";


$(() => {
    /* set up automated vendored js stuff */
    Vex.setup();
    Autoslug.setup();
    Flash.setup();
    Slideout.setup();
    Sequence.setup();
    Toolbar.setup();

    switch ($('body').attr('data-script')) {
        case "images-index":
            Images.setup();
        case "dashboard-system_info":
            Stats.setup();
    }
    /* set up ws */
    WS.setup();
});