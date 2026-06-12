#!/bin/bash

# ==============================================================================
# SCRIPT: Backup Automatizado Restic + Cópia Local Intermediária
# VERSÃO: 3.0 (Com Compressão Local .tar.gz)
# ==============================================================================

set -euo pipefail
# -e: parar se houver erros; 
# -u: parar se variáveis não definidas; 
# -o pipefail: parar se qualquer comando no pipe falhar.

# Arquivo de configuração externo
CONFIG_FILE="/srv/docs/scripts/backup.conf"
LOG_FILE="/var/log/backup.log"

# ------------------------------------------------------------------------------
# 1. CARREGAR CONFIGURAÇÃO
# ------------------------------------------------------------------------------

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Erro Crítico: Arquivo de configuração $CONFIG_FILE não encontrado." >&2
    exit 1
fi

# Carrega as variáveis de forma segura e nativa
source "$CONFIG_FILE"

# Definições derivadas (não precisam estar no config)
DUMP_DIR="${LOCAL_BACKUP_ROOT}/db_dumps"
FILES_ARCHIVE_DIR="${LOCAL_BACKUP_ROOT}/file_archives"

# ------------------------------------------------------------------------------
# 2. FUNÇÕES DE LOG E UTILITÁRIOS
# ------------------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local level=$1
    local msg=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${msg}" | tee -a "$LOG_FILE"
}

log_info()  { log "${GREEN}INFO${NC}" "$1"; }
log_warn()  { log "${YELLOW}WARN${NC}" "$1"; }
log_error() { log "${RED}ERROR${NC}" "$1"; }

# --- INTEGRAÇÃO UPTIME KUMA ---
send_kuma_success() {
    # Só executa se a variável NÃO estiver vazia
    if [[ -n "${KUMA_URL:-}" ]]; then
        log_info "Notificando Uptime Kuma (Sucesso)..."
        # --retry 3: tenta 3 vezes se se o envio falhar
        curl -fsS -m 10 --retry 3 "$KUMA_URL" > /dev/null || log_warn "Falha ao contactar Uptime Kuma"
    fi
}

error_handler() {
    local line_no=$1
    log_error "O script FALHOU inesperadamente na linha $line_no."

    # Envia para o Telegram APENAS se Token E ChatID estiverem configurados
    if [[ -n "${TELEGRAM_TOKEN:-}" ]] && [[ -n "${TELEGRAM_CHAT_ID:-}" ]]; then
        log_info "Enviando alerta para Telegram..."
        
        # O '|| true' no final é vital: se o Telegram estiver fora do ar, 
        # o script não trava aqui e consegue dar o exit 1 corretamente.
        curl -s -X POST \
            "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" \
            -d parse_mode="Markdown" \
            -d text="❌ *FALHA CRÍTICA DE BACKUP* %0AHost: $(hostname) %0ALinha do Erro: $line_no %0AData: $(date '+%Y-%m-%d %H:%M:%S')" \
            > /dev/null || true
    fi
        
    exit 1
}

# TRAP: Se qualquer comando falhar (exceto em ifs), pula para error_handler
trap 'error_handler $LINENO' ERR

# ------------------------------------------------------------------------------
# 3. PREPARAÇÃO
# ------------------------------------------------------------------------------

# VALIDAÇÃO DE CREDENCIAIS
# ==============================================================================
# 1. Verifica variáveis COMUNS (Obrigatórias para todos)
if [[ -z "${RESTIC_REPOSITORY:-}" ]]; then
    log_error "Erro Crítico: RESTIC_REPOSITORY não definida."
    exit 1
fi

if [[ -z "${RESTIC_PASSWORD:-}" ]]; then
    log_error "Erro Crítico: RESTIC_PASSWORD não definida."
    exit 1
fi

# 2. Detecta o provedor e verifica as específicas
if [[ "$RESTIC_REPOSITORY" == b2:* ]]; then
    # --- MODO BACKBLAZE B2 ---
    if [[ -z "${B2_ACCOUNT_ID:-}" ]]; then
        log_error "Erro: Repositório B2 detectado, mas B2_ACCOUNT_ID não definida."
        exit 1
    fi
    if [[ -z "${B2_ACCOUNT_KEY:-}" ]]; then
        log_error "Erro: Repositório B2 detectado, mas B2_ACCOUNT_KEY não definida."
        exit 1
    fi
    log_info "Provedor Detectado: Backblaze B2"

