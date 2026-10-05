# Cybergram website (W20-WEB): a small static site next to the game server.
# Build from the REPO ROOT (the site is generated from repo files):
#   docker build -f web/Dockerfile -t cybergram-web .
#   docker run -d -p 8081:8080 -v cybergram-public:/srv/public:ro cybergram-web
# web/Dockerfile.dockerignore keeps the build context to the files needed.
# Releases publish it as ghcr.io/letsmanu/cybergram-web (build.yml).

# Stage 1: generate the pages (patch notes, heroes) with the stdlib script.
FROM python:3.12-alpine AS build
WORKDIR /repo
COPY web/ web/
COPY launcher/assets/notes/ launcher/assets/notes/
COPY assets/data/heroes/ assets/data/heroes/
COPY assets/data/skills/ assets/data/skills/
COPY assets/data/weapons/ assets/data/weapons/
COPY assets/localization/hud.csv assets/localization/hud.csv
COPY assets/ui/portraits/ assets/ui/portraits/
COPY assets/fonts/ assets/fonts/
COPY src/ui/menu/hero_showcase.gd src/ui/menu/hero_showcase.gd
RUN python3 web/build.py --repo /repo --out /site

# Stage 2: nginx, running as its unprivileged user on port 8080.
FROM nginx:alpine
RUN rm -f /etc/nginx/conf.d/default.conf \
    && mkdir -p /var/cache/cybergram-web /srv/public \
    && chown nginx:nginx /var/cache/cybergram-web
COPY web/docker/nginx.conf /etc/nginx/nginx.conf
COPY web/docker/40-cybergram-release.sh /docker-entrypoint.d/40-cybergram-release.sh
COPY --from=build /site/ /usr/share/nginx/html/
RUN chmod 0755 /docker-entrypoint.d/40-cybergram-release.sh && nginx -t
USER nginx
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -fsS -o /dev/null http://127.0.0.1:8080/ || exit 1
