export default {
  /**
   * Text shown in title bar
   */
  name: 'CLIENT NAME',
  /**
   * Available container sections for Villain
   */
  sections: [
    { label: 'Standard', value: 'standard', color: '#000', wrapper: '' }
  ],
  /**
   * If the Villain editor should only show modules as available blocks
   */
  moduleMode: (page) => {
    return true
  },
  /**
   * Which modules to show ('all', 'pages', etc)
   */
  // modules: 'all',
  /**
   * Additional styling for the figure element on the login page
   */
  logoStyle: '',
  /**
   * SVG logo used for login screen and menu
   */
  logo: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 800">< path fill="#312783" d="M587.2 133.8v310.1c0 26.1-4.9 50.5-14.7 73.2-9.8 22.6-23.2 42.3-40.2 59.1s-37 30.1-59.8 39.9c-22.9 9.8-47.1 14.7-72.8 14.7-26.1 0-50.5-4.9-73.1-14.7-22.6-9.8-42.3-23.1-59.2-39.9-16.8-16.8-30.1-36.5-39.9-59.1-9.8-22.6-14.7-47-14.7-73.2V133.8h140v310.1c0 13.5 4.4 24.7 13.3 33.6 8.9 8.9 20.1 13.3 33.6 13.3s24.8-4.4 34-13.3c9.1-8.9 13.6-20.1 13.6-33.6V133.8h139.9zm-352 364c5.6 16.8 13.3 32.2 23.1 46.2l43.4-39.2c-12.6-19.1-18.9-40.6-18.9-64.4V203.8l56-56h-112v296.1c0 19.2 2.8 37.1 8.4 53.9zM343.3 543c16.6 9.6 35.3 14.4 56.3 14.4 16.3 0 31.6-3 45.8-9.1s26.7-14.3 37.5-24.8 19.1-22.9 25.2-37.1c6.1-14.2 9.1-29.5 9.1-45.9V203.8l56-56h-112v296.1c0 17.3-6 31.7-17.8 43.4-11.9 11.7-26.5 17.5-43.8 17.5-13.1 0-24.6-3.4-34.6-10.2s-17.4-15.5-22-26.2l-40.6 36.4c10.7 15.9 24.3 28.6 40.9 38.2z" /></svg>'
}
