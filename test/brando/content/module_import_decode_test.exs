defmodule Brando.Content.ModuleImportDecodeTest do
  @moduledoc """
  Module import reads text a user pastes (audit NV4). It is decoded without
  creating atoms or functions, and only a list of modules gets through.
  """
  use ExUnit.Case, async: true

  alias Brando.Content
  alias Brando.Content.Module
  alias BrandoAdmin.Content.ModuleListLive
  alias Phoenix.LiveView.Socket

  defp encode(term), do: term |> :erlang.term_to_binary() |> Base.encode64()

  defp module(attrs \\ %{}), do: struct(Module, Map.merge(%{vars: [], refs: [], children: []}, attrs))

  describe "deserialize_modules/1" do
    test "reads an export back" do
      modules = [module(%{name: %{"en" => "Text"}, children: [module()]})]

      assert {:ok, [%Module{name: %{"en" => "Text"}, children: [%Module{}]}]} =
               modules |> Content.serialize_modules() |> Content.deserialize_modules()
    end

    test "creates no atom the text names" do
      name = "brando_module_import_#{System.unique_integer([:positive])}"
      # External term format: a list holding one atom (SMALL_ATOM_UTF8_EXT)
      binary = <<131, 108, 1::32, 119, byte_size(name), name::binary, 106>>

      assert Content.deserialize_modules(Base.encode64(binary)) == {:error, :invalid}
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end

    test "refuses a function" do
      assert Content.deserialize_modules(encode([fn -> :ok end])) == {:error, :invalid}
    end

    test "refuses anything but a list of modules" do
      for term <- [%{}, "text", [%{vars: [], refs: [], children: []}], [module(%{vars: nil})], [module(%{children: :x})]] do
        assert Content.deserialize_modules(encode(term)) == {:error, :invalid}, inspect(term)
      end

      for term <- [
            [module() | :x],
            [module(%{vars: [module()]})],
            [module(%{refs: [:ref]})],
            [module(%{vars: [nil | nil]})]
          ] do
        assert Content.deserialize_modules(encode(term)) == {:error, :invalid}, inspect(term)
      end

      grandchild = module(%{children: [module()]})
      assert Content.deserialize_modules(encode([module(%{children: [grandchild]})])) == {:error, :invalid}
    end

    test "refuses a compressed term that would expand past the limit, before expanding it" do
      # A compressed term (tag 80) claiming 64 MB once inflated
      binary = <<131, 80, 64 * 1_048_576::32>> <> :zlib.compress(<<107, 0, 1, 0>>)

      assert Content.deserialize_modules(Base.encode64(binary)) == {:error, :invalid}
    end

    test "refuses text that is not base64" do
      assert Content.deserialize_modules("not base64!") == {:error, :invalid}
    end
  end

  describe "the import dialog" do
    defp validate(text) do
      socket =
        Phoenix.Component.assign(%Socket{},
          imported_modules: nil,
          import_invalid?: false,
          current_user: :system
        )

      {:noreply, socket} =
        ModuleListLive.handle_event("validate_module_import", %{"encoded_modules" => text}, socket)

      socket.assigns
    end

    test "says so when the text is not an export, and keeps nothing to import" do
      assert %{imported_modules: nil, import_invalid?: true} = validate("not base64!")
      assert %{imported_modules: nil, import_invalid?: true} = validate(encode(%{}))
    end

    test "lists the modules of an export" do
      assert %{imported_modules: [%Module{}], import_invalid?: false} =
               validate(Content.serialize_modules([module()]))
    end
  end
end
