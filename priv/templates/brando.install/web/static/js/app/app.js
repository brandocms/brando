import {Socket} from "deps/phoenix/web/static/js/phoenix"
import {Flexslider} from "./flexslider"
import "deps/phoenix_html/web/static/js/phoenix_html"


$(() => {
    /* page specific switch */
    /*
    switch ($('body').attr('data-script')) {
        case "section-name-here":
            break;
    }
    */
    // Look for flexsliders on page and initialize.
    Flexslider.setup();
});

let App = {
}

export default App