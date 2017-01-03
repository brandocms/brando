import vex from 'vex-js';
import vexDialog from 'vex-dialog';
import i18n from './i18n';

vex.registerPlugin(vexDialog);

vex.defaultOptions.className = 'vex-theme-plain';
vex.dialog.buttons.YES.text = 'OK';
vex.dialog.buttons.NO.text = i18n.t('vex:cancel');

export default vex;
