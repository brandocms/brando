"use strict";

class Slideout {
    static setup() {
        // set up mobile slide menu
        var slideout = new Slideout({
            'panel': document.getElementById('burger'),
            'menu': document.getElementById('menu'),
            'padding': 0,
            'tolerance': 70
        });
        document.querySelector('#burger button').addEventListener('click', function(e) {
            e.preventDefault();
            slideout.toggle();
        });
    }
}

export default Slideout;