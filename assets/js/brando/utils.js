"use strict";

class Utils {
    static addToPathName(relativeUrl) {
      let divider = (window.location.pathname.slice(-1) == "/") ? "" : "/";
      return window.location.pathname + divider + relativeUrl;
    }
    static test() {
        console.log("testing");
    }
}

export default Utils;