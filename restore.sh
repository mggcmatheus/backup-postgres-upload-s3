#!/usr/bin/env bash

set -euo pipefail

echo "🚀 Iniciando restore no STAGE..."

PREFIX="billings-ease-prod-bkp/prod"
FILEPATH="/tmp/restore.dump"

export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"

# =========================
# Buscar último backup (ROBUSTO)
# =========================
echo "🔎 Buscando último backup..."

LATEST_FILE=$(aws s3api list-objects-v2 \
  --bucket "$R2_BUCKET" \
  --prefix "$PREFIX/" \
  --endpoint-url "$R2_ENDPOINT" \
  --query 'sort_by(Contents, &LastModified)[-1].Key' \
  --output text)

if [[ -z "$LATEST_FILE" || "$LATEST_FILE" == "None" ]]; then
  echo "❌ Nenhum backup encontrado"
  exit 1
fi

echo "📦 Último backup: ${LATEST_FILE}"

# =========================
# Download
# =========================
echo "⬇️ Baixando backup..."

aws s3 cp \
  "s3://${R2_BUCKET}/${LATEST_FILE}" \
  "${FILEPATH}" \
  --endpoint-url "${R2_ENDPOINT}"

# valida arquivo
if [[ ! -s "${FILEPATH}" ]]; then
  echo "❌ Download inválido (arquivo vazio ou não encontrado)"
  exit 1
fi

ls -lh "${FILEPATH}"
echo "✅ Download concluído"

# =========================
# Derrubar conexões
# =========================
echo "🔪 Encerrando conexões ativas..."

psql "$DATABASE_URL" -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = current_database()
AND pid <> pg_backend_pid();
"

# =========================
# Limpar banco
# =========================
echo "🧹 Limpando schema..."

psql "$DATABASE_URL" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

# =========================
# Restore
# =========================
echo "♻️ Restaurando backup..."

timeout 10m pg_restore \
  --no-owner \
  --no-privileges \
  --clean \
  --if-exists \
  -d "$DATABASE_URL" \
  "${FILEPATH}"

echo "✅ Restore concluído"

# =========================
# Limpeza
# =========================
rm -f "${FILEPATH}"
echo "🧹 Arquivo local removido"

echo "🎉 STAGE atualizado com sucesso!"