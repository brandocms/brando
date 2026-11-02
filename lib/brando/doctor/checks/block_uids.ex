defmodule Brando.Doctor.Checks.BlockUids do
  @moduledoc """
  Block rows whose uid has another shape than `Brando.Content.Block.valid_uid?/1`
  admits, stored before uids had one. Such a block renders without the markers
  frontend edit and live preview find it by, and a uid holding markup is still
  in the database. The uids are counted, and matched in SQL
  (`Brando.Content.Block.uid_sql_pattern/0`), so none of them is printed.
  """
  use Brando.Doctor.Check
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Doctor.Context

  @impl true
  def id, do: "block_uids"

  @impl true
  def label, do: dgettext("doctor", "Block uids")

  @impl true
  def run(%Context{} = context) do
    context
    |> Context.each_environment(&count/0)
    |> evaluate()
  end

  @doc "The rows of the current prefix with a uid of another shape."
  @spec count() :: non_neg_integer()
  def count do
    pattern = Block.uid_sql_pattern()
    Brando.Repo.one(from(b in Block, where: fragment("coalesce(?, '') !~ ?", b.uid, ^pattern), select: count()))
  end

  @doc "Turns `[{environment_label, count}]` into a result."
  def evaluate(per_environment) do
    case per_environment |> Enum.map(&elem(&1, 1)) |> Enum.sum() do
      0 ->
        ok(dgettext("doctor", "every block has a uid of the expected shape"))

      total ->
        warning(
          dngettext("doctor", "%{count} block with a badly shaped uid", "%{count} blocks with badly shaped uids", total),
          fix:
            dgettext(
              "doctor",
              "they render without frontend edit and live preview markers: duplicate each one in its entry, which gives the copy a good uid, and delete the original. Look into any uid holding markup. List them in SQL: SELECT id, source, uid FROM content_blocks WHERE coalesce(uid, '') !~ '%{pattern}'",
              pattern: Block.uid_sql_pattern()
            ),
          items:
            for {label, count} <- per_environment, label != nil, count > 0 do
              Context.label_item(label, dngettext("doctor", "%{count} block", "%{count} blocks", count))
            end
        )
    end
  end
end
