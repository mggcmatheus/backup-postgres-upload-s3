#!/usr/bin/env bash

set -e

echo "🚀 Iniciando backup PostgreSQL..."

DATE=$(date +"%Y-%m-%d_%H-%M-%S")
FILENAME="backup_${DATE}.dump"
PREFIX="prod"
FILEPATH="/tmp/${FILENAME}"

export PGPASSWORD="$PGPASSWORD"

# =========================
# Teste de conexão com retry
# =========================
echo "🔎 Testando conexão com banco..."

for i in {1..5}; do
  if pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER"; then
    echo "✅ Banco disponível"
    break
  fi
  echo "⏳ Tentativa $i falhou... aguardando"
  sleep 2
done

# =========================
# Dump do banco
# =========================
echo "📦 Gerando dump..."

pg_dump \
  -h "$PGHOST" \
  -p "$PGPORT" \
  -U "$PGUSER" \
  -d "$PGDATABASE" \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file="${FILEPATH}"

echo "✅ Dump gerado: ${FILEPATH}"

# =========================
# Upload com retry
# =========================
echo "☁️ Enviando para R2..."

export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"

for i in {1..5}; do
  if aws s3 cp "${FILEPATH}" \
    "s3://${R2_BUCKET}/${PREFIX}/${FILENAME}" \
    --endpoint-url "${R2_ENDPOINT}"; then
    echo "✅ Upload concluído"
    break
  fi
  echo "⏳ Upload falhou, tentativa $i..."
  sleep 2
done

# =========================
# Limpeza local
# =========================
rm -f "${FILEPATH}"
echo "🧹 Arquivo local removido"

# =========================
# RETENÇÃO (7 dias)
# =========================
echo "🧠 Aplicando retenção (7 dias)..."

LIMIT_DATE=$(date +%s)
LIMIT_DATE=$((LIMIT_DATE - 7*24*60*60))

aws s3 ls "s3://${R2_BUCKET}" --recursive \
  --endpoint-url "${R2_ENDPOINT}" | grep "${PREFIX}/" > /tmp/r2_files.txt || true

while read -r line; do
  FILE_DATE=$(echo "$line" | awk '{print $1" "$2}')
  FILE_NAME=$(echo "$line" | awk '{print $4}')

  if [[ -z "$FILE_NAME" ]]; then
    continue
  fi

  # só remove arquivos válidos
  if [[ ! "$FILE_NAME" =~ ^${PREFIX}/backup_.*\.dump$ ]]; then
    continue
  fi

  FILE_TS=$(date -d "$FILE_DATE" +%s 2>/dev/null || echo 0)

  if [[ $FILE_TS -lt $LIMIT_DATE ]]; then
    echo "🗑️ Removendo: $FILE_NAME"

    aws s3 rm "s3://${R2_BUCKET}/${FILE_NAME}" \
      --endpoint-url "${R2_ENDPOINT}"
  fi
done < /tmp/r2_files.txt

echo "✅ Retenção aplicada"

echo "🎉 Backup finalizado!"