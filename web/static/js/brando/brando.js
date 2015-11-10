"use strict";

import Autoslug from "./components/autoslug";
import Flash from "./components/flash";
import FilterTable from "./components/filter_table";
import Mobile from "./components/mobile";
import Utils from "./components/utils";
import Vex from "./components/vex";
import Images from "./components/images";
import Instagram from "./components/instagram";
import Pages from "./components/pages";
import Sequence from "./components/sequence";
import Stats from "./components/stats";
import Tags from "./components/tags";
import Toolbar from "./components/toolbar";
import WS from "./components/ws";


$(() => {
    /* set up automated vendored js stuff */
    Vex.setup();
    Autoslug.setup();
    FilterTable.setup();
    Flash.setup();
    Mobile.setup();
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
        case "pages-index":
            Pages.setup();
            break;
    }
    /* set up ws */
    WS.setup();
});