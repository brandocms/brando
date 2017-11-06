exports.config = {
  // See http://brunch.io/#documentation for docs.

  files: {
    javascripts: {
      entryPoints: {
        // Frontend javascript
        'js/app/index.js': {
          'js/app.js': [
            /^(node_modules|js\/app)/,
          ],
        },
      },
    },
    stylesheets: {
      joinTo: {
        /* Frontend application-specific CSS/SCSS */
        'css/app.css': [
          'node_modules/bootstrap/scss/_bootstrap.scss',
          'css/app.scss',
        ],
      },
    },
    templates: {
      joinTo: 'js/app.js',
    },
  },

  // Phoenix paths configuration
  paths: {
    // Which directories to watch
    watched: [
      'static', 'css', 'js', 'vendor',
    ],

    // Where to compile files to
    public: '../../priv/static',
  },

  conventions: {
    // This option sets where we should place non-css and non-js assets in.
    // By default, we set this to '/assets/static'. Files in this directory
    // will be copied to `paths.public`, which is "priv/static" by default.
    assets: [
      /^(static)/,
    ],
  },

  // Configure your plugins
  plugins: {
    babel: {
      // Do not use ES6 compiler in vendor code
      ignore: [
        /^(app\/vendor|bower_components|node_modules)/,
      ],
    },
    postcss: {
      processors: [
        require('autoprefixer')(['last 2 versions']),
      ],
    },
    sass: {
      options: {
        precision: 10,
        includePaths: [
          'node_modules/bootstrap-sass/assets/stylesheets',
        ],
      },
    },
  },

  modules: {
    autoRequire: {
      'js/app.js': ['app']
    },
    nameCleaner: function(path) { return path.replace(/^js\//, ''); },
  },

  npm: {
    enabled: true,
    globals: {
      // $: 'jquery',
      // jQuery: 'jquery',
    },
  },
};
