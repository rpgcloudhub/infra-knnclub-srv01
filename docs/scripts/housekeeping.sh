#!/bin/bash
# ==============================================================================
# SCRIPT: Housekeeping (Limpeza Semanal)
# MONITORAMENTO: Telegram + Uptime Kuma (Push)
# ==============================================================================

set -euo pipefail

# --- CONFIGURAÇÃO ---
ENV_FILE="/srv/docs/scripts/housekeeping.env"
LOG_DIR="/srv/logs/housekeeping"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/cleanup-$(date +%F).log"
DATE_NOW=$(date '+%Y-%m-%d %H:%M:%S')

# Validação do arquivo de ambiente
if [[ ! -f "$ENV_FILE" ]]; then
    ERR_MSG="❌ ERRO CRÍTICO: Arquivo de configuração '$ENV_FILE' não encontrado."
    echo "$ERR_MSG" >&2
    echo "$ERR_MSG" >> "$LOG_FILE" 2>/dev/null || true
    exit 1
fi

source "$ENV_FILE"

# --- FUNÇÃO DE TRATAMENTO DE ERRO ---
on_failure() {
    echo "❌ FALHA CRÍTICA! Notificando..."
    
    # 1. Avisa Telegram
    if [ -n "${TELEGRAM_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
        MSG="🚨 *ERRO: HOUSEKEEPING FALHOU* %0AHost: $(hostname)%0AVerifique: $LOG_FILE"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            -d chat_id="${TELEGRAM_CHAT_ID}" -d parse_mode="Markdown" -d text="$MSG" > /dev/null
    fi

    # 2. Avisa Kuma (Derruba o monitor imediatamente)
    if [ -n "${KUMA_URL:-}" ]; then
        curl -fsS -m 10 "${KUMA_URL}&status=down&msg=ERRO_SCRIPT" > /dev/null
    fi
    
    exit 1
}

# Ativa a armadilha
trap 'on_failure' ERR

# --- INÍCIO DA LIMPEZA ---
{
    echo "========================================"
    echo "HOUSEKEEPING START: $DATE_NOW"
    echo "========================================"
    
    # Cálculo de Espaço (Coluna 4 = Available no padrão GNU df)
    # Se der erro no df, queremos saber, então sem || true
    SPACE_BEFORE=$(df / | awk 'NR==2 {print $4}')
    echo ">>> Espaço Disponível ANTES: $(numfmt --to=iec --from-unit=1K $SPACE_BEFORE)"
    echo ""

    # 1. DOCKER
    # Removido '|| true'. Se o Docker estiver travado, TEM que dar erro e avisar.
    echo ">>> [1] Limpeza Docker..."
    if command -v docker &> /dev/null; then
        docker system prune -f
        docker image prune -a --filter "until=336h" -f
        echo "Docker limpo."
    else
        echo "Docker não instalado ou não encontrado."
    fi
    echo ""

    # 2. JOURNALD
    echo ">>> [2] Otimizando Journald..."
    journalctl --vacuum-size=500M
    journalctl --vacuum-time=2weeks
    echo ""

    # 3. CACHE DE PACOTES
    echo ">>> [3] Limpando Cache de Pacotes..."
    if command -v apt-get &> /dev/null; then
        apt-get clean && apt-get autoremove -y
    elif command -v dnf &> /dev/null; then
        dnf clean all && dnf autoremove -y
    fi
    echo ""

    # 4. ARQUIVOS TEMPORÁRIOS
    # Aqui usamos '|| true' estrategicamente apenas no find, pois as vezes
    # arquivos somem durante a execução, causando erro falso positivo.
    echo ">>> [4] Limpando /tmp (arquivos > 7 dias)..."
    find /tmp -type f -atime +7 -delete 2>/dev/null || true
    find /tmp -type d -empty -delete 2>/dev/null || true
    echo "/tmp limpo."
    echo ""

    # 5. LOGS ANTIGOS DO SISTEMA
    echo ">>> [5] Removendo logs antigos compactados (> 30 dias)..."
    find /var/log -name "*.gz" -mtime +30 -delete 2>/dev/null || true
    find /var/log -name "*.old" -mtime +30 -delete 2>/dev/null || true
    find /var/log -name "*.1" -mtime +30 -delete 2>/dev/null || true
    echo "Logs do sistema limpos."
    echo ""

    # Cálculo Final
    SPACE_AFTER=$(df / | awk 'NR==2 {print $4}')
    echo ">>> Espaço Disponível DEPOIS: $(numfmt --to=iec --from-unit=1K $SPACE_AFTER)"
    echo ""
    
    FREED=$((SPACE_AFTER - SPACE_BEFORE))
    
    # Tratamento para não mostrar números negativos se algo escreveu no disco durante a limpeza
    if [ "$FREED" -gt 0 ]; then
        HUMAN_FREED=$(numfmt --to=iec --from-unit=1K $FREED)
        echo "✅ Espaço liberado: ~$HUMAN_FREED"
    else
        echo "✅ Limpeza concluída (Nenhum ganho significativo de espaço)"
    fi

    echo "========================================"
    echo "HOUSEKEEPING CONCLUÍDO"
    echo "========================================"

} | tee -a "$LOG_FILE"

# 6. SUCESSO (Avisa Kuma que está tudo bem)
if [ -n "${KUMA_URL:-}" ]; then
    curl -fsS -m 10 "${KUMA_URL}&status=up&msg=OK" > /dev/null
fi

# 7. AUTO-LIMPEZA
find "$LOG_DIR" -name "cleanup-*.log" -mtime +60 -delete 2>/dev/null || true
