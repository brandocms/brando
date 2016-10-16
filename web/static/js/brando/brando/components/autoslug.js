import $ from 'jquery';

class Autoslug {
  static setup() {
    // set up auto slug
    $('[data-slug-from]')
      .each((index, elem) => {
        const slugFrom = $(elem)
          .attr('data-slug-from');
        $(`[name="${slugFrom}"]`)
          .slugIt({
            output: $(elem),
            map: {
              æ: 'ae',
              ø: 'oe',
              å: 'aa',
            },
            space: '-',
            after: function afterSlugging(slug) {
              return slug.replace(/'/g, '');
            },
          });
      });
  }
}

export default Autoslug;
