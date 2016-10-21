import $ from 'jquery';

class FilterTable {
  static setup() {
    // set up table filtering
    $('[data-filter-table]')
      .each((index, elem) => {
        $(elem)
          .searcher({
            inputSelector: '#filter-input',
          });
      });
  }
}

export default FilterTable;
