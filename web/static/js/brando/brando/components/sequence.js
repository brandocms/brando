import $ from 'jquery';
import bI18n from './i18n';
import Sortable from './sortable';

class Sequence {
  static setup() {
    if ($('#sequence').length !== 0) {
      const el = document.getElementById('sequence');
      this.sortable = new Sortable(el, {
        animation: 150,
        ghostClass: 'sequence-ghost',
        onUpdate: function onUpdate() {
          $('#sort-post')
            .removeClass('btn-default', 'btn-success')
            .addClass('btn-warning')
            .html(bI18n.t('sequence:store_new'));
        },
      });
      this.sortListener();
    }
  }


  static sortSuccess(data) {
    if (data.status === '200') {
      $('#sort-post')
        .removeClass('btn-warning')
        .addClass('btn-success')
        .html(bI18n.t('sequence:stored'));
    }
  }

  static sortListener() {
    const that = this;
    $('#sort-post')
      .on('click', function onClick(e) {
        e.preventDefault();
        $(this)
          .removeClass('btn-default')
          .addClass('btn-warning')
          .html(bI18n.t('sequence:storing'));
        $.ajax({
          headers: {
            Accept: 'application/json; charset=utf-8',
          },
          type: 'POST',
          url: '',
          data: {
            order: that.sortable.toArray(),
          },
          success: that.sortSuccess,
        });
      });
  }
}

export default Sequence;
