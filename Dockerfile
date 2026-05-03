FROM racket/racket:9.0

WORKDIR /app

# Install Racket package dependencies (--no-docs to avoid pulling huge doc chains)
RUN raco pkg install --auto --skip-installed --no-docs simple-oauth2 http-easy colormaps plot

# Copy application code
COPY . .

# OAuth tokens live on a persistent volume mounted at /data/.oauth2.rkt
# Symlink so simple-oauth2 finds them at $HOME/.oauth2.rkt
RUN mkdir -p /data/.oauth2.rkt && \
    ln -sf /data/.oauth2.rkt /root/.oauth2.rkt

CMD ["racket", "bin/schemail", "daemon", "--recent-only", "--classifier", "experiment-3", "--model", "haiku-4-5", "--interval", "5"]
