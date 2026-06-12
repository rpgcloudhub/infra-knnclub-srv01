#!/bin/bash
# ==============================================================================
# SCRIPT: Daily Briefing (Auditoria Diária Unificada)
# DESCRIÇÃO: Coleta logs SSH, Sudo, Saúde Docker Completa, Git Drift, Checksums.
# COMPATIBILIDADE: Ubuntu / Debian / AlmaLinux / RHEL
# ==============================================================================

set -uo pipefail

# --- CONFIGURAÇÃO ---
ENV_FILE="/srv/docs/scripts/auditoria.env"
LOG_DIR="/srv/logs/auditoria"
BASELINE_FILE="/srv/docs/integrity/system.sha256"

mkdir -p "$LOG_DIR"
CURRENT_LOG="$LOG_DIR/audit-$(date +%F).log"

# Carrega variáveis
if [ -f "$ENV_FILE" ]; then source "$ENV_FILE"; fi

# Defaults
LIMIT_FAILED=${LIMIT_FAILED_LOGINS:-20}
LIMIT_ORPHAN=${LIMIT_ORPHAN_IMAGES:-5}
TELEGRAM_TOKEN=${TELEGRAM_TOKEN:-}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID:-}
KUMA_URL=${KUMA_URL:-}

# Detecta log de auth
if [ -f /var/log/auth.log ]; then AUTH_LOG="/var/log/auth.log"; 
elif [ -f /var/log/secure ]; then AUTH_LOG="/var/log/secure"; 
else AUTH_LOG=""; fi

CRITICAL_ALERTS=""

