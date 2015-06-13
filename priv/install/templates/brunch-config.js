exports.config = {
  // See http://brunch.io/#documentation for docs.
  files: {
    javascripts: {
      joinTo: {
        'js/app.js': /^(web\/static\/js)/,
        'js/vendor.js': [
          /^(web\/static\/vendor)/,
          'bower_components/jquery/dist/jquery.js',
          'bower_components/bootstrap-sass/assets/javascripts/bootstrap.js',
          'bower_components/jscroll/jquery.jscroll.js',
          'bower_components/responsive-nav/responsive-nav.js',
          'bower_components/salvattore/dist/salvattore.min.js',
          'bower_components/owl.carousel/dist/owl.carousel.js'
        ],
      },
      // order: {
      //   before: [
      //     /^bower_components/,
      //     /^web\/static\/vendor/
      //   ]
      // }
    },
    stylesheets: {
      joinTo: {
        'css/app.css': [
          /^(web\/static\/css)/,
          'bower_components/bootstrap-sass/assets/stylesheets/_bootstrap.scss',
          'bower_components/responsive-nav/responsive-nav.css',
          'bower_components/owl.carousel/dist/assets/owl.carousel.css',
          'bower_components/owl.carousel/dist/assets/owl.theme.default.css'
        ]
      }
    },
    templates: {
      joinTo: 'js/app.js'
    }
  },

  // Phoenix paths configuration
  paths: {
    // Which directories to watch
    watched: [
      "web/static",
      "test/static"
    ],

    // Where to compile files to
    public: "priv/static"
  },

  conventions: {
    // This option sets where we should place non-css and non-js assets in.
    // By default, we set this to '/web/static/assets'. Files in this directory
    // will be copied to `paths.public`, which is "priv/static" by default.
    assets: /^(web\/static\/assets)/,
    ignored: [
      'bower_components/owl.carousel/dist/owl.carousel.min.js',
      'bower_components/owl.carousel/dist/assets/owl.carousel.min.css',
      'bower_components/owl.carousel/dist/assets/owl.theme.default.min.css',
      'bower_components/owl.carousel/dist/assets/owl.theme.green.min.css',
      'bower_components/owl.carousel/dist/assets/owl.theme.green.css'
    ]
  },

  // Configure your plugins
  plugins: {
    ES6to5: {
      // Do not use ES6 compiler in vendor code
      ignore: [/^(web\/static\/vendor)/, /^bower_components/]
    }
  }
};
