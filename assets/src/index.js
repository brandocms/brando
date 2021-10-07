// BRANDOJS
//
// Let the incantations begin. 
// We're in the realm of Javascript now.
//
// '             .           .
//      o       '   o  .     '   . O
//   '   .   ' .   _____  '    .      .
//    .     .   .mMMMMMMMm.  '  o  '   .
//  '   .     .MMXXXXXXXXXMM.    .   ' 
// .       . /XX77:::::::77XX\ .   .   .
//    o  .  ;X7:::''''''':::7X;   .  '
//   '    . |::'.:'        '::| .   .  .
//      .   ;:.:.            :;. o   .
//   '     . \'.:            /.    '   .
//      .     `.':.        .'.  '    .
//    '   . '  .`-._____.-'   .  . '  .
//     ' o   '  .   O   .   '  o    '
//      . ' .  ' . '  ' O   . '  '   '
//       . .   '    '  .  '   . '  '
//        . .'..' . ' ' . . '.  . '
//         `.':.'        ':'.'.'
//           `\\_  |     _//'
//             \(  |\    )/
//             //\ |_\  /\\
//            (/ /\(" )/\ \)
//             \/\ (  ) /\/
//                |(  )|
//                | \( \
//                |  )  \
//                |      \
//                |       \
//                |        `.__,
//                \_________.-'Ojo/gnv
//

// CSS imports
import 'nprogress/nprogress.css'
import 'vex-js/dist/css/vex.css'
import 'tippy.js/dist/tippy.css'
import 'flatpickr/dist/flatpickr.css'
import '../css/app.css'

// main app construction
import buildApplication from './buildApplication'
import brandoHooks from './hooks'
import initializeLiveSocket from './initializeLiveSocket'

export {
  buildApplication,
  brandoHooks,
  initializeLiveSocket,
}