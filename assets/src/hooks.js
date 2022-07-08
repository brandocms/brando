// hooks and callbacks
import AdminHook from './hooks/Admin'
import BlockHook from './hooks/Block'
import CodeEditorHook from './hooks/CodeEditor'
import ColorPickerHook from './hooks/ColorPicker'
import ConfirmClickHook from './hooks/ConfirmClick'
import DateTimePickerHook from './hooks/DateTimePicker'
import DragDropHook from './hooks/DragDrop'
import FocalPointHook from './hooks/FocalPoint'
import FormHook from './hooks/Form'
import LegacyImageUploadHook from './hooks/LegacyImageUpload'
import ListingHook from './hooks/Listing'
import LivePreviewHook from './hooks/LivePreview'
import MapURLParserHook from './hooks/MapURLParser'
import ModalHook from './hooks/Modal'
import ModulePickerHook from './hooks/ModulePicker'
import SelectFilterHook from './hooks/SelectFilter'
import RememberScrollPositionHook from './hooks/RememberScrollPosition'
import SchedulerHook from './hooks/Scheduler'
import SlugHook from './hooks/Slug'
import SortableHook from './hooks/Sortable'
import SortableBlocksHook from './hooks/SortableBlocks'
import SubFormSortableHook from './hooks/SubFormSortable'
import SubmitHook from './hooks/Submit'
import SVGDropHook from './hooks/SVGDrop'
import TipTapHook from './hooks/TipTap'
import VideoURLParserHook from './hooks/VideoURLParser'

// Brando hooks
export default app => {
  return {
    'Brando.Admin': AdminHook(app),
    'Brando.Block': BlockHook(app),
    'Brando.CodeEditor': CodeEditorHook(app),
    'Brando.ColorPicker': ColorPickerHook(app),
    'Brando.ConfirmClick': ConfirmClickHook(app),
    'Brando.DateTimePicker': DateTimePickerHook(app),
    'Brando.DragDrop': DragDropHook(app),
    'Brando.FocalPoint': FocalPointHook(app),
    'Brando.Form': FormHook(app),
    'Brando.LegacyImageUpload': LegacyImageUploadHook(app),
    'Brando.Listing': ListingHook(app),
    'Brando.LivePreview': LivePreviewHook(app),
    'Brando.MapURLParser': MapURLParserHook(app),
    'Brando.Modal': ModalHook(app),
    'Brando.ModulePicker': ModulePickerHook(app),
    'Brando.SelectFilter': SelectFilterHook(app),
    'Brando.RememberScrollPosition': RememberScrollPositionHook(app),
    'Brando.Scheduler': SchedulerHook(app),
    'Brando.Slug': SlugHook(app),
    'Brando.Sortable': SortableHook(app),
    'Brando.SortableBlocks': SortableBlocksHook(app),
    'Brando.SubFormSortable': SubFormSortableHook(app),
    'Brando.Submit': SubmitHook(app),
    'Brando.SVGDrop': SVGDropHook(app),
    'Brando.TipTap': TipTapHook(app),
    'Brando.VideoURLParser': VideoURLParserHook(app)
  }
}