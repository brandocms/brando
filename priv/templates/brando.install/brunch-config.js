exports.config = {
  // See http://brunch.io/#documentation for docs.
  files: {
    javascripts: {
      joinTo: {
        'js/app.js': /^(web\/static\/js)/,
        'js/jquery.js': 'bower_components/jquery/dist/jquery.js',
        'js/vendor.js': [
          'node_modules/phoenix/priv/static/phoenix.js',
          'node_modules/phoenix_html/priv/static/phoenix_html.js',
          'bower_components/bootstrap-sass/assets/javascripts/bootstrap.js',
          'bower_components/jscroll/jquery.jscroll.js',
          'bower_components/salvattore/dist/salvattore.js',
          'bower_components/flexslider/jquery.flexslider.js',
          /^(web\/static\/vendor)/
        ],
        'js/brando.js': 'deps/brando/priv/static/vendor/js/brando.js',
        'js/brando.auth.js': 'deps/brando/priv/static/vendor/js/brando.auth.js',
        'js/brando.custom.js': 'web/static/js/admin/*.js',
        'js/villain.all.js': [
          'bower_components/jquery/dist/jquery.js',
          'deps/brando/priv/static/vendor/js/villain.all.js'
        ]
      },
    },
    stylesheets: {
      joinTo: {
        'css/brando.css': ['deps/brando/priv/static/vendor/css/brando.css'],
        'css/brando.vendor.css': ['deps/brando/priv/static/vendor/css/brando.vendor.css'],
        'css/villain.css': ['deps/brando/priv/static/vendor/css/villain.css'],

        'css/app.css': [
          'node_modules/bootstrap-sass/assets/stylesheets/_bootstrap.scss',
          'bower_components/responsive-nav/responsive-nav.css',
          'bower_components/flexslider/flexslider.css',
          'web/static/css/app.scss',
        ],
        'css/brando.custom.css': [
          'web/static/css/custom/*.scss'
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
      "deps/brando/priv/static",
      "web/static", "test/static"
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
      'web/static/css/includes/*',
      'web/static/css/custom/includes/*'
    ],
  },

  // Configure your plugins
  plugins: {
    babel: {
      // Do not use ES6 compiler in vendor code
      ignore: [
        /^(web\/static\/vendor)/,
        /^bower_components/,
        "deps/brando/priv/static/vendor/js/*.js",
      ]
    },
    postcss: {
      processors: [
        require('autoprefixer')(['last 2 versions'])
      ]
    }
  },

  modules: {
    autoRequire: {
      'js/app.js': ['web/static/js/app']
    }
  },

  npm: {
    enabled: true,
    // Whitelist the npm deps to be pulled in as front-end assets.
    // All other deps in package.json will be excluded from the bundle.
    whitelist: ["phoenix", "phoenix_html"]
  }
};
