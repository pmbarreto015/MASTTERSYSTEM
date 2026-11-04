# Licenças pela internet e por chave offline

O mesmo APK ou EXE oferece duas opções na ativação: **Internet / rede** e
**Chave offline**. O administrador continua sendo um programa Windows separado.
Os cadastros de rede local existentes são preservados.

## Gerar os aplicativos

Execute na pasta do projeto:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\compilar_licencas.ps1
```

O script prepara uma identidade de assinatura, compila o EXE e o APK clientes e
depois o ADM com os dois instaladores. Os pacotes anteriores são preservados em
`dist` com o sufixo `-anterior-`.

- ADM: `dist/ServidorLicencas/ServidorLicencas.exe`.
- Cliente Windows: `dist/MastterSystemCliente_Windows.zip` (extrair a pasta inteira).
- Cliente Android: `dist/MastterSystemCliente.apk`.

Para embutir o endereço da hospedagem nos clientes, use
`-ServidorInternet 'https://seu-servico.onrender.com'`. Sem esse parâmetro, o cliente
pode preencher o endereço na ativação. Para gerar somente Windows e ADM, use
`-SkipAndroid`. O parâmetro `-Alvo Servidor` gera apenas o administrador.

O arquivo `data/licensing/issuer_private.json` é a identidade privada do emissor.
Guarde uma cópia segura dele. O script reutiliza o mesmo par em cada compilação
e recusa substituir uma identidade incompatível. Somente a chave pública entra
nos clientes; a chave privada é incluída exclusivamente no ADM. Distribua aos
clientes apenas o APK ou o ZIP do cliente.

## Opção 1: licença online

O servidor de licenças roda na hospedagem. Você usa o ADM para criar, renovar,
bloquear acessos e liberar vagas; seu computador pode ser desligado depois.
Os clientes precisam de internet para ativar e validar licenças com prazo.

### Hospedar no Render

Os arquivos estão em `deploy/licensing`. O serviço usa um arquivo de dados e
precisa de armazenamento persistente. O Blueprint configura **um serviço pago
com disco de 1 GB**, uma única instância, verificação de saúde e uma credencial
administrativa gerada pelo Render. Nenhum serviço foi publicado automaticamente.

1. Envie o código para um repositório sob seu controle, respeitando `.gitignore`.
   Não envie `data/licensing/issuer_private.json`, `build_defines_admin.json`,
   backups, arquivos `.env` ou cadastros reais.
2. No Render, crie um Blueprint com o arquivo `deploy/licensing/render.yaml`.
   Confira o serviço e os custos apresentados antes de criar.
3. Confirme o disco montado em `/var/data` e a variável
   `LICENSE_DATA_FILE=/var/data/lan_licenses.json`.
4. Após o deploy, copie a URL HTTPS fornecida pelo Render e obtenha, no painel
   privado do serviço, o valor da variável `LICENSE_ADMIN_TOKEN`.
5. No ADM, abra **Internet**, informe URL e credencial administrativa e conecte.
6. Na aba **Licenças**, crie o acesso com login, senha, prazo e limite de aparelhos.
   Envie ao cliente a URL, o login e a senha de instalação.
7. No APK ou EXE, escolha **Internet / rede**, preencha esses dados e ative.

O token administrativo dá controle das licenças e fica somente com o responsável
pelo ADM. O cliente recebe seu próprio login e senha. O ADM só lembra a credencial
se você selecionar essa opção; ela não entra nos pacotes dos clientes.

A validação ocorre na abertura, ao voltar ao aplicativo e a cada cinco minutos.
O vencimento também fecha o acesso enquanto o sistema está aberto. Bloqueios e
renovações online são reconhecidos na próxima validação. Licenças com prazo
exigem conexão; as permanentes mantêm a tolerância anterior de até três dias
após uma validação bem-sucedida, salvo recusa explícita do servidor.

Os cadastros locais e os da hospedagem são independentes. Ao conectar ao servidor
online, a lista passa a mostrar os cadastros desse servidor. Uma falha de conexão
não substitui a lista por dados locais. Para voltar à rede local, desconecte na
aba Internet e inicie o servidor local. Migrar um cadastro existente exige criar
o acesso na hospedagem e ativar novamente os aparelhos; os dados do ERP são
independentes das licenças.

### Outras hospedagens

O servidor é Dart, sem interface gráfica ou dependência de Flutter. É possível
usar o Dockerfile em outro provedor ou `compose.yaml` com Caddy em uma VPS. O
arquivo `.env.example` documenta as variáveis; defina um token aleatório com pelo
menos 32 caracteres e use HTTPS. Execute uma única instância sobre o arquivo de
dados e mantenha backup persistente de `lan_licenses.json`.

O Render gratuito não oferece disco persistente e pode suspender por inatividade;
não use um arquivo de cadastros no disco efêmero. Supabase (banco e Edge Functions)
e Vercel (funções e banco externo) exigem outra implementação de backend; os
arquivos entregues nesta versão hospedam o servidor Dart no Render ou numa VPS.

Referências oficiais: [Render — discos](https://render.com/docs/disks),
[serviços gratuitos](https://render.com/docs/free) e
[Blueprint](https://render.com/docs/blueprint-spec).

## Opção 2: chave offline com prazo

1. O cliente abre a ativação no APK/EXE, copia **Código deste aparelho** e envia
   para você por mensagem.
2. No ADM, abra **Chaves offline**. Informe nome, código do aparelho, Android ou
   Windows e a duração ou data de vencimento.
3. Gere a chave e envie o texto completo ao cliente. Você também pode exportar
   um arquivo `.lic` e enviá-lo.
4. O cliente escolhe **Chave offline**, cola a chave ou importa o arquivo e ativa.

A chave vale somente para o aparelho, plataforma e prazo assinados. Não precisa
da mesma rede, internet nem do ADM aberto. O prazo é contado a partir da emissão,
conforme o vencimento exibido, e não da primeira instalação.

Para renovar, gere e envie outra chave com vencimento futuro. Alterações na aba
Licenças e bloqueios online não revogam uma chave offline já entregue: ela vale
até o prazo assinado. Cada chave é emitida para um aparelho; não há contagem
central de aparelhos offline. Reinstalar o APK ou limpar os dados pode gerar um
novo código e exigir outra chave.

O aplicativo verifica a assinatura novamente ao abrir, ao voltar e
periodicamente. O vencimento fecha o acesso com o sistema aberto. Alterar o
texto ou a data gravada nas preferências não altera o prazo assinado. O cliente
detecta recuos do relógio em relação ao último uso registrado e pede corrigir
data e hora. A operação offline depende do relógio e dos dados locais e não
oferece a mesma fiscalização de um servidor online.

Ativar por uma opção substitui a autorização da outra naquele aparelho. A
licença online bloqueada não usa automaticamente uma chave offline antiga.

## Backup

- Código e instaladores anteriores: backup criado antes destas mudanças em
  `backup_antes_nota_fiscal_20261015_0425`.
- Identidade de emissão: `data/licensing/issuer_private.json` (acesso privado).
- Servidor local: `lan_licenses.json` na pasta de dados do administrador.
- Servidor online: `/var/data/lan_licenses.json` no disco persistente.

O login de licença é separado dos usuários do ERP e da configuração do banco de
dados. Este recurso não emite nota fiscal nem modifica a conexão do banco.
