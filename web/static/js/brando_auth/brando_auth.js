"use strict";

import $ from "jquery";
import textFit from "textfit";

$(() => {
    /**
     * Setup Textfit
    **/
    textFit(document.getElementById("app-name"), {widthOnly: true, maxFontSize: 80});

    /**
     * Setup spinner
    **/
    $('input[type=submit]').click(function(e) {
        $('.spinner').fadeIn();
    });

});
