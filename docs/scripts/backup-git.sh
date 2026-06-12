#!/bin/bash

# ==============================================================================
# SCRIPT: Backup da Documentação para GitHub
# ==============================================================================

set -euo pipefail

SRV_DIR="/srv"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M')

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOG_FILE="/var/log/backup.log"

log_info() {
    # Imprime na tela (-a para append no arquivo)
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}
log_warn() {
    # Imprime na tela (-a para append no arquivo)    
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

cd "$SRV_DIR"

# Verificar se é repositório Git
if [[ ! -d .git ]]; then
    echo "Erro: $SRV_DIR não é um repositório Git"
    exit 1
fi

# Mensagem de commit (usa argumento ou padrão)
COMMIT_MSG="${1:-Auto-backup: $TIMESTAMP}"

# Adicionar alterações
git add .

# Verificar se há mudanças
if git diff --cached --quiet; then
    log_info "Nenhuma alteração para commitar."
    exit 0
fi

# Commit
git commit -m "$COMMIT_MSG"

# Push
if git remote | grep -q origin; then
    git push origin main
    log_info "Backup enviado para GitHub: $COMMIT_MSG"
else
    log_warn "Remote não configurado. Commit feito apenas localmente."
fi
