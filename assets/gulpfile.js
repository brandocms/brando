var gulp = require('gulp');
var sass = require('gulp-ruby-sass');
var watch = require('gulp-watch');
var concat = require('gulp-concat');
var minify = require('gulp-minify-css');
var rename = require('gulp-rename');
var uglify = require('gulp-uglify');
var babel = require("gulp-babel");
var sourcemaps = require("gulp-sourcemaps");
var autoprefixer = require('gulp-autoprefixer');

gulp.task('css', function () {
    return sass('./scss/brando.scss', {sourcemap: true})
        .on('error', function (err) { console.log(err.message); })
        .pipe(autoprefixer({browsers: ['last 2 versions']}))
        .pipe(gulp.dest('../priv/static/vendor/css'))
});

gulp.task('css-vendor', function () {
  return gulp.src(['./css/font-awesome.min.css', './css/dropzone.css'])
      .on('error', function (err) { console.log(err.message); })
      .pipe(concat('brando.vendor.css'))
      .pipe(gulp.dest('../priv/static/vendor/css'))
});

var browserify = require('browserify');
var babelify = require('babelify');
var util = require('gulp-util');
var source = require('vinyl-source-stream');


gulp.task('scripts-brando', function() {
  browserify('./js/brando/brando.js', { debug: false })
  .add(require.resolve('babel/polyfill'))
  .transform(babelify)
  .bundle()
  .on('error', util.log.bind(util, 'Browserify Error'))
  .pipe(source('brando.js'))
  .pipe(gulp.dest('../priv/static/vendor/js'))
});

gulp.task('scripts-auth', function () {
    return gulp.src(['js/vendor/trianglify.min.js',
                     'js/vendor/jquery.min.js',
                     'js/vendor/fittext.js'])
        .pipe(concat('brando.auth.js'))
        .pipe(gulp.dest('../priv/static/vendor/js'))
});

gulp.task('scripts-vendor', function () {
    return gulp.src(['js/vendor/jquery.min.js',
                     'js/vendor/accordion.js',
                     'js/vendor/dropzone.js',
                     'js/vendor/dropdown.js',
                     'js/vendor/sortable.js',
                     'js/vendor/slideout.js',
                     'js/vendor/jquery.slugit.js',
                     'js/vendor/searcher.js',
                     'js/vendor/sparkline.min.js',
                     'js/vendor/tagsinput.min.js',
                     'js/vendor/vex.js',
                     'js/vendor/vex.dialog.js'])
        .pipe(babel()).on('error', errorHandler)
        .pipe(concat('brando.vendor.js'))
        .pipe(gulp.dest('../priv/static/vendor/js'))
});

gulp.task('default', function() {
  // place code for your default task here
  gulp.start('css');
  gulp.start('css-vendor');
  gulp.start('scripts-vendor');
  gulp.start('scripts-auth');
  gulp.start('scripts-brando');
});

gulp.task('watch', function () {
    watch('./scss/**/*.scss', function () {
        gulp.start('css');
    });
    watch('./css/**/*.css', function () {
        gulp.start('css-vendor');
    });
    watch('./js/vendor/**/*.js', function () {
        gulp.start('scripts-vendor');
        gulp.start('scripts-auth');
    });
    watch('./js/brando/**/*.js', function () {
        gulp.start('scripts-brando');
    });
});

// Handle the error
function errorHandler (error) {
  console.log(error.toString());
  this.emit('end');
}