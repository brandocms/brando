defmodule BrandoAdmin.Components.Form.SuggestAltTextTest do
  # "Suggest alt text" in the image drawer and the image's own form: the reply
  # is a suggestion in the field's panel (`AltTextSuggestion`); only Accept
  # writes it into the form, unsaved.
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.AltTextSuggestion

  @panel "image_alt-alt-suggestion"

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

  describe "in the image drawer" do
    test "the reply goes to the field's suggestion panel, and the drawer's form is unchanged" do
      result = {:ok, {:ok, %{values: %{"en" => "Two people talking", "no" => "To personer"}, model: "m"}}}
      {:noreply, socket} = Form.handle_async({:suggest_alt_text, 7, @panel}, result, socket(@image))

      assert_received {:phoenix, :send_update,
                       {{AltTextSuggestion, @panel}, %{values: %{"en" => "Two people talking", "no" => "To personer"}}}}

      assert Ecto.Changeset.get_change(socket.assigns.image_changeset, :alt) == nil
      refute socket.assigns.alt_text_suggesting
    end

    test "accepted, it joins the alt text already there, unsaved" do
      {:ok, socket} =
        Form.update(
          %{event: "accept_alt_suggestion", scope: "suggest_alt_text", values: %{"en" => "Two people", "no" => "To"}},
          socket(@image)
        )

      assert Ecto.Changeset.get_change(socket.assigns.image_changeset, :alt) == %{"no" => "To", "en" => "Two people"}
    end

    test "a suggestion for an image no longer in the drawer is dropped" do
      result = {:ok, {:ok, %{values: %{"en" => "Other"}, model: "m"}}}
      {:noreply, _socket} = Form.handle_async({:suggest_alt_text, 99, @panel}, result, socket(@image))

      refute_received {:phoenix, :send_update, _}
    end

    test "a failure leaves the fields as they were" do
      {:noreply, socket} = Form.handle_async({:suggest_alt_text, 7, @panel}, {:ok, {:error, :timeout}}, socket(@image))

      assert Ecto.Changeset.get_change(socket.assigns.image_changeset, :alt) == nil
      refute_received {:phoenix, :send_update, _}
      refute socket.assigns.alt_text_suggesting
    end
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

    test "the reply is a suggestion; accepted, it fills the form's alt text, unsaved" do
      result = {:ok, {:ok, %{values: %{"en" => "Two people talking"}, model: "m"}}}
      {:noreply, socket} = Form.handle_async({:suggest_entry_alt_text, 7, @panel}, result, form_socket(@image))

      assert_received {:phoenix, :send_update, {{AltTextSuggestion, @panel}, %{values: %{"en" => "Two people talking"}}}}
      assert Ecto.Changeset.get_change(socket.assigns.form.source, :alt) == nil
    end
  end

  describe "for a picture block, in the entry's language" do
    test "the text for that language goes back to the block" do
      result = {:ok, {"en", {:ok, %{values: %{"en" => "A chair"}, model: "m"}}}}

      {:noreply, _} =
        Form.handle_async({:suggest_ref_alt_text, {SomeBlock, "ref-1"}}, result, %Phoenix.LiveView.Socket{})

      assert_received {:phoenix, :send_update,
                       {{SomeBlock, "ref-1"}, %{event: "alt_text_suggested", result: {:ok, "en", "A chair"}}}}
    end

    test "no text in that language is a failure the block reports" do
      result = {:ok, {"en", {:ok, %{values: %{"no" => "En stol"}, model: "m"}}}}

      {:noreply, _} =
        Form.handle_async({:suggest_ref_alt_text, {SomeBlock, "ref-1"}}, result, %Phoenix.LiveView.Socket{})

      assert_received {:phoenix, :send_update, {{SomeBlock, "ref-1"}, %{result: :error}}}
    end
  end
end
