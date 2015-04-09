"use strict";

import Autoslug from "./autoslug.js";
import Flash from "./flash.js";
import Slideout from "./slideout.js";
import Utils from "./utils.js";
import Vex from "./vex.js";

import Images from "./images.js";


$(() => {
    /* set up automated vendored js stuff */
    Vex.setup();
    Autoslug.setup();
    Flash.setup();
    Slideout.setup();

    /* set up brando js stuff */
    Images.setup();
});