defmodule Boop.Config do
  @moduledoc """
  Resolved configuration for a send. Values come from per-call options, then the
  `:boop_ex` application environment, then the `BOOP_URL` / `BOOP_API_KEY` environment variables.
  """

  defstruct url: nil,
            api_key: nil,
            source: nil,
            timeout: 10_000,
            enabled: true,
            redact_keys: [],
            req_options: []

  @type t :: %__MODULE__{
          url: String.t() | nil,
          api_key: String.t() | nil,
          source: String.t() | nil,
          timeout: pos_integer(),
          enabled: boolean(),
          redact_keys: [String.t()],
          req_options: keyword()
        }

  @keys [:url, :api_key, :source, :timeout, :enabled, :redact_keys, :req_options]

  @doc "Resolves configuration, with `opts` taking precedence over the application env."
  @spec resolve(keyword()) :: t()
  def resolve(opts \\ []) do
    env = Application.get_all_env(:boop_ex)

    fields =
      for key <- @keys, into: %{} do
        {key, Keyword.get(opts, key, Keyword.get(env, key, default(key)))}
      end

    struct(__MODULE__, fields)
    |> Map.update!(:url, &normalise_url/1)
    |> Map.update!(:api_key, &blank_to_nil/1)
    |> Map.update!(:source, &blank_to_nil/1)
    |> Map.update!(:redact_keys, &List.wrap/1)
    |> Map.update!(:req_options, &List.wrap/1)
  end

  defp default(:url), do: System.get_env("BOOP_URL")
  defp default(:api_key), do: System.get_env("BOOP_API_KEY")
  defp default(:timeout), do: 10_000
  defp default(:enabled), do: true
  defp default(:redact_keys), do: []
  defp default(:req_options), do: []
  defp default(_), do: nil

  defp normalise_url(nil), do: nil
  defp normalise_url(url) when is_binary(url), do: url |> String.trim() |> String.trim_trailing("/") |> blank_to_nil()
  defp normalise_url(_), do: nil

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value) when is_binary(value), do: value
  defp blank_to_nil(value) when is_atom(value) and not is_nil(value), do: Atom.to_string(value)
  defp blank_to_nil(_), do: nil
end
