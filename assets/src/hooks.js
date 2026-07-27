// hooks and callbacks
import AdminHook from './hooks/Admin'
import AssetFolderDropHook from './hooks/AssetFolderDrop'
import BlockFieldHook from './hooks/BlockField'
import BlockHook from './hooks/Block'
import CodeEditorHook from './hooks/CodeEditor'
import ColorPickerHook from './hooks/ColorPicker'
import ConfirmClickHook from './hooks/ConfirmClick'
import DatePickerHook from './hooks/DatePicker'
import DateTimePickerHook from './hooks/DateTimePicker'
import FieldBaseHook from './hooks/FieldBase'
import FocalPointHook from './hooks/FocalPoint'
import ImageEditorHook from './hooks/ImageEditor'
import ImagePickerGridHook from './hooks/ImagePickerGrid'
import FormHook from './hooks/Form'
import ListingHook from './hooks/Listing'
import LivePreviewHook from './hooks/LivePreview'
import MapURLParserHook from './hooks/MapURLParser'
import MuxUploaderHook from './hooks/MuxUploader'
import BunnyUploaderHook from './hooks/BunnyUploader'
import CloudflareUploaderHook from './hooks/CloudflareUploader'
import NavigationHook from './hooks/Navigation'
import PublishClosestInputHook from './hooks/PublishClosestInput'
import PublishInputHook from './hooks/PublishInput'
import RememberScrollPositionHook from './hooks/RememberScrollPosition'
import SelectFilterHook from './hooks/SelectFilter'
import SchedulerHook from './hooks/Scheduler'
import SlugHook from './hooks/Slug'
import SortableHook from './hooks/Sortable'
import SortableInputsForHook from './hooks/SortableInputsFor'
import SortableAssocsHook from './hooks/SortableAssocs'
import SortableBlocksHook from './hooks/SortableBlocks'
import SortableEmbedsHook from './hooks/SortableEmbeds'
import SubFormSortableHook from './hooks/SubFormSortable'
import SubmitHook from './hooks/Submit'
import SVGDropHook from './hooks/SVGDrop'
import TipTapHook from './hooks/TipTap'
import UploadManagerHook from './hooks/UploadManager'
import UploadTriggerHook from './hooks/UploadTrigger'
import VarLayoutHook from './hooks/VarLayout'
import VideoPickerGridHook from './hooks/VideoPickerGrid'
import VideoURLParserHook from './hooks/VideoURLParser'

// Brando hooks
export default (app) => {
  return {
    'Brando.Admin': AdminHook(app),
    'Brando.AssetFolderDrop': AssetFolderDropHook(app),
    'Brando.BlockField': BlockFieldHook(app),
    'Brando.Block': BlockHook(app),
    'Brando.CodeEditor': CodeEditorHook(app),
    'Brando.ColorPicker': ColorPickerHook(app),
    'Brando.ConfirmClick': ConfirmClickHook(app),
    'Brando.DatePicker': DatePickerHook(app),
    'Brando.DateTimePicker': DateTimePickerHook(app),
    'Brando.FieldBase': FieldBaseHook(app),
    'Brando.FocalPoint': FocalPointHook(app),
    'Brando.Form': FormHook(app),
    'Brando.ImageEditor': ImageEditorHook(app),
    'Brando.ImagePickerGrid': ImagePickerGridHook(app),
    'Brando.Listing': ListingHook(app),
    'Brando.LivePreview': LivePreviewHook(app),
    'Brando.MapURLParser': MapURLParserHook(app),
    'Brando.MuxUploader': MuxUploaderHook(app),
    'Brando.BunnyUploader': BunnyUploaderHook(app),
    'Brando.CloudflareUploader': CloudflareUploaderHook(app),
    'Brando.Navigation': NavigationHook(app),
    'Brando.PublishClosestInput': PublishClosestInputHook(app),
    'Brando.PublishInput': PublishInputHook(app),
    'Brando.RememberScrollPosition': RememberScrollPositionHook(app),
    'Brando.SelectFilter': SelectFilterHook(app),
    'Brando.Scheduler': SchedulerHook(app),
    'Brando.Slug': SlugHook(app),
    'Brando.Sortable': SortableHook(app),
    'Brando.SortableInputsFor': SortableInputsForHook(app),
    'Brando.SortableAssocs': SortableAssocsHook(app),
    'Brando.SortableBlocks': SortableBlocksHook(app),
    'Brando.SortableEmbeds': SortableEmbedsHook(app),
    'Brando.SubFormSortable': SubFormSortableHook(app),
    'Brando.Submit': SubmitHook(app),
    'Brando.SVGDrop': SVGDropHook(app),
    'Brando.TipTap': TipTapHook(app),
    'Brando.UploadManager': UploadManagerHook(app),
    'Brando.UploadTrigger': UploadTriggerHook(app),
    'Brando.VarLayout': VarLayoutHook(app),
    'Brando.VideoPickerGrid': VideoPickerGridHook(app),
    'Brando.VideoURLParser': VideoURLParserHook(app),
  }
}
