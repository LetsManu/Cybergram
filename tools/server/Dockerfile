# Cybergram dedicated server (x86_64 Linux). Releases publish this image as
# ghcr.io/letsmanu/cybergram-server (see .github/workflows/build.yml).
# To build it yourself, extract the Linux release next to it:
#   tar -xzf Cybergram-v0.2.0-linux-x86_64.tar.gz -C tools/server/game
#   docker build -t cybergram-server tools/server
#   docker run -d --name cybergram -p 7777:7777/udp -p 8080:8080/tcp cybergram-server
#
# The image also serves the client builds for the launcher on TCP 8080
# (busybox httpd). The release workflow fills tools/server/updates/ with
# version.json + the Windows/Linux zips (launcher/tools/make_update_feed.sh).
# Without them (empty updates/) the update host simply stays off.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends busybox-static \
    && rm -rf /var/lib/apt/lists/* && ln -s /bin/busybox /usr/local/bin/busybox
RUN useradd --system --create-home cybergram
COPY game/ /opt/cybergram/
COPY updates/ /opt/cybergram-updates/
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/cybergram/Cybergram.x86_64 /opt/entrypoint.sh \
    && mkdir -p /data/accounts /data/tls && chown -R cybergram:cybergram /data
# Accounts (one JSON store, written atomically) and the TLS certificate for
# encrypted login live in the /data volume. Without a certificate the server
# runs guest-only: it never accepts a password over an unencrypted link.
ENV CYBERGRAM_DATA_DIR=/data/accounts \
    CYBERGRAM_TLS_CERT=/data/tls/fullchain.pem \
    CYBERGRAM_TLS_KEY=/data/tls/privkey.pem
VOLUME /data
USER cybergram
WORKDIR /opt/cybergram
EXPOSE 7777/udp
EXPOSE 8080/tcp
ENTRYPOINT ["/opt/entrypoint.sh"]
# Extra flags go after the image name, e.g.  ... cybergram-server --max-clients 4
