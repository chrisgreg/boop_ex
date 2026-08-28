defmodule Boop do
  @moduledoc """
  Send events to a self-hosted [Boop](https://github.com/chrisgreg/boop) server.

  Boop is a tiny notification inbox: your app POSTs a small JSON event, Boop stores it and
  pushes a notification to your phone. This library does one thing — send events reliably
  without ever taking your application down.

  ## Configuration

      config :boop_ex,
        url: System.fetch_env!("BOOP_URL"),
        api_key: System.fetch_env!("BOOP_API_KEY"),
        source: "my_app",              # optional default for every event
        timeout: 10_000,               # ms, default 10_000
        enabled: config_env() == :prod # default true

  `url` and `api_key` fall back to the `BOOP_URL` and `BOOP_API_KEY` environment variables
  when not configured.

  ## Usage

      Boop.send("Deploy complete")

      Boop.send(title: "Payment received", body: "£19.99", level: :success, source: "polar",
                data: %{customer_id: "123", amount: 19.99, currency: "GBP"})

      Boop.send(%Boop.Event{title: "Backup failed", level: :error, data: %{host: "db-01"}})

      Boop.send_async(title: "Cron finished", level: :info)

  `send/2` returns `{:ok, %{id: "evt_...", created_at: ~U[...]}}` or `{:error, %Boop.Error{}}`.
  `send_async/2` returns `:ok` immediately and never raises.
  """

  alias Boop.{Client, Config, Error, Event}

  @type result :: {:ok, %{id: String.t(), created_at: DateTime.t()}} | {:ok, :disabled} | {:error, Error.t()}

  @doc """
  Sends an event and waits for the server's answer.

  Accepts a title string, a keyword list / map of event fields, or a `%Boop.Event{}`.
  `opts` may override `:url`, `:api_key`, `:timeout`, and `:enabled` for this call.

  Never raises: bad input, network failures and server errors all come back as
  `{:error, %Boop.Error{}}`. When Boop is disabled it returns `{:ok, :disabled}`.
  """
  @spec send(String.t() | keyword() | map() | Event.t(), keyword()) :: result()
  def send(event, opts \\ []) do
    config = Config.resolve(opts)

    if config.enabled do
      with {:ok, event} <- Event.new(event, config) do
        Client.post_event(event, config)
      end
    else
      {:ok, :disabled}
    end
  rescue
    exception -> {:error, Error.exception_error(exception)}
  end

  @doc """
  Sends an event on a supervised task and returns `:ok` immediately.

  Failures are logged at `:warning` and never surface to the caller. Use this on hot paths
  and anywhere a notification must not slow down or break the request.
  """
  @spec send_async(String.t() | keyword() | map() | Event.t(), keyword()) :: :ok
  def send_async(event, opts \\ []) do
    # Validate now so callers hear about mistakes in dev, but still never raise.
    config = Config.resolve(opts)

    case (config.enabled && Event.new(event, config)) || {:ok, :disabled} do
      {:ok, :disabled} ->
        :ok

      {:ok, %Event{} = event} ->
        start_task(fn ->
          case Client.post_event(event, config) do
            {:ok, _} -> :ok
            {:error, error} -> Boop.Logger.warn_failure(event, error)
          end
        end)

      {:error, error} ->
        Boop.Logger.warn_failure(event, error)
        :ok
    end
  rescue
    exception ->
      Boop.Logger.warn_failure(event, Error.exception_error(exception))
      :ok
  end

  @doc """
  Checks whether the configured server is reachable (`GET /health`, no auth).
  """
  @spec healthy?(keyword()) :: boolean()
  def healthy?(opts \\ []) do
    Client.healthy?(Config.resolve(opts))
  rescue
    _ -> false
  end

  @doc "Whether sending is enabled by configuration."
  @spec enabled?() :: boolean()
  def enabled?, do: Config.resolve([]).enabled

  defp start_task(fun) do
    case Task.Supervisor.start_child(Boop.TaskSupervisor, fun) do
      {:ok, _pid} ->
        :ok

      {:error, _} ->
        # Supervisor not running (application not started); fall back to an unlinked task.
        Task.start(fun)
        :ok
    end
  end
end
