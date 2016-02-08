"use strict";

export class Utils {
    static addToPathName(relativeUrl) {
      let divider = (window.location.pathname.slice(-1) == "/") ? "" : "/";
      return window.location.pathname + divider + relativeUrl;
    }
}
