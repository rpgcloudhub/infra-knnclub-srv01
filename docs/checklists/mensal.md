## Manutenção Mensal - ____/____

### Pré-requisitos
- [ ] Criar snapshot no provedor: `pre-manutencao-YYYY-MM`
- [ ] Verificar backup recente OK

### Atualizações de Sistema
- [ ] Verificar disponíveis: `apt list --upgradable` / `dnf check-update`
- [ ] Aplicar: `sudo apt upgrade -y` / `sudo dnf upgrade -y`
- [ ] Verificar se reboot necessário
- [ ] Se sim, agendar reboot

### Atualizações de Containers
- [ ] Verificar changelogs de atualizações importantes
- [ ] Atualizar containers usando script seguro:
      `/srv/docs/scripts/update-container.sh <app> <servico>`
- [ ] Atualizar Traefik: ____
- [ ] Atualizar Netdata: ____
- [ ] Atualizar Grafana/Loki: ____
- [ ] Atualizar Uptime Kuma: ____
- [ ] Atualizar outros: ____
- [ ] Validar todos os serviços após updates

### Limpeza
- [ ] Executar limpeza: `sudo /srv/docs/scripts/housekeeping.sh`
- [ ] Espaço liberado: ____ GB

### Teste de Backup
- [ ] Listar snapshots: `source /srv/docs/scripts/backup.conf && restic snapshots`
- [ ] Restaurar arquivo de teste:
      `restic restore latest --target /tmp/restore-test --include "/srv/data/traefik"`
- [ ] Verificar arquivo restaurado
- [ ] Limpar: `rm -rf /tmp/restore-test`
- [ ] Backup funcionando: [ ] Sim [ ] Não

### Documentação
- [ ] Executar inventário: `/srv/docs/scripts/gerar-docs.sh`
- [ ] Revisar inventário gerado
- [ ] Atualizar runbooks se necessário
- [ ] Commit e push: `cd /srv && git add -A && git commit -m "Manutenção mensal" && git push`

### Observações
_____________________________________________
-
-
-
```
