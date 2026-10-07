defmodule Brando.DoctorFixtures do
  @moduledoc false
  # Checks with fixed results, for the doctor's runner, report and mix task tests

  defmodule Healthy do
    @moduledoc false
    use Brando.Doctor.Check

    @impl true
    def id, do: "healthy"
    @impl true
    def label, do: "Healthy"
    @impl true
    def run(_context), do: ok("all good", items: ["one thing"])
  end

  defmodule Warns do
    @moduledoc false
    use Brando.Doctor.Check

    @impl true
    def id, do: "warns"
    @impl true
    def label, do: "Warns"
    @impl true
    def run(_context), do: warning("2 things", fix: "do the thing", items: ["a", "b"])
  end

  defmodule Fails do
    @moduledoc false
    use Brando.Doctor.Check

    @impl true
    def id, do: "fails"
    @impl true
    def label, do: "Fails"
    @impl true
    def run(_context), do: error("broken", fix: "mend it")
  end

  defmodule Raises do
    @moduledoc false
    use Brando.Doctor.Check

    @impl true
    def id, do: "raises"
    @impl true
    def label, do: "Raises"
    @impl true
    def run(_context), do: raise("boom")
  end

  defmodule NeedsSource do
    @moduledoc false
    use Brando.Doctor.Check

    @impl true
    def id, do: "needs_source"
    @impl true
    def label, do: "Needs source"
    @impl true
    def needs_source?, do: true
    @impl true
    def run(_context), do: ok("read the files")
  end
end
