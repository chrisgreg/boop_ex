defmodule Boop.Client do
  @moduledoc """
  The HTTP layer, built on `Req`. You normally call `Boop.send/2` instead.

  Retries network errors and 5xx responses twice with a short jittered backoff; never
  retries 4xx. Every request has a timeout. Passes `config.req_options` through to
  `Req.new/1`, which is how tests plug in a stub (`plug: {Req.Test, Boop}`).
  """

  alias Boop.{Config, Error, Event}
  require Logger

  @user_agent "boop_ex/#{Mix.Project.config()[:version]}"

  @doc "POSTs an event. Returns `{:ok, %{id, created_at}}` or `{:error, %Boop.Error{}}`."
  @spec post_event(Event.t(), Config.t()) :: {:ok, %{id: String.t(), created_at: DateTime.t()}} | {:error, Error.t()}
  def post_event(%Event{} = event, %Config{} = config) do
    with :ok <- check_configured(config) do
      payload = Event.to_payload(event, config)

      request =
        config
        |> new(auth: true)
        |> Req.merge(url: "/api/v1/events", json: payload)

      case Req.post(request) do
        {:ok, %Req.Response{status: 201, body: %{"id" => id} = body}} ->
          {:ok, %{id: id, created_at: parse_time(body["created_at"])}}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, Error.from_response(status, body)}

        {:error, exception} ->
          {:error, Error.new(:unreachable, Exception.message(exception), details: exception)}
      end
    end
  end

  @doc "Whether `GET /health` answers `{\"status\": \"ok\"}`."
  @spec healthy?(Config.t()) :: boolean()
  def healthy?(%Config{url: nil}), do: false

  def healthy?(%Config{} = config) do
    case config |> new(auth: false) |> Req.merge(url: "/health", retry: false) |> Req.get() do
      {:ok, %Req.Response{status: 200, body: %{"status" => "ok"}}} -> true
      _ -> false
    end
  end

  defp new(%Config{} = config, auth: auth) do
    headers = [{"user-agent", @user_agent}] ++ if auth, do: [{"authorization", "Bearer #{config.api_key}"}], else: []

    [
      base_url: config.url,
      headers: headers,
      receive_timeout: config.timeout,
      connect_options: [timeout: min(config.timeout, 5_000)],
      retry: &retry?/2,
      max_retries: 2,
      retry_delay: fn attempt -> 200 * Integer.pow(2, attempt) + :rand.uniform(100) end,
      retry_log_level: false
    ]
    |> Keyword.merge(config.req_options)
    |> Req.new()
  end

  defp retry?(_request, %Req.Response{status: status}), do: status >= 500
  defp retry?(_request, %Req.TransportError{}), do: true
  defp retry?(_request, _), do: false

  defp check_configured(%Config{url: nil}), do: {:error, Error.new(:not_configured, "Boop url is not configured (set config :boop_ex, url: or BOOP_URL)")}
  defp check_configured(%Config{api_key: nil}), do: {:error, Error.new(:not_configured, "Boop api_key is not configured (set config :boop_ex, api_key: or BOOP_API_KEY)")}
  defp check_configured(_), do: :ok

  defp parse_time(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_time(_), do: nil
end
