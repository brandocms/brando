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

      {:noreply, socket} =
        Form.handle_async({:suggest_alt_text, 7, @panel, %{"no" => "Eksisterende"}}, result, socket(@image))

      assert_received {:phoenix, :send_update,
                       {{AltTextSuggestion, @panel},
                        %{values: %{"en" => "Two people talking", "no" => "To personer"}, image_id: 7}}}

      assert Ecto.Changeset.get_change(socket.assigns.image_changeset, :alt) == nil
      refute socket.assigns.alt_text_suggesting
    end

    test "accepted, it joins the alt text already there, unsaved" do
      {:ok, socket} =
        Form.update(
          %{
            event: "accept_alt_suggestion",
            scope: "suggest_alt_text",
            values: %{"en" => "Two people", "no" => "To"},
            image_id: 7,
            original: %{"no" => "Eksisterende"}
          },
          socket(@image)
        )

      assert Ecto.Changeset.get_change(socket.assigns.image_changeset, :alt) == %{"no" => "To", "en" => "Two people"}
    end

    test "accepted after the drawer moved on to another image, it changes nothing" do
      other = %Brando.Images.Image{id: 8, alt: %{"no" => "Annet"}}

      {:ok, socket} =
        Form.update(
          %{
            event: "accept_alt_suggestion",
            scope: "suggest_alt_text",
            values: %{"en" => "Of 7"},
            image_id: 7,
            original: %{}
          },
          socket(other)
        )

      assert Ecto.Changeset.get_change(socket.assigns.image_changeset, :alt) == nil
    end

    test "accepted, it leaves a language written since it was asked for" do
      changeset = Ecto.Changeset.change(@image, alt: %{"no" => "Skrevet nå", "en" => ""})
      socket = put_in(socket(@image).assigns.image_changeset, changeset)

      {:ok, socket} =
        Form.update(
          %{
            event: "accept_alt_suggestion",
            scope: "suggest_alt_text",
            values: %{"en" => "Two people", "no" => "To"},
            image_id: 7,
            original: %{"no" => "Eksisterende"}
          },
          socket
        )

      assert Ecto.Changeset.get_change(socket.assigns.image_changeset, :alt) == %{
               "no" => "Skrevet nå",
               "en" => "Two people"
             }
    end

    test "a suggestion for an image no longer in the drawer is dropped" do
      result = {:ok, {:ok, %{values: %{"en" => "Other"}, model: "m"}}}
      {:noreply, _socket} = Form.handle_async({:suggest_alt_text, 99, @panel, %{}}, result, socket(@image))

      refute_received {:phoenix, :send_update, _}
    end

    test "a failure leaves the fields as they were" do
      {:noreply, socket} =
        Form.handle_async(
          {:suggest_alt_text, 7, @panel, %{"no" => "Eksisterende"}},
          {:ok, {:error, :timeout}},
          socket(@image)
        )

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

      {:noreply, socket} =
        Form.handle_async({:suggest_entry_alt_text, 7, @panel, %{"no" => "Eksisterende"}}, result, form_socket(@image))

      assert_received {:phoenix, :send_update, {{AltTextSuggestion, @panel}, %{values: %{"en" => "Two people talking"}}}}
      assert Ecto.Changeset.get_change(socket.assigns.form.source, :alt) == nil
    end
  end

  describe "for a picture block, in the entry's language" do
    test "the text for that language goes back to the block" do
      result = {:ok, {"en", {:ok, %{values: %{"en" => "A chair"}, model: "m"}}}}

      {:noreply, _} =
        Form.handle_async({:suggest_ref_alt_text, {SomeBlock, "ref-1"}, 5}, result, %Phoenix.LiveView.Socket{})

      assert_received {:phoenix, :send_update,
                       {{SomeBlock, "ref-1"}, %{event: "alt_text_suggested", result: {:ok, "en", "A chair"}, image_id: 5}}}
    end

    test "no text in that language is a failure the block reports" do
      result = {:ok, {"en", {:ok, %{values: %{"no" => "En stol"}, model: "m"}}}}

      {:noreply, _} =
        Form.handle_async({:suggest_ref_alt_text, {SomeBlock, "ref-1"}, 5}, result, %Phoenix.LiveView.Socket{})

      assert_received {:phoenix, :send_update, {{SomeBlock, "ref-1"}, %{result: :error}}}
    end
  end

  describe "which languages, and what Accept keeps" do
    test "asks only for the languages the field has no text in, as the form has it" do
      assert AltTextSuggestion.languages(%{"en" => "Typed, unsaved", "no" => " "}) == ["no"]
      assert AltTextSuggestion.languages(nil) == Brando.Images.AltText.languages()
      # Text in every language: asked again for all of them
      assert AltTextSuggestion.languages(%{"en" => "A", "no" => "B"}) == Brando.Images.AltText.languages()
    end

    test "merges over empty languages and those unchanged since, not over new text" do
      assert AltTextSuggestion.merge(
               %{"en" => "Typed since", "no" => "Was here", "de" => ""},
               %{"en" => "AI", "no" => "KI", "de" => "KI-de"},
               %{"en" => "", "no" => "Was here"}
             ) == %{"en" => "Typed since", "no" => "KI", "de" => "KI-de"}
    end
  end

  describe "a picture block" do
    alias BrandoAdmin.Components.Form.Input.Blocks.PictureBlock

    defp block_socket(image_id, alt) do
      block =
        %Brando.Villain.Blocks.PictureBlock{}
        |> Brando.Villain.Blocks.PictureBlock.changeset(%{"data" => %{"alt" => alt}})
        |> Phoenix.Component.to_form()

      %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          block: block,
          image: %Brando.Images.Image{id: image_id},
          target_ref: {SomeBlock, "block-1"},
          ref_name: "picture",
          uid: "ref-uid",
          alt_suggesting: true,
          alt_requested_from: alt
        }
      }
    end

    defp accept(socket, image_id, original) do
      PictureBlock.update(
        %{event: "accept_alt_suggestion", values: %{"en" => "A chair"}, image_id: image_id, original: original},
        socket
      )
    end

    test "Accept writes this use's alt text" do
      {:ok, _socket} = accept(block_socket(5, nil), 5, %{"en" => nil})

      assert_received {:phoenix, :send_update,
                       {{SomeBlock, "block-1"}, %{event: "update_ref_data", ref_data: %{alt: "A chair"}, image_id: 5}}}
    end

    test "after the block took another image, the reply is dropped and Accept changes nothing" do
      {:ok, _socket} =
        PictureBlock.update(
          %{event: "alt_text_suggested", result: {:ok, "en", "A chair"}, image_id: 5},
          block_socket(6, nil)
        )

      refute_received {:phoenix, :send_update, _}

      {:ok, _socket} = accept(block_socket(6, nil), 5, %{"en" => nil})
      refute_received {:phoenix, :send_update, _}
    end

    test "the reply for the block's image goes to that image's panel" do
      {:ok, _socket} =
        PictureBlock.update(
          %{event: "alt_text_suggested", result: {:ok, "en", "A chair"}, image_id: 5},
          block_socket(5, "Old")
        )

      assert_received {:phoenix, :send_update,
                       {{AltTextSuggestion, "block-ref-uid-ref-alt-5-alt-suggestion"},
                        %{values: %{"en" => "A chair"}, image_id: 5, original: %{"en" => "Old"}}}}
    end

    test "Accept leaves alt text written since it was asked for" do
      {:ok, _socket} = accept(block_socket(5, "Written since"), 5, %{"en" => "Old"})
      refute_received {:phoenix, :send_update, _}
    end
  end
end
