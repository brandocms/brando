exports.config = {
  // See http://brunch.io/#documentation for docs.

  files: {
    javascripts: {
      entryPoints: {
        'web/static/js/admin/index.js': {
          'js/brando.js': /^(node_modules|web\/static\/js\/admin)/,
        },
      },
      joinTo: {
        /* Frontend JS application */
        'js/app.js': /^(web\/static\/js\/app)/,

        /* JQuery module */
        'js/jquery.js': 'node_modules/jquery/dist/jquery.js',

        /* Frontend vendors */
        'js/vendor.js': [
          'node_modules/phoenix/priv/static/phoenix.js',
          'node_modules/bootstrap-sass/assets/javascripts/bootstrap.js',
          /^(web\/static\/js\/app\/vendor)/,
        ],

        /* Copy Villain lib */
        'js/villain.all.js': [
          'node_modules/brando_villain/priv/static/js/villain.all.js',
        ],
      },
    },
    stylesheets: {
      joinTo: {
        /* Frontend application-specific CSS/SCSS */
        'css/app.css': [
          'node_modules/bootstrap-sass/assets/stylesheets/_bootstrap.scss',
          /^(web\/static\/app\/vendor)/,
          'web/static/css/app.scss',
        ],

        /* Backend stylesheets */
        'css/brando.css': ['node_modules/brando/priv/static/css/brando.css'],
        'css/villain.css': ['node_modules/brando_villain/priv/static/css/villain.css'],

        /* Custom stylesheets for backend, loaded after brando.css */
        'css/brando.custom.css': [
          'web/static/css/custom/*.scss',
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
      // static
      'web/static',
      'test/static',
    ],

    // Where to compile files to
    public: 'priv/static',
  },

  conventions: {
    // This option sets where we should place non-css and non-js assets in.
    // By default, we set this to '/web/static/assets'. Files in this directory
    // will be copied to `paths.public`, which is "priv/static" by default.
    assets: [
      /^(web\/static\/assets)/,
    ],
  },

  // Configure your plugins
  plugins: {
    babel: {
      // Do not use ES6 compiler in vendor code
      ignore: [
        /^(web\/static\/app\/vendor|bower_components|node_modules)/,
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
      'js/brando.js': ['brando', 'admin/index.js'],
    },
    nameCleaner: function(path) { return path.replace(/^web\/static\/js\//, ''); },
  },

  npm: {
    enabled: true,
    globals: {
      $: 'jquery',
      jQuery: 'jquery',
    },
    static: [
      'node_modules/brando_villain/priv/static/js/villain.all.js',
      'node_modules/bootstrap-sass/assets/javascripts/bootstrap.js',
    ],
    styles: {
      brando: ['priv/static/css/brando.css'],
      brando_villain: ['priv/static/css/villain.css'],
    },
  },
};
