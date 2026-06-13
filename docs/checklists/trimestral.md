## Manutenção Trimestral - __/____

### Firewall e Segurança
- [ ] Revisar regras iptables: `sudo iptables -L`
- [ ] Remover regras obsoletas
- [ ] Verificar portas expostas: `sudo ss -tlnp`
- [ ] Revisar middlewares Traefik
- [ ] Verificar Cloudflare: IPs permitidos, regras WAF

### Usuários e Permissões
- [ ] Listar usuários: `cat /etc/passwd | grep -E '/bin/(bash|sh)'`
- [ ] Remover usuários desnecessários
- [ ] Verificar chaves SSH: `ls -la ~/.ssh/authorized_keys`
- [ ] Remover chaves antigas/desconhecidas
- [ ] Revisar sudoers: `sudo cat /etc/sudoers.d/*`

### Credenciais
- [ ] Rotacionar senha do usuário ops
- [ ] Rotacionar senhas de bancos de dados
- [ ] Gerar nova RESTIC_PASSWORD (se necessário)
- [ ] Rotacionar API keys (B2, R2, etc.)
- [ ] Atualizar senhas no gerenciador

### Certificados
- [ ] Verificar certificados Cloudflare Origin (se usados)
- [ ] Verificar certificados locais (se houver)
- [ ] Data de expiração: ____/____/____

### VPN
- [ ] Revisar peers WireGuard: `sudo wg show`
- [ ] Remover peers não utilizados
- [ ] Verificar se chaves precisam rotação

### Auditoria
- [ ] Executar auditoria completa: `/srv/docs/scripts/auditoria.sh`
- [ ] Revisar relatório gerado
- [ ] Corrigir problemas encontrados

### Documentação
- [ ] Comparar estado atual vs documentado
- [ ] Atualizar diagramas se necessário
- [ ] Revisar runbooks: ainda funcionam?

### Observações
_____________________________________________
-
-
-
```
