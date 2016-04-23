"use strict";

import $ from "jquery";

class Datepicker {
    static setup() {
        // setup date pickers here.
        $('.datetimepicker').datetimepicker({
            format: 'yyyy-mm-dd hh:ii:ss',
            autoclose: true,
            todayHighlight: true,
            fontAwesome: true,
            pickerPosition: "top-right"
        });
    }
}

export default Datepicker;
