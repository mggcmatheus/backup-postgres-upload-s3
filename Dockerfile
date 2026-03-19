FROM alpine:3.20

# Instalar dependências
RUN apk add --no-cache \
    postgresql-client \
    bash \
    curl \
    ca-certificates \
    tzdata \
    aws-cli

WORKDIR /app

COPY backup.sh /app/backup.sh

RUN chmod +x /app/backup.sh

CMD ["/app/backup.sh"]