exports.config = {
  // See http://brunch.io/#documentation for docs.
  files: {
    javascripts: {
      joinTo: {
        'js/app.js': /^(web\/static\/js)/,
        'js/jquery.js': 'bower_components/jquery/dist/jquery.js',
        'js/vendor.js': [
          'bower_components/bootstrap-sass/assets/javascripts/bootstrap.js',
          'bower_components/jscroll/jquery.jscroll.js',
          'bower_components/responsive-nav/responsive-nav.js',
          'bower_components/salvattore/dist/salvattore.min.js',
          'bower_components/flexslider/jquery.flexslider.js',
          'bower_components/colorbox/jquery.colorbox.js',
          /^(web\/static\/vendor)/
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
          'bower_components/bootstrap-sass/assets/stylesheets/_bootstrap.scss',
          'bower_components/responsive-nav/responsive-nav.css',
          'bower_components/flexslider/flexslider.css',
          'web/static/css/app.scss',
        ]
      },
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
    assets: [
      /^(web\/static\/assets)/,
    ],
    ignored: [
      'web/static/css/includes'
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
