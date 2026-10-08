defmodule Brando.Test.Forms do
  @moduledoc """
  Drive an entry's admin form in a LiveView test: open it, fill fields by
  their blueprint names, add blocks, save and read the validation errors.
  Imported by `use Brando.Test`; see `Brando.Test`.

      {view, _html} = open_form(conn, MyApp.Projects.Project)
      fill_form(view, MyApp.Projects.Project, title: "Sommerro", client: client.id)
      add_block(view, MyApp.Projects.Project, text_module)
      assert {:ok, _path} = save_form(view, MyApp.Projects.Project)

  The form must be mounted by a logged-in user (`Brando.Test.log_in_as/2`),
  and the test must not be `async`: the form's LiveView reads the test's data
  through a shared SQL sandbox.
  """

  import ExUnit.Assertions, only: [flunk: 1]

  alias Brando.Blueprint.{Assets, Attributes, Relations}
  alias Phoenix.LiveViewTest

  @doc """
  The admin path and form id for an entry (its update form) or a schema (its
  create form). `path:` and `form_id:` override them, for a named form.
  """
  @spec form_target(struct() | module(), keyword()) :: {String.t(), String.t()}
  def form_target(schema_or_entry, opts \\ [])

  def form_target(%schema{id: id}, opts),
    do: {opts[:path] || schema.__admin_route__(:update, [id]), opts[:form_id] || form_id(schema)}

  def form_target(schema, opts) when is_atom(schema),
    do: {opts[:path] || schema.__admin_route__(:create, []), opts[:form_id] || form_id(schema)}

  @doc "The id of the form component for `schema`'s default form, such as `\"project_form\"`."
  @spec form_id(module()) :: String.t()
  def form_id(schema), do: "#{schema.__naming__().singular}_form"

  @doc "The params key the form posts `schema`'s fields under, such as `\"project\"`."
  @spec form_name(module()) :: String.t()
  def form_name(schema), do: schema |> Module.split() |> List.last() |> Macro.underscore()

  @doc """
  Re-render `view` until `selector` matches, and return the HTML. Fails the
  test after `timeout` milliseconds.
  """
  @spec await_selector(struct(), String.t(), non_neg_integer()) :: String.t()
  def await_selector(view, selector, timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_selector(view, selector, deadline)
  end

  defp do_await_selector(view, selector, deadline) do
    html = LiveViewTest.render(view)

    cond do
      html |> Floki.parse_document!() |> Floki.find(selector) |> Enum.any?() ->
        html

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("`#{selector}` never appeared in the rendered LiveView")

      true ->
        Process.sleep(20)
        do_await_selector(view, selector, deadline)
    end
  end

  @doc """
  Fill fields of `schema`'s form, as typing would (a `phx-change`), and return
  the rendered HTML. `attrs` are named as in the blueprint: attributes, assets
  and relations, where a `belongs_to` relation takes the related id.

      fill_form(view, Project, title: "Sommerro", status: :draft, client: client.id)

  Raises for a name the blueprint does not have, and, through
  `Phoenix.LiveViewTest.form/3`, for a field the form does not show.
  """
  @spec fill_form(struct(), module(), map() | keyword(), keyword()) :: String.t()
  def fill_form(view, schema, attrs, opts \\ []) do
    view
    |> LiveViewTest.form("##{opts[:form_id] || form_id(schema)}_form", form_params(schema, attrs))
    |> LiveViewTest.render_change()
  end

  @doc ~S|`attrs` as the form posts them: `%{"project" => %{"title" => …}}`.|
  @spec form_params(module(), map() | keyword()) :: map()
  def form_params(schema, attrs) do
    fields = Map.new(attrs, fn {name, value} -> {field_key(schema, name), param(value)} end)
    %{form_name(schema) => fields}
  end

  defp field_key(schema, name) do
    name = if is_binary(name), do: String.to_existing_atom(name), else: name

    cond do
      Attributes.__attribute__(schema, name) -> to_string(name)
      relation = Relations.__relation__(schema, name) -> relation_key(relation)
      Assets.__asset__(schema, name) -> "#{name}_id"
      String.ends_with?(to_string(name), "_id") -> to_string(name)
      true -> raise ArgumentError, "#{inspect(schema)} has no field #{inspect(name)}"
    end
  end

  defp relation_key(%{type: :belongs_to, name: name}), do: "#{name}_id"
  defp relation_key(%{name: name}), do: to_string(name)

  defp param(value) when is_atom(value) and not is_boolean(value) and not is_nil(value), do: to_string(value)
  defp param(%{__struct__: _} = value), do: value
  defp param(value) when is_map(value), do: Map.new(value, fn {key, v} -> {to_string(key), param(v)} end)
  defp param(value), do: value

  @doc """
  Add a block from `module` to the form's block field, as picking it in the
  block editor does, and return the new block's uid once it is shown.

  Options: `field:` (the schema's first block field by default),
  `sequence:` (the position; the end by default) and `form_id:`.
  """
  @spec add_block(struct(), module(), Brando.Content.Module.t() | integer(), keyword()) :: String.t()
  def add_block(view, schema, module, opts \\ []) do
    field = opts[:field] || schema.__blocks_fields__() |> List.first() |> Map.fetch!(:name)
    field_id = "#{opts[:form_id] || form_id(schema)}-blocks-#{field}"
    # The block editor renders a moment after the form.
    await_selector(view, "##{field_id}-wrapper")
    known = block_uids(view, field_id)

    Phoenix.LiveView.send_update(view.pid, BrandoAdmin.Components.Form.BlockField,
      id: field_id,
      event: "insert_block",
      sequence: Keyword.get(opts, :sequence, length(known)),
      module_id: module_id(module)
    )

    await_new_block(view, field_id, known, System.monotonic_time(:millisecond) + 2_000)
  end

  defp module_id(%{id: id}), do: id
  defp module_id(id) when is_integer(id), do: id

  defp await_new_block(view, field_id, known, deadline) do
    case block_uids(view, field_id) -- known do
      [uid | _] ->
        uid

      [] ->
        if System.monotonic_time(:millisecond) >= deadline, do: flunk("the new block never appeared in ##{field_id}")
        Process.sleep(20)
        await_new_block(view, field_id, known, deadline)
    end
  end

  defp block_uids(view, field_id) do
    view
    |> LiveViewTest.render()
    |> Floki.parse_document!()
    |> Floki.find("##{field_id}-wrapper [data-block-uid]")
    |> Enum.flat_map(&Floki.attribute(&1, "data-block-uid"))
    |> Enum.uniq()
  end

  @doc """
  Save the form, with `attrs` filled in first (see `fill_form/4`).

  Saving is two submits, as in the browser: the first collects the block
  fields and the second writes. Returns `{:ok, path}` with the path the form
  went to after saving, or `{:error, errors}` with the validation errors the
  form shows, by field (see `form_errors/2`).
  """
  @spec save_form(struct(), module(), map() | keyword(), keyword()) ::
          {:ok, String.t()} | {:error, %{atom() => [String.t()]}}
  def save_form(view, schema, attrs \\ %{}, opts \\ []) do
    selector = "##{opts[:form_id] || form_id(schema)}_form"
    params = form_params(schema, attrs)
    %{proxy: {ref, topic, _}} = view

    view |> LiveViewTest.form(selector, params) |> LiveViewTest.render_submit()

    receive do
      {^ref, {:push_event, "b:submit", _}} -> :ok
    after
      Keyword.get(opts, :timeout, 2_000) -> flunk("the form did not collect its fields for saving")
    end

    view |> LiveViewTest.form(selector, params) |> LiveViewTest.render_submit()

    receive do
      {^ref, {kind, ^topic, %{to: to}}} when kind in [:redirect, :live_redirect] -> {:ok, to}
    after
      Keyword.get(opts, :timeout, 2_000) ->
        case form_errors(view, schema) do
          errors when errors == %{} ->
            flunk(
              "the form neither saved nor showed an error. A required field the form does not show " <>
                "fails without a message on screen; the log has the changeset errors"
            )

          errors ->
            {:error, errors}
        end
    end
  end

  @doc """
  The validation errors `view` (or rendered `html`) shows for `schema`'s
  form, as a map of field names to messages. Only fields the editor has
  touched show errors, as in the browser.
  """
  @spec form_errors(struct() | String.t(), module()) :: %{atom() => [String.t()]}
  def form_errors(%LiveViewTest.View{} = view, schema), do: view |> LiveViewTest.render() |> form_errors(schema)

  def form_errors(html, schema) when is_binary(html) do
    prefix = form_name(schema) <> "_"

    html
    |> Floki.parse_document!()
    |> Floki.find(".field-errors[id$='-error']")
    |> Enum.reduce(%{}, fn element, errors ->
      [id] = Floki.attribute(element, "id")
      field = id |> String.trim_trailing("-error") |> String.replace_prefix(prefix, "")
      messages = element |> Floki.find(".field-error") |> Enum.map(&(&1 |> Floki.text() |> String.trim()))

      if messages == [],
        do: errors,
        else: Map.update(errors, field_atom(field), messages, &(&1 ++ messages))
    end)
  end

  defp field_atom(field) do
    String.to_existing_atom(field)
  rescue
    ArgumentError -> field
  end
end
