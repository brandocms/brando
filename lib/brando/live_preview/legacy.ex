defmodule Brando.LivePreview.Legacy do
  @moduledoc false

  # Retained for generated migration code from older Brando releases.
  @deprecated "use layout/1 instead"
  defmacro layout_module(_), do: nil

  @deprecated "use template/1 instead"
  defmacro view_module(_), do: nil

  @deprecated "use template/1 instead"
  defmacro view_template(_), do: nil
end
