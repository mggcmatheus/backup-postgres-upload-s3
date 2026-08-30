#!/usr/bin/env bash
#
# Backup do PostgreSQL para R2 (ou qualquer storage compatível com S3).
#
# Regra que orienta o script inteiro: um backup que falha em silêncio é pior do
# que backup nenhum, porque produz confiança sem cobertura. Toda falha aqui sai
# com código diferente de zero e mensagem, para o agendador registrar.

set -euo pipefail

PREFIX="${BACKUP_PREFIX:-prod}"
RETENCAO_DIAS="${BACKUP_RETENTION_DAYS:-7}"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
FILENAME="backup_${DATE}.dump"
FILEPATH="/tmp/${FILENAME}"
CHAVE="${PREFIX}/${FILENAME}"

erro() { echo "❌ $*" >&2; exit 1; }

echo "🚀 Iniciando backup PostgreSQL..."

# =========================
# Variáveis obrigatórias
#
# Com `set -u` uma variável ausente aborta no meio do trabalho, com mensagem do
# bash. Conferir antes dá mensagem útil e falha antes de gastar um pg_dump.
# =========================
for var in PGDATABASE PGHOST PGPORT PGUSER PGPASSWORD \
           R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET R2_ENDPOINT; do
  [[ -n "${!var:-}" ]] || erro "variável obrigatória não definida: ${var}"
done

export PGPASSWORD
export AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}"

# =========================
# Teste de conexão com retry
#
# Esgotar as tentativas ABORTA. Antes o laço apenas terminava e o script partia
# para o pg_dump assim mesmo, contra um banco que sabidamente não respondia.
# =========================
echo "🔎 Testando conexão com banco..."

CONECTOU=0
for i in {1..5}; do
  if pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER"; then
    echo "✅ Banco disponível"
    CONECTOU=1
    break
  fi
  echo "⏳ Tentativa $i falhou... aguardando"
  sleep 2
done

[[ "$CONECTOU" -eq 1 ]] || erro "banco indisponível após 5 tentativas. Backup NÃO foi gerado."

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

# pg_dump pode sair 0 e deixar arquivo vazio em caso de disco cheio no /tmp.
[[ -s "${FILEPATH}" ]] || erro "o dump saiu vazio (${FILEPATH}). Backup inválido."

TAMANHO=$(stat -c %s "${FILEPATH}")
echo "✅ Dump gerado: ${FILEPATH} (${TAMANHO} bytes)"

# =========================
# Upload com retry
#
# Esgotar as tentativas ABORTA e PRESERVA o arquivo local. Antes o laço
# terminava, o script seguia para o `rm`, apagava o dump e saía com código 0 —
# o backup sumia e o agendador reportava sucesso.
# =========================
echo "☁️ Enviando para R2..."

ENVIOU=0
for i in {1..5}; do
  if aws s3 cp "${FILEPATH}" \
    "s3://${R2_BUCKET}/${CHAVE}" \
    --endpoint-url "${R2_ENDPOINT}"; then
    ENVIOU=1
    break
  fi
  echo "⏳ Upload falhou, tentativa $i..."
  sleep 2
done

if [[ "$ENVIOU" -eq 0 ]]; then
  erro "upload falhou após 5 tentativas. O dump foi MANTIDO em ${FILEPATH} — copie antes de o container sumir."
fi

# =========================
# Confirmação de existência
#
# `aws s3 cp` sair 0 diz que o comando terminou, não que o objeto está lá com o
# tamanho certo. Confirmar custa uma chamada e é o que separa "achamos que tem
# backup" de "tem backup".
# =========================
echo "🔍 Confirmando o objeto no destino..."

TAMANHO_REMOTO=$(aws s3api head-object \
  --bucket "${R2_BUCKET}" \
  --key "${CHAVE}" \
  --endpoint-url "${R2_ENDPOINT}" \
  --query 'ContentLength' \
  --output text 2>/dev/null || echo "ausente")

if [[ "$TAMANHO_REMOTO" != "$TAMANHO" ]]; then
  erro "o objeto s3://${R2_BUCKET}/${CHAVE} não confere: local ${TAMANHO} bytes, remoto ${TAMANHO_REMOTO}. O dump foi MANTIDO em ${FILEPATH}."
fi

echo "✅ Upload confirmado: s3://${R2_BUCKET}/${CHAVE} (${TAMANHO_REMOTO} bytes)"

# =========================
# Limpeza local
# =========================
rm -f "${FILEPATH}"
echo "🧹 Arquivo local removido"

# =========================
# RETENÇÃO
#
# Só depois do backup confirmado — apagar antigo antes de garantir o novo é
# como se ficaria sem nenhum. Falha aqui avisa mas não reprova o backup, que já
# está seguro no destino.
# =========================
echo "🧠 Aplicando retenção (${RETENCAO_DIAS} dias)..."

aplicar_retencao() {
  local limite
  limite=$(( $(date +%s) - RETENCAO_DIAS * 24 * 60 * 60 ))

  aws s3 ls "s3://${R2_BUCKET}/${PREFIX}/" --recursive \
    --endpoint-url "${R2_ENDPOINT}" > /tmp/r2_files.txt || return 1

  while read -r linha; do
    local data nome ts
    data=$(echo "$linha" | awk '{print $1" "$2}')
    nome=$(echo "$linha" | awk '{print $4}')

    [[ -n "$nome" ]] || continue
    # Só remove o que este script escreve. Qualquer outra coisa no bucket fica.
    [[ "$nome" =~ ^${PREFIX}/backup_.*\.dump$ ]] || continue

    ts=$(date -d "$data" +%s 2>/dev/null || echo 0)
    if [[ "$ts" -lt "$limite" && "$ts" -ne 0 ]]; then
      echo "🗑️ Removendo: $nome"
      aws s3 rm "s3://${R2_BUCKET}/${nome}" --endpoint-url "${R2_ENDPOINT}" || true
    fi
  done < /tmp/r2_files.txt
}

if aplicar_retencao; then
  echo "✅ Retenção aplicada"
else
  echo "⚠️ Retenção falhou — o backup desta execução está salvo. Arquivos antigos podem estar acumulando."
fi

echo "🎉 Backup finalizado!"
