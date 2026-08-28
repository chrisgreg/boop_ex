defmodule Boop.Event do
  @moduledoc """
  An event to send to Boop. Only `title` is required.

  | Field | Notes |
  | --- | --- |
  | `title` | required, truncated to 200 characters |
  | `body` | truncated to 4000 characters |
  | `level` | `:info` (default), `:success`, `:warning`, `:error`, `:critical` |
  | `source` | what produced it, e.g. `"cron"`; defaults to the configured `source` |
  | `type` | a category within the source, e.g. `"deploy"` |
  | `external_id` | your own id for the event |
  | `fingerprint` | a stable grouping key |
  | `occurred_at` | `DateTime`, `NaiveDateTime` (assumed UTC) or ISO 8601 string; defaults to now |
  | `data` | a map of anything JSON-serialisable; sensitive keys are redacted before sending |

  The keys `exception`, `stacktrace`, `tags`, `context` and `breadcrumbs` inside `data`
  get a rich rendering in Boop. See `Boop.Event.exception/3` for a helper.
  """

  alias Boop.{Config, Error, Redactor}

  @levels [:info, :success, :warning, :error, :critical]
  @max_title 200
  @max_body 4000
  @max_short 200
  @max_data_bytes 256 * 1024

  defstruct title: nil,
            body: nil,
            level: :info,
            source: nil,
            type: nil,
            external_id: nil,
            fingerprint: nil,
            occurred_at: nil,
            data: %{}

  @type level :: :info | :success | :warning | :error | :critical
  @type t :: %__MODULE__{
          title: String.t() | nil,
          body: String.t() | nil,
          level: level(),
          source: String.t() | nil,
          type: String.t() | nil,
          external_id: String.t() | nil,
          fingerprint: String.t() | nil,
          occurred_at: DateTime.t() | nil,
          data: map()
        }

  @doc "The valid levels, in ascending severity."
  @spec levels() :: [level()]
  def levels, do: @levels

  @doc """
  Builds and validates an event from a title, keyword list, map, or `%Boop.Event{}`.

  Strings that exceed their limits are truncated rather than rejected. Returns
  `{:error, %Boop.Error{code: :invalid}}` when the title is missing or the level is unknown.
  """
  @spec new(String.t() | keyword() | map() | t(), Config.t() | keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(input, config \\ [])

  def new(input, config) when is_list(config), do: new(input, Config.resolve(config))

  def new(title, %Config{} = config) when is_binary(title), do: new(%{title: title}, config)

  def new(fields, %Config{} = config) when is_list(fields) do
    if Keyword.keyword?(fields),
      do: new(Map.new(fields), config),
      else: {:error, Error.new(:invalid, "event must be a title, keyword list, map or %Boop.Event{}")}
  end

  def new(%__MODULE__{} = event, %Config{} = config), do: new(Map.from_struct(event), config)

  def new(%{} = fields, %Config{} = config) do
    fields = Map.new(fields, fn {k, v} -> {to_atom_key(k), v} end)

    with {:ok, title} <- title(fields[:title]),
         {:ok, level} <- level(Map.get(fields, :level, :info)),
         {:ok, occurred_at} <- occurred_at(fields[:occurred_at]),
         {:ok, data} <- data(fields[:data]) do
      {:ok,
       %__MODULE__{
         title: title,
         body: clip(fields[:body], @max_body),
         level: level,
         source: clip(fields[:source] || config.source, @max_short),
         type: clip(fields[:type], @max_short),
         external_id: clip(fields[:external_id], @max_short),
         fingerprint: clip(fields[:fingerprint], @max_short),
         occurred_at: occurred_at,
         data: data
       }}
    end
  end

  def new(_, _), do: {:error, Error.new(:invalid, "event must be a title, keyword list, map or %Boop.Event{}")}

  @doc """
  Converts an event to the JSON-ready map the server expects, redacting sensitive keys in
  `data` and dropping `data` (with a note in `body`) if it is still over 256 KB.
  """
  @spec to_payload(t(), Config.t() | keyword()) :: map()
  def to_payload(event, config \\ [])
  def to_payload(event, config) when is_list(config), do: to_payload(event, Config.resolve(config))

  def to_payload(%__MODULE__{} = event, %Config{} = config) do
    data = Redactor.redact(event.data, config.redact_keys)

    {body, data} =
      case json_encode(data) do
        {:ok, encoded} when byte_size(encoded) <= @max_data_bytes -> {event.body, data}
        _ -> {append_note(event.body, "[data omitted: over 256 KB or not JSON-serialisable]"), %{}}
      end

    %{
      "title" => event.title,
      "body" => body,
      "level" => Atom.to_string(event.level),
      "source" => event.source,
      "type" => event.type,
      "external_id" => event.external_id,
      "fingerprint" => event.fingerprint,
      "occurred_at" => event.occurred_at && DateTime.to_iso8601(event.occurred_at),
      "data" => data
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Builds `data` for an error event from an exception and stacktrace, in the shape Boop renders richly.

      rescue e -> Boop.send(title: inspect(e.__struct__), level: :error,
                            data: Boop.Event.exception(e, __STACKTRACE__, tags: %{env: "prod"}))
  """
  @spec exception(Exception.t(), Exception.stacktrace(), keyword()) :: map()
  def exception(exception, stacktrace, extra \\ []) do
    base = %{
      "exception" => %{
        "type" => inspect(exception.__struct__),
        "message" => Exception.message(exception)
      },
      "stacktrace" => Enum.map(stacktrace, &frame/1)
    }

    Enum.reduce(extra, base, fn {k, v}, acc -> Map.put(acc, to_string(k), v) end)
  end

  defp frame({mod, fun, arity_or_args, location}) do
    arity = if is_list(arity_or_args), do: length(arity_or_args), else: arity_or_args
    file = location |> Keyword.get(:file) |> to_string_or_nil()

    %{
      "function" => Exception.format_mfa(mod, fun, arity),
      "file" => file,
      "line" => Keyword.get(location, :line),
      "in_app" => in_app?(mod)
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp frame(other), do: %{"function" => inspect(other)}

  defp in_app?(mod) do
    case :code.which(mod) do
      path when is_list(path) -> not String.contains?(to_string(path), ["/deps/", "/lib/elixir/", "/lib/erlang/"])
      _ -> false
    end
  end

  # ---- validation ----

  defp title(nil), do: {:error, Error.new(:invalid, "title is required")}
  defp title(t) when is_binary(t) do
    case String.trim(t) do
      "" -> {:error, Error.new(:invalid, "title is required")}
      t -> {:ok, clip(t, @max_title)}
    end
  end
  defp title(t), do: t |> to_string() |> title()

  defp level(l) when l in @levels, do: {:ok, l}
  defp level(l) when is_binary(l) do
    case Enum.find(@levels, &(Atom.to_string(&1) == String.downcase(l))) do
      nil -> {:error, Error.new(:invalid, "level must be one of #{Enum.map_join(@levels, ", ", &inspect/1)}")}
      level -> {:ok, level}
    end
  end
  defp level(_), do: {:error, Error.new(:invalid, "level must be one of #{Enum.map_join(@levels, ", ", &inspect/1)}")}

  defp occurred_at(nil), do: {:ok, DateTime.utc_now()}
  defp occurred_at(%DateTime{} = dt), do: {:ok, dt}
  defp occurred_at(%NaiveDateTime{} = ndt), do: {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
  defp occurred_at(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> {:ok, dt}
      _ -> {:error, Error.new(:invalid, "occurred_at must be a DateTime or ISO 8601 string")}
    end
  end
  defp occurred_at(_), do: {:error, Error.new(:invalid, "occurred_at must be a DateTime or ISO 8601 string")}

  defp data(nil), do: {:ok, %{}}
  defp data(%{} = m) when not is_struct(m), do: {:ok, m}
  defp data(kw) when is_list(kw) do
    if Keyword.keyword?(kw), do: {:ok, Map.new(kw)}, else: {:error, Error.new(:invalid, "data must be a map")}
  end
  defp data(_), do: {:error, Error.new(:invalid, "data must be a map")}

  defp clip(nil, _), do: nil
  defp clip(s, max) when is_binary(s), do: if(String.length(s) > max, do: String.slice(s, 0, max - 1) <> "…", else: s)
  defp clip(s, max) when is_atom(s), do: clip(Atom.to_string(s), max)
  defp clip(s, max), do: clip(to_string(s), max)

  defp append_note(nil, note), do: note
  defp append_note(body, note), do: clip(body <> "\n" <> note, @max_body)

  defp to_atom_key(k) when is_atom(k), do: k
  defp to_atom_key(k) when is_binary(k) do
    String.to_existing_atom(k)
  rescue
    ArgumentError -> :"__unknown_#{k}"
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(v), do: to_string(v)

  # Jason ships with Req; use it via Req's JSON so we do not add a direct dependency.
  defp json_encode(term) do
    {:ok, Jason.encode!(term)}
  rescue
    _ -> :error
  end
end
