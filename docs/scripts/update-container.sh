#!/bin/bash
# ==============================================================================
# SCRIPT: Update Container Safe
# DESCRIÇÃO: Atualiza serviços Docker com Backup, Validação de Saúde e Rollback.
# USO: ./update-container.sh <pasta> <servico> [versao]
# ==============================================================================

set -euo pipefail

# --- CONFIGURAÇÃO ---
APPS_ROOT="/srv/apps"
DATA_ROOT="/srv/data"
BACKUP_ROOT="/srv/backups/file_archives"

# Garante que diretório de backup existe
mkdir -p "$BACKUP_ROOT"

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- VERIFICAÇÃO DE ARGUMENTOS ---
if [ $# -lt 2 ]; then
    echo "Uso: $0 <nome-pasta-app> <nome-servico-compose> [nova-versao]"
    echo "Exemplo (Update Versão): $0 traefik traefik v3.0.4"
    echo "Exemplo (Refresh Imagem): $0 traefik traefik"
    exit 1
fi

APP_NAME="$1"       # Nome da pasta em /srv/apps
SERVICE_NAME="$2"   # Nome do serviço no docker-compose.yml
NEW_VERSION="${3:-}" 

APP_DIR="$APPS_ROOT/$APP_NAME"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Variáveis de controle de estado
BACKUP_YAML_CREATED=0
ENV_UPDATED=0

# --- FUNÇÕES ---
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERRO]${NC} $1"; }

perform_rollback() {
    log_err "❌ FALHA DETECTADA. Iniciando Rollback..."
    
    # 1. Reverte docker-compose.yml
    if [ "$BACKUP_YAML_CREATED" -eq 1 ]; then
        log_warn "Restaurando docker-compose.yml original..."
        mv docker-compose.yml.bak docker-compose.yml
    fi

    # 2. Reverte .env
    if [ "$ENV_UPDATED" -eq 1 ]; then
        log_warn "Restaurando .env original..."
        mv .env.bak .env
    fi

    # 3. Recria container com configuração anterior
    log_warn "Recriando container na versão anterior..."
    docker compose up -d "$SERVICE_NAME"
    exit 1
}

# --- VALIDAÇÃO INICIAL ---
if [ ! -d "$APP_DIR" ]; then
    log_err "Diretório $APP_DIR não existe."
    exit 1
fi

echo "=== Iniciando atualização: $APP_NAME ($SERVICE_NAME) ==="

# --- 1. BACKUP DE DADOS (Crítico) ---
log_info "Etapa 1/4: Backup de dados..."

TARGET_DATA="$DATA_ROOT/$APP_NAME"
BACKUP_FILE="$BACKUP_ROOT/pre_update_${APP_NAME}-${TIMESTAMP}.tar.gz"

# Verifica se existe dados ou app para backupear
if [ -d "$TARGET_DATA" ] || [ -d "$APP_DIR" ]; then
    # O tar usa caminhos relativos (-C) para facilitar a extração futura
    tar -czf "$BACKUP_FILE" \
        -C "$(dirname "$DATA_ROOT")" "$(basename "$DATA_ROOT")/$APP_NAME" \
        -C "$(dirname "$APPS_ROOT")" "$(basename "$APPS_ROOT")/$APP_NAME" \
        2>/dev/null || log_warn "Aviso: Backup parcial (algum diretório vazio/ausente)."

    if [ -f "$BACKUP_FILE" ]; then
        log_info "Snapshot salvo em: $BACKUP_FILE"
    else
        log_err "Falha crítica: O arquivo de backup não foi criado."
        exit 1
    fi
else
    log_warn "Nenhum diretório padrão encontrado. Pulando backup de arquivos."
fi

# --- 2. EDIÇÃO DE VERSÃO (Se solicitada) ---
cd "$APP_DIR"

if [ -n "$NEW_VERSION" ]; then
    log_info "Etapa 2/4: Alterando versão para $NEW_VERSION..."

    # Tenta editar .env primeiro (Mais seguro e limpo)
    if [ -f .env ] && grep -qE "^(${SERVICE_NAME}_VERSION|VERSION|APP_VERSION)=" .env; then
        cp .env .env.bak
        sed -i -E "s/^(${SERVICE_NAME}_VERSION|VERSION|APP_VERSION)=.*/\1=$NEW_VERSION/" .env
        log_info "✅ Versão atualizada no arquivo .env"
        ENV_UPDATED=1
    # Se não, tenta editar docker-compose.yml
    elif [ -f docker-compose.yml ]; then
        cp docker-compose.yml docker-compose.yml.bak
        BACKUP_YAML_CREATED=1
        
        log_info "Editando docker-compose.yml..."
        # Substitui a imagem apenas dentro do bloco do serviço especificado
        if sed -i -e "/^[[:space:]]*${SERVICE_NAME}:/,/image:/ s|\(image: [^:]*\):.*|\1:$NEW_VERSION|" docker-compose.yml; then
            log_info "✅ Arquivo docker-compose.yml atualizado."
        else
            perform_rollback
        fi
    else
        log_warn "Não foi possível identificar onde alterar a versão automaticamente."
        exit 1
    fi
else
    log_info "Etapa 2/4: Versão não especificada. Mantendo atual (apenas pull)."
fi

# --- 3. APLICAÇÃO ---
log_info "Etapa 3/4: Baixando e recriando container..."
docker compose pull "$SERVICE_NAME"
docker compose up -d --remove-orphans "$SERVICE_NAME"

# --- 4. VALIDAÇÃO E LIMPEZA ---
log_info "Etapa 4/4: Validando (Aguardando Healthcheck ou Timeout)..."

# Tenta subir esperando ficar 'healthy' ou 'running'
if docker compose up -d --wait "$SERVICE_NAME"; then
    
    # Validação Profunda
    CONTAINER_ID=$(docker compose ps -q "$SERVICE_NAME")
    HEALTH_STATUS=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER_ID")

    if [ "$HEALTH_STATUS" == "none" ]; then
        log_warn "⚠️  Container rodando, mas SEM Healthcheck nativo."
        log_info "Executando verificação extra de estabilidade (10s)..."
        
        sleep 10
        
        # 1. Verifica se morreu (Crash Loop)
        if ! docker compose ps --filter "status=running" --services | grep -q "^${SERVICE_NAME}$"; then
            log_err "O container morreu logo após iniciar."
            perform_rollback
        fi

        # 2. Verifica logs por erros fatais
        if docker compose logs --tail 20 "$SERVICE_NAME" 2>&1 | grep -iqE "fatal|panic|exception|error"; then
             log_warn "⚠️  Palavras-chave de erro encontradas nos logs. Verifique manualmente."
             # Não fazemos rollback automático aqui pois 'error' pode ser benigno em logs, 
             # mas avisamos o admin.
        fi
        
        log_info "✅ SUCESSO: Container estável."
    else
        log_info "✅ SUCESSO: Container Healthy (Validado pelo Docker)."
    fi

    # Limpeza de arquivos temporários de backup
    [ "$BACKUP_YAML_CREATED" -eq 1 ] && rm docker-compose.yml.bak
    [ "$ENV_UPDATED" -eq 1 ] && rm .env.bak

else
    # Se o comando 'up --wait' falhar (timeout ou exit code 1)
    perform_rollback
fi

echo ""
log_info "Atualização concluída com sucesso."
