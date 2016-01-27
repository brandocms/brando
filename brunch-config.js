exports.config = {
  // See http://brunch.io/#documentation for docs.
  files: {
    javascripts: {
      joinTo: {
        'js/brando.js': [
          'node_modules/phoenix/priv/static/phoenix.js',
          /^(web\/static\/js\/brando)/
        ],
        'js/brando.auth.js': [
          'web/static/js/vendor/trianglify.min.js',
          'web/static/js/vendor/jquery.min.js',
          'web/static/js/vendor/fittext.js'
        ],
        'js/brando.vendor.js': /^(web\/static\/js\/vendor)/,
      },
      order: {
        before: [
          'web/static/js/vendor/jquery.min.js',
          'web/static/js/vendor/vex.js',
        ]
      }
    },
    stylesheets: {
      joinTo: {
        'css/brando.css': ['web/static/scss/brando.scss'],
        'css/brando.vendor.css': [
          'web/static/css/font-awesome.min.css',
          'web/static/css/dropzone.css'
        ],
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
      'web/static',
    ],
    // Where to compile files to
    public: 'priv/static/vendor'
  },

  conventions: {
    // This option sets where we should place non-css and non-js assets in.
    // By default, we set this to '/web/static/assets'. Files in this directory
    // will be copied to `paths.public`, which is "priv/static/vendor" by default.
    assets: [
      /^(web\/static\/assets)/,
    ],
    ignored: [
      /[\\/]_/,
    ],
  },

  // Configure your plugins
  plugins: {
    babel: {
      // Do not use ES6 compiler in vendor code
      ignore: [
        /^(web\/static\/js\/vendor)/,
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
      'js/brando.js': ['web/static/js/brando/brando']
    }
  },

  npm: {
    enabled: true,
  }
};
