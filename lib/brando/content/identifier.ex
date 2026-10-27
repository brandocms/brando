defmodule Brando.Content.Identifier do
  @moduledoc """
  Schema for content identifiers.

  This is a regular Ecto schema rather than a Blueprint so identifier generation does not
  introduce a compile-time dependency cycle back into the Blueprint system.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @fields ~w(
    entry_id
    title
    status
    language
    cover
    url
    external_url
    schema
    updated_at
  )a

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: pos_integer() | nil,
          entry_id: pos_integer() | nil,
          schema: module() | nil,
          title: String.t() | nil,
          status: Brando.Type.Status.status() | nil,
          language: atom() | nil,
          cover: String.t() | nil,
          url: String.t() | nil,
          external_url: String.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @derive {Jason.Encoder, only: @fields}
  schema "content_identifiers" do
    field :entry_id, :id
    field :schema, Brando.Type.Module
    field :title, :string
    field :status, Brando.Type.Status
    field :language, Brando.Type.Atom
    field :cover, :string
    # `url` is the entry's page on this site (`__absolute_url__/1`);
    # `external_url` is where links go when it has none
    # (`absolute_url ..., link_others_to:`). Link to `link_url/1`.
    field :url, :string
    field :external_url, :string
    field :updated_at, :utc_datetime
  end

  @doc """
  Where a link to the entry goes: its page on this site, else the external
  destination its blueprint names with `link_others_to:`, else `nil`.
  """
  @spec link_url(t() | map() | nil) :: String.t() | nil
  def link_url(%{url: url}) when is_binary(url) and url != "", do: url
  def link_url(%{external_url: url}) when is_binary(url) and url != "", do: url
  def link_url(_), do: nil

  @doc """
  The identifier's title as plain text, for HEEx, an attribute or
  `textContent` to escape once.

  A HEEx identifier (`identifier ~H"{@entry.title}"`) stores the title
  escaped, `Rock &amp; Roll`, and HEEx escapes the stored text again, so its
  title is decoded first and every character is encoded once. A Liquid
  identifier stores the title as written; it is returned as it is. Markup in
  a title comes back as markup: the result must never reach `raw/1` or
  `innerHTML` unescaped.

  Takes an identifier, or the entry's schema and the title it stored.
  """
  @spec title_text(t() | map() | nil) :: String.t() | nil
  def title_text(%{schema: schema, title: title}), do: title_text(schema, title)
  def title_text(%{title: title}) when is_binary(title), do: title
  def title_text(_), do: nil

  @spec title_text(module() | nil, String.t() | nil) :: String.t() | nil
  def title_text(schema, title) when is_binary(title),
    do: if(heex_identifier?(schema), do: HtmlEntities.decode(title), else: title)

  def title_text(_schema, _title), do: nil

  defp heex_identifier?(schema) when is_atom(schema) and not is_nil(schema) do
    Code.ensure_loaded?(schema) and function_exported?(schema, :__identifier_type__, 0) and
      schema.__identifier_type__() == :heex
  end

  defp heex_identifier?(_), do: false

  @doc """
  Builds a changeset for persisting an identifier snapshot.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params \\ %{}) do
    cast(struct, params, @fields)
  end

  @doc """
  Reports that identifiers do not implement the soft-delete trait.

  This compatibility callback lets query code treat identifiers like Blueprint-backed schemas.
  """
  @spec has_trait(Brando.Trait.SoftDelete) :: false
  def has_trait(Brando.Trait.SoftDelete), do: false

  @doc """
  Returns the identifier preloads required by entry relations on `schema`.
  """
  @spec preloads_for(module()) :: [{atom(), [:identifier]}]
  def preloads_for(schema) do
    schema
    |> Brando.Blueprint.Relations.__relations__()
    |> Enum.filter(&(&1.type == :entries))
    |> Enum.map(&{&1.name, [:identifier]})
  end

  @doc """
  Returns the module registry expected by shared schema and query helpers.
  """
  @spec __modules__() :: %{
          context: module(),
          application: module(),
          gettext: module(),
          schema: module(),
          admin_form_view: nil,
          admin_list_view: nil
        }
  def __modules__ do
    %{
      context: Brando.Content,
      application: Brando,
      gettext: Brando.Gettext,
      schema: Brando.Content.Identifier,
      admin_form_view: nil,
      admin_list_view: nil
    }
  end
end
