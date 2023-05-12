defmodule Ueberauth.Strategy.Shift4Shop do
  @moduledoc """
  Shift4Shop Strategy for Überauth.
  """

  use Ueberauth.Strategy,
    uid_field: "SecureURL",
    default_scope: "identify",
    send_redirect_uri: true,
    oauth2_module: Ueberauth.Strategy.Shift4Shop.OAuth

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Extra
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Strategy.Shift4Shop.Token

  @doc """
  Handles initial request for Shift4Shop authentication.
  """
  def handle_request!(conn) do
    opts =
      options_from_conn(conn)
      |> with_scopes(conn)
      |> with_state_param(conn)
      |> with_redirect_uri(conn)

    module = option(conn, :oauth2_module)
    redirect!(conn, apply(module, :authorize_url!, [opts]))
  end

  @doc false
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    opts = [redirect_uri: callback_url(conn)]

    decoded =
      option(conn, :oauth2_module)
      |> apply(:get_token!, [[code: code], opts])
      |> token()

    if decoded.token_key == nil do
      err = "Token Error"
      desc = "Invalid Token"
      set_errors!(conn, [error(err, desc)])
    else
      conn
      |> store_token(decoded)
    end
  end

  @doc false
  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @doc false
  def handle_cleanup!(conn) do
    conn
    |> put_private(:shift4shop_token, nil)
  end

  # Store the token for later use.
  @doc false
  defp store_token(conn, token) do
    put_private(conn, :shift4shop_token, token)
  end

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth` struct.
  """
  def info(conn) do
    %Info{
      urls: [
        %{"SecureURL" => conn.private.shift4shop_token.secure_url,
        "PostBackURL" => conn.private.shift4shop_token.post_back_url
        }
      ]
    }
  end

  @doc """
  Includes the token from the Shift4Shop response.
  """
  def token(conn) do
    Token.decode(conn.private.shift4shop_token)
  end

  @doc """
  Includes the credentials from the GitHub response.
  """
  def credentials(conn, scopes \\ []) do
    token = Token.decode(conn.private.shift4shop_token)

    %Credentials{
      token: token.token_key,
      refresh_token: token.token_key,
      expires_at: nil,
      token_type: token.action,
      expires: nil,
      scopes: scopes
    }
  end

  @doc """
  Stores the raw information (the token and user)
  obtained from the Shift4Shop callback.
  """
  def extra(conn) do
    %{
      shift4shop_token: :token
    }
    |> Enum.filter(fn {original_key, _} ->
      Map.has_key?(conn.private, original_key)
    end)
    |> Enum.map(fn {original_key, mapped_key} ->
      {mapped_key, Map.fetch!(conn.private, original_key)}
    end)
    |> Map.new()
    |> (&%Extra{raw_info: &1}).()
  end

  @doc """
  Fetches the uid field from the response.
  """
  def uid(conn) do
    conn.private.shift4shop_token.secure_url
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end

  defp with_scopes(opts, conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)

    opts |> Keyword.put(:scope, scopes)
  end

  defp with_redirect_uri(opts, conn) do
    if option(conn, :send_redirect_uri) do
      opts |> Keyword.put(:redirect_uri, callback_url(conn))
    else
      opts
    end
  end

  defp options_from_conn(conn) do
    base_options = []
    request_options = conn.private[:ueberauth_request_options].options

    case {request_options[:client_id], request_options[:client_secret]} do
      {nil, _} -> base_options
      {_, nil} -> base_options
      {id, secret} -> [client_id: id, client_secret: secret] ++ base_options
    end
  end
end
