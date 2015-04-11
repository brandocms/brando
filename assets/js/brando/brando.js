"use strict";

import Autoslug from "./autoslug.js";
import Flash from "./flash.js";
import Slideout from "./slideout.js";
import Utils from "./utils.js";
import Vex from "./vex.js";
import Images from "./images.js";
import WS from "./ws.js";


$(() => {
    /* set up automated vendored js stuff */
    Vex.setup();
    Autoslug.setup();
    Flash.setup();
    Slideout.setup();

    /* set up brando js stuff */
    Images.setup();

    /* set up ws */
    WS.setup();
});