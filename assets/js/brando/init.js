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

    // set up dismissal of alerts
    $('[data-dismiss]').each((index, elem) => {
        $(elem).click(e => {
            e.preventDefault();
            $(elem).parent().hide();
        });
    });
});