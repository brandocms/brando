var gulp = require('gulp');
var sass = require('gulp-ruby-sass');
var watch = require('gulp-watch');
var concat = require('gulp-concat');
var rename = require('gulp-rename');
var uglify = require('gulp-uglify');
var babel = require("gulp-babel");
var sourcemaps = require("gulp-sourcemaps")

gulp.task('sass', function () {
    return sass('scss/brando.scss', {sourcemap: true})
        .on('error', function (err) { console.log(err.message); })
        .pipe(sourcemaps.write())
        .pipe(gulp.dest('../priv/static/brando/css'));
});

gulp.task('scripts', function () {
    return gulp.src(['js/accordion.js',
                     'js/dropdown.js',
                     'js/sortable.js',
                     'js/slideout.js',
                     'js/gridforms.js',
                     'js/vex.js',
                     'js/vex.dialog.js',
                     'js/brando/utils.js',
                     'js/brando/init.js'
        ])
        .pipe(babel())
        .pipe(concat('brando.js'))
        .pipe(gulp.dest('../priv/static/brando/js'))
        .pipe(rename('brando-min.js'))
        .pipe(uglify())
        .pipe(gulp.dest('../priv/static/brando/js'));
});

gulp.task('default', function() {
  // place code for your default task here
});

gulp.task('watch', function () {
    watch('scss/**/*.scss', function () {
        gulp.start('sass');
    });
});