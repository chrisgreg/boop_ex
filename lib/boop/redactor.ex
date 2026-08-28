defmodule Boop.Redactor do
  @moduledoc """
  Replaces the values of sensitive keys anywhere inside event data with `"[REDACTED]"`.

  The server does the same, but the wire is the first place a secret can leak, so it happens
  here too. Matching is case-insensitive and treats `-` and `_` alike. Add keys with
  `config :boop_ex, redact_keys: ["ssn"]`.
  """

  @placeholder "[REDACTED]"
  @default_keys ~w(password password_confirmation secret token access_token refresh_token api_key authorization cookie set-cookie private_key)

  @doc "The keys redacted by default."
  @spec default_keys() :: [String.t()]
  def default_keys, do: @default_keys

  @doc "Redacts `data` recursively. `extra` adds to the default key list."
  @spec redact(term(), [String.t() | atom()]) :: term()
  def redact(data, extra \\ []) do
    keys = MapSet.new(@default_keys ++ Enum.map(extra, &to_string/1), &normalise/1)
    walk(data, keys)
  end

  defp walk(%{} = map, keys) when not is_struct(map) do
    Map.new(map, fn {k, v} ->
      if MapSet.member?(keys, normalise(to_string(k))), do: {k, @placeholder}, else: {k, walk(v, keys)}
    end)
  end

  defp walk(list, keys) when is_list(list) do
    if Keyword.keyword?(list) and list != [],
      do: list |> Map.new() |> walk(keys),
      else: Enum.map(list, &walk(&1, keys))
  end

  defp walk(%DateTime{} = v, _), do: v
  defp walk(%Date{} = v, _), do: v
  defp walk(%NaiveDateTime{} = v, _), do: v
  defp walk(%Time{} = v, _), do: v
  defp walk(%_{} = struct, keys), do: struct |> Map.from_struct() |> walk(keys)
  defp walk(tuple, keys) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> walk(keys)
  defp walk(other, _), do: other

  defp normalise(key), do: key |> String.downcase() |> String.replace("-", "_") |> String.trim()
end
