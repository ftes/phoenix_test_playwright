defmodule PhoenixTest.Playwright.DependencyFloorsTest do
  use ExUnit.Case, async: true

  @oldest_lock Path.expand("../../mix.lock.oldest", __DIR__)
  @external_resource @oldest_lock

  # CI's oldest lane runs mix.lock.oldest, so it tests a floor only when the lock holds it.
  test "mix.lock.oldest locks every runtime dependency at its floor" do
    {lock, _binding} = Code.eval_file(@oldest_lock)

    floors =
      for dep <- Mix.Project.config()[:deps],
          tuple_size(dep) == 2 or not Keyword.has_key?(elem(dep, 2), :only),
          into: %{},
          do: {elem(dep, 0), lowest_accepted(elem(dep, 1))}

    # nil: the dependency is missing from mix.lock.oldest.
    assert floors == Map.new(floors, fn {app, _floor} -> {app, lock[app] && elem(lock[app], 2)} end)
  end

  # The lowest version `requirement` names and accepts: 1.7.10 for `~> 1.7 and >= 1.7.10`,
  # 1.1.0 for `~> 1.1`.
  defp lowest_accepted(requirement) do
    ~r/\d+\.\d+(\.\d+)?(-[\w.]+)?/
    |> Regex.scan(requirement)
    |> Enum.map(fn [version | _] -> String.replace(version, ~r/^\d+\.\d+(?=-|$)/, "\\0.0") end)
    |> Enum.filter(&Version.match?(&1, requirement))
    |> Enum.min(Version, fn -> flunk("write out the floor of #{inspect(requirement)}, as `>= x.y.z`") end)
  end
end
