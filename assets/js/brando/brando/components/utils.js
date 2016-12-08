export default class Utils {
  static addToPathName(relativeUrl) {
    const divider = (window.location.pathname.slice(-1) === '/') ? '' : '/';
    return window.location.pathname + divider + relativeUrl;
  }
}
