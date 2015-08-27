"use strict";

export class Flexslider {
    static setup() {
        $('.flexslider').flexslider({
            controlNav: false,
            directionNav: false,
            slideshowSpeed: 6500,
            animationSpeed: 2000,
            easing: "linear"
        });
    }
}