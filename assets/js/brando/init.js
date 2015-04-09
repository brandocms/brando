$(() => {
    // set default theme for vex dialogs
    vex.defaultOptions.className = 'vex-theme-plain';
    vex.dialog.buttons.YES.text = 'OK';
    vex.dialog.buttons.NO.text = 'Angre';

    // set up phoenix back channel

    // set up auto slug

    $('[data-slug-from]').each((index, elem) => {
        var slugFrom = $(elem).attr('data-slug-from');
        $('[name="' + slugFrom + '"]').slugIt({
            output: $(elem),
        });
    });
});