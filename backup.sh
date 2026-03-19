#!/usr/bin/env bash

set -e

echo "🚀 Iniciando backup PostgreSQL..."

DATE=$(date +"%Y-%m-%d_%H-%M-%S")
FILENAME="backup_${DATE}.dump"
PREFIX="prod"
FILEPATH="/tmp/${FILENAME}"

# =========================
# Dump do banco
# =========================
echo "📦 Gerando dump..."

pg_dump \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file="${FILEPATH}"

echo "✅ Dump gerado: ${FILEPATH}"

# =========================
# Upload para R2
# =========================
echo "☁️ Enviando para R2..."

export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"

aws s3 cp "${FILEPATH}" \
  "s3://${R2_BUCKET}/${PREFIX}/${FILENAME}" \
  --endpoint-url "${R2_ENDPOINT}"

echo "✅ Upload concluído!"

# =========================
# Limpeza local
# =========================
rm -f "${FILEPATH}"

echo "🧹 Arquivo local removido"

# =========================
# RETENÇÃO (7 dias)
# =========================
echo "🧠 Aplicando retenção (7 dias) no prefixo ${PREFIX}/..."

aws s3 ls "s3://${R2_BUCKET}/${PREFIX}/" \
  --endpoint-url "${R2_ENDPOINT}" > /tmp/r2_files.txt

LIMIT_DATE=$(date -d "-7 days" +%s)

while read -r line; do
  FILE_DATE=$(echo "$line" | awk '{print $1" "$2}')
  FILE_NAME=$(echo "$line" | awk '{print $4}')

  # ignora linhas inválidas
  if [[ -z "$FILE_NAME" ]]; then
    continue
  fi

  # 🔒 garante que só processa backups válidos
  if [[ ! "$FILE_NAME" =~ ^backup_.*\.dump$ ]]; then
    echo "⚠️ Ignorando arquivo fora do padrão: $FILE_NAME"
    continue
  fi

  FILE_TS=$(date -d "$FILE_DATE" +%s)

  if [[ $FILE_TS -lt $LIMIT_DATE ]]; then
    echo "🗑️ Removendo backup antigo: $FILE_NAME"

    aws s3 rm "s3://${R2_BUCKET}/${PREFIX}/${FILE_NAME}" \
      --endpoint-url "${R2_ENDPOINT}"
  fi
done < /tmp/r2_files.txt

echo "✅ Retenção aplicada com sucesso!"

echo "🎉 Backup finalizado!"