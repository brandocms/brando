var gulp = require('gulp');
var sass = require('gulp-ruby-sass');
var watch = require('gulp-watch');

gulp.task('sass', function () {
    return sass('scss/brando.scss')
        .on('error', function (err) { console.log(err.message); })
        .pipe(gulp.dest('../priv/static/brando/css'));
});

gulp.task('default', function() {
  // place code for your default task here
});

gulp.task('watch', function () {
    watch('scss/**/*.scss', function () {
        gulp.start('sass');
    });
});