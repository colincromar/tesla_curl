defmodule Tesla.Middleware.Curl do
  @moduledoc """
  A middleware for the Tesla HTTP client that logs requests expressed in Curl.

  Parses Tesla.Env structs into a curl command and logs it. This is useful for debugging
  requests and responses.

  ### Examples

  ```
  defmodule MyClient do
    use Tesla

    plug Tesla.Middleware.Curl, follow_redirects: true, redact_fields: ["api_token", "authorization"]
  end
  ```

  ### Options

  - `:follow_redirects` - boolean, will add the `-L` flag to the curl command
  - `:redact_fields` - a list of keys or regex capture groups to redact from the request body
  - `:compressed` - boolean, will add the `--compressed` flag to the curl command
  - `:logger_level` - the level at which to log the curl command, as an atom. Must be one of -
      `:emergency`, `:alert`, `:critical`, `:error`, `:warning`, `:notice`, `:info`, `:debug`
  """

  require Logger

  @behaviour Tesla.Middleware

  @type method :: :head | :get | :delete | :trace | :options | :post | :put | :patch

  @doc """
  Serves as the main entrypoint to the middleware. Handles this middleware and calls
  the next piece of middleware in the chain.
  """
  @spec call(Tesla.Env.t(), Tesla.Env.stack(), keyword() | nil) :: Tesla.Env.result()
  def call(env, next, opts \\ []) do
    env
    |> log_request_as_curl(opts)
    |> Tesla.run(next)
  end

  # Calls the function to construct the curl command and logs it. If an error occurs,
  # it will be logged, and the request will continue as normal.
  @spec log_request_as_curl(Tesla.Env.t(), keyword() | nil) :: Tesla.Env.t()
  defp log_request_as_curl(env, opts) do
    try do
      construct_curl(env, opts)
      |> log(opts)
    rescue
      e ->
        Logger.error(Exception.format(:error, e, __STACKTRACE__))
    end

    env
  end

  # Logs request as :info, or as the level specified in the opts
  # Must be one of -
  # :emergency, :alert, :critical, :error, :warning, :notice, :info, :debug
  @spec log(String.t(), keyword() | nil) :: :ok
  defp log(curl_request, nil), do: Logger.info(curl_request)

  defp log(curl_request, opts) do
    with {:ok, logger_level} <- Keyword.fetch(opts, :logger_level) do
      Logger.log(logger_level, curl_request)
    else
      _ -> Logger.info(curl_request)
    end
  end

  defp construct_curl(%Tesla.Env{body: %Tesla.Multipart{}} = env, opts) do
    headers = parse_headers(env.headers, opts)
    query_params = format_query_params(env.query)
    parsed_parts = parse_parts_lazy(env.body.parts)
    compressed = compressed_flag(opts)

    "curl -X POST #{compressed}#{headers}#{parsed_parts} '#{env.url}#{query_params}'"
  end

  # Handle requests with an Env that has a binary body, but may have query params
  defp construct_curl(%Tesla.Env{} = env, opts) when is_binary(env.body) do
    flag_type = set_flag_type(env.headers)
    headers = parse_headers(env.headers, opts)
    location = location_flag(opts)
    method = translate_method(env.method)
    compressed = compressed_flag(opts)
    body = env.body

    sanitized_body =
      with {:ok, redact_fields} <- Keyword.fetch(opts, :redact_fields) do
        Enum.reduce(redact_fields, body, fn field, acc ->
          filter_string_body(field, acc)
        end)
      else
        _ -> body
      end

    query_params = format_query_params(env.query)

    "curl #{location}#{method}#{compressed}#{headers}#{flag_type} '#{sanitized_body}' '#{env.url}#{query_params}'"
  end

  # Handle requests with an Env that has query params.
  defp construct_curl(%Tesla.Env{} = env, opts) do
    flag_type = set_flag_type(env.headers)
    location = location_flag(opts)
    headers = parse_headers(env.headers, opts)
    compressed = compressed_flag(opts)
    body = parse_body(env.body, flag_type, opts)
    method = translate_method(env.method)

    query_params =
      sanitize_query_params(env.query, opts)
      |> format_query_params()

    "curl #{location}#{method}#{compressed}#{headers}#{body}'#{env.url}#{query_params}'"
  end

  # Parses the body parts of multipart requests into Curl format.
  @spec parse_part(%Tesla.Multipart.Part{}) :: String.t()
  defp parse_part(%Tesla.Multipart.Part{
         dispositions: [{_, field} | _],
         body: %File.Stream{path: path}
       }) do
    "--form '#{field}=@#{path}'"
  end

  defp parse_part(%Tesla.Multipart.Part{dispositions: [{_, field} | _]} = part) do
    "--form '#{field}=#{part.body}'"
  end

  # Top-level function to parse headers
  @spec parse_headers(list(), keyword() | nil) :: String.t()
  defp parse_headers(nil, _opts), do: ""
  defp parse_headers([], _opts), do: ""

  defp parse_headers(headers, opts) do
    Enum.map(headers, fn {k, v} ->
      construct_header(k, maybe_redact_field(k, v, opts))
    end)
    |> Enum.join(" ")
    |> Kernel.<>(" ")
  end

  # Returns either an empty string or a query string to append to the URL
  @spec format_query_params(keyword() | nil) :: String.t()
  defp format_query_params([]), do: nil

  defp format_query_params(params) when params == %{}, do: nil

  defp format_query_params(query) do
    "?" <> URI.encode_query(Enum.into(query, %{}), :rfc3986)
  end

  # Lazy parses the parts of a multipart request
  @spec parse_parts_lazy(list()) :: String.t()
  defp parse_parts_lazy(parts) do
    parts
    |> Stream.map(&parse_part/1)
    |> Enum.join(" ")
  end

  # Redacts query parameters from the curl command
  @spec sanitize_query_params(keyword() | map(), keyword() | nil) :: keyword()
  defp sanitize_query_params(query_params, nil), do: query_params

  defp sanitize_query_params(query_params, opts) when is_map(query_params) do
    with {:ok, redact_fields} <- Keyword.fetch(opts, :redact_fields) do
      Enum.reduce(redact_fields, query_params, fn field, acc ->
        query_param_redact_for_map(field, acc)
      end)
    else
      _ -> query_params
    end
  end

  defp sanitize_query_params(query_params, opts) when is_list(query_params) do
    with {:ok, redact_fields} <- Keyword.fetch(opts, :redact_fields) do
      Enum.reduce(redact_fields, query_params, fn field, acc ->
        query_param_redact_for_list(field, acc)
      end)
    else
      _ -> query_params
    end
  end

  # Tesla's spec is a little loose for query params, they can be either a list or map.
  # Handles field redaction for query params in a map, for atoms, strings, or Regex values in redact_fields
  @spec query_param_redact_for_map(atom() | binary() | Regex.t(), map()) :: list()
  defp query_param_redact_for_map(field, query_params) when is_atom(field) do
    case Map.has_key?(query_params, field) do
      true -> Map.put(query_params, field, "REDACTED")
      false -> query_params
    end
  end

  defp query_param_redact_for_map(field, query_params) when is_binary(field) do
    field_as_atom = String.to_atom(field)

    case Map.has_key?(query_params, field_as_atom) do
      true -> Map.put(query_params, field_as_atom, "REDACTED")
      false -> query_params
    end
  end

  defp query_param_redact_for_map(%Regex{}, %{}), do: %{}

  defp query_param_redact_for_map(%Regex{} = field, query_params) do
    Enum.map(query_params, fn {k, _v} ->
      f = standardize_fields_for_redaction(k)

      case Regex.match?(field, f) do
        true -> Map.put(query_params, k, "REDACTED")
        false -> query_params
      end
    end)
    |> List.first()
  end

  # Tesla's spec is a little loose for query params, they can be either a list or map.
  # Handles field redaction for query params in a list, for atoms, strings, or Regex values in redact_fields
  @spec query_param_redact_for_list(atom() | binary() | Regex.t(), list()) :: list()
  defp query_param_redact_for_list(%Regex{} = field, query_params) do
    Enum.map(query_params, fn {k, v} ->
      f = standardize_fields_for_redaction(k)

      case Regex.match?(field, f) do
        true -> {k, "REDACTED"}
        false -> {k, v}
      end
    end)
  end

  defp query_param_redact_for_list(field, query_params) when is_atom(field) do
    case Keyword.has_key?(query_params, field) do
      true -> Keyword.replace(query_params, field, "REDACTED")
      false -> query_params
    end
  end

  defp query_param_redact_for_list(field, query_params) when is_binary(field) do
    field_as_atom = String.to_atom(field)

    case Keyword.has_key?(query_params, field_as_atom) do
      true -> Keyword.replace(query_params, field_as_atom, "REDACTED")
      false -> query_params
    end
  end

  # Filters items from a string request body, as defined in a capture regex
  @spec filter_string_body(Regex.t() | String.t(), String.t()) :: String.t()
  defp filter_string_body(%Regex{} = regex, body) do
    match_set = Regex.scan(regex, body)
    captures = Enum.map(match_set, fn match -> match |> List.last() end)

    Enum.reduce(captures, body, fn match, acc ->
      String.replace(acc, match, "REDACTED", global: true)
    end)
  end

  defp filter_string_body(_field, body), do: body

  # Constructs the header string
  @spec construct_header(String.t(), String.t()) :: String.t()
  defp construct_header(key, value), do: "--header '#{key}: #{value}'"

  # Top-level function to parse body
  @spec parse_body(list() | nil, String.t(), keyword() | nil) :: String.t()
  defp parse_body(nil, _flag_type, _opts), do: ""
  defp parse_body([], _flag_type, _opts), do: ""

  defp parse_body(body, flag_type, opts) do
    Enum.flat_map(body, fn {k, v} ->
      translate_parameters(flag_type, k, v, opts)
    end)
    |> Enum.join(" ")
    |> Kernel.<>(" ")
  end

  # Recursively handles any nested maps or lists, returns a list of the translated parameters
  @spec translate_parameters(String.t(), String.t(), any(), keyword() | nil) :: [String.t()]
  defp translate_parameters(flag_type, key, value, opts) when is_map(value) do
    value
    |> Map.to_list()
    |> Enum.flat_map(fn {k, v} ->
      translate_parameters(flag_type, "#{key}[#{k}]", v, opts)
    end)
  end

  defp translate_parameters(flag_type, key, value, opts) when is_tuple(value) do
    value
    |> Enum.flat_map(fn {k, v} ->
      translate_parameters(flag_type, "#{key}[#{k}]", v, opts)
    end)
  end

  defp translate_parameters(flag_type, key, value, opts) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {v, i} ->
      translate_parameters(flag_type, "#{key}[#{i}]", v, opts)
    end)
  end

  defp translate_parameters(flag_type, key, value, opts) do
    safe_value = maybe_redact_field(key, value, opts)
    [construct_parameter(flag_type, key, safe_value)]
  end

  # Redacts the value if the key matches any of the redact_fields, if supplied
  @spec maybe_redact_field(String.t(), any(), keyword() | nil) :: any()
  defp maybe_redact_field(_key, value, nil), do: value

  defp maybe_redact_field(key, value, opts) do
    with {:ok, redact_fields} <- Keyword.fetch(opts, :redact_fields) do
      needs_redaction =
        Enum.any?(redact_fields, fn field ->
          needs_redact?(field, key)
        end)

      case needs_redaction do
        true -> "REDACTED"
        false -> value
      end
    else
      _ -> value
    end
  end

  @spec needs_redact?(String.t() | Regex.t(), String.t()) :: boolean()
  defp needs_redact?(%Regex{} = regex, match_string) when is_binary(match_string),
    do: Regex.match?(regex, match_string)

  defp needs_redact?(%Regex{} = regex, match_string) when is_atom(match_string),
    do: Regex.match?(regex, to_string(match_string))

  defp needs_redact?(field, key) do
    standard_field = standardize_fields_for_redaction(field)
    standard_key = standardize_fields_for_redaction(key)

    standard_field == standard_key ||
      String.contains?(
        standard_key,
        "[#{standard_field}]"
      )
  end

  # Standardizes the field for redaction comparison, converts to string and downcases
  @spec standardize_fields_for_redaction(String.t() | atom()) :: String.t()
  defp standardize_fields_for_redaction(field) when is_atom(field) do
    to_string(field)
    |> String.downcase()
  end

  defp standardize_fields_for_redaction(field) when is_binary(field) do
    field
    |> String.downcase()
  end

  # Constructs the body string
  @spec construct_parameter(String.t(), String.t(), String.t()) :: String.t()
  defp construct_parameter("--data-urlencode" = flag_type, key, value),
    do: "#{flag_type} '#{key}=#{URI.encode(value)}'"

  defp construct_parameter(flag_type, key, value), do: "#{flag_type} '#{key}=#{value}'"

  # Determines the flag type based on the content type header
  @spec set_flag_type(list() | nil) :: String.t()
  defp set_flag_type(nil), do: "--data"

  defp set_flag_type(headers) do
    content_type = Enum.find(headers, fn {key, _val} -> key == "Content-Type" end)

    case content_type do
      {"Content-Type", "application/x-www-form-urlencoded"} -> "--data-urlencode"
      {"Content-Type", "multipart/form-data"} -> "--form"
      _ -> "--data"
    end
  end

  # Converts method atom into a string and assigns proper flag prefixes
  @spec translate_method(method()) :: String.t()
  defp translate_method(:get), do: ""
  defp translate_method(:head), do: "-I "

  defp translate_method(method) do
    translated =
      method
      |> Atom.to_string()
      |> String.upcase()

    "-X #{translated} "
  end

  # Sets the location flag based on the follow_redirects option
  @spec location_flag(keyword() | nil) :: String.t()
  defp location_flag(nil), do: ""

  defp location_flag(opts) do
    with {:ok, follow_redirects} <- Keyword.fetch(opts, :follow_redirects) do
      (follow_redirects == true) |> set_location_flag()
    else
      _ -> ""
    end
  end

  # Sets the compressed flag based on the compressed option
  @spec compressed_flag(keyword() | nil) :: String.t()
  defp compressed_flag(nil), do: ""

  defp compressed_flag(opts) do
    case Keyword.fetch(opts, :compressed) do
      {:ok, true} -> "--compressed "
      _ -> ""
    end
  end

  # Returns a location flag based on boolean input
  @spec set_location_flag(boolean()) :: String.t()
  defp set_location_flag(true), do: "-L "
  defp set_location_flag(_), do: ""
end
