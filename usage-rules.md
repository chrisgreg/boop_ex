# boop_ex usage rules

boop_ex sends events to a self-hosted Boop server so the developer gets a push notification on their phone. It is a notification transport, not a logger, error tracker, or queue. The public API is `Boop.send/2`, `Boop.send_async/2`, `Boop.healthy?/1` and the `Boop.Event` struct. Do not call `Boop.Client` directly from application code.

## Configuration

- Configure in `config/runtime.exs` (not `config.exs`) so the values come from the environment at boot:

  ```elixir
  config :boop_ex,
    url: System.fetch_env!("BOOP_URL"),
    api_key: System.fetch_env!("BOOP_API_KEY"),
    source: "my_app",
    enabled: config_env() == :prod
  ```

- `url` and `api_key` fall back to the `BOOP_URL` / `BOOP_API_KEY` env vars automatically; prefer explicit config in `runtime.exs` anyway.
- Always set `source` to the app's name. Every event is tagged with it and the Boop UI filters on it.
- In `config/test.exs` set `enabled: false` (every send returns `{:ok, :disabled}`), or route to a `Req.Test` stub with `req_options: [plug: {Req.Test, Boop}]` when the test needs to assert on the request.
- Other options: `timeout` (ms, default 10_000), `redact_keys` (list of extra keys to redact inside `data`), `req_options` (keyword merged into `Req.new/1`).
- The API key is a secret (`boop_proj_...`). Never commit it, never log it, never put it in `config.exs`.

## Sending events

- Prefer `Boop.send_async/2` in request paths, LiveViews, Oban jobs, GenServers and anywhere latency or failure must not affect the caller. It returns `:ok` immediately and logs failures at `:warning`.
- Use `Boop.send/2` only when the caller needs the result (release tasks, scripts, tests). It returns `{:ok, %{id: "evt_...", created_at: %DateTime{}}}`, `{:ok, :disabled}`, or `{:error, %Boop.Error{}}`. It never raises; do not wrap it in `try/rescue`.
- Input can be a title string, a keyword list, a map (atom or string keys), or a `%Boop.Event{}`. Only `title` is required.

  ```elixir
  Boop.send_async("Backup complete")
  Boop.send_async(title: "Payment received", body: "£19.99", level: :success, source: "polar", data: %{customer_id: id})
  ```

- Fields: `title` (required, ≤200 chars), `body` (≤4000), `level`, `source`, `type`, `external_id`, `fingerprint`, `occurred_at` (`DateTime`, `NaiveDateTime` or ISO 8601), `data` (map). Over-long strings are truncated, not rejected.
- Levels are atoms: `:info` (default), `:success`, `:warning`, `:error`, `:critical`. `:critical` produces a prominent push; reserve it for outages. Unknown levels return `{:error, %Boop.Error{code: :invalid}}`.
- Keep `title` short and specific ("Deploy failed: uini", not "Error"). Put detail in `body`; put structured facts in `data`, not interpolated into `body`.
- `data` must be a map (keyword lists are converted). Values must be JSON-serialisable; structs are converted to maps. Keep it under 256 KB or it is dropped with a note in `body`.
- Use `fingerprint` for "the same problem again" (e.g. `"#{module}-#{reason}"`), `external_id` for your own record id, `type` for a category within the source (`"deploy"`, `"job"`, `"error"`).

## Error events

- For exceptions, build `data` with `Boop.Event.exception(exception, __STACKTRACE__, tags: %{...}, context: %{...})`. It produces the `exception` / `stacktrace` shape the Boop UI renders richly, with `in_app` frames marked.
- The `data` keys `exception`, `stacktrace`, `tags`, `context` and `breadcrumbs` get special rendering; anything else is shown as expandable JSON. Do not invent other shapes for these keys.
- Do not install a global error handler for the user unprompted. If asked to report all unhandled errors, add a `:logger` handler or `Plug.ErrorHandler` that calls `Boop.send_async/2`, and reraise.

## Secrets and redaction

- The client redacts `password`, `password_confirmation`, `secret`, `token`, `access_token`, `refresh_token`, `api_key`, `authorization`, `cookie`, `set-cookie`, `private_key` anywhere inside `data` before sending (case-insensitive; `-` and `_` are equivalent). The server redacts again.
- Redaction only covers `data`. Never put secrets in `title` or `body`.
- Add app-specific keys with `config :boop_ex, redact_keys: ["ssn", "card_number"]`.

## Behaviour to rely on

- Retries: network errors and 5xx are retried twice with jittered backoff; 4xx is never retried. Do not add your own retry loop around `Boop.send/2`.
- Timeouts: 5 s connect, `timeout` (10 s) receive. Do not call `Boop.send/2` inside a database transaction or a LiveView `mount/3`; use `send_async/2`.
- `Boop.Error.code` values: `:invalid`, `:not_configured`, `:unauthorized`, `:rejected`, `:server_error`, `:unreachable`, `:unexpected`. Pattern-match on `code`, not on `message`.
- `Boop.send_async/2` runs on `Boop.TaskSupervisor`, started by the `:boop_ex` application. Do not add it to the app's supervision tree.

## Testing application code that uses Boop

```elixir
# config/test.exs
config :boop_ex, url: "https://boop.test", api_key: "boop_proj_test", req_options: [plug: {Req.Test, Boop}]

# in a test
Req.Test.stub(Boop, fn conn ->
  Req.Test.json(conn, %{"id" => "evt_1", "created_at" => "2026-01-01T00:00:00Z"})
end)
```

Assert on the request inside the stub (`Plug.Conn.read_body/1`, `Jason.decode!/1`). For async sends, have the stub `send/2` a message to the test process and `assert_receive` it.
