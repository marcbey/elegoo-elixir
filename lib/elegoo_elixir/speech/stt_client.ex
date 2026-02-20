defmodule ElegooElixir.Speech.STTClient do
  @moduledoc """
  Client for a local whisper.cpp HTTP service.
  """

  @default_timeout_ms 10_000
  @default_base_url "http://127.0.0.1:8088"
  @default_path "/inference"
  @default_language "de"

  @type transcribe_result :: %{
          text: String.t(),
          raw: map() | String.t() | nil
        }

  @spec transcribe_upload(Plug.Upload.t(), keyword()) ::
          {:ok, transcribe_result()} | {:error, term()}
  def transcribe_upload(%Plug.Upload{} = upload, opts \\ []) do
    with {:ok, audio_binary} <- File.read(upload.path) do
      do_transcribe_binary(audio_binary,
        filename: upload.filename || "voice-command.webm",
        content_type: upload.content_type || "audio/webm",
        opts: opts
      )
    end
  end

  @spec transcribe_binary(binary(), keyword()) :: {:ok, transcribe_result()} | {:error, term()}
  def transcribe_binary(audio_binary, opts \\ []) when is_binary(audio_binary) do
    filename = Keyword.get(opts, :filename, "voice-command.webm")
    content_type = Keyword.get(opts, :content_type, "audio/webm")
    request_opts = Keyword.drop(opts, [:filename, :content_type])

    do_transcribe_binary(audio_binary,
      filename: filename,
      content_type: content_type,
      opts: request_opts
    )
  end

  defp do_transcribe_binary(audio_binary, request_opts) when is_binary(audio_binary) do
    opts = Keyword.get(request_opts, :opts, [])
    filename = Keyword.fetch!(request_opts, :filename)
    content_type = Keyword.fetch!(request_opts, :content_type)

    timeout_ms =
      Keyword.get(opts, :timeout_ms, speech_config(:stt_timeout_ms, @default_timeout_ms))

    language = Keyword.get(opts, :language, speech_config(:stt_language, @default_language))
    base_url = Keyword.get(opts, :base_url, speech_config(:base_url, @default_base_url))
    path = Keyword.get(opts, :path, speech_config(:path, @default_path))
    endpoint = normalize_endpoint(base_url, path)

    with :ok <- ensure_httpc_started(),
         {:ok, {headers, body, boundary}} <-
           build_multipart(audio_binary, filename, content_type, language),
         {:ok, response} <- request(endpoint, headers, body, boundary, timeout_ms),
         {:ok, parsed} <- parse_response(response) do
      {:ok, parsed}
    end
  end

  defp ensure_httpc_started do
    case Application.ensure_all_started(:inets) do
      {:ok, _started} -> :ok
      {:error, reason} -> {:error, {:inets_unavailable, reason}}
    end
  end

  defp request(url, headers, body, boundary, timeout_ms) do
    content_type = ~c"multipart/form-data; boundary=" ++ boundary

    request = {String.to_charlist(url), headers, content_type, body}

    options = [timeout: timeout_ms, connect_timeout: min(timeout_ms, 3_000)]

    case :httpc.request(:post, request, options, body_format: :binary) do
      {:ok, {{_http_version, status_code, _reason_phrase}, response_headers, response_body}}
      when status_code in 200..299 ->
        {:ok, %{headers: response_headers, body: response_body}}

      {:ok, {{_http_version, status_code, _reason_phrase}, _response_headers, response_body}} ->
        {:error, {:http_error, status_code, summarize_error_body(response_body)}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp parse_response(%{headers: headers, body: body}) when is_binary(body) do
    content_type = header_value(headers, "content-type")

    cond do
      String.contains?(content_type, "application/json") ->
        parse_json_payload(body)

      true ->
        text = body |> String.trim()

        if text == "" do
          {:error, :empty_transcript}
        else
          {:ok, %{text: text, raw: nil}}
        end
    end
  end

  defp parse_json_payload(body) do
    with {:ok, payload} <- Jason.decode(body),
         {:ok, text} <- extract_text(payload) do
      {:ok, %{text: text, raw: payload}}
    else
      {:error, %Jason.DecodeError{} = decode_error} ->
        {:error, {:invalid_json, decode_error}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_text(%{"text" => text}) when is_binary(text) do
    normalized = String.trim(text)

    if normalized == "" do
      {:error, :empty_transcript}
    else
      {:ok, normalized}
    end
  end

  defp extract_text(%{"result" => result}) when is_binary(result),
    do: extract_text(%{"text" => result})

  defp extract_text(%{"transcription" => text}) when is_binary(text),
    do: extract_text(%{"text" => text})

  defp extract_text(%{"error" => reason}), do: {:error, {:stt_error, reason}}
  defp extract_text(_payload), do: {:error, :missing_transcript}

  defp build_multipart(audio_binary, filename, content_type, language)
       when is_binary(audio_binary) and is_binary(filename) and is_binary(content_type) do
    boundary = "----elegoo-whisper-" <> Integer.to_string(System.unique_integer([:positive]))
    boundary_line = "--#{boundary}\r\n"

    body =
      IO.iodata_to_binary([
        boundary_line,
        "Content-Disposition: form-data; name=\"file\"; filename=\"",
        filename,
        "\"\r\n",
        "Content-Type: ",
        content_type,
        "\r\n\r\n",
        audio_binary,
        "\r\n",
        boundary_line,
        "Content-Disposition: form-data; name=\"language\"\r\n\r\n",
        language,
        "\r\n",
        boundary_line,
        "Content-Disposition: form-data; name=\"response-format\"\r\n\r\n",
        "json",
        "\r\n",
        "--",
        boundary,
        "--\r\n"
      ])

    headers = [{~c"accept", ~c"application/json"}]
    {:ok, {headers, body, String.to_charlist(boundary)}}
  end

  defp header_value(headers, key) when is_list(headers) do
    key_downcased = String.downcase(key)

    headers
    |> Enum.find_value("", fn
      {header_name, value} when is_list(header_name) and is_list(value) ->
        if String.downcase(to_string(header_name)) == key_downcased do
          to_string(value)
        end

      {header_name, value} when is_binary(header_name) and is_binary(value) ->
        if String.downcase(header_name) == key_downcased do
          value
        end

      _other ->
        nil
    end)
  end

  defp summarize_error_body(body) when is_binary(body) do
    body
    |> String.trim()
    |> String.slice(0, 300)
  end

  defp summarize_error_body(body), do: inspect(body)

  defp normalize_endpoint(base_url, path) do
    base_url = String.trim_trailing(base_url, "/")
    path = "/" <> String.trim_leading(path, "/")
    base_url <> path
  end

  defp speech_config(key, default) do
    Application.get_env(:elegoo_elixir, :speech, [])
    |> Keyword.get(key, default)
  end
end
