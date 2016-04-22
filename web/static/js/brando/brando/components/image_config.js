"use strict";

import $ from "jquery";

class ImageConfig {
    static replaceKey(name, newKey) {
        return name.replace(/^sizes\[(\w+)?\]\[(\w+)?\]$/, 'sizes[$1][' + newKey + ']');
    }

    static replaceRecursiveKey(name, newKey) {
        return name.replace(/^sizes\[(\w+)?\]\[(\w+)?\]\[(\w+)?\]$/, 'sizes[$1][$2][' + newKey + ']');
    }

    static replaceMasterKey(name, newKey) {
        return name.replace(/^sizes\[(\w+)?\]\[(\w+)?\]$/, 'sizes[' + newKey + '][$2]');
    }

    static replaceRecursiveMasterKey(name, newKey) {
        return name.replace(/^sizes\[(\w+)?\]\[(\w+)?\]\[(\w+)?\]$/, 'sizes[' + newKey + '][$2][$3]');
    }
    static setup() {
        console.log("Image config setting up...");
        
        $(document).on('keyup', '.standard-key-input, .standard-val-input', function(e) {
            var $el = $(this);
            var $sumEl = $el.parent().parent().find('.actual-value:first');
            if ($el.hasClass('standard-key-input')) {
                $sumEl.attr('name', ImageConfig.replaceKey($sumEl.attr('name'), $el.val()));
            } else if ($el.hasClass('standard-val-input')) {
                $sumEl.val($el.val());
            }
        });

        $(document).on('keyup', '.recursive-key-input, .recursive-val-input', function(e) {
            var $el = $(this);
            var $sumEl = $el.parent().parent().find('.actual-value:first');
            if ($el.hasClass('recursive-key-input')) {
                $sumEl.attr('name', ImageConfig.replaceRecursiveKey($sumEl.attr('name'), $el.val()));
            } else if ($el.hasClass('recursive-val-input')) {
                $sumEl.val($el.val());
            }
        });

        $(document).on('keyup', '.standard-masterkey-input', function(e) {
            var $el = $(this);
            var domain = $el.parent().parent().parent().find('.actual-value');
            $.each(domain, function(k, input) {
                $(input).attr('name', ImageConfig.replaceMasterKey($(input).attr('name'), $el.val()));
            });
        });

        $(document).on('keyup', '.recursive-masterkey-input', function(e) {
            var $el = $(this);
            var domain = $el.parent().parent().parent().find('.actual-value');
            $.each(domain, function(k, input) {
                $(input).attr('name', ImageConfig.replaceRecursiveMasterKey($(input).attr('name'), $el.val()));
            });
        });

        $(document).on('click', '.delete-subkey', function(e) {
            // remove row
            $(this).parent().parent().parent().remove();
        });

        $(document).on('click', '.delete-key', function(e) {
            // remove fieldset
            $(this).parent().parent().remove();
        });

        $(document).on('click', '.add-masterkey-standard', function(e) {
            var lastFieldset = $('.grid-form > fieldset').last();

            e.preventDefault();

            var $fieldset = $([
                '<fieldset>',
                '  <legend>',
                '  <br>',
                '    Key <span class="btn btn-xs delete-key"><i class="fa fa-fw fa-ban"></i></span>',
                '  </legend>',
                '  <div class="form-row">',
                '    <div class="form-group required no-height">',
                '      <label>Masterkey</label>',
                '      <input type="text" class="standard-masterkey-input" value="keyname" placeholder="keyname">',
                '    </div>',
                '  </div>',
                '',
                '  <div class="form-row">',
                '    <div class="form-group required no-height">',
                '      <label>Key <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>',
                '      <input type="text" class="standard-key-input" value="quality">',
                '    </div>',
                '    <div class="form-group required no-height">',
                '      <label>Value</label>',
                '      <input type="text" class="standard-val-input" value="100">',
                '    </div>',
                '    <input type="hidden" class="actual-value" name="sizes[keyname][quality]" value="100">',
                '  </div>',
                '  <div class="form-row">',
                '    <div class="form-group required no-height">',
                '      <label>Key <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>',
                '      <input type="text" class="standard-key-input" value="size">',
                '    </div>',
                '    <div class="form-group required no-height">',
                '      <label>Value</label>',
                '      <input type="text" class="standard-val-input" value="700">',
                '    </div>',
                '    <input type="hidden" class="actual-value" name="sizes[keyname][size]" value="700">',
                '  </div>',
                '</fieldset>'
            ].join(""));

            if (lastFieldset.length == 0) {
                $fieldset.insertBefore($(this).parent());
            } else {
                $fieldset.insertAfter(lastFieldset);
            }
        });

        $(document).on('click', '.add-masterkey-pl', function(e) {
            var lastFieldset = $('.grid-form > fieldset').last();

            e.preventDefault();

            var $fieldset = $([
                '<fieldset>',
                '  <legend>',
                '  <br>',
                '    Key <span class="btn btn-xs delete-key"><i class="fa fa-fw fa-ban"></i></span>',
                '  </legend>',
                '  <div class="form-row">',
                '    <div class="form-group required no-height">',
                '      <label>Masterkey</label>',
                '      <input type="text" class="recursive-masterkey-input" value="keyname" placeholder="keyname">',
                '    </div>',
                '  </div>',
                '  <fieldset>',
                '    <legend>',
                '      <br>',
                '      Orientation: landscape',
                '    </legend>',
                '    <div class="form-row">',
                '      <div class="form-group required no-height">',
                '        <label>Key <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>',
                '        <input type="text" class="recursive-key-input" value="quality">',
                '      </div>',
                '      <div class="form-group required no-height">',
                '        <label>Value</label>',
                '        <input type="text" class="recursive-val-input" value="100">',
                '      </div>',
                '      <input type="hidden" class="actual-value orientation-value" name="sizes[keyname][landscape][quality]" value="100">',
                '    </div>',
                '    <div class="form-row">',
                '      <div class="form-group required no-height">',
                '        <label>Key <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>',
                '        <input type="text" class="recursive-key-input" value="size">',
                '      </div>',
                '      <div class="form-group required no-height">',
                '        <label>Value</label>',
                '        <input type="text" class="recursive-val-input" value="900">',
                '      </div>',
                '      <input type="hidden" class="actual-value orientation-value" name="sizes[keyname][landscape][size]" value="900">',
                '    </div>',
                '  </fieldset>',
                '  <fieldset>',
                '    <legend>',
                '      <br>',
                '      Orientation: portrait',
                '    </legend>',
                '    <div class="form-row">',
                '      <div class="form-group required no-height">',
                '        <label>Key <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>',
                '        <input type="text" class="recursive-key-input" value="quality">',
                '      </div>',
                '      <div class="form-group required no-height">',
                '        <label>Value</label>',
                '        <input type="text" class="recursive-val-input" value="100">',
                '      </div>',
                '      <input type="hidden" class="actual-value orientation-value" name="sizes[keyname][portrait][quality]" value="100">',
                '    </div>',
                '    <div class="form-row">',
                '      <div class="form-group required no-height">',
                '        <label>Key <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>',
                '        <input type="text" class="recursive-key-input" value="size">',
                '      </div>',
                '      <div class="form-group required no-height">',
                '        <label>Value</label>',
                '        <input type="text" class="recursive-val-input" value="900">',
                '      </div>',
                '      <input type="hidden" class="actual-value orientation-value" name="sizes[keyname][portrait][size]" value="900">',
                '    </div>',
                '  </fieldset>',
                '</fieldset>'
            ].join(""));

            if (lastFieldset.length == 0) {
                $fieldset.insertBefore($(this).parent());
            } else {
                $fieldset.insertAfter(lastFieldset);
            }
        });

        $(document).on('click', '.add-key-standard', function(e) {
            e.preventDefault();
            // grab masterkey
            var masterkey = $(this).parent().parent().find('.standard-masterkey-input').val();

            var $row = $([
                '<div class="form-row">',
                '  <div class="form-group required no-height">',
                '    <label>Key <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>',
                '    <input type="text" class="standard-key-input" value="keyname">',
                '  </div>',
                '  <div class="form-group required no-height">',
                '    <label>Value</label>',
                '    <input type="text" class="standard-val-input" value="keyvalue">',
                '  </div>',
                '  <input type="hidden" class="actual-value" name="sizes[' + masterkey + '][keyname]" value="keyvalue">',
                '</div>'
            ].join(""));

            $row.insertBefore($(this).parent());

        });

        $(document).on('click', '.add-key-recursive', function(e) {
            e.preventDefault();
            // grab masterkey
            var masterkey = $(this).parent().parent().parent().find('.recursive-masterkey-input').val();
            var orientation = $(this).attr('data-orientation');

            var $row = $([
                '<div class="form-row">',
                '  <div class="form-group required no-height">',
                '    <label>Key <span class="btn btn-xs delete-subkey"><i class="fa fa-fw fa-ban"></i></span></label>',
                '    <input type="text" class="standard-key-input" value="keyname">',
                '  </div>',
                '  <div class="form-group required no-height">',
                '    <label>Value</label>',
                '    <input type="text" class="standard-val-input" value="keyvalue">',
                '  </div>',
                '  <input type="hidden" class="actual-value" name="sizes[' + masterkey + '][' + orientation + '][keyname]" value="keyvalue">',
                '</div>'
            ].join(""));

            $row.insertBefore($(this).parent());
        });
    }
}

export default ImageConfig;
