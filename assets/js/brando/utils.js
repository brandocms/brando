class Utils {
    static addToPathName(relativeUrl) {
      divider = (window.location.pathname.slice(-1) == "/") ? "" : "/";
      return window.location.pathname + divider + relativeUrl;
    }
}