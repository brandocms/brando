exports.config = {
  // See http://brunch.io/#documentation for docs.
  files: {
    javascripts: {
      joinTo: {
        'js/brando.js': [
          'node_modules/phoenix/priv/static/phoenix.js',
          'node_modules/jquery/dist/jquery.js',
          'node_modules/vex-js/js/vex.js',
          'node_modules/dropzone/dist/dropzone.js',
          /^(web\/static\/js\/brando)/
        ],

        'js/brando.auth.js': [
          'node_modules/jquery/dist/jquery.js',
          'node_modules/textfit/textFit.js',
          /^(web\/static\/js\/brando_auth)/
        ]
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
    public: 'priv/static'
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
      'js/brando.js': ['brando', 'jquery'],
      'js/brando.auth.js': ['brando_auth']
    },
    definition: false,
    nameCleaner: function(path) {
        return path.replace(/^(web\/static\/js\/brando\/)|(web\/static\/js\/brando_auth\/)/, '');
    }
  },

  npm: {
    enabled: true,
    globals: {
        $: 'jquery',
        jQuery: 'jquery'
    }
  }
};
