defmodule Brando.Upload do
  @moduledoc false
  # Deprecated name for `Brando.Uploads.Store` (renamed in 0.55, #2833;
  # removed in 0.57). Singular `Brando.Upload` beside the `Brando.Uploads`
  # context said nothing about which did what. The struct moved with the
  # functions: `%Brando.Upload{}` needs the new name.

  @type t :: Brando.Uploads.Store.t()

  @deprecated "Use Brando.Uploads.Store.handle_upload/4 instead"
  defdelegate handle_upload(meta, upload_entry, cfg, user), to: Brando.Uploads.Store

  @deprecated "Use Brando.Uploads.Store.process_upload/3 instead"
  defdelegate process_upload(image, cfg, user), to: Brando.Uploads.Store

  @deprecated "Use Brando.Uploads.Store.handle_upload_type/2 instead"
  defdelegate handle_upload_type(upload, user), to: Brando.Uploads.Store

  @deprecated "Use Brando.Uploads.Store.handle_upload_type/3 instead"
  defdelegate handle_upload_type(upload, user, transport), to: Brando.Uploads.Store

  @deprecated "Use Brando.Uploads.Store.filter_plugs/1 instead"
  defdelegate filter_plugs(params), to: Brando.Uploads.Store

  @deprecated "Use Brando.Uploads.Store.handle_upload_error/1 instead"
  defdelegate handle_upload_error(error), to: Brando.Uploads.Store

  @deprecated "Use Brando.Uploads.Store.error_to_string/1 instead"
  defdelegate error_to_string(error), to: Brando.Uploads.Store
end
