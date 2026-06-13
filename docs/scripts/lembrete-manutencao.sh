#!/bin/bash
# Envia lembrete de manutenção via Discord (webhook compartilhado com o Diun)

set -uo pipefail

ENV_FILE="/srv/apps/diun/.env"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

TYPE="${1:-}"
HOSTNAME=$(hostname)
MESSAGE=""

case "$TYPE" in
    weekly)
        MESSAGE="🔔 Lembrete: ronda semanal (15 min) do servidor $HOSTNAME — revisar alertas do Kuma, uso de disco (df -h), updates apontados pelo Diun e erros no Grafana/Loki. Checklist: /srv/docs/checklists/semanal.md"
        ;;
    monthly)
        MESSAGE="🔧 Lembrete: manutenção mensal do servidor $HOSTNAME — snapshot, updates de sistema e containers, teste de restauração de backup. Checklist: /srv/docs/checklists/mensal.md"
        ;;
    quarterly)
        MESSAGE="🛡️ Lembrete: manutenção trimestral do servidor $HOSTNAME — firewall, usuários/chaves SSH, rotação de credenciais. Checklist: /srv/docs/checklists/trimestral.md"
        ;;
    annual)
        MESSAGE="🔥 Lembrete: manutenção anual do servidor $HOSTNAME — avaliação de OS, custos e SIMULAÇÃO DE DESASTRE. Checklist: /srv/docs/checklists/anual.md"
        ;;
    *)
        echo "Uso: $0 {weekly|monthly|quarterly|annual}"
        exit 1
        ;;
esac

if [ -n "${DISCORD_WEBHOOK:-}" ]; then
    curl -s -X POST "$DISCORD_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "{\"content\": \"$MESSAGE\"}" > /dev/null
    echo "Lembrete enviado: $MESSAGE"
else
    echo "Webhook não configurado em $ENV_FILE. Mensagem: $MESSAGE"
fi