elif [[ "$RESTIC_REPOSITORY" == s3:* ]]; then
    # --- MODO S3 / CLOUDFLARE R2 ---
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
        log_error "Erro: Repositório S3/R2 detectado, mas AWS_ACCESS_KEY_ID não definida."
        exit 1
    fi
    if [[ -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        log_error "Erro: Repositório S3/R2 detectado, mas AWS_SECRET_ACCESS_KEY não definida."
        exit 1
    fi
    log_info "Provedor Detectado: S3-Compatível (Cloudflare R2 / AWS)"

else
    # --- FORMATO DESCONHECIDO ---
    log_error "Formato de repositório desconhecido: $RESTIC_REPOSITORY"
    log_error "Use o formato 'b2:bucket' ou 's3:https://endpoint/bucket'"
    exit 1
fi
# ==============================================================================

# Cria diretórios locais se não existirem
if [ ! -d "$DUMP_DIR" ]; then
    mkdir -p "$DUMP_DIR"
    mkdir -p "$FILES_ARCHIVE_DIR"
    log_info "Diretórios de backup local criados."
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
log_info "=== INICIANDO ROTINA DE BACKUP V3.0 ==="

# ------------------------------------------------------------------------------
# 4. DUMP DE BANCOS DE DADOS (Compressão GZIP)
# ------------------------------------------------------------------------------
log_info "Etapa 1/6: Exportando bancos de dados..."

# Função modular para evitar repetição de código
dump_and_check() {
    local container=$1
    local type=$2
    local outfile="$DUMP_DIR/${container}_${TIMESTAMP}.sql.gz"

    log_info "Dump $type: $container"
    local cmd=""
    
    # --- LÓGICA POSTGRESQL ---
    if [[ "$type" == "Postgres" ]]; then
        # Descobre o usuário (Ex: drmuser)
        local pg_user=$(docker exec "$container" printenv POSTGRES_USER)
        if [[ -z "$pg_user" ]]; then pg_user="postgres"; fi
        
        # O SEGREDO: '-l postgres' força conexão no banco padrão
        cmd="docker exec $container pg_dumpall -U $pg_user -l postgres"

    # --- LÓGICA MYSQL / MARIADB ---
    elif [[ "$type" == "MySQL" ]]; then
        # Descobre se é mariadb-dump ou mysqldump
        local dump_bin="mysqldump"
        if docker exec "$container" command -v mariadb-dump > /dev/null 2>&1; then
            dump_bin="mariadb-dump"
        elif docker exec "$container" command -v mysqldump > /dev/null 2>&1; then
            dump_bin="mysqldump"
        else
            log_warn "Nenhum binário de dump encontrado em $container"
            return 1
        fi

        # Descobre a senha
        local db_pass=$(docker exec "$container" printenv MYSQL_ROOT_PASSWORD)
        if [[ -z "$db_pass" ]]; then
            db_pass=$(docker exec "$container" printenv MARIADB_ROOT_PASSWORD)
        fi

        # Monta comando
        if [[ -n "$db_pass" ]]; then
            cmd="docker exec $container $dump_bin -u root -p$db_pass --all-databases"
        else
            cmd="docker exec $container $dump_bin -u root --all-databases"
        fi
    fi

    # --- EXECUÇÃO E VALIDAÇÃO ---
    if $cmd 2>/dev/null | gzip > "$outfile"; then
        # Validação Nível 2: Estrutura GZIP e Tamanho Mínimo
        if gzip -t "$outfile"; then
             local size=$(stat -c%s "$outfile")
             if [[ $size -gt 100 ]]; then
                log_info "Integridade OK: $container ($size bytes)"
             else
                log_error "❌ ARQUIVO SUSPEITO ($size bytes): $outfile. Verifique usuário/senha."
                rm "$outfile"
                return 1
             fi
        else
            log_error "❌ ARQUIVO GZIP CORROMPIDO: $outfile."
            rm "$outfile"
            return 1
        fi
    else
        log_warn "Falha fatal ao executar comando no container $container."
        rm -f "$outfile"
    fi
}

# --- SELEÇÃO INTELIGENTE DE CONTAINERS (POR IMAGEM) ---
# Auto-discovery de containers
for c in $(docker ps --format '{{.Names}}' | grep -iE 'postgres|postgis'); do dump_and_check "$c" "Postgres"; done
for c in $(docker ps --format '{{.Names}}' | grep -iE 'mysql|mariadb'); do dump_and_check "$c" "MySQL"; done

# ------------------------------------------------------------------------------
# 5. LIMPEZA LOCAL (Housekeeping) - FEITO ANTES DA CÓPIA
# ------------------------------------------------------------------------------
# Fazemos a limpeza ANTES de criar o novo arquivo para liberar espaço.
log_info "Etapa 2/6: Limpando backups locais antigos (> $LOCAL_RETENTION_DAYS dias)..."

# O '|| true' evita que o script pare se não encontrar arquivos para deletar
find "$DUMP_DIR" -name "*.sql.gz" -mtime +$LOCAL_RETENTION_DAYS -delete || true
find "$FILES_ARCHIVE_DIR" -name "*.tar.gz" -mtime +$LOCAL_RETENTION_DAYS -delete || true

# ------------------------------------------------------------------------------
# 6. CÓPIA LOCAL DE ARQUIVOS (TAR.GZ) COM PROTEÇÃO DE DISCO
# ------------------------------------------------------------------------------
# Isso garante que você tenha um arquivo único localmente para 
# recuperação rápida sem internet.
log_info "Etapa 3/6: Verificando espaço para compactação local..."

ARCHIVE_NAME="data_files_${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${FILES_ARCHIVE_DIR}/${ARCHIVE_NAME}"

# Estima tamanho necessário (Soma das duas fontes)
SIZE_DATA=$(du -s "$DATA_SOURCE" | awk '{print $1}')
SIZE_APPS=$(du -s "$APPS_SOURCE" | awk '{print $1}')
TOTAL_SIZE=$((SIZE_DATA + SIZE_APPS))

# Espaço livre
FREE_SPACE=$(df "$FILES_ARCHIVE_DIR" | tail -1 | awk '{print $4}')

# Se espaço livre for menor que o tamanho da fonte (assumindo compressão ruim para segurança)
if [[ $FREE_SPACE -lt $TOTAL_SIZE ]]; then
    log_warn "⚠️  ESPAÇO INSUFICIENTE para criar tar.gz local."
    log_warn "Necessário: ${TOTAL_SIZE}KB, Livre: ${FREE_SPACE}KB."
    log_warn "Pulando criação de arquivo local, mas prosseguindo com upload para nuvem."
else
    log_info "Criando arquivo compactado local..."
    # MUDANÇA: Backup relativo a /srv para pegar data e apps juntos
    tar -czf "$ARCHIVE_PATH" \
        -C "$(dirname "$DATA_SOURCE")" "$(basename "$DATA_SOURCE")" \
        -C "$(dirname "$APPS_SOURCE")" "$(basename "$APPS_SOURCE")" \
        || log_warn "Falha não-crítica no tar local"
    
    if [[ -f "$ARCHIVE_PATH" ]]; then
        log_info "Arquivo local criado: $ARCHIVE_PATH"
    fi
fi

# ------------------------------------------------------------------------------
# 7. UPLOAD PARA NUVEM (RESTIC)
# ------------------------------------------------------------------------------
log_info "Etapa 4/6: Inicializando Repositório Remoto..."
restic init 2>/dev/null || true

log_info "Etapa 5/6: Enviando dados para Backblaze B2..."

# ESTRATÉGIA HÍBRIDA:
# 1. Enviamos os Dumps de Banco (que já são arquivos fechados).
# 2. Enviamos a pasta original /srv/data (para aproveitar a DEDUPLICAÇÃO do Restic).
# NOTA: Não enviamos o 'tar.gz' gerado na etapa 5 para a nuvem, pois mataria a eficiência do Restic.
# O tar.gz fica apenas como backup LOCAL.

restic backup \
    "$DATA_SOURCE" \
    "$APPS_SOURCE" \
    "$DUMP_DIR" \
    --exclude="*.log" \
    --exclude="**/cache/*" \
    --exclude="**/tmp/*" \
    --tag "automated" \
    --tag "$(hostname)" \
    2>&1 | tee -a "$LOG_FILE"

# ------------------------------------------------------------------------------
# 8. MANUTENÇÃO REMOTA
# ------------------------------------------------------------------------------
log_info "Etapa 6/6: Verificação e Limpeza Remota..."

# Check de integridade (5% aleatório)
restic check --read-data-subset=5% 2>&1 | tee -a "$LOG_FILE"
## Testa se o backup armazenado na nuvem é legível e descriptografável.

# Limpeza de snapshots antigos no Object Storage
restic forget \
    --keep-daily $KEEP_DAILY \
    --keep-weekly $KEEP_WEEKLY \
    --keep-monthly $KEEP_MONTHLY \
    --prune \
    2>&1 | tee -a "$LOG_FILE"

# ------------------------------------------------------------------------------
# FIM
# ------------------------------------------------------------------------------
log_info "=== BACKUP CONCLUÍDO ==="
log_info "Uso do Repositório:"
restic stats 2>&1 | tee -a "$LOG_FILE"

# Se chegou aqui sem erros, avisa o Kuma
send_kuma_success
