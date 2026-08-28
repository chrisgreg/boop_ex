defmodule Boop.EventTest do
  use ExUnit.Case, async: true

  alias Boop.{Error, Event}

  test "a bare title becomes an info event with a timestamp" do
    assert {:ok, %Event{title: "Deploy complete", level: :info, occurred_at: %DateTime{}, data: %{}}} =
             Event.new("Deploy complete")
  end

  test "keyword lists, maps, string keys and structs are accepted" do
    assert {:ok, %Event{title: "a", level: :success}} = Event.new(title: "a", level: :success)
    assert {:ok, %Event{title: "b", level: :warning}} = Event.new(%{title: "b", level: "warning"})
    assert {:ok, %Event{title: "c"}} = Event.new(%{"title" => "c", "level" => "ERROR"})
    assert {:ok, %Event{title: "d", level: :critical}} = Event.new(%Event{title: "d", level: :critical})
  end

  test "title is required" do
    assert {:error, %Error{code: :invalid, message: "title is required"}} = Event.new(title: "   ")
    assert {:error, %Error{code: :invalid}} = Event.new(level: :info)
    assert {:error, %Error{code: :invalid}} = Event.new(42)
  end

  test "unknown levels are rejected" do
    assert {:error, %Error{code: :invalid, message: "level must be one of" <> _}} = Event.new(title: "x", level: :fatal)
  end

  test "long strings are truncated, not rejected" do
    {:ok, e} = Event.new(title: String.duplicate("t", 300), body: String.duplicate("b", 5000), source: String.duplicate("s", 300))
    assert String.length(e.title) == 200 and String.ends_with?(e.title, "…")
    assert String.length(e.body) == 4000
    assert String.length(e.source) == 200
  end

  test "occurred_at accepts DateTime, NaiveDateTime and ISO 8601" do
    dt = ~U[2026-08-28 12:51:44Z]
    assert {:ok, %Event{occurred_at: ^dt}} = Event.new(title: "x", occurred_at: dt)
    assert {:ok, %Event{occurred_at: ^dt}} = Event.new(title: "x", occurred_at: ~N[2026-08-28 12:51:44])
    assert {:ok, %Event{occurred_at: ^dt}} = Event.new(title: "x", occurred_at: "2026-08-28T12:51:44Z")
    assert {:error, %Error{code: :invalid}} = Event.new(title: "x", occurred_at: "yesterday")
  end

  test "data must be a map (keyword lists are converted)" do
    assert {:ok, %Event{data: %{a: 1}}} = Event.new(title: "x", data: [a: 1])
    assert {:error, %Error{code: :invalid, message: "data must be a map"}} = Event.new(title: "x", data: [1, 2])
  end

  test "the configured source is the default" do
    assert {:ok, %Event{source: "uini"}} = Event.new("x", source: "uini")
    assert {:ok, %Event{source: "cron"}} = Event.new([title: "x", source: "cron"], source: "uini")
  end

  test "to_payload drops nils, stringifies the level and redacts data" do
    {:ok, e} = Event.new(title: "x", level: :error, occurred_at: ~U[2026-08-28 12:51:44Z], data: %{password: "hunter2", nested: %{"api-key" => "k", ok: 1}})
    payload = Event.to_payload(e)

    assert payload == %{
             "title" => "x",
             "level" => "error",
             "occurred_at" => "2026-08-28T12:51:44Z",
             "data" => %{password: "[REDACTED]", nested: %{"api-key" => "[REDACTED]", ok: 1}}
           }
  end

  test "oversized data is dropped with a note rather than failing" do
    {:ok, e} = Event.new(title: "x", body: "b", data: %{blob: String.duplicate("z", 300_000)})
    payload = Event.to_payload(e)
    assert payload["data"] == %{}
    assert payload["body"] =~ "data omitted"
  end

  test "exception/3 builds the rich error shape" do
    data =
      try do
        raise ArgumentError, "boom"
      rescue
        e -> Event.exception(e, __STACKTRACE__, tags: %{env: "test"})
      end

    assert data["exception"] == %{"type" => "ArgumentError", "message" => "boom"}
    assert [%{"function" => _, "file" => _, "line" => _, "in_app" => true} | _] = data["stacktrace"]
    assert data["tags"] == %{env: "test"}
  end
end
