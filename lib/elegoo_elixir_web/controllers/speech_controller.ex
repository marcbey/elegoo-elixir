defmodule ElegooElixirWeb.SpeechController do
  use ElegooElixirWeb, :controller

  alias ElegooElixir.Speech.STTClient

  def transcribe(conn, params) do
    with {:ok, upload} <- extract_upload(params),
         {:ok, result} <- STTClient.transcribe_upload(upload) do
      json(conn, %{text: result.text, raw: result.raw})
    else
      {:error, :missing_audio} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "missing_audio"})

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: format_reason(reason)})
    end
  end

  defp extract_upload(%{"audio" => %Plug.Upload{} = upload}), do: {:ok, upload}
  defp extract_upload(%{"file" => %Plug.Upload{} = upload}), do: {:ok, upload}
  defp extract_upload(_params), do: {:error, :missing_audio}

  defp format_reason({:http_error, status, body}),
    do: "stt_http_error status=#{status} body=#{inspect(body)}"

  defp format_reason({:stt_error, message}), do: "stt_error #{inspect(message)}"
  defp format_reason({:request_failed, reason}), do: "stt_request_failed #{inspect(reason)}"
  defp format_reason({:invalid_json, reason}), do: "stt_invalid_json #{inspect(reason)}"
  defp format_reason(reason), do: inspect(reason)
end
