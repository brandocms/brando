defmodule Brando.System do
  @moduledoc """
  Simple checks on startup to verify system integrity
  """
  require Logger

  def initialize do
    run_checks()
    set_cache()
  end

  def run_checks do
    Logger.info("==> Brando >> Running system checks...")
    {:ok, {:executable, :exists}} = check_image_processing_executable()
    {:ok, {:identity, :exists}} = check_identity_exists()
    Logger.info("==> Brando >> System checks complete!")
  end

  defp check_image_processing_executable do
    image_processing_module =
      Brando.config(Brando.Images)[:processor_module] || Brando.Images.Processor.Mogrify

    apply(image_processing_module, :confirm_executable_exists, [])
  end

  defp check_identity_exists do
    with [] <- Brando.repo().all(Brando.Sites.Identity),
         {:ok, _} <- Brando.Sites.create_default_identity() do
      {:ok, {:identity, :exists}}
    else
      {:error, _} ->
        {:error, {:identity, :failed}}

      _ ->
        {:ok, {:identity, :exists}}
    end
  end

  defp set_cache do
    Brando.Sites.cache_identity()
  end
end
