#!/bin/bash
# /srv/docs/scripts/generate-baseline.sh
# Gera ou atualiza o hash de arquivos críticos do sistema

set -euo pipefail

BASELINE_DIR="/srv/docs/integrity"
BASELINE_FILE="$BASELINE_DIR/system.sha256"

# Lista de arquivos críticos para monitorar (Ubuntu + AlmaLinux)
CRITICAL_FILES=(
    # Acesso e Autenticação
    "/etc/ssh/sshd_config"
    "/etc/passwd"
    "/etc/shadow"
    "/etc/group"
    "/etc/sudoers"
    
    # Rede e Sistema
    "/etc/hosts"
    "/etc/fstab"
    "/etc/resolv.conf"

    # IPTABLES - Ubuntu/Debian (pacote iptables-persistent)
    "/etc/iptables/rules.v4"
    "/etc/iptables/rules.v6"

    # IPTABLES - AlmaLinux/RHEL (pacote iptables-services)
    "/etc/sysconfig/iptables"
    "/etc/sysconfig/ip6tables"
)

mkdir -p "$BASELINE_DIR"

echo "Gerando baseline de integridade..."

# Limpa arquivo anterior para garantir idempotência (Reset)
: > "$BASELINE_FILE"

for file in "${CRITICAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        # Gera o hash e anexa ao arquivo limpo
        sha256sum "$file" >> "$BASELINE_FILE"
        echo "Monitorando: $file"
    else
        # Se o arquivo não existir (ex: regras v6 ou distro diferente), apenas ignora sem erro
        true
    fi
done

echo "✅ Baseline gerado em: $BASELINE_FILE"
chmod 600 "$BASELINE_FILE" # Protege o arquivo de leitura pública
