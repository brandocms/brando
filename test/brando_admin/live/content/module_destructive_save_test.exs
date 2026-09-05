defmodule BrandoAdmin.Live.Content.ModuleDestructiveSaveTest do
  @moduledoc """
  A module save migrates every block that uses it. These cover the gate in front
  of the saves that orphan editor content — that it opens, that it says how far
  the change reaches, and that it does not stand between the editor and an
  ordinary save.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component, only: [to_form: 2]

  alias Brando.Content.Block
  alias Brando.Content.Module
  alias Brando.Content.Ref
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Villain.Blocks.TextBlock
  alias BrandoAdmin.Content.ModuleFormLive
  alias Ecto.Changeset

  defp text_ref(name) do
    %Ref{
      name: name,
      uid: "uid-#{name}",
      data: %TextBlock{type: "text", data: %TextBlock.Data{text: "Hello"}},
      sequence: 0
    }
  end

  defp insert_module(refs, vars \\ []) do
    :module
    |> Factory.build(%{code: "<div>{% ref refs.intro %}</div>"})
    |> Changeset.change()
    |> Changeset.put_assoc(:refs, refs)
    |> Changeset.put_assoc(:vars, vars)
    |> Brando.Repo.insert!()
    |> Brando.Repo.preload([:refs, :vars])
  end

  defp insert_block(module, user) do
    %Block{}
    |> Changeset.change(%{
      uid: Brando.Utils.generate_uid(),
      type: :module,
      module_id: module.id,
      module_version: module.version,
      creator_id: user.id,
      sequence: 0
    })
    |> Brando.Repo.insert!()
  end

  defp socket_for(module, user) do
    form = module |> Module.changeset(%{}, user) |> to_form([])

    %Phoenix.LiveView.Socket{}
    |> Phoenix.Component.assign(:form, form)
    |> Phoenix.Component.assign(:entry, module)
    |> Phoenix.Component.assign(:current_user, user)
    |> Phoenix.Component.assign(:shared_library?, false)
    |> Phoenix.Component.assign(:save_redirect_target, :self)
    |> Phoenix.Component.assign(:pending_destructive_save, nil)
  end

  # The params a save event carries. Refs and vars come back as index-keyed maps,
  # so dropping one is expressed by simply not sending it.
  defp params(module, overrides) do
    Map.merge(
      %{
        "name" => module.name,
        "namespace" => module.namespace,
        "help_text" => module.help_text,
        "class" => module.class,
        "code" => module.code
      },
      overrides
    )
  end

  defp ref_params(refs) do
    refs
    |> Enum.with_index()
    |> Map.new(fn {ref, index} ->
      {to_string(index),
       %{
         "id" => to_string(ref.id),
         "name" => ref.name,
         "uid" => ref.uid,
         "data" => %{"type" => "text", "data" => %{"text" => "Hello"}}
       }}
    end)
  end

  setup do
    %{user: Factory.insert(:random_user)}
  end

  describe "a destructive save" do
    test "is held for confirmation instead of running", %{user: user} do
      module = insert_module([text_ref("intro"), text_ref("outro")])
      block = insert_block(module, user)

      assert {:noreply, socket} =
               ModuleFormLive.handle_event(
                 "save",
                 %{"module" => params(module, %{"refs" => ref_params([hd(module.refs)])})},
                 socket_for(module, user)
               )

      pending = socket.assigns.pending_destructive_save
      assert pending
      assert pending.summary != []
      assert Enum.any?(pending.summary, &(&1 =~ "outro"))

      # Nothing was written: the module and its block are exactly as they were.
      assert Brando.Repo.get(Module, module.id).version == module.version
      assert Brando.Repo.get(Block, block.id).module_version == module.version
    end

    test "reports how many blocks the change reaches", %{user: user} do
      module = insert_module([text_ref("intro"), text_ref("outro")])
      for _ <- 1..3, do: insert_block(module, user)

      {:noreply, socket} =
        ModuleFormLive.handle_event(
          "save",
          %{"module" => params(module, %{"refs" => ref_params([hd(module.refs)])})},
          socket_for(module, user)
        )

      assert socket.assigns.pending_destructive_save.affected == {:blocks, 3}
    end

    test "runs once confirmed", %{user: user} do
      module = insert_module([text_ref("intro"), text_ref("outro")])

      {:noreply, held} =
        ModuleFormLive.handle_event(
          "save",
          %{"module" => params(module, %{"refs" => ref_params([hd(module.refs)])})},
          socket_for(module, user)
        )

      assert {:noreply, saved} = ModuleFormLive.handle_event("confirm_destructive_save", %{}, held)

      assert saved.assigns.pending_destructive_save == nil
      reloaded = Brando.Repo.get(Module, module.id)
      assert reloaded.version == module.version + 1
      assert Brando.Repo.preload(reloaded, :refs).refs |> Enum.map(& &1.name) == ["intro"]
    end

    test "is abandoned on cancel, leaving the module untouched", %{user: user} do
      module = insert_module([text_ref("intro"), text_ref("outro")])

      {:noreply, held} =
        ModuleFormLive.handle_event(
          "save",
          %{"module" => params(module, %{"refs" => ref_params([hd(module.refs)])})},
          socket_for(module, user)
        )

      assert {:noreply, cancelled} =
               ModuleFormLive.handle_event("cancel_destructive_save", %{}, held)

      assert cancelled.assigns.pending_destructive_save == nil
      assert Brando.Repo.get(Module, module.id).version == module.version
    end

    test "removing a variable also asks", %{user: user} do
      module = insert_module([], [%Var{key: "title", type: :string, label: "Title"}])

      {:noreply, socket} =
        ModuleFormLive.handle_event(
          "save",
          %{"module" => params(module, %{"vars" => %{}})},
          socket_for(module, user)
        )

      assert socket.assigns.pending_destructive_save
      assert Enum.any?(socket.assigns.pending_destructive_save.summary, &(&1 =~ "title"))
    end
  end

  describe "a non-destructive save" do
    test "goes straight through", %{user: user} do
      module = insert_module([text_ref("intro")])

      assert {:noreply, socket} =
               ModuleFormLive.handle_event(
                 "save",
                 %{
                   "module" =>
                     params(module, %{
                       "code" => "<p>rewritten</p>",
                       "refs" => ref_params(module.refs)
                     })
                 },
                 socket_for(module, user)
               )

      assert socket.assigns.pending_destructive_save == nil
      assert Brando.Repo.get(Module, module.id).code == "<p>rewritten</p>"
    end

    test "adding a reference goes straight through", %{user: user} do
      module = insert_module([text_ref("intro")])

      new_refs =
        module.refs
        |> ref_params()
        |> Map.put("1", %{
          "name" => "added",
          "uid" => "uid-added",
          "data" => %{"type" => "text", "data" => %{"text" => "Hi"}}
        })

      {:noreply, socket} =
        ModuleFormLive.handle_event(
          "save",
          %{"module" => params(module, %{"refs" => new_refs})},
          socket_for(module, user)
        )

      assert socket.assigns.pending_destructive_save == nil
      reloaded = Brando.Repo.preload(Brando.Repo.get(Module, module.id), :refs)
      assert Enum.sort(Enum.map(reloaded.refs, & &1.name)) == ["added", "intro"]
    end
  end
end
