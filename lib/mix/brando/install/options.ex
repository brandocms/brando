defmodule Mix.Brando.Install.Options do
  @moduledoc false

  @doc "Resolves installer tenancy without prompting or changing project configuration."
  def tenancy(options, existing \\ %{mode: :none, site_key: nil}) do
    case {Keyword.fetch(options, :tenancy_mode), Keyword.fetch(options, :site_key)} do
      {:error, :error} -> validate(existing.mode, existing.site_key)
      {:error, {:ok, _}} -> {:error, "--site-key can only be used with --tenancy-mode single"}
      {{:ok, mode}, site_key} -> explicit_tenancy(mode, site_key)
    end
  end

  defp explicit_tenancy(mode, site_key) do
    key =
      case site_key do
        {:ok, key} -> key
        :error -> nil
      end

    case mode do
      "none" -> validate(:none, key)
      "single" -> validate(:single, key)
      "multi" -> validate(:multi, key)
      _ -> {:error, "Invalid --tenancy-mode #{inspect(mode)}; expected none, single, or multi"}
    end
  end

  defp validate(:single, nil), do: {:error, "--site-key is required with --tenancy-mode single"}

  defp validate(:single, key) do
    if Brando.Tenant.valid_key?(key) do
      {:ok, %{mode: :single, site_key: key}}
    else
      {:error, "--site-key must be a lowercase, URL-safe key such as my-site"}
    end
  end

  defp validate(mode, nil) when mode in [:none, :multi], do: {:ok, %{mode: mode, site_key: nil}}

  defp validate(mode, _key) when mode in [:none, :multi] do
    {:error, "--site-key can only be used with --tenancy-mode single"}
  end

  defp validate(mode, _key) do
    {:error, "Invalid existing tenancy mode #{inspect(mode)}; expected none, single, or multi"}
  end

  @doc "Resolves installer tenancy options, prompting only when explicitly requested."
  def resolve_tenancy_options!(opts, default_site_key) do
    interactive? = (opts[:interactive] == true or opts[:tenancy_prompt] == true) and opts[:tenancy_prompt] != false

    case {interactive?, opts[:tenancy_mode], opts[:site_key]} do
      {true, nil, nil} ->
        prompt_tenancy_options(default_site_key)

      {true, "single", nil} ->
        opts
        |> Keyword.put(:site_key, prompt_site_key(default_site_key))
        |> parse_tenancy_options!()

      _ ->
        parse_tenancy_options!(opts)
    end
  end

  @doc "Parses and validates non-interactive installer tenancy options."
  def parse_tenancy_options!(opts) do
    case tenancy(opts) do
      {:ok, tenancy} -> tenancy
      {:error, message} -> Mix.raise(message)
    end
  end

  defp prompt_tenancy_options(default_site_key) do
    response =
      Mix.Brando.prompt("""
      + Choose tenancy mode [1]
        1. none   — classic single-site Brando
        2. single — one site with named environments
        3. multi  — multiple sites with named environments
      """)

    case String.downcase(response) do
      mode when mode in ["", "none", "1"] ->
        %{mode: :none, site_key: nil}

      mode when mode in ["single", "2"] ->
        %{mode: :single, site_key: prompt_site_key(default_site_key)}

      mode when mode in ["multi", "3"] ->
        %{mode: :multi, site_key: nil}

      _invalid ->
        Mix.shell().error("Please choose none, single, or multi.")
        prompt_tenancy_options(default_site_key)
    end
  end

  defp prompt_site_key(default_site_key) do
    site_key =
      case Mix.Brando.prompt("+ Site key [#{default_site_key}]") do
        "" -> default_site_key
        site_key -> site_key
      end

    if Brando.Tenant.valid_key?(site_key) do
      site_key
    else
      Mix.shell().error("Use lowercase letters, numbers, and single hyphens only.")
      prompt_site_key(default_site_key)
    end
  end
end
