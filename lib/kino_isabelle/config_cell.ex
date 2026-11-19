defmodule KinoIsabelle.ConfigCell do
  @moduledoc false

  use Kino.JS, assets_path: "lib/assets/config/build"
  use Kino.JS.Live
  use Kino.SmartCell, name: "Isabelle server"

  # The password is kept as the name of a Livebook secret, which the generated
  # source reads from LB_<name>, so it is not stored in the notebook.
  @defaults %{
    "server" => "local",
    "url" => "",
    "host" => "",
    "port" => nil,
    "password_secret" => "",
    "sessions" => %{}
  }

  @impl true
  def init(attrs, ctx),
    do: {:ok, assign(ctx, fields: Map.merge(@defaults, Map.take(attrs, Map.keys(@defaults))))}

  @impl true
  def handle_connect(ctx), do: {:ok, ctx.assigns.fields, ctx}

  @impl true
  def handle_event("update", fields, ctx) do
    casts = for {key, value} <- Map.take(fields, Map.keys(@defaults)), do: {key, cast(key, value)}
    accepted = for {key, {:ok, value}} <- casts, into: %{}, do: {key, value}
    ctx = assign(ctx, fields: Map.merge(ctx.assigns.fields, accepted))

    if map_size(accepted) < length(casts), do: broadcast_event(ctx, "fields", ctx.assigns.fields)

    {:noreply, ctx}
  end

  @impl true
  def to_attrs(ctx), do: ctx.assigns.fields

  @impl true
  def to_source(%{"server" => "local"}), do: "KinoIsabelle.use_server(:local)"

  def to_source(attrs) do
    options =
      for {key, value} <-
            address(attrs) ++
              [password: attrs["password_secret"], sessions: attrs["sessions"]],
          value not in [nil, "", %{}],
          do: {key, option(key, value)}

    Macro.to_string(quote(do: KinoIsabelle.use_server(unquote(options))))
  end

  defp address(%{"server" => "url"} = attrs), do: [url: attrs["url"]]
  defp address(attrs), do: [host: attrs["host"], port: attrs["port"]]

  defp option(:password, secret), do: quote(do: System.fetch_env!(unquote("LB_" <> secret)))
  defp option(_key, value), do: Macro.escape(value)

  defp cast("server", server) when server in ~w(local host url), do: {:ok, server}
  defp cast("url", url) when is_binary(url), do: {:ok, url}
  defp cast("host", host) when is_binary(host), do: {:ok, host}
  defp cast("port", nil), do: {:ok, nil}
  defp cast("port", port) when port in 1..65535, do: {:ok, port}

  defp cast("password_secret", secret) when is_binary(secret) do
    if secret =~ ~r/\A\w*\z/, do: {:ok, secret}, else: :error
  end

  # The client sends sessions as [logic, id] pairs.
  defp cast("sessions", pairs) when is_list(pairs) do
    if Enum.all?(pairs, &match?([<<_, _::binary>>, <<_, _::binary>>], &1)),
      do: {:ok, Map.new(pairs, &List.to_tuple/1)},
      else: :error
  end

  defp cast(_key, _value), do: :error
end
