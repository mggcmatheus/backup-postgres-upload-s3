FROM alpine:3.20

# Instalar dependências
RUN apk add --no-cache \
    postgresql-client \
    bash \
    curl \
    ca-certificates \
    tzdata

# Instalar AWS CLI (compatível com R2)
RUN apk add --no-cache python3 py3-pip && \
    pip install --no-cache-dir awscli

WORKDIR /app

COPY backup.sh /app/backup.sh

RUN chmod +x /app/backup.sh

CMD ["/app/backup.sh"]