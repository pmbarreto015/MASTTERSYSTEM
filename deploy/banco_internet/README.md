# Banco do MatterdiSistem na internet

Este kit hospeda o servidor de banco já usado pelo aplicativo. O PC e o celular
passam a ler e salvar no mesmo SQLite da hospedagem usando um endereço HTTPS e
uma chave de acesso. O servidor só abre um banco existente na versão 27.

## Usar o Render

Para hospedar no Render com endereço HTTPS fornecido pela plataforma, siga
[o guia do Render](RENDER.md). O kit inclui `render.yaml` e `Dockerfile.render`,
com disco persistente e preparação para importar seu banco. Esse caminho usa
um Web Service pago; não precisa de VPS, domínio próprio nem Caddy.

## Preparar o kit no PC

Na raiz do projeto, execute no PowerShell:

```powershell
.\tool\preparar_banco_internet.ps1
```

O comando gera `dist/MatterdiBancoInternet/` e
`dist/MatterdiBancoInternet.zip`, contendo código e configurações. Ele não
publica um serviço e não copia dados ou chaves do PC. Os arquivos Dart são
extraídos do RPC e da CLI atuais do projeto; não há uma cópia permanente
separada desses servidores no template.

O gerador recusa um destino que já existe para preservar dados, chaves e
configurações de uma instalação anterior. Para gerar outra edição:

```powershell
.\tool\preparar_banco_internet.ps1 -OutputDirectory dist\MatterdiBancoInternetNovo
```

Para incluir também um executável para o sistema operacional do PC, instale
um SDK Dart compatível e use a opção abaixo. O SDK 3.11.5 foi escolhido para
validação local. A opção executa `dart pub get` e `dart build cli`; a primeira
compilação também pode baixar o SQLite nativo pelo hook do pacote.

```powershell
.\tool\preparar_banco_internet.ps1 -BuildLocalBundle `
  -DartExecutable E:\Flutter\bin\cache\dart-sdk\bin\dart.exe `
  -OutputDirectory dist\MatterdiBancoInternetComExecutavel
```

O diretório `local-runtime/` acompanha o pacote completo `bin/` e `lib/`.
Preserve ambos: o executável precisa da biblioteca nativa do SQLite. Esse
executável local serve para o mesmo sistema operacional e arquitetura do SDK
que o compilou; o Docker compila um bundle próprio para a hospedagem Linux.

## Levar o banco existente para a hospedagem

1. Atualize e abra o sistema no PC principal para concluir as migrações até a
   versão 27. Em **Backup**, faça um backup dos dados existentes.
2. Use esse backup consistente como o arquivo que será transferido. Guarde uma
   cópia anterior à mudança para poder consultar os dados originais.
3. Prepare uma VPS Linux com Docker Engine e Docker Compose v2. Aponte o DNS
   do domínio escolhido para o IP dessa VPS; se houver um registro AAAA, ele
   também precisa apontar para ela. Libere as portas TCP 80 e 443.
4. Transfira e extraia o ZIP em uma pasta da VPS. Transfira o backup por SSH/SFTP
   para `data/matterdi_sistem.db` dentro dessa pasta.

Na VPS, entre na pasta extraída e crie a configuração e a chave:

```sh
cp .env.example .env
# Edite DOMAIN e ACME_EMAIL no .env com seu domínio e e-mail reais.
nano .env
install -d -m 700 secrets data
umask 077
openssl rand -hex 32 > secrets/chave_banco
chmod 600 secrets/chave_banco data/matterdi_sistem.db
```

Guarde a chave criada para configurar os dois aplicativos. Os diretórios
`data/` e `secrets/` ficam fora do contexto do Docker: o arquivo SQLite e a chave
são montados quando o container inicia, sem entrar na imagem.

Revise a configuração e inicie na VPS:

```sh
docker compose config --quiet
docker compose up -d --build
docker compose logs --tail=50 banco caddy
```

O Caddy obtém e renova o certificado HTTPS do domínio. Ele recebe as conexões
nas portas 80/443 e encaminha ao backend 8080 pela rede interna do Compose.
O backend não publica uma porta no host. Os certificados persistem nos volumes
`caddy_data` e `caddy_config`; o banco persiste na pasta `data/` da VPS.

## Apontar PC e celular para o mesmo banco

No PC, abra **Conexão com o banco**, selecione **Banco por IP ou hospedagem** e
informe `https://banco.seudominio.com` e a chave da hospedagem. Clique em
**Testar conexão**, salve e entre novamente com um usuário do banco transferido.
Faça os mesmos passos no celular com a mesma URL e a mesma chave.

A partir dessa configuração, ambos salvam no banco da hospedagem. Alterações
feitas em um arquivo local separado não são sincronizadas automaticamente.
O acesso passa a depender da internet e de a VPS estar disponível. Backups e
restaurações desse banco devem ser feitos na hospedagem.

## Backup e atualização da hospedagem

Para uma cópia consistente sem ferramentas SQLite adicionais, pare o backend
e salve a pasta de dados inteira. Os aplicativos ficam temporariamente sem
acesso enquanto ele estiver parado:

```sh
mkdir -p backups
docker compose stop banco
tar -czf "backups/banco-$(date +%Y-%m-%d_%H-%M-%S).tgz" data
docker compose start banco
```

Copie o backup também para outro armazenamento. Para restaurar, pare o backend,
preserve os dados atuais, restaure a pasta `data/` do backup e inicie novamente.

Gere uma nova edição do kit para atualizar o código do servidor. Na VPS, substitua
somente `Dockerfile`, `.dockerignore`, `compose.yaml`, `Caddyfile` e `source/`;
preserve `.env`, `data/`, `secrets/` e os volumes do Caddy. Execute novamente
`docker compose up -d --build`. Mudanças futuras na versão do esquema exigem um
banco atualizado pelo aplicativo antes de iniciar o novo servidor.

O Docker usa a imagem oficial Dart e copia `/runtime/` e o bundle completo para
uma imagem final `scratch`. Você pode fixar `DART_IMAGE` no `.env` antes de
compilar. O segredo usa um arquivo montado pelo Compose, lido em
`/run/secrets/chave_banco`. Referências: [imagem oficial Dart](https://hub.docker.com/_/dart),
[segredos no Compose](https://docs.docker.com/compose/how-tos/use-secrets/) e
[HTTPS automático do Caddy](https://caddyserver.com/docs/automatic-https).
