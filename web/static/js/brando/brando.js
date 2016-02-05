"use strict";
import $ from "jquery";
import Dropzone from "dropzone";

import Accordion from "./components/accordion";
import Autoslug from "./components/autoslug";
import Flash from "./components/flash";
import FilterTable from "./components/filter_table";
import Mobile from "./components/mobile";
import {VexBrando} from "./components/vex_brando";
import Images from "./components/images";
import Instagram from "./components/instagram";
import Menu from "./components/menu";
import Pages from "./components/pages";
import Sequence from "./components/sequence";
import Stats from "./components/stats";
import Tags from "./components/tags";
import Toolbar from "./components/toolbar";
import Utils from "./components/utils";
import WS from "./components/ws";

import "./extensions/dropdown";
import "./extensions/searcher";
import "./extensions/slugit";
import "./extensions/sparkline";
import "./extensions/tags_input";

$(() => {
    /**
     * Setup vendored modules.
     */

    VexBrando.setup();
    Autoslug.setup();
    FilterTable.setup();
    Flash.setup();
    Mobile.setup();
    Sequence.setup();
    Toolbar.setup();
    Tags.setup();

    /**
     * Section-specific setup
     */

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

    /**
     * Global setup
     */

    WS.setup();
    Accordion.setup();
    Menu.setup();
});
