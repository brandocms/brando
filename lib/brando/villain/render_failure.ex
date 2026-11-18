defmodule Brando.Villain.RenderFailure do
  @moduledoc """
  One block template that failed while blocks rendered: what
  `Brando.Villain.parse_checked/3` and `Brando.Content.Blocks.render_fields/3`
  return, and what a stored render that refused to store returns as
  `{:error, {:render_failed, failures}}`.

    * `:kind`: `:parse` (the template does not parse or compile) or `:render`
      (it raised while it rendered). A loop or collection filter over a list
      that is nil is no failure: it reads as an empty list, as in Liquid
    * `:message`: what Liquex or HEEx said
    * `:line`: the template line, when the error gives one
    * `:block_uid`, `:block_id`, `:block_type`: the block whose template failed,
      the innermost one (a container's child, a multi module's entry). Nil
      when the failure could not be traced to a block.
    * `:module_id`, `:module_uid`, `:module_origin`, `:module_name`: the
      block's module, for a module block
    * `:field`: the block field (`:blocks`), set by
      `Brando.Content.Blocks.render_fields/3`
  """

  @type kind :: :parse | :render

  @type t :: %__MODULE__{
          kind: kind,
          message: String.t(),
          line: pos_integer | nil,
          field: atom | nil,
          block_uid: String.t() | nil,
          block_id: integer | nil,
          block_type: atom | nil,
          module_id: integer | nil,
          module_uid: String.t() | nil,
          module_origin: atom | nil,
          module_name: String.t() | nil
        }

  defstruct [
    :kind,
    :message,
    :line,
    :field,
    :block_uid,
    :block_id,
    :block_type,
    :module_id,
    :module_uid,
    :module_origin,
    :module_name
  ]

  @doc "One line naming the block, its module and the error, for logs and reports."
  @spec describe(t) :: String.t()
  def describe(%__MODULE__{} = failure) do
    where =
      [
        failure.field && "field #{failure.field}",
        failure.block_uid && "block #{failure.block_uid}",
        failure.module_name &&
          "module #{inspect(failure.module_name)}#{if failure.module_id, do: " (#{failure.module_id})"}"
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    line = if failure.line, do: " on line #{failure.line}", else: ""
    where = if where == "", do: "", else: where <> ": "

    "#{where}#{failure.kind}#{line}: #{first_line(failure.message)}"
  end

  @doc "`describe/1` for each failure, joined with `; `."
  @spec describe_all([t]) :: String.t()
  def describe_all(failures), do: Enum.map_join(failures, "; ", &describe/1)

  defp first_line(nil), do: ""
  defp first_line(message), do: message |> String.split("\n", parts: 2) |> hd() |> String.trim()
end
