defmodule ElegooElixirWeb.SpeechControllerTest do
  use ElegooElixirWeb.ConnCase, async: false

  setup do
    original_config = Application.get_env(:elegoo_elixir, :speech, [])

    on_exit(fn ->
      Application.put_env(:elegoo_elixir, :speech, original_config)
    end)

    :ok
  end

  test "returns 400 when audio payload is missing", %{conn: conn} do
    response =
      conn
      |> put_req_header("accept", "application/json")
      |> post(~p"/api/speech/transcribe", %{})
      |> json_response(400)

    assert response["error"] == "missing_audio"
  end

  test "returns 502 when stt service is unavailable", %{conn: conn} do
    Application.put_env(:elegoo_elixir, :speech,
      provider: "whisper_local",
      base_url: "http://127.0.0.1:1",
      path: "/inference",
      stt_timeout_ms: 30,
      stt_language: "de"
    )

    tmp_file =
      Path.join(System.tmp_dir!(), "voice-upload-#{System.unique_integer([:positive])}.webm")

    File.write!(tmp_file, "fake audio")

    upload = %Plug.Upload{
      path: tmp_file,
      filename: "voice-command.webm",
      content_type: "audio/webm"
    }

    response =
      conn
      |> put_req_header("accept", "application/json")
      |> post(~p"/api/speech/transcribe", %{"audio" => upload})
      |> json_response(502)

    assert is_binary(response["error"])
    assert response["error"] =~ "stt_request_failed"
  end
end
