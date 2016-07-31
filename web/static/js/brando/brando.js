"use strict";

import $ from "jquery";
import Dropzone from "dropzone";
import Chart from "chart.js";

import "./brando/extensions/datepicker";
import "./brando/extensions/dropdown";
import "./brando/extensions/searcher";
import "./brando/extensions/slugit";
import "./brando/extensions/tablesaw";
import "./brando/extensions/tags_input";

import {Accordion} from "./brando/components/accordion";
import Autoslug from "./brando/components/autoslug";
import {brando} from "./brando/components/brando";
import DatePicker from "./brando/components/datepicker";
import Flash from "./brando/components/flash";
import FilterTable from "./brando/components/filter_table";
import ImagePreview from "./brando/components/image_preview";
import Mobile from "./brando/components/mobile";
import {VexBrando, vex} from "./brando/components/vex_brando";
import {bI18n} from "./brando/components/i18n";
import Images from "./brando/components/images";
import ImageConfig from "./brando/components/image_config";
import Menu from "./brando/components/menu";
import Pages from "./brando/components/pages";
import PopupForm from "./brando/components/popup_form";
import Sequence from "./brando/components/sequence";
import Sortable from "./brando/components/sortable";
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
    DatePicker.setup();
    ImagePreview.setup();

    /**
     * Section-specific setup
     */

    switch ($('body').attr('data-script')) {
        case "images-index":
            Images.setup();
            break;
        case "images-configure":
            ImageConfig.setup();
            break;
        case "portfolio-configure":
            ImageConfig.setup();
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

    $(document).trigger('enhance.tablesaw');
    $('.expander-trigger').click(function() {
        $(this).toggleClass('expander-hidden');
    });
});

export {
    Accordion,
    Chart,
    Dropzone,
    PopupForm,
    Sortable,
    Utils,

    brando,
    bI18n,
    vex
};
