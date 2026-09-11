# Server-only container for the WdpMgr licensing/admin service.
# The Windows client projects and kernel driver are intentionally not included.

FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY Server/WdpMgrServer.csproj Server/

# BuildKit supplies TARGETARCH (amd64 or arm64). Map it to .NET's Linux RIDs.
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "amd64" ]; then RID=linux-x64; \
    elif [ "$TARGETARCH" = "arm64" ]; then RID=linux-arm64; \
    else echo "Unsupported target architecture: $TARGETARCH" >&2; exit 1; fi; \
    dotnet restore Server/WdpMgrServer.csproj --runtime "$RID" -p:RuntimeIdentifier="$RID"

COPY Server/ Server/

RUN if [ "$TARGETARCH" = "amd64" ]; then RID=linux-x64; \
    elif [ "$TARGETARCH" = "arm64" ]; then RID=linux-arm64; \
    else echo "Unsupported target architecture: $TARGETARCH" >&2; exit 1; fi; \
    dotnet publish Server/WdpMgrServer.csproj \
      --configuration Release \
      --runtime "$RID" \
      --self-contained false \
      --no-restore \
      -p:RuntimeIdentifier="$RID" \
      -p:PublishSingleFile=false \
      --output /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

COPY --from=build /app/publish/ ./

# SQLite, licenses, RSA keys, and uploaded base EXEs live here.
RUN mkdir -p /data && chown -R app:app /data
VOLUME ["/data"]

ENV ASPNETCORE_URLS=http://0.0.0.0:5000 \
    PORT=5000 \
    WDPMGR_DB_PATH=/data/wdpmgr.db

EXPOSE 5000
USER app
ENTRYPOINT ["dotnet", "WdpMgrServer.dll"]
