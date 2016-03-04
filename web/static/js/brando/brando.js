"use strict";
import $ from "jquery";
import Dropzone from "dropzone";

import "./brando/extensions/dropdown";
import "./brando/extensions/searcher";
import "./brando/extensions/slugit";
import "./brando/extensions/sparkline";
import "./brando/extensions/tags_input";

import {Accordion} from "./brando/components/accordion";
import Autoslug from "./brando/components/autoslug";
import Flash from "./brando/components/flash";
import FilterTable from "./brando/components/filter_table";
import Mobile from "./brando/components/mobile";
import {VexBrando, vex} from "./brando/components/vex_brando";
import Images from "./brando/components/images";
import Menu from "./brando/components/menu";
import Pages from "./brando/components/pages";
import Sequence from "./brando/components/sequence";
import Stats from "./brando/components/stats";
import Tags from "./brando/components/tags";
import Toolbar from "./brando/components/toolbar";
import {Utils} from "./brando/components/utils";
import WS from "./brando/components/ws";

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

export {
    Accordion,
    Utils,
    vex,
    Dropzone
};
