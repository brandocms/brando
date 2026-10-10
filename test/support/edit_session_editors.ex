defmodule Brando.EditSessionEditors do
  @moduledoc """
  What two editors in one entry's edit session do, through real LiveViews
  (`Brando.LiveCase`): type in a block's text, read it back, and wait for
  the other editor to catch up.
  """

  import ExUnit.Assertions, only: [flunk: 1]
  import Phoenix.LiveViewTest, only: [element: 2, render: 1, render_change: 2]

  alias Brando.Pages.Page
  alias Brando.Repo

  @text ["entry_block", "block", "refs", "0", "data", "data", "text"]

  @doc "The text ref's path in a block form's params."
  def text_path, do: @text

  @doc "The page's saved entry blocks, read fresh."
  def rows(page) do
    Page
    |> Repo.get!(page.id)
    |> Repo.preload(Brando.Content.BlockPreloads.for_schema(Page), force: true)
    |> Map.get(:entry_blocks)
  end

  @doc """
  A keystroke in a block's text, as the browser sends it: the whole block
  form with the one value changed, targeted at it.
  """
  def type(view, uid, text), do: set(view, uid, @text, text)

  @doc """
  A change to one field of a block's form (`path` as the form names it,
  e.g. `["entry_block", "block", "table_rows", "0", "vars", "0", "value"]`),
  sent as the browser sends it.
  """
  def set(view, uid, path, value) do
    selector = "#entry_block_form-#{uid}"

    params =
      view
      |> render()
      |> Brando.LiveCase.form_params(selector)
      |> put_in(path, value)
      |> Map.put("_target", path)

    view |> element(selector) |> render_change(params)
  end

  @doc "The text a view shows in a block."
  def shown_text(view, uid),
    do: view |> render() |> Brando.LiveCase.form_params("#entry_block_form-#{uid}") |> get_in(@text)

  @doc """
  Whether a view shows the block from its saved row: the block's form
  carries the row's id. A block another editor's save wrote has it once
  that save's rebase reached this view's block field, which then also asked
  its form to collect again: any event sent to the view after this holds
  is handled after that.

  The session's state (`Brando.EditSession.fetch/3`) moves on before the
  rebase reaches the views, so it cannot tell when a view can act on it.
  """
  def shows_saved?(view, uid) do
    id =
      view
      |> render()
      |> Brando.LiveCase.form_params("#entry_block_form-#{uid}")
      |> get_in(["entry_block", "block", "id"])

    id not in [nil, ""]
  end

  @doc "Waits for `fun` to hold, polling every 20 ms."
  def await(fun, tries \\ 150) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition never held")
      true -> Process.sleep(20) && await(fun, tries - 1)
    end
  end
end
