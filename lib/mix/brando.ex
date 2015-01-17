defmodule Mix.Brando do
  require Logger
  # Conveniences for Brando mix tasks.
  @moduledoc false

    @doc """
  Copy's the files from one directory to the specified directory, renaming files as needed.
  """
  def copy_from(source_dir, target_dir, file_name_template, fun) do
    source_paths =
      source_dir
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)

    for source_path <- source_paths do
      unless source_path == ".DS_Store" do
        target_path = make_destination_path(source_path, source_dir,
                                            target_dir, file_name_template)

        unless File.dir?(source_path) do
          contents = fun.(source_path)
          Mix.Generator.create_file(target_path, contents)
        end
      end
    end
  end

  @doc """
  Creates a file or folder, renaming where applicable.
  """
  def make_destination_path(source_path, source_dir, target_dir, {string_to_replace, name_of_generated}) do
    target_path =
      source_path
      |> String.replace(string_to_replace, String.downcase(name_of_generated))
      |> Path.relative_to(source_dir)
    Path.join(target_dir, target_path)
  end

  def make_destination_path(source_path, source_dir, target_dir, {}) do
    target_path =
      source_path
      #|> String.replace(string_to_replace, String.downcase(name_of_generated))
      |> Path.relative_to(source_dir)
    Path.join(target_dir, target_path)
  end

  def make_destination_path(source_path, source_dir, target_dir, application_name) do
    target_path =
      source_path
      |> String.replace("application_name", application_name)
      |> Path.relative_to(source_dir)
    Path.join(target_dir, target_path)
  end
end
