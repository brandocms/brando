var gulp = require('gulp');
var sass = require('gulp-ruby-sass');
var watch = require('gulp-watch');
var concat = require('gulp-concat');
var rename = require('gulp-rename');
var uglify = require('gulp-uglify');

gulp.task('sass', function () {
    return sass('scss/brando.scss')
        .on('error', function (err) { console.log(err.message); })
        .pipe(gulp.dest('../priv/static/brando/css'));
});

gulp.task('scripts', function () {
    return gulp.src(['js/brando/accordion.js', 'js/brando/dropdown.js', 'js/brando/gridforms.js'])
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