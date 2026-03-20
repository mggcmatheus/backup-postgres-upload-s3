# 🚀 PostgreSQL Backup to R2 (S3 Compatible)

Backup automatizado de PostgreSQL com upload para Cloudflare R2 (ou qualquer storage compatível com S3), com retenção automática.

Projetado para rodar em ambientes como **Railway, Docker, Cron Jobs ou CI/CD**.

---

## ✨ Features

- 📦 Backup PostgreSQL (`pg_dump` custom format)
- ☁️ Upload para R2 / S3
- 🔁 Retry automático (banco + upload)
- 🧹 Retenção automática (7 dias)
- ⚡ Leve (Alpine + AWS CLI)
- 🔐 Seguro (não remove arquivos fora do padrão)
- 🐳 Pronto para Docker / Railway

---

## 📁 Estrutura

```
.
├── Dockerfile
└── backup.sh
```

---

## ⚙️ Variáveis de Ambiente

### 🗄️ PostgreSQL

```
PGDATABASE=
PGHOST=
PGPASSWORD=
PGPORT=
PGUSER=
```

### ☁️ R2 / S3

```
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
R2_BUCKET=
R2_ENDPOINT=
```

---

## 🐳 Uso com Docker

### Build

```
docker build -t postgres-backup .
```

### Run

```
docker run --rm \
  -e PGDATABASE=... \
  -e PGHOST=... \
  -e PGPASSWORD=... \
  -e PGPORT=... \
  -e PGUSER=... \
  -e R2_ACCESS_KEY_ID=... \
  -e R2_SECRET_ACCESS_KEY=... \
  -e R2_BUCKET=... \
  -e R2_ENDPOINT=... \
  postgres-backup
```

---

## ⏱️ Uso com Cron (ex: Railway)

```
0 * * * *
```

---

## 📦 Formato do Backup

```
backup_YYYY-MM-DD_HH-MM-SS.dump
```

Exemplo:

```
prod/backup_2026-03-20_10-02-59.dump
```

---

## 🔄 Retenção

- Mantém apenas **últimos 7 dias**
- Remove automaticamente arquivos antigos
- Só remove arquivos que seguem o padrão:

```
backup_*.dump
```

---

## ♻️ Restore

```
pg_restore -U postgres \
  -d seu_banco \
  --no-owner --no-privileges \
  backup.dump
```

---

## 🧠 Como funciona

```
Container inicia
   ↓
Testa conexão com banco
   ↓
Gera dump
   ↓
Upload para R2
   ↓
Remove arquivo local
   ↓
Aplica retenção
   ↓
Finaliza
```

---

## ⚠️ Requisitos

- PostgreSQL ≥ versão do `pg_dump`
- R2 ou S3 compatível
- Acesso de rede ao banco

---

## 💡 Recomendações

Use prefixos por ambiente:

```
prod/
stage/
dev/
```

---

## 📜 Licença

MIT
