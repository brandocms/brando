defmodule BrandoAdmin.FileReplacementAcceptTest do
  # The Replace file dialog's picker offers the files the replacement check
  # takes: the stored extension and the others of its type that the check
  # also takes, or every file when no list can name them.
  use Brando.LiveCase

  alias Brando.Files
  alias Brando.Files.Replacement

  setup do
    put_test_env(:tenancy_mode, :none)
    put_file_config(slugify_filename: true)
    :ok
  end

  test "lists the stored extension and the others of its type the check takes", %{conn: conn, current_user: user} do
    for {stored, accept} <- [
          {"report.pdf", ".pdf"},
          {"photo.jpg", ".jpg,.jpeg"},
          {"photo.jpeg", ".jpeg"},
          {"scan.tif", ".tif"},
          {"REPORT.PDF", ".pdf"}
        ] do
      file = insert_file(user, stored)

      assert replacement_accept(conn, file) == accept, stored

      for ext <- String.split(accept, ",") do
        assert {:ok, :server} = initiate(file, "picked" <> ext), "#{ext} for #{stored}"
      end
    end
  end

  test "lists .jpeg for a stored .jpg whether or not the config slugs", %{conn: conn, current_user: user} do
    for opts <- [[slugify_filename: false], [random_filename: true]] do
      put_file_config(opts)
      file = insert_file(user, "photo.jpg")

      assert replacement_accept(conn, file) == ".jpg,.jpeg", inspect(opts)
    end
  end

  # `scan.jpglarge` was slugged from a name such as `scan.jpg_large`, which the
  # check takes but no list can name
  test "does not filter the picker for an extension of no known type when the config slugs", %{
    conn: conn,
    current_user: user
  } do
    for stored <- ["scan.jpglarge", "scan.jpg_large", "brochure.indd", "README"] do
      file = insert_file(user, stored)

      assert replacement_accept(conn, file) == nil, stored
    end

    file = insert_file(user, "scan.jpglarge")
    assert {:ok, :server} = initiate(file, "scan.jpg_large")
  end

  # Without slugging, the check takes such an extension only as stored
  test "lists an extension of no known type when the config does not slug", %{conn: conn, current_user: user} do
    for opts <- [[slugify_filename: false], [slugify_filename: true, random_filename: true]],
        {stored, accept} <- [{"scan.jpg_large", ".jpg_large"}, {"brochure.INDD", ".indd"}] do
      put_file_config(opts)
      file = insert_file(user, stored)

      assert replacement_accept(conn, file) == accept, "#{stored} #{inspect(opts)}"
      assert {:ok, :server} = initiate(file, "picked" <> accept)
      assert {:error, _} = initiate(file, "picked.pdf")
    end

    put_file_config(slugify_filename: false)
    assert replacement_accept(conn, insert_file(user, "README")) == nil
  end

  defp replacement_accept(conn, file) do
    {:ok, view, _html} = live(conn, "/admin/assets/files")
    render_click(view, "replace_file", %{"id" => to_string(file.id)})

    view
    |> element("#file-replacement-upload-#{file.id}")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.attribute("data-accept")
    |> List.first()
  end

  defp initiate(file, name) do
    Replacement.initiate(file.id, %{name: name, size: 20, type: "application/octet-stream"})
  end

  defp put_file_config(opts) do
    put_test_env(Files,
      default_config: Map.merge(%{upload_path: "files/accept", allowed_mimetypes: ["*"], size_limit: 100}, Map.new(opts))
    )
  end

  defp insert_file(user, filename) do
    {:ok, file} =
      Files.create_file(
        %{filename: filename, filesize: 8, mime_type: "application/octet-stream", config_target: "default"},
        user
      )

    file
  end
end
