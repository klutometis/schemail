FROM racket/racket:9.0

WORKDIR /app

# Installation scope, so the daemon can run as an unprivileged uid (the host
# user who owns the token files) rather than root. --no-docs avoids pulling
# huge doc chains.
RUN raco pkg install --scope installation --auto --skip-installed --no-docs \
      simple-oauth2 http-easy colormaps plot

# Application code, compiled at build time so startup doesn't recompile and
# /app never needs to be writable.
COPY . .
RUN raco make -v bin/schemail

# State lives on a volume at /data, which is also $HOME, so simple-oauth2
# finds its tokens at $HOME/.oauth2.rkt/{tokens,preferences}. USER must match
# the name the tokens were stored under (simple-oauth2 keys them by $USER).
ENV HOME=/data \
    USER=danenberg \
    SCHEMAIL_HEADLESS=1 \
    SCHEMAIL_HEARTBEAT=/data/heartbeat

# Unhealthy if no poll has completed in 20 minutes (interval is 5).
HEALTHCHECK --interval=5m --timeout=10s --start-period=10m \
  CMD test $(( $(date +%s) - $(cat /data/heartbeat) )) -lt 1200

CMD ["racket", "bin/schemail", "daemon", "--classifier", "experiment-4", "--model", "haiku-4-5", "--interval", "5"]
