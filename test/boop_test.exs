defmodule BoopTest do
  use ExUnit.Case

  import Boop.TestStub
  import ExUnit.CaptureLog

  alias Boop.Error

  setup do
    Req.Test.set_req_test_to_shared()
    on_exit(fn -> Req.Test.set_req_test_to_private() end)
    :ok
  end

  describe "send/2" do
    test "posts the event with bearer auth and returns the id" do
      test = self()

      Req.Test.stub(Boop, fn conn ->
        {body, conn} = json_body(conn)
        send(test, {:request, conn, body})
        json(conn, 201, %{"id" => "evt_1", "created_at" => "2026-08-28T14:10:46.716098000Z"})
      end)

      assert {:ok, %{id: "evt_1", created_at: %DateTime{year: 2026}}} =
               Boop.send([title: "Deploy complete", level: :success, data: %{password: "x", n: 1}], opts(source: "uini"))

      assert_receive {:request, conn, body}
      assert conn.method == "POST" and conn.request_path == "/api/v1/events"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer boop_proj_testkey"]
      assert Plug.Conn.get_req_header(conn, "content-type") == ["application/json"]
      assert [ua] = Plug.Conn.get_req_header(conn, "user-agent")
      assert ua =~ "boop_ex/"
      assert body["title"] == "Deploy complete"
      assert body["level"] == "success"
      assert body["source"] == "uini"
      assert body["data"] == %{"password" => "[REDACTED]", "n" => 1}
      assert is_binary(body["occurred_at"])
    end

    test "a bare title works" do
      Req.Test.stub(Boop, fn conn -> json(conn, 201, %{"id" => "evt_2", "created_at" => "2026-08-28T14:10:46Z"}) end)
      assert {:ok, %{id: "evt_2"}} = Boop.send("Backup complete", opts())
    end

    test "401 is surfaced and not retried" do
      counter = :counters.new(1, [])

      Req.Test.stub(Boop, fn conn ->
        :counters.add(counter, 1, 1)
        json(conn, 401, %{"error" => "unauthorized", "message" => "invalid project API key"})
      end)

      assert {:error, %Error{code: :unauthorized, status: 401, message: "invalid project API key"}} = Boop.send("x", opts())
      assert :counters.get(counter, 1) == 1
    end

    test "422 is surfaced with the server message" do
      Req.Test.stub(Boop, fn conn -> json(conn, 422, %{"error" => "invalid", "message" => "title is required"}) end)
      assert {:error, %Error{code: :rejected, status: 422, message: "title is required", details: "invalid"}} = Boop.send(%{title: "x"}, opts())
    end

    test "5xx is retried twice then returned" do
      counter = :counters.new(1, [])

      Req.Test.stub(Boop, fn conn ->
        :counters.add(counter, 1, 1)
        json(conn, 503, %{"error" => "internal", "message" => "something went wrong"})
      end)

      assert {:error, %Error{code: :server_error, status: 503}} = Boop.send("x", opts())
      assert :counters.get(counter, 1) == 3
    end

    test "a 5xx followed by success succeeds" do
      counter = :counters.new(1, [])

      Req.Test.stub(Boop, fn conn ->
        if :counters.get(counter, 1) == 0 do
          :counters.add(counter, 1, 1)
          json(conn, 500, %{})
        else
          json(conn, 201, %{"id" => "evt_3", "created_at" => "2026-08-28T14:10:46Z"})
        end
      end)

      assert {:ok, %{id: "evt_3"}} = Boop.send("x", opts())
    end

    test "network errors become :unreachable after retries" do
      counter = :counters.new(1, [])

      Req.Test.stub(Boop, fn conn ->
        :counters.add(counter, 1, 1)
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, %Error{code: :unreachable}} = Boop.send("x", opts())
      assert :counters.get(counter, 1) == 3
    end

    test "invalid events never hit the network" do
      Req.Test.stub(Boop, fn _ -> flunk("should not be called") end)
      assert {:error, %Error{code: :invalid}} = Boop.send(%{title: "x", level: :nope}, opts())
      assert {:error, %Error{code: :invalid}} = Boop.send(nil, opts())
    end

    test "missing configuration is a clear error" do
      assert {:error, %Error{code: :not_configured, message: msg}} = Boop.send("x", url: nil, api_key: nil)
      assert msg =~ "BOOP_URL"
    end

    test "disabled returns {:ok, :disabled} without a request" do
      Req.Test.stub(Boop, fn _ -> flunk("should not be called") end)
      assert {:ok, :disabled} = Boop.send("x", opts(enabled: false))
    end
  end

  describe "send_async/2" do
    test "returns :ok immediately and delivers in the background" do
      test = self()

      Req.Test.stub(Boop, fn conn ->
        {body, conn} = json_body(conn)
        send(test, {:delivered, body["title"]})
        json(conn, 201, %{"id" => "evt_4", "created_at" => "2026-08-28T14:10:46Z"})
      end)

      assert :ok = Boop.send_async("Async hello", opts())
      assert_receive {:delivered, "Async hello"}, 2_000
    end

    test "failures are logged, never raised" do
      Req.Test.stub(Boop, fn conn -> json(conn, 401, %{"error" => "unauthorized", "message" => "nope"}) end)

      log =
        capture_log(fn ->
          assert :ok = Boop.send_async("x", opts())
          Process.sleep(200)
        end)

      assert log =~ "boop.send_failed"
      assert log =~ "unauthorized"
      refute log =~ "boop_proj_testkey"
    end

    test "invalid input is logged and returns :ok" do
      log = capture_log(fn -> assert :ok = Boop.send_async(%{level: :info}, opts()) end)
      assert log =~ "title is required"
    end
  end

  describe "healthy?/1" do
    test "true only for a healthy server" do
      Req.Test.stub(Boop, fn conn -> json(conn, 200, %{"status" => "ok"}) end)
      assert Boop.healthy?(opts())
      Req.Test.stub(Boop, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)
      refute Boop.healthy?(opts())
      refute Boop.healthy?(url: nil)
    end
  end
end
