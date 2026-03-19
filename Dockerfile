FROM postgres:17-alpine

RUN apk add --no-cache \
    bash \
    curl \
    ca-certificates \
    tzdata \
    aws-cli

WORKDIR /app

COPY backup.sh /app/backup.sh

RUN chmod +x /app/backup.sh

CMD ["/app/backup.sh"]