# WdpMgr Server — Docker Runbook

This runbook deploys the ASP.NET licensing/admin server from `Server/WdpMgrServer.csproj`.
It does not run the Windows client applications or the kernel driver, and it does not
require Cloudflare.

## Prerequisites

- Docker Desktop (macOS/Windows) or Docker Engine (Linux)
- A host port that remote clients can reach
- The repository checked out locally

Run the commands below from the repository root.

## 1. Build the server image

```bash
docker build -t wdpmgr-server:local .
```

The Dockerfile publishes the server for the target Linux architecture. Docker Desktop
uses ARM64 on Apple Silicon by default; build explicitly for an x64 host when needed:

```bash
docker build --platform linux/amd64 -t wdpmgr-server:local .
```

## 2. Create persistent storage

Create the volume once:

```bash
docker volume create wdpmgr-live-data
```

The volume stores `wdpmgr.db`, the RSA key pair, and uploaded base EXEs. Do not remove
this volume during normal container updates; losing it invalidates licenses signed by
the previous server.

## 3. Start the server

This publishes the service on all host interfaces so a remote machine can reach it:

```bash
docker run -d \
  --name wdpmgr-server \
  --restart unless-stopped \
  -p 18080:5000 \
  -e WDPMGR_ADMIN_KEY='replace-with-a-long-secret' \
  -e WDPMGR_FIRST_USER='admin' \
  -e WDPMGR_FIRST_PASS='replace-with-a-password' \
  -v wdpmgr-live-data:/data \
  wdpmgr-server:local
```

Open the admin panel on the host at `http://localhost:18080`.

The image listens on container port `5000`. The host-side `18080` can be changed if
that port is already in use, for example `-p 18081:5000`.

For a local-only deployment, bind the host port to loopback instead:

```bash
-p 127.0.0.1:18080:5000
```

## 4. Configure a remote client URL

`localhost` is meaningful only on the machine making the request. For a Windows VM or
another machine, use a host address it can route to, such as:

```text
http://192.168.1.25:18080
```

In **Settings → Server URL**, enter the reachable LAN IP/DNS name and click **Save**.
Then download a new licensed EXE. The server URL is embedded into each downloaded EXE;
previously downloaded EXEs keep their old URL.

Allow TCP port `18080` through the host firewall and the VM/network firewall. For
machines outside the LAN, use a VPN, port-forwarded DNS name, or reverse proxy with
HTTPS. Cloudflare is optional.

## 5. First login and base EXE

- If the volume is new, sign in with `WDPMGR_FIRST_USER` and `WDPMGR_FIRST_PASS`.
- The master key is also accepted with username `master`.
- Upload the compiled Windows `WdpMgr.exe` under **Settings** before downloading
  licensed client builds.

The client and driver binaries are intentionally excluded from the Docker build
context. They must be built separately and uploaded as the base EXE.

The first-user and admin-key environment variables initialize an empty database. Once
the database contains a saved master key, changing those variables does not reset the
existing credentials; change the key from **Settings** instead. Until a master key is
saved in the database, keep `WDPMGR_ADMIN_KEY` the same whenever you recreate the
container (omitting it falls back to the insecure default `changeme`).

## 6. Container operations

```bash
docker ps
docker logs --tail 100 wdpmgr-server
docker logs -f wdpmgr-server
docker stop wdpmgr-server
docker start wdpmgr-server
docker restart wdpmgr-server
```

`--restart unless-stopped` starts the container after Docker or the host restarts. A
container that was manually stopped remains stopped until `docker start` is used.

## 7. Update the image

Rebuild and recreate the container when the server source or Dockerfile changes:

```bash
docker build -t wdpmgr-server:local .
docker rm -f wdpmgr-server
docker run -d \
  --name wdpmgr-server \
  --restart unless-stopped \
  -p 18080:5000 \
  -e WDPMGR_ADMIN_KEY='replace-with-a-long-secret' \
  -e WDPMGR_FIRST_USER='admin' \
  -e WDPMGR_FIRST_PASS='replace-with-a-password' \
  -v wdpmgr-live-data:/data \
  wdpmgr-server:local
```

`docker rm -f` removes only the container; the named data volume remains intact.
Restarting an existing container alone does not replace it with a newly built image.

## 8. Back up the data volume

Stop the server before backing up SQLite data:

```bash
docker stop wdpmgr-server
docker run --rm \
  -v wdpmgr-live-data:/data:ro \
  -v "$PWD:/backup" \
  alpine tar czf /backup/wdpmgr-data.tgz -C /data .
docker start wdpmgr-server
```

The archive contains the database, RSA keys, and uploaded base EXEs. Keep it private.

The backup command above is for Bash/WSL. In PowerShell, use an explicit host path:

```powershell
docker stop wdpmgr-server
docker run --rm `
  -v wdpmgr-live-data:/data:ro `
  -v "${PWD.Path}:/backup" `
  alpine tar czf /backup/wdpmgr-data.tgz -C /data .
docker start wdpmgr-server
```

## Troubleshooting

**The Server URL still says `localhost`.** The URL was saved in the database when the
panel was first opened. Replace it with the reachable LAN/DNS URL and save it.

**A remote machine cannot connect.** Confirm the container mapping with
`docker port wdpmgr-server`, use `-p 18080:5000` rather than the loopback-only mapping,
and check host/VM firewall rules.

**The port is already in use.** Choose another host port, such as `-p 18081:5000`,
and use that port in the Server URL.

**The base EXE is missing.** Upload `WdpMgr.exe` from the Windows build under
**Settings**. It is not copied into the image automatically.

**The admin key from the environment does not work.** The persistent database may
already contain a different saved master key. Use that key or update it in Settings.

For live remote screen/control, MeshCentral and its agent still need their own
reachable server connection; the WdpMgr container is the licensing/admin service.
