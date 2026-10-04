FROM racket/racket:9.0

WORKDIR /app

# Installation scope, so the daemon can run as an unprivileged uid (the host
# user who owns the token files) rather than root. --no-docs avoids pulling
# huge doc chains.
RUN raco pkg install --scope installation --auto --skip-installed --no-docs \
      simple-oauth2 http-easy colormaps plot

# The image bundles OpenSSL 1.1.1 in /usr/lib/racket and Racket prefers it,
# but crypto-lib rejects 1.1 ("library version not supported"), so
# simple-oauth2 cannot decrypt its AES-GCM token file. Delete the bundled
# copies (after pkg install, which needs them); Racket then falls back to the
# system libssl/libcrypto 3.x.
RUN rm -f /usr/lib/racket/libssl.so.1.1 /usr/lib/racket/libcrypto.so.1.1

# Application code, compiled at build time so startup doesn't recompile and
# /app never needs to be writable.
COPY . .
# COPY keeps host modes but makes root the owner, and the daemon runs as the
# host uid: a chmod-600 config/credentials.json was unreadable, which went
# unnoticed for exactly one access-token lifetime (1h) until the first
# refresh. Make /app world-readable; the image never leaves the VM.
RUN chmod -R a+rX /app && raco make -v bin/schemail

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
