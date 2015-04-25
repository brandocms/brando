var gulp = require('gulp');
var sass = require('gulp-ruby-sass');
var watch = require('gulp-watch');
var concat = require('gulp-concat');
var rename = require('gulp-rename');
var uglify = require('gulp-uglify');
var babel = require("gulp-babel");
var sourcemaps = require("gulp-sourcemaps");
var autoprefixer = require('gulp-autoprefixer');

gulp.task('sass', function () {
    return sass('scss/brando.scss', {sourcemap: true})
        .on('error', function (err) { console.log(err.message); })
        .pipe(autoprefixer({
          browsers: ['last 2 versions']
        }))
        .pipe(sourcemaps.write())
        .pipe(gulp.dest('../priv/static/brando/css'));
});

var browserify = require('browserify');
var babelify= require('babelify');
var util = require('gulp-util');
var buffer = require('vinyl-buffer');
var source = require('vinyl-source-stream');


gulp.task('scripts-brando', function() {
  browserify('./js/brando/brando.js', { debug: true })
  .add(require.resolve('babel/polyfill'))
  .transform(babelify)
  .bundle()
  .on('error', util.log.bind(util, 'Browserify Error'))
  .pipe(source('brando.js'))
  .pipe(buffer())
  .pipe(sourcemaps.init({loadMaps: true}))
  .pipe(gulp.dest('../priv/static/brando/js'))
  .pipe(rename('brando-min.js'))
  .pipe(uglify({ mangle: false }))
  .pipe(sourcemaps.write('./'))
  .pipe(gulp.dest('../priv/static/brando/js'));
});


gulp.task('scripts-vendor', function () {
    return gulp.src([
                     'js/vendor/jquery.min.js',
                     'js/vendor/accordion.js',
                     'js/vendor/dropdown.js',
                     'js/vendor/sortable.js',
                     'js/vendor/slideout.js',
                     'js/vendor/jquery.slugit.js',
                     'js/vendor/vex.js',
                     'js/vendor/vex.dialog.js'
                    ])
        .pipe(babel()).on('error', errorHandler)
        .pipe(concat('brando.vendor.js'))
        .pipe(gulp.dest('../priv/static/brando/js'))
        .pipe(rename('brando.vendor-min.js'))
        .pipe(uglify()).on('error', errorHandler)
        .pipe(gulp.dest('../priv/static/brando/js'));
});

gulp.task('default', function() {
  // place code for your default task here
});

gulp.task('watch', function () {
    watch('scss/**/*.scss', function () {
        gulp.start('sass');
    });
    watch('js/vendor/**/*.js', function () {
        gulp.start('scripts-vendor');
    });
    watch('js/brando/**/*.js', function () {
        gulp.start('scripts-brando');
    });
});

// Handle the error
function errorHandler (error) {
  console.log(error.toString());
  this.emit('end');
}