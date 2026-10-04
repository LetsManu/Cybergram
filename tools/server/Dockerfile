# Cybergram dedicated server (x86_64 Linux). Releases publish this image as
# ghcr.io/letsmanu/cybergram-server (see .github/workflows/build.yml).
# To build it yourself, extract the Linux release next to it:
#   tar -xzf Cybergram-v0.2.0-linux-x86_64.tar.gz -C tools/server/game
#   docker build -t cybergram-server tools/server
#   docker run -d --name cybergram -p 7777:7777/udp cybergram-server
FROM debian:bookworm-slim
RUN useradd --system --create-home cybergram
COPY game/ /opt/cybergram/
RUN chmod +x /opt/cybergram/Cybergram.x86_64
USER cybergram
WORKDIR /opt/cybergram
EXPOSE 7777/udp
ENTRYPOINT ["/opt/cybergram/Cybergram.x86_64", "--headless", "--", "--server", "--port", "7777"]
# Extra flags go after the image name, e.g.  ... cybergram-server --max-clients 4
