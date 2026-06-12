#!/bin/bash
# ==============================================================================
# SCRIPT: Monitoramento de Updates e Reboot (Híbrido: Ubuntu/Debian + Alma/RHEL)
# ==============================================================================
# Funcionalidade:
# 1. Verifica se houve atualizações HOJE.
# 2. Verifica se o sistema pede REBOOT.
# 3. Envia notificação única para o Uptime Kuma com o status mais crítico.
#
# Idempotente: Pode rodar múltiplas vezes sem efeitos colaterais.
# ==============================================================================

set -uo pipefail

# --- CONFIGURAÇÃO ---
TOKEN_FILE=/srv/docs/scripts/kuma-updates-token.conf; [ -f $TOKEN_FILE ] && source $TOKEN_FILE; KUMA_URL="${KUMA_URL:-}"

# --- VARIÁVEIS INTERNAS ---
TODAY=$(date +%Y-%m-%d)
MSG=""
STATUS="up"
HAS_UPDATES=0
NEEDS_REBOOT=0
UPDATE_COUNT=0
PACKAGE_LIST=""

# ------------------------------------------------------------------------------
# 1. DETECTAR ATUALIZAÇÕES (Lógica Híbrida)
# ------------------------------------------------------------------------------

# >>>> CENÁRIO UBUNTU / DEBIAN
if [ -f /var/log/unattended-upgrades/unattended-upgrades.log ]; then
    LOG_FILE="/var/log/unattended-upgrades/unattended-upgrades.log"
    
    UPDATE_COUNT=$(grep -c "$TODAY.*Packages that will be upgraded" "$LOG_FILE" 2>/dev/null || true)
    
    if [ "$UPDATE_COUNT" -gt 0 ]; then
        HAS_UPDATES=1
        PACKAGE_LIST=$(grep "$TODAY" "$LOG_FILE" | grep -A1 "Packages that will be upgraded" | tail -1 | head -c 50 | tr -d '\n')
    fi

# >>>> CENÁRIO ALMALINUX / RHEL / ROCKY
elif [ -f /var/log/dnf.rpm.log ]; then
    LOG_FILE="/var/log/dnf.rpm.log"
    
    UPDATE_COUNT=$(grep -c "$TODAY.*\(Upgraded:\|Installed:\)" "$LOG_FILE" 2>/dev/null || true)
    
    if [ "$UPDATE_COUNT" -gt 0 ]; then
        HAS_UPDATES=1
        PACKAGE_LIST=$(grep "$TODAY" "$LOG_FILE" | grep -E "Upgraded:|Installed:" | tail -3 | awk '{print $NF}' | tr '\n' ' ' | head -c 50)
    fi
fi

# ------------------------------------------------------------------------------
# 2. DETECTAR NECESSIDADE DE REBOOT (Lógica Híbrida)
# ------------------------------------------------------------------------------

# Método Ubuntu/Debian
if [ -f /var/run/reboot-required ]; then
    NEEDS_REBOOT=1

# Método AlmaLinux/RHEL (pacote yum-utils)
elif command -v needs-restarting &> /dev/null; then
    # Exit 0 = NÃO precisa reboot, Exit 1 = PRECISA reboot
    if ! needs-restarting -r &> /dev/null; then
        NEEDS_REBOOT=1
    fi
fi

# ------------------------------------------------------------------------------
# 3. CONSTRUIR MENSAGEM E ENVIAR
# ------------------------------------------------------------------------------

# Prioridade 1: Reboot (Crítico)
if [ "$NEEDS_REBOOT" -eq 1 ]; then
    STATUS="down"
    MSG="REBOOT PENDENTE (Updates hoje: $UPDATE_COUNT)"

# Prioridade 2: Updates Aplicados (Informativo)
elif [ "$HAS_UPDATES" -eq 1 ]; then
    STATUS="up"
    MSG="Updates aplicados: ${PACKAGE_LIST:-$UPDATE_COUNT pacotes}"

# Prioridade 3: Tudo calmo (Heartbeat)
else
    STATUS="up"
    MSG="Sistema OK (Sem updates hoje)"
fi

# Codificar espaços para URL
FINAL_MSG=$(echo "$MSG" | sed 's/ /+/g; s/:/%3A/g; s/(/%28/g; s/)/%29/g')

# Enviar para o Kuma
if [[ -n "$KUMA_URL" && "$KUMA_URL" != *"SEU_TOKEN"* ]]; then
    curl -fsS -m 10 --retry 3 "${KUMA_URL}?status=${STATUS}&msg=${FINAL_MSG}&ping=" > /dev/null 2>&1
    exit $?
else
    echo "[$STATUS] $MSG"
    echo "KUMA_URL não configurada. Configure a variável ou edite o script."
    exit 0
fi
