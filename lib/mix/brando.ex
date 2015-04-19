defmodule Mix.Brando do
  require Logger
  # Conveniences for Brando mix tasks.
  @moduledoc false

  @doc """
  Copies the files from one directory to the specified directory, renaming files as needed.
  """
  def copy_from(source_dir, target_dir, file_name_template, fun) do
    source_paths =
      source_dir
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)

    for source_path <- source_paths do
      unless Path.basename(source_path) == ".DS_Store" do
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
  def make_destination_path(source_path, source_dir, target_dir, {}) do
    target_path =
      source_path
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

  def logo do
    Mix.shell.info(IO.ANSI.red() <> ~s(
     .S_SSSs     .S_sSSs     .S_SSSs     .S_sSSs     .S_sSSs      sSSs_sSSs
    .SS~SSSSS   .SS~YS%%b   .SS~SSSSS   .SS~YS%%b   .SS~YS%%b    d%%SP~YS%%b
    S%S   SSSS  S%S   `S%b  S%S   SSSS  S%S   `S%b  S%S   `S%b  d%S'     `S%b
    S%S    S%S  S%S    S%S  S%S    S%S  S%S    S%S  S%S    S%S  S%S       S%S
    S%S SSSS%P  S%S    d*S  S%S SSSS%S  S%S    S&S  S%S    S&S  S&S       S&S
    S&S  SSSY   S&S   .S*S  S&S  SSS%S  S&S    S&S  S&S    S&S  S&S       S&S
    S&S    S&S  S&S_sdSSS   S&S    S&S  S&S    S&S  S&S    S&S  S&S       S&S
    S&S    S&S  S&S~YSY%b   S&S    S&S  S&S    S&S  S&S    S&S  S&S       S&S
    S*S    S&S  S*S   `S%b  S*S    S&S  S*S    S*S  S*S    d*S  S*b       d*S
    S*S    S*S  S*S    S%S  S*S    S*S  S*S    S*S  S*S   .S*S  S*S.     .S*S
    S*S SSSSP   S*S    S&S  S*S    S*S  S*S    S*S  S*S_sdSSS    SSSbs_sdSSS
    S*S  SSY    S*S    SSS  SSS    S*S  S*S    SSS  SSS~YSSY      YSSP~YSSY
    SP          SP                 SP   SP
    Y           Y                  Y    Y
    ) <> IO.ANSI.default_color())
  end
end
