defmodule Boop.Logger do
  @moduledoc false
  require Logger

  # Logs a failed async send. Never includes the API key or the full payload.
  def warn_failure(event, %Boop.Error{} = error) do
    title =
      case event do
        %Boop.Event{title: t} -> t
        t when is_binary(t) -> t
        fields when is_list(fields) or is_map(fields) -> get(fields, :title)
        _ -> nil
      end

    Logger.warning("boop.send_failed code=#{error.code} status=#{inspect(error.status)} title=#{inspect(title)} message=#{inspect(error.message)}")
    :ok
  end

  defp get(fields, key) when is_list(fields), do: Keyword.get(fields, key)
  defp get(fields, key) when is_map(fields), do: Map.get(fields, key) || Map.get(fields, Atom.to_string(key))
end
