# Server Setup

This guide connects Codex App Server Mobile to `codex app-server` over a private
Tailscale network. Tailscale authenticates peers and encrypts traffic, allowing
the mobile client to use the app-server's native `ws://` listener without a TLS
reverse proxy.

> Codex currently documents its WebSocket transport as experimental and
> unsupported. Keep the mobile app and Codex CLI reasonably up to date.

## Security Model

Use both layers:

1. **Tailscale** limits network reachability and encrypts traffic between peers.
2. **App-server capability authentication** requires a bearer token during the
   WebSocket upgrade.

Do not publish the listener to the public internet. If the listener binds to
`0.0.0.0`, use host firewall rules or Tailscale ACLs to prevent unintended LAN
access.

## 1. Generate a Capability Token

Run this on the Linux/WSL machine that hosts Codex:

```bash
mkdir -p ~/.codex
head -c 32 /dev/urandom | base64 > ~/.codex/app-server-token
chmod 600 ~/.codex/app-server-token
cat ~/.codex/app-server-token
```

Copy the printed value into the mobile app's **Access token** field.

## 2. Choose a WSL Network Layout

### Option A: Tailscale Inside WSL

This is the clearest ownership model: WSL gets its own Tailscale identity and
IP address. Bind app-server to that Tailscale IP or to all WSL interfaces:

```bash
tailscale ip -4

codex app-server \
  --listen ws://0.0.0.0:9999 \
  --ws-auth capability-token \
  --ws-token-file ~/.codex/app-server-token
```

Connect the mobile app to:

```text
ws://<wsl-tailscale-ip>:9999
```

### Option B: Tailscale on Windows, WSL Mirrored Networking

Enable mirrored networking in
`C:\Users\<you>\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Restart WSL from PowerShell:

```powershell
wsl --shutdown
```

Start app-server inside WSL:

```bash
codex app-server \
  --listen ws://0.0.0.0:9999 \
  --ws-auth capability-token \
  --ws-token-file ~/.codex/app-server-token
```

Allow inbound TCP port `9999` only on the appropriate Windows/Tailscale network
profile, then connect to the Windows Tailscale IP or MagicDNS name:

```text
ws://<windows-tailscale-ip>:9999
ws://<windows-magicdns-name>:9999
```

### Option C: Tailscale on Windows, WSL NAT Networking

Forward a Windows port to the current WSL address. In WSL:

```bash
hostname -I
```

Then run an elevated PowerShell command, replacing `<wsl-ip>`:

```powershell
netsh interface portproxy add v4tov4 `
  listenaddress=0.0.0.0 listenport=9999 `
  connectaddress=<wsl-ip> connectport=9999
```

Add a narrowly scoped firewall rule for TCP `9999`. WSL NAT addresses can
change after restart, so mirrored networking or running Tailscale inside WSL is
preferable for regular use.

## 3. Verify the Listener

Inside WSL:

```bash
ss -ltnp | grep 9999
```

From another machine on the same tailnet:

```bash
curl http://<tailscale-ip-or-name>:9999/readyz
```

The health endpoint should return HTTP `200`.

## 4. Connect the Mobile App

Enter:

- **Server address:** `ws://<tailscale-ip-or-name>:9999`
- **Access token:** contents of `~/.codex/app-server-token`

The app stores both values for the next launch. The token is kept in platform
secure storage.

## Tailscale ACL Example

Prefer restricting the app-server port to your phone or an appropriate device
group. The exact syntax depends on your tailnet policy, but the intent is:

```text
phone/device group -> development machine:9999 only
```

Review the current
[Tailscale access-control documentation](https://tailscale.com/kb/1018/acls)
before applying policy changes.

## Troubleshooting

- **Connection refused:** app-server is not listening on the forwarded
  interface, the WSL port proxy is stale, or a firewall blocks port `9999`.
- **401 Unauthorized:** the access token does not match the token file, or
  whitespace was copied with it.
- **403 Forbidden:** an intermediary added an `Origin` header. This mobile
  client deliberately sends none.
- **Android emulator:** `10.0.2.2` reaches the development host, not an
  arbitrary tailnet peer. Prefer the actual Tailscale address for device-like
  testing.
- **Server overloaded (`-32001`):** retry after a short delay; the client
  includes reconnect/backoff behavior for transient failures.
