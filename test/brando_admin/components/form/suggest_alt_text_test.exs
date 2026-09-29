defmodule BrandoAdmin.Components.Form.SuggestAltTextTest do
  # "Suggest alt text" in the image drawer fills the drawer's form, as if
  # typed: saved only with the drawer, so it is reviewed first.
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form

  defp socket(image) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        edit_image: %{image: image},
        image_changeset: Ecto.Changeset.change(image),
        alt_text_suggesting: true
      }
    }
  end

  @image %Brando.Images.Image{id: 7, alt: %{"no" => "Eksisterende"}}

  test "the suggestion joins the alt text already there, unsaved" do
    result = {:ok, {:ok, %{values: %{"en" => "Two people talking", "no" => "To personer"}, model: "m"}}}
    {:noreply, socket} = Form.handle_async({:suggest_alt_text, 7}, result, socket(@image))

    assert Ecto.Changeset.get_change(socket.assigns.image_changeset, :alt) ==
             %{"no" => "To personer", "en" => "Two people talking"}

    refute socket.assigns.alt_text_suggesting
  end

  test "a suggestion for an image no longer in the drawer is dropped" do
    result = {:ok, {:ok, %{values: %{"en" => "Other"}, model: "m"}}}
    {:noreply, socket} = Form.handle_async({:suggest_alt_text, 99}, result, socket(@image))

    assert Ecto.Changeset.get_change(socket.assigns.image_changeset, :alt) == nil
  end

  test "a failure leaves the fields as they were" do
    {:noreply, socket} = Form.handle_async({:suggest_alt_text, 7}, {:ok, {:error, :timeout}}, socket(@image))

    assert Ecto.Changeset.get_change(socket.assigns.image_changeset, :alt) == nil
    refute socket.assigns.alt_text_suggesting
  end

  describe "on the image's own form" do
    defp form_socket(image) do
      %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          entry: image,
          form: Phoenix.Component.to_form(Ecto.Changeset.change(image), [])
        }
      }
    end

    test "the suggestion fills the form's alt text, unsaved" do
      result = {:ok, {:ok, %{values: %{"en" => "Two people talking"}, model: "m"}}}
      {:noreply, socket} = Form.handle_async({:suggest_entry_alt_text, 7}, result, form_socket(@image))

      assert Ecto.Changeset.get_change(socket.assigns.form.source, :alt) ==
               %{"no" => "Eksisterende", "en" => "Two people talking"}
    end
  end

  describe "for a picture block, in the entry's language" do
    test "the text for that language goes back to the block" do
      result = {:ok, {"en", {:ok, %{values: %{"en" => "A chair"}, model: "m"}}}}

      {:noreply, _} =
        Form.handle_async({:suggest_ref_alt_text, {SomeBlock, "ref-1"}}, result, %Phoenix.LiveView.Socket{})

      assert_received {:phoenix, :send_update,
                       {{SomeBlock, "ref-1"}, %{event: "alt_text_suggested", result: {:ok, "A chair"}}}}
    end

    test "no text in that language is a failure the block reports" do
      result = {:ok, {"en", {:ok, %{values: %{"no" => "En stol"}, model: "m"}}}}

      {:noreply, _} =
        Form.handle_async({:suggest_ref_alt_text, {SomeBlock, "ref-1"}}, result, %Phoenix.LiveView.Socket{})

      assert_received {:phoenix, :send_update, {{SomeBlock, "ref-1"}, %{result: :error}}}
    end
  end
end
