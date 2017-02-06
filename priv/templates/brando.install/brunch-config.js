exports.config = {
  // See http://brunch.io/#documentation for docs.

  files: {
    javascripts: {
      entryPoints: {
        'js/admin/index.js': {
          'js/brando.js': /^(node_modules|js\/admin)/,
        },
      },
      'js/app/index.js': {
        'js/app.js': [
          'node_modules/process/browser.js',
          'node_modules/jquery/dist/jquery.js',
          'node_modules/phoenix/priv/static/phoenix.js',
          'node_modules/phoenix_html/priv/static/phoenix_html.js',
          'node_modules/bootstrap-sass/assets/javascripts/bootstrap.js',
          /^(js\/app)/,
        ],
      },
      joinTo: {
        /* Copy Villain lib */
        'js/villain.all.js': [
          'node_modules/@twined/villain/dist/villain.all.js',
        ],
      },
    },
    stylesheets: {
      joinTo: {
        /* Frontend application-specific CSS/SCSS */
        'css/app.css': [
          'node_modules/bootstrap-sass/assets/stylesheets/_bootstrap.scss',
          /^(app\/vendor)/,
          'css/app.scss',
        ],

        /* Backend stylesheets */
        'css/brando.css': ['node_modules/@twined/brando/priv/static/css/brando.css'],
        'css/villain.css': ['node_modules/@twined/villain/dist/villain.css'],

        /* Custom stylesheets for backend, loaded after brando.css */
        'css/brando.custom.css': [
          'css/custom/*.scss',
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
    public: '../priv/static',
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
      'js/app.js': ['app'],
      'js/brando.js': ['@twined/brando', 'admin/index.js'],
    },
    nameCleaner: function(path) { return path.replace(/^js\//, ''); },
  },

  npm: {
    enabled: true,
    globals: {
      $: 'jquery',
      jQuery: 'jquery',
    },
    static: [
      'node_modules/@twined/villain/dist/villain.all.js',
      'node_modules/bootstrap-sass/assets/javascripts/bootstrap.js',
    ],
    styles: {
      '@twined/brando': ['priv/static/css/brando.css'],
      '@twined/villain': ['dist/villain.css'],
    },
  },
};
