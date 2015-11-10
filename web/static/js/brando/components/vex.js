"use strict";

class Vex {
    static setup() {
        // set default theme for vex dialogs
        vex.defaultOptions.className = 'vex-theme-plain';
        vex.dialog.buttons.YES.text = 'OK';
        vex.dialog.buttons.NO.text = 'Angre';
    }
}

export default Vex;