## Manutenção Semanal - Semana de ____/____/____

### Alertas
- [ ] Acessar Uptime Kuma
- [ ] Revisar alertas disparados na semana
- [ ] Investigar qualquer downtime
- [ ] Anotar: _________________________________

### Disco
- [ ] Verificar uso: `df -h /`
- [ ] Uso atual: ____%
- [ ] Se > 70%, investigar

### Containers
- [ ] Verificar atualizações: `docker exec diun diun image list` ou manual
- [ ] Atualizações disponíveis: _______________
- [ ] Agendar updates para manutenção mensal

### Logs
- [ ] Verificar erros recentes: `journalctl -p err --since "1 week ago" | head -30`
- [ ] Checagem rápida de logs no Grafana/Loki por erros recorrentes
- [ ] Erros encontrados: _____________________

### Observações
_____________________________________________
-
-
-
```