# --- INÍCIO DO RELATÓRIO ---
{
    echo "========================================"
    echo "RESUMO DIÁRIO: $(hostname)"
    echo "DATA: $(date)"
    echo "========================================"
    echo ""

    # CONFIGURAÇÃO DE DATA OTIMIZADA
    # LC_TIME=C: Força Inglês (Feb vs fev) para alinhar com logs.
    # %e: Dia com espaço ( 5) em vez de zero (05). O date já trata isso nativamente.
    TODAY_GREP=$(date +%Y-%m-%d)

    # --------------------------------------------------------------------------
    # 1. SEGURANÇA E ACESSO
    # --------------------------------------------------------------------------
    echo "[1] SEGURANÇA E ACESSO (Hoje)"
    echo "----------------------------------------"

    if [ -n "$AUTH_LOG" ]; then
        # SSH
        SUCCESS=$(grep "$TODAY_GREP" "$AUTH_LOG" | grep -c "Accepted" || true)
        echo "SSH - Logins Sucesso: $SUCCESS"
        [ "$SUCCESS" -gt 0 ] && grep "$TODAY_GREP" "$AUTH_LOG" | grep "Accepted" | tail -3
        
        echo ""
        FAILED=$(grep "$TODAY_GREP" "$AUTH_LOG" | grep -c "Failed" || true)
        echo "SSH - Tentativas Falhas: $FAILED"
        
        if [ "$FAILED" -gt "$LIMIT_FAILED" ]; then
            echo "⚠️  ALERTA: Força bruta detectada ($FAILED tentativas)!"
            CRITICAL_ALERTS+="- SSH Brute Force: $FAILED tentativas%0A"
            grep "$TODAY_GREP" "$AUTH_LOG" | grep "Failed" | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -3
        fi
        echo ""

        # SUDO
        echo "--- Comandos Administrativos (SUDO) ---"
        SUDO_COUNT=$(grep "$TODAY_GREP" "$AUTH_LOG" | grep -c "sudo" || true)
        if [ "$SUDO_COUNT" -gt 0 ]; then
             grep "$TODAY_GREP" "$AUTH_LOG" | grep "sudo" | grep "COMMAND=" | tail -5
        else
             echo "Nenhum comando sudo executado hoje."
        fi
    else
        echo "❌ Log de autenticação não acessível."
    fi
    echo ""

    # --------------------------------------------------------------------------
    # 2. SAÚDE DOS CONTAINERS (DETALHADA)
    # --------------------------------------------------------------------------
    echo "[2] SAÚDE DOCKER"
    echo "----------------------------------------"
    
    # A. Rodando (Apenas informativo no log)
    echo "--- Containers Rodando ---"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
    echo ""

    # B. Parados (Alerta Crítico)
    echo "--- Containers Parados (Exited) ---"
    STOPPED=$(docker ps -a --filter "status=exited" --format "{{.Names}}")
    if [ -n "$STOPPED" ]; then
        echo "⚠️  AVISO: Containers parados encontrados:"
        echo "$STOPPED"
        # Converte quebras de linha em vírgula para o alerta do Telegram
        STOPPED_LIST=$(echo "$STOPPED" | tr '\n' ',' | sed 's/,$//')
        CRITICAL_ALERTS+="- Docker PARADO: $STOPPED_LIST%0A"
    else
        echo "✅ Nenhum container parado."
    fi
    echo ""

    # C. Restart Loop (Alerta Crítico)
    RESTARTING=$(docker ps --filter "status=restarting" --format "{{.Names}}")
    if [ -n "$RESTARTING" ]; then
        echo "⚠️  CRÍTICO: Containers reiniciando!"
        echo "$RESTARTING"
        CRITICAL_ALERTS+="- Docker RESTART LOOP: $RESTARTING%0A"
    fi

    # D. Unhealthy (Alerta Crítico)
    UNHEALTHY=$(docker ps --filter "health=unhealthy" --format "{{.Names}}")
    if [ -n "$UNHEALTHY" ]; then
        echo "⚠️  CRÍTICO: Containers Unhealthy!"
        echo "$UNHEALTHY"
        CRITICAL_ALERTS+="- Docker UNHEALTHY: $UNHEALTHY%0A"
    fi
    echo ""

    # E. Lixo e Volumes (Alerta)
    echo "--- Limpeza e Uso ---"
    DANGLING=$(docker images -f "dangling=true" -q | wc -l)
    if [ "$DANGLING" -gt "$LIMIT_ORPHAN" ]; then
        echo "⚠️  Imagens órfãs acumuladas: $DANGLING"
        CRITICAL_ALERTS+="- Lixo Docker: $DANGLING imagens orfas%0A"
    else
        echo "✅ Imagens órfãs sob controle ($DANGLING)."
    fi

    UNUSED_VOL=$(docker volume ls -f "dangling=true" -q | wc -l)
    if [ "$UNUSED_VOL" -gt 0 ]; then
        echo "⚠️  Volumes não utilizados: $UNUSED_VOL"
        CRITICAL_ALERTS+="- Volumes Orfãos: $UNUSED_VOL (Verifique!)%0A"
    else
        echo "✅ Nenhum volume órfão."
    fi
    echo ""

    # --------------------------------------------------------------------------
    # 3. INTEGRIDADE E DRIFT (/srv)
    # --------------------------------------------------------------------------
    echo "[3] INTEGRIDADE (DRIFT)"
    echo "----------------------------------------"
    
    if [ -d /srv/.git ]; then
        cd /srv
        if git status --porcelain | grep -q .; then
            DRIFT_COUNT=$(git status --porcelain | wc -l)
            echo "⚠️  DRIFT DETECTADO: $DRIFT_COUNT arquivo(s) modificado(s)."
            git status --short
            CRITICAL_ALERTS+="- Drift Config: $DRIFT_COUNT arquivos%0A"
        else
            echo "✅ Configuração íntegra (Git Clean)."
        fi
    else
        echo "Ignorado: /srv não é repo Git."
    fi
    echo ""

    # --------------------------------------------------------------------------
    # 4. INTEGRIDADE SISTEMA (CHECKSUMS)
    # --------------------------------------------------------------------------
    echo "[4] INTEGRIDADE SISTEMA (/etc)"
    echo "----------------------------------------"
    if [ -f "$BASELINE_FILE" ]; then
        if sha256sum -c "$BASELINE_FILE" --quiet 2>/dev/null; then
            echo "✅ Arquivos de sistema íntegros."
        else
            echo "⚠️  ALERTA: Arquivos de sistema modificados!"
            sha256sum -c "$BASELINE_FILE" 2>/dev/null | grep "FAILED"
            CRITICAL_ALERTS+="- Sistema Modificado (Checksum Fail)%0A"
        fi
    else
        echo "❌ ERRO CRÍTICO: Baseline de segurança não encontrado!"
        CRITICAL_ALERTS+="- Baseline de Seguranca NAO EXISTE%0A"
    fi
    echo ""

    echo "========================================"
    echo "Fim do Relatório"

} | tee "$CURRENT_LOG"

# --- NOTIFICAÇÕES ---

# 1. Telegram
if [ -n "$CRITICAL_ALERTS" ] && [ -n "$TELEGRAM_TOKEN" ]; then
    MSG="🚨 *ALERTA SERVIDOR* $(hostname) %0A%0A${CRITICAL_ALERTS}"
    # Remove caracteres especiais que podem quebrar a URL do curl
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" -d parse_mode="Markdown" -d text="$MSG" > /dev/null
fi

# 2. Uptime Kuma (Heartbeat)
if [ -n "$KUMA_URL" ]; then
    STATUS="up"
    MSG="OK"
    if [ -n "$CRITICAL_ALERTS" ]; then
        STATUS="down"
        MSG="Falhas_Detectadas"
    fi
    curl -fsS -m 10 "${KUMA_URL}&status=${STATUS}&msg=${MSG}" > /dev/null
fi

# Limpeza logs (30 dias)
find "$LOG_DIR" -name "*.log" -mtime +30 -delete
