# TeslaCurl

TeslaCurl is a middleware for [Tesla](https://hex.pm/packages/tesla). It will log a curl command for each request.

The package can be installed by adding `tesla_curl` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tesla_curl, "~> 1.3.1"}
  ]
end
```

## Usage

#### As a middleware with Plug:
```elixir
defmodule HelloWorld do
  use Tesla

  plug Tesla.Middleware.Curl
end
```

Note - Plugs are executed in the order they are defined. As such, it is recommended you define TeslaCurl below other middlewares.
For example, if the TeslaCurl plug is defined above the Headers middleware, headers will not be included in the curl log output.

#### Without Plug:
If you prefer to use this library without the plug, you can use the `TeslaCurl` module directly with `log/2`:

```elixir
defmodule HelloWorld do
  def foo(Tesla.Env{} = env, opts \\ []) do
    Tesla.Middleware.Curl.log(env, opts)
  end
end
```

## Options

#### Field Redaction

You can pass a list of header keys or body field keys to be redacted in the options, like so: 
`redact_fields: ["api_token", "authorization", "password"]`

If supplied, the redacted fields will be replaced with `REDACTED` in the curl command.

If a request's body is a string, you can use a regular expression with a capture group to redact the field. For example, if
you were supplying Tesla with a string body that looked like this- 

```xml
"<username>John Doe</username><password>horse battery staple</password>"
```

You could redact the password field by supplying the following option- `redact_fields: [~r{<password>(.*?)</password>}]`. This field 
will be replaced with `<password>REDACTED</password>` in the curl command.

#### Follow Redirects

If you would like to enable the flag to follow redirects by default, supply `follow_redirects: true` in the options list.

#### Compressed

For compressed responses, you can supply the `compressed: true` option. This will add the `--compressed` flag to the curl command.

#### Logger Level

You can supply the `logger_level` option to set the level of the logger. The default is `:info`. Must be one of `:debug`, `:info`, `:warn`, `:error`, `:fatal`, `:none`.

Here is an example of options configuration with all options enabled:


```elixir
plug Tesla.Middleware.Curl, follow_redirects: true, redact_fields: ["api_token", "authorization", "password"], compressed: true, logger_level: :debug
```

## License

The source code is under the MIT License. Copyright (c) 2023-2025 Colin Cromar.