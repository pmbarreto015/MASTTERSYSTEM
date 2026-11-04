# Mesmo banco no PC e no celular usando Render

O Render pode executar este servidor Docker com o SQLite em um disco persistente.
PC e celular passam a usar a mesma URL HTTPS, mesmo em redes diferentes. O PC
pode ficar desligado. O Render fornece o endereço `https://nome.onrender.com`
e o certificado; este caminho usa `Dockerfile.render` e dispensa o Caddy.
[Serviços web e HTTPS](https://render.com/docs/web-services).

## Plano necessário

Use um **Web Service pago com disco persistente**. Na consulta de 06/10/2026,
a configuração de 0,5 CPU/512 MB custa US$ 7/mês e o disco custa US$ 0,25 por
GB/mês. Com 1 GB, a base é **US$ 7,25/mês**, antes de excedentes e impostos,
usando o workspace Hobby. Confira os valores antes de contratar.
[Preços oficiais](https://render.com/pricing).

O plano gratuito não aceita disco persistente. Sem esse disco, o SQLite perde
as alterações quando o serviço reinicia ou recebe uma atualização.
[Discos persistentes](https://render.com/docs/disks).

## Preparar e criar o serviço

1. Na raiz do projeto no Windows, gere uma edição nova:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tool/preparar_banco_internet.ps1 -OutputDirectory dist/MatterdiBancoRender
   ```

2. Coloque o conteúdo de `dist/MatterdiBancoRender` na raiz de um repositório
   GitHub privado. Inclua o `.gitignore` do kit e os arquivos de código e
   configuração. O banco, backups e a chave de acesso ficam fora do repositório.
3. No Render, escolha **New → Blueprint**, conecte esse repositório e use o
   `render.yaml` da raiz. Revise o plano pago e o disco antes de criar o serviço.
   O Blueprint configura uma instância, disco de 1 GB em `/var/data` e uma
   chave aleatória na variável `MATTERDI_DATABASE_TOKEN`.
   [Blueprints](https://render.com/docs/blueprint-spec).
4. Aguarde o primeiro deploy ficar **Live**. Enquanto o banco ainda não foi
   importado, o servidor permanece aguardando e responde erro 503 às chamadas
   HTTP. Nesse momento, a tela de conexão do aplicativo ainda não funciona.

Para criação manual como **Web Service**, selecione Docker, informe
`./Dockerfile.render`, escolha o plano pago e adicione o disco em `/var/data`.
Defina `MATTERDI_DATABASE_TOKEN` com uma chave de pelo menos 24 caracteres e
`MATTERDI_DATABASE_PATH=/var/data/matterdi_sistem.db`. A porta vem da variável
`PORT` do Render, normalmente `10000`. Deixe **Health Check Path vazio**:
este kit usa o teste TCP padrão, pois `/health` exige a chave do aplicativo.
[Portas](https://render.com/docs/web-services#port-binding) e
[health checks](https://render.com/docs/health-checks).

## Importar o banco do PC pela primeira vez

1. No PC principal, use a versão atual do sistema e faça um backup em **Backup**.
   Esse arquivo `.db` consistente precisa estar na versão 27 do banco.
2. Configure sua chave SSH pública na conta Render e, no serviço, abra
   **Connect → SSH**. Use o endereço exato fornecido pelo painel.
   [Configuração de SSH](https://render.com/docs/ssh).
3. No PowerShell do PC, transfira o backup para um nome temporário. Substitua
   o caminho do arquivo e `SEU_SERVICO@HOST_SSH` pelo destino do painel:

   ```powershell
   scp 'C:/seus-backups/backup.db' SEU_SERVICO@HOST_SSH:/var/data/banco.incoming
   ```

   A transferência precisa terminar antes do próximo passo. Se seu cliente
   SCP for antigo, consulte o modo SFTP recomendado na
   [documentação de transferência](https://render.com/docs/disks#transferring-files).
4. Abra **Shell** no serviço em execução ou conecte por SSH. Confira o arquivo:

   ```sh
   sqlite3 /var/data/banco.incoming 'PRAGMA integrity_check; PRAGMA user_version;'
   ```

   O resultado esperado é `ok` e `27`. Se aparecer outro resultado, corrija
   o backup antes de continuar. Para a primeira importação, execute:

   ```sh
   test ! -e /var/data/matterdi_sistem.db && mv /var/data/banco.incoming /var/data/matterdi_sistem.db
   ```

   O comando só publica o arquivo se ainda não existe banco ativo. O servidor
   detecta esse nome final e inicia o acesso ao SQLite. Confira nos logs a
   mensagem de servidor ativo. Ele também valida a versão e as tabelas exigidas.

Use o Shell da instância em execução: shells efêmeros e tarefas avulsas não
recebem esse disco. O arquivo `.incoming` evita abrir uma transferência incompleta.
O serviço aguarda um banco existente e não cria um banco vazio para substituí-lo.

## Conectar os aplicativos

No painel Render, copie a URL HTTPS do serviço e consulte a chave em
**Environment → MATTERDI_DATABASE_TOKEN**. Guarde essa chave somente nos
dispositivos autorizados; ela permite acessar o banco inteiro.

No PC e no celular, abra **Conexão com o banco**, selecione **Banco por IP ou
hospedagem**, informe a mesma URL, como `https://matterdi-banco.onrender.com`,
e a mesma chave. Use a URL real do painel, sem `:10000`, `/health` ou `/database`.
Toque em **Testar conexão**, salve e entre com o usuário e senha do banco importado.
Teste também no celular com o Wi-Fi desligado e os dados móveis ligados.

As alterações passam a ser feitas no banco do Render. Registros novos criados
em uma cópia local separada não são enviados automaticamente. Fotos, logos e
arquivos que ficam fora do SQLite não são transferidos por esta conexão.

## Fazer backup e atualizar

No Shell do serviço, crie uma cópia consistente com o próprio SQLite:

```sh
mkdir -p /var/data/backups
sqlite3 /var/data/matterdi_sistem.db ".backup '/var/data/backups/backup.db'"
```

Transfira esse backup para seu PC ou outro armazenamento:

```powershell
scp SEU_SERVICO@HOST_SSH:/var/data/backups/backup.db 'C:/seus-backups/render-backup.db'
```

O nome do exemplo é fixo; use nomes diferentes para manter um histórico.
Não substitua o arquivo de banco ativo enquanto o servidor estiver em execução.
Atualize o código com um backup recente e faça um deploy manual no Render.
O disco preserva os dados, mas a atualização causa uma breve interrupção.
Mantenha somente uma instância com esse SQLite. O banco deve continuar compatível
com a versão exigida pelo servidor.

Este kit é uma configuração para publicar na sua conta. A geração local não
cria serviços nem contrata planos. O launcher e o RPC podem ser validados
localmente; Docker Linux, SSH e HTTPS precisam ser confirmados no primeiro deploy.
