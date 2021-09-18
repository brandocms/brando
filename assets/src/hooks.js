// hooks and callbacks
import AdminHook from './hooks/Admin'
import BlockHook from './hooks/Block'
import BlocksHook from './hooks/Blocks'
import CodeEditorHook from './hooks/CodeEditor'
import CircleDropdownHook from './hooks/CircleDropdown'
import ConfirmClickHook from './hooks/ConfirmClick'
import DateTimePickerHook from './hooks/DateTimePicker'
import DragDropHook from './hooks/DragDrop'
import FocalPointHook from './hooks/FocalPoint'
import FormHook from './hooks/Form'
import LegacyImageUploadHook from './hooks/LegacyImageUpload'
import ModalHook from './hooks/Modal'
import ModulePickerHook from './hooks/ModulePicker'
import PopoverHook from './hooks/Popover'
import PresenceHook from './hooks/Presence'
import SelectFilterHook from './hooks/SelectFilter'
import SelectOptionsScrollerHook from './hooks/SelectOptionsScroller'
import SlugHook from './hooks/Slug'
import SortableHook from './hooks/Sortable'
import SubFormSortableHook from './hooks/SubFormSortable'
import SubEntryAddButtonHook from './hooks/SubEntryAddButton'
import SubmitHook from './hooks/Submit'
import StatusDropdownHook from './hooks/StatusDropdown'
import TipTapHook from './hooks/TipTap'

// Brando hooks
export default app => {
  return {
    'Brando.Admin': AdminHook(app),
    'Brando.Block': BlockHook(app),
    'Brando.Blocks': BlocksHook(app),
    'Brando.CircleDropdown': CircleDropdownHook(app),
    'Brando.CodeEditor': CodeEditorHook(app),
    'Brando.ConfirmClick': ConfirmClickHook(app),
    'Brando.DateTimePicker': DateTimePickerHook(app),
    'Brando.DragDrop': DragDropHook(app),
    'Brando.FocalPoint': FocalPointHook(app),
    'Brando.Form': FormHook(app),
    'Brando.LegacyImageUpload': LegacyImageUploadHook(app),
    'Brando.Modal': ModalHook(app),
    'Brando.ModulePicker': ModulePickerHook(app),
    'Brando.Popover': PopoverHook(app),
    'Brando.Presence': PresenceHook(app),
    'Brando.SelectFilter': SelectFilterHook(app),
    'Brando.SelectOptionsScroller': SelectOptionsScrollerHook(app),
    'Brando.Slug': SlugHook(app),
    'Brando.Sortable': SortableHook(app),
    'Brando.StatusDropdown': StatusDropdownHook(app),
    'Brando.SubEntryAddButton': SubEntryAddButtonHook(app),
    'Brando.SubFormSortable': SubFormSortableHook(app),
    'Brando.Submit': SubmitHook(app),
    'Brando.TipTap': TipTapHook(app)
  }
}