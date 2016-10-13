'use strict';

import $ from 'jquery';
import {
  bI18n
} from './i18n';

class ImageConfig {
  static replaceKey(name, newKey) {
    return name.replace(/^sizes\[(\w+)?\]\[(\w+)?\]$/, 'sizes[$1][' + newKey + ']');
  }

  static replaceRecursiveKey(name, newKey) {
    return name.replace(/^sizes\[(\w+)?\]\[(\w+)?\]\[(\w+)?\]$/, 'sizes[$1][$2][' + newKey +
      ']');
  }

  static replaceMasterKey(name, newKey) {
    return name.replace(/^sizes\[(\w+)?\]\[(\w+)?\]$/, 'sizes[' + newKey + '][$2]');
  }

  static replaceRecursiveMasterKey(name, newKey) {
    return name.replace(/^sizes\[(\w+)?\]\[(\w+)?\]\[(\w+)?\]$/, 'sizes[' + newKey +
      '][$2][$3]');
  }

  static setup() {
    $(document)
      .on('keyup', '.standard-key-input, .standard-val-input', function() {
        var $el = $(this);
        var $sumEl = $el.parent()
          .parent()
          .find('.actual-value:first');
        if ($el.hasClass('standard-key-input')) {
          $sumEl.attr('name', ImageConfig.replaceKey($sumEl.attr('name'), $el.val()));
        } else if ($el.hasClass('standard-val-input')) {
          $sumEl.val($el.val());
        }
      });

    $(document)
      .on('keyup', '.recursive-key-input, .recursive-val-input', function() {
        var $el = $(this);
        var $sumEl = $el.parent()
          .parent()
          .find('.actual-value:first');
        if ($el.hasClass('recursive-key-input')) {
          $sumEl.attr('name', ImageConfig.replaceRecursiveKey($sumEl.attr('name'), $el.val()));
        } else if ($el.hasClass('recursive-val-input')) {
          $sumEl.val($el.val());
        }
      });

    $(document)
      .on('keyup', '.standard-masterkey-input', function() {
        var $el = $(this);
        var domain = $el.parent()
          .parent()
          .parent()
          .find('.actual-value');
        $.each(domain, function(k, input) {
          $(input)
            .attr('name', ImageConfig.replaceMasterKey($(input)
              .attr('name'), $el.val()));
        });
      });

    $(document)
      .on('keyup', '.recursive-masterkey-input', function() {
        var $el = $(this);
        var domain = $el.parent()
          .parent()
          .parent()
          .find('.actual-value');
        $.each(domain, function(k, input) {
          $(input)
            .attr('name', ImageConfig.replaceRecursiveMasterKey($(input)
              .attr('name'), $el.val()));
        });
      });

    $(document)
      .on('click', '.delete-subkey', function() {
        // remove row
        $(this)
          .parent()
          .parent()
          .parent()
          .remove();
      });

    $(document)
      .on('click', '.delete-key', function() {
        // remove fieldset
        $(this)
          .parent()
          .parent()
          .remove();
      });

    $(document)
      .on('click', '.add-masterkey-standard', function(e) {
        var lastFieldset = $('.grid-form > fieldset')
          .last();

        e.preventDefault();

        var $fieldset = $([
          `<fieldset>`,
          `  <legend>`,
          `  <br>`,
          `    ${bI18n.t('image_config:key')} <span class="btn btn-xs delete-key"><i class="fa fa-fw fa-ban"></i></span>`,
          `  </legend>`,
          `  <div class="form-row">`,
          `    <div class="form-group required no-height">`,
          `      <label>${bI18n.t('image_config:masterkey')}</label>`,
          `      <input type="text" class="standard-masterkey-input" value="keyname" placeholder="keyname">`,
          `    </div>`,
          `  </div>`,
          ``,
          `  <div class="form-row">`,
          `    <div class="form-group required no-height">`,
          `      <label>${bI18n.t('image_config:key')} <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>`,
          `      <input type="text" class="standard-key-input" value="quality">`,
          `    </div>`,
          `    <div class="form-group required no-height">`,
          `      <label>${bI18n.t('image_config:value')}</label>`,
          `      <input type="text" class="standard-val-input" value="100">`,
          `    </div>`,
          `    <input type="hidden" class="actual-value" name="sizes[keyname][quality]" value="100">`,
          `  </div>`,
          `  <div class="form-row">`,
          `    <div class="form-group required no-height">`,
          `      <label>${bI18n.t('image_config:key')} <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>`,
          `      <input type="text" class="standard-key-input" value="size">`,
          `    </div>`,
          `    <div class="form-group required no-height">`,
          `      <label>${bI18n.t('image_config:value')}</label>`,
          `      <input type="text" class="standard-val-input" value="700">`,
          `    </div>`,
          `    <input type="hidden" class="actual-value" name="sizes[keyname][size]" value="700">`,
          `  </div>`,
          `</fieldset>`
        ].join(''));

        if (lastFieldset.length == 0) {
          $fieldset.insertBefore($(this)
            .parent());
        } else {
          $fieldset.insertAfter(lastFieldset);
        }
      });

    $(document)
      .on('click', '.add-masterkey-pl', function(e) {
        var lastFieldset = $('.grid-form > fieldset')
          .last();

        e.preventDefault();

        var $fieldset = $([
          `<fieldset>`,
          `  <legend>`,
          `  <br>`,
          `    ${bI18n.t('image_config:key')} <span class="btn btn-xs delete-key"><i class="fa fa-fw fa-ban"></i></span>`,
          `  </legend>`,
          `  <div class="form-row">`,
          `    <div class="form-group required no-height">`,
          `      <label>${bI18n.t('image_config:masterkey')}</label>`,
          `      <input type="text" class="recursive-masterkey-input" value="keyname" placeholder="keyname">`,
          `    </div>`,
          `  </div>`,
          `  <fieldset>`,
          `    <legend>`,
          `      <br>`,
          `      ${bI18n.t('image_config:orientation_landscape')} `,
          `    </legend>`,
          `    <div class="form-row">`,
          `      <div class="form-group required no-height">`,
          `        <label>${bI18n.t('image_config:key')} <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>`,
          `        <input type="text" class="recursive-key-input" value="quality">`,
          `      </div>`,
          `      <div class="form-group required no-height">`,
          `        <label>${bI18n.t('image_config:value')}</label>`,
          `        <input type="text" class="recursive-val-input" value="100">`,
          `      </div>`,
          `      <input type="hidden" class="actual-value orientation-value" name="sizes[keyname][landscape][quality]" value="100">`,
          `    </div>`,
          `    <div class="form-row">`,
          `      <div class="form-group required no-height">`,
          `        <label>${bI18n.t('image_config:key')} <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>`,
          `        <input type="text" class="recursive-key-input" value="size">`,
          `      </div>`,
          `      <div class="form-group required no-height">`,
          `        <label>${bI18n.t('image_config:value')} </label>`,
          `        <input type="text" class="recursive-val-input" value="900">`,
          `      </div>`,
          `      <input type="hidden" class="actual-value orientation-value" name="sizes[keyname][landscape][size]" value="900">`,
          `    </div>`,
          `  </fieldset>`,
          `  <fieldset>`,
          `    <legend>`,
          `      <br>`,
          `      ${bI18n.t('image_config:orientation_portrait')}`,
          `    </legend>`,
          `    <div class="form-row">`,
          `      <div class="form-group required no-height">`,
          `        <label>${bI18n.t('image_config:key')} <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>`,
          `        <input type="text" class="recursive-key-input" value="quality">`,
          `      </div>`,
          `      <div class="form-group required no-height">`,
          `        <label>${bI18n.t('image_config:value')}</label>`,
          `        <input type="text" class="recursive-val-input" value="100">`,
          `      </div>`,
          `      <input type="hidden" class="actual-value orientation-value" name="sizes[keyname][portrait][quality]" value="100">`,
          `    </div>`,
          `    <div class="form-row">`,
          `      <div class="form-group required no-height">`,
          `        <label>${bI18n.t('image_config:key')} <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>`,
          `        <input type="text" class="recursive-key-input" value="size">`,
          `      </div>`,
          `      <div class="form-group required no-height">`,
          `        <label>${bI18n.t('image_config:value')}</label>`,
          `        <input type="text" class="recursive-val-input" value="900">`,
          `      </div>`,
          `      <input type="hidden" class="actual-value orientation-value" name="sizes[keyname][portrait][size]" value="900">`,
          `    </div>`,
          `  </fieldset>`,
          `</fieldset>`
        ].join(''));

        if (lastFieldset.length == 0) {
          $fieldset.insertBefore($(this)
            .parent());
        } else {
          $fieldset.insertAfter(lastFieldset);
        }
      });

    $(document)
      .on('click', '.add-key-standard', function(e) {
        e.preventDefault();
        // grab masterkey
        var masterkey = $(this)
          .parent()
          .parent()
          .find('.standard-masterkey-input')
          .val();

        var $row = $([
          `<div class="form-row">`,
          `  <div class="form-group required no-height">`,
          `    <label>${bI18n.t('image_config:key')} <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>`,
          `    <input type="text" class="standard-key-input" value="keyname">`,
          `  </div>`,
          `  <div class="form-group required no-height">`,
          `    <label>${bI18n.t('image_config:value')}</label>`,
          `    <input type="text" class="standard-val-input" value="keyvalue">`,
          `  </div>`,
          `  <input type="hidden" class="actual-value" name="sizes[${masterkey}][keyname]" value="keyvalue">`,
          `</div>`
        ].join(''));

        $row.insertBefore($(this)
          .parent());

      });

    $(document)
      .on('click', '.add-key-recursive', function(e) {
        e.preventDefault();
        // grab masterkey
        var masterkey = $(this)
          .parent()
          .parent()
          .parent()
          .find('.recursive-masterkey-input')
          .val();
        var orientation = $(this)
          .attr('data-orientation');

        var $row = $([
          `<div class="form-row">`,
          `  <div class="form-group required no-height">`,
          `    <label>${bI18n.t('image_config:key')} <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>`,
          `    <input type="text" class="standard-key-input" value="keyname">`,
          `  </div>`,
          `  <div class="form-group required no-height">`,
          `    <label>${bI18n.t('image_config:value')}</label>`,
          `    <input type="text" class="standard-val-input" value="keyvalue">`,
          `  </div>`,
          `  <input type="hidden" class="actual-value" name="sizes[${masterkey}][${orientation}][keyname]" value="keyvalue">`,
          `</div>`
        ].join(''));

        $row.insertBefore($(this)
          .parent());
      });

    $(document)
      .on('click', '.propagate-configuration', function(e) {
        var $btn = $(this);
        var url = $btn.attr('data-url');
        var prevCaption = $btn.html();
        $btn
          .removeClass('btn-default')
          .addClass('btn-warning')
          .html('<i class="fa fa-cog fa-spin"></i>');
        e.preventDefault();

        $.ajax({
          headers: {
            Accept: 'application/json; charset=utf-8'
          },
          type: 'GET',
          url: url
        })
        .done($.proxy(function() {
          /**
           * Callback after confirming.
           */

          $btn
            .removeClass('btn-warning')
            .addClass('btn-success')
            .html(prevCaption);
        }));
      });
  }
}

export default ImageConfig;
