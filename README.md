# TeslaCurl

TeslaCurl is a middleware for [Tesla](https://hex.pm/packages/tesla). It will log a curl command for each request.

The package can be installed by adding `tesla_curl` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tesla, "~> 1.13"},
    {:tesla_curl, "~> 1.3.1", only: [:dev, :test]}
  ]
end
```

## Usage

#### As a middleware with Plug:
You can use TeslaCurl as a middleware with Plug to automatically log cURL commands for each request:

```elixir
defmodule HelloWorld do
  use Tesla

  plug Tesla.Middleware.Headers
  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.Curl, logger_level: :debug, redact_fields: ["authorization"]
end
```

Tesla executes middlewares in order, meaning Tesla.Middleware.Curl should come after other middlewares that
modify the request or response. For example, if you are using Tesla.Middleware.Headers and Tesla.Middleware.JSON-

```elixir
plug Tesla.Middleware.Headers
plug Tesla.Middleware.JSON
plug Tesla.Middleware.Curl  # Correct order

plug Tesla.Middleware.Curl
plug Tesla.Middleware.Headers
plug Tesla.Middleware.JSON  # Incorrect order (won’t log JSON encoding or supply headers to the Curl middleware)
```

#### Use without Plug:
If you prefer to use this library without the plug, you can use the `TeslaCurl` module directly with `log/2`:

```elixir
defmodule HelloWorld do
  def foo(Tesla.Env{} = env, opts \\ []) do
    Tesla.Middleware.Curl.log(env, opts)
  end
end
```

## Configuration Options

#### Field Redaction

To prevent sensitive information from being logged, use redact_fields to specify headers or body fields that should be redacted:

```elixir
plug Tesla.Middleware.Curl, redact_fields: ["api_token", "authorization", "password"]
```

Sensitive values will be replaced with `REDACTED` in the generated cURL command.

If the request body is a string (e.g., XML or JSON), you can redact values using regular expressions with capture groups:

Example:

```elixir
redact_fields: [~r{<password>(.*?)</password>}]
```

For a request body like:

```xml
  "<username>John Doe</username><password>horse battery staple</password>"
```

The logged output would be:

```xml
"<username>John Doe</username><password>REDACTED</password>"
```

#### Follow Redirects

If you would like to enable the flag to follow redirects by default, supply `follow_redirects: true` in the options list.

#### Compressed

For compressed responses, you can supply the `compressed: true` option. This will add the `--compressed` flag to the curl command.

#### Logger Level

You can supply the `logger_level` option to set the level of the logger. The default is `:info`. Must be one of `:debug`, `:info`, `:warn`, `:error`, `:fatal`, `:none`.

Here is an example of options configuration with all options enabled:


```elixir
plug Tesla.Middleware.Curl,
  follow_redirects: true,
  redact_fields: ["api_token", "authorization", "password"],
  compressed: true,
  logger_level: :debug
```

## Best Practices
- **Avoid Logging Sensitive Data:** Always use redact_fields in production to prevent exposing secrets.
- **Use in Development & Debugging:** Consider enabling TeslaCurl only in non-production environments.
- **Define Middleware Order Correctly:** Ensure the definition for `plug Tesla.Middleware.Curl` is placed after
`plug Tesla.Middleware.Headers` and `plug Tesla.Middleware.JSON`.

## License

The source code is under the MIT License. Copyright (c) 2023-2025 Colin Cromar.
