# Acessar o banco do PC pelo celular no 4G/5G

Você pode manter o banco no PC e acessá-lo de outra rede. O PC precisa ficar
ligado, conectado à internet e com o MatterdiSistem aberto. O celular acessa
os mesmos cadastros e grava no mesmo banco, sem copiar o arquivo `.db`.

O APK atual já aceita endereços HTTPS. Faça a configuração abaixo usando uma
das duas opções: Tailscale Serve ou Cloudflare Tunnel.

## Preparar o sistema no PC

1. Abra **Configurações → Conexão com o banco**.
2. Selecione **Banco deste dispositivo**, ou **Banco deste PC (arquivo
   compartilhado)** se esse já for o arquivo que contém seus dados.
3. Ative **Compartilhar este banco com o celular** e mantenha a porta `8080`.
4. Gere ou mantenha a chave de acesso. Use **Copiar chave** para transferi-la
   somente ao celular autorizado; não publique a chave nem o arquivo do banco.
5. Clique em **Salvar e voltar ao login** e entre novamente no sistema.

O PC continua usando seu banco local com o compartilhamento ativado. Na opção
de manter o banco no PC, configure a URL HTTPS no celular. A chave do banco é
separada da senha do usuário e das credenciais do Tailscale ou Cloudflare.

## Opção 1: Tailscale Serve, sem comprar domínio

Tailscale conecta os dispositivos por uma rede privada pela internet. Instale
o aplicativo Tailscale no Windows e no Android, entre na mesma conta/rede
Tailscale e mantenha os dois conectados. No Android, aceite a criação da
conexão VPN. O endereço HTTPS será fornecido pelo próprio Tailscale.
[Instalação no Windows](https://tailscale.com/docs/install/windows) e
[downloads oficiais](https://tailscale.com/download).

1. Com o sistema aberto no PC, abra o **Terminal ou PowerShell como
   administrador**.
2. Execute:

   ```powershell
   tailscale serve --bg --https=443 http://127.0.0.1:8080
   ```

   Se o comando `tailscale` não for encontrado, feche e reabra o terminal
   após a instalação. Na instalação padrão, também pode executar:

   ```powershell
   & 'C:\Program Files\Tailscale\tailscale.exe' serve --bg --https=443 http://127.0.0.1:8080
   ```

   O destino `127.0.0.1:8080` é o servidor do sistema nesse mesmo PC. Se você
   escolheu outra porta no sistema, substitua `8080` no comando. A opção
   `--bg` mantém o compartilhamento ativo ao fechar o terminal.
   [Comandos do Serve](https://tailscale.com/docs/reference/tailscale-cli/serve)
   e [uso no Windows e em segundo plano](https://tailscale.com/docs/reference/examples/serve).

3. Se aparecer um link de autorização, abra-o e habilite HTTPS para sua rede
   Tailscale. Também é possível acessar o painel Tailscale, abrir **DNS**,
   ativar **MagicDNS** e, em **HTTPS Certificates**, selecionar **Enable HTTPS**.
   O Serve providencia o certificado automaticamente. Se o comando encerrar
   pedindo autorização, execute-o novamente após habilitar HTTPS.
   [Configuração de HTTPS](https://tailscale.com/docs/how-to/set-up-https-certificates)
   e [início do Serve](https://tailscale.com/docs/features/tailscale-serve).
4. Consulte o endereço configurado:

   ```powershell
   tailscale serve status
   ```

5. Copie a URL exibida, semelhante a
   `https://pc-principal.sua-rede.ts.net`. Esse é apenas um exemplo; use a URL
   real mostrada no seu PC.
6. No celular, deixe o Tailscale **conectado**. Abra o MatterdiSistem e siga os
   passos de conexão abaixo. Você pode usar Wi-Fi de outro lugar ou 4G/5G.

Use a URL HTTPS completa, sem adicionar `:8080`. O APK atual rejeita endereços
HTTP da faixa `100.64.0.0/10` usada pelo Tailscale. O endereço `192.168...`
exibido pelo sistema é para a rede local; para este acesso, use a URL do Serve.

## Opção 2: Cloudflare Tunnel com endereço fixo

Esta opção precisa de uma conta Cloudflare e um domínio configurado nela.
O celular utiliza a URL HTTPS do domínio e não precisa instalar uma VPN.
[Pré-requisitos e configuração oficial](https://developers.cloudflare.com/tunnel/get-started/).

1. No painel Cloudflare, abra **Networking → Tunnels** e crie um túnel.
2. Em **Setup Environment**, selecione Windows e a arquitetura do PC.
   Instale `cloudflared` nesse PC seguindo o painel. Execute os comandos
   fornecidos pelo painel em um terminal como administrador para instalar o
   conector como serviço. Mantenha o token do túnel privado.
3. Confira se o túnel fica **Healthy**.
4. Em **Routes → Add route → Published application**, escolha um subdomínio,
   por exemplo `banco.suaempresa.com.br`. Em **Service URL**, informe
   `http://127.0.0.1:8080` e salve a rota.
5. No celular, informe `https://banco.suaempresa.com.br`, substituindo pelo
   domínio real, e a chave do banco gerada no sistema. Teste e salve.

O `cloudflared` e o sistema precisam continuar ativos no PC. A URL externa
usa HTTPS; o destino HTTP em `127.0.0.1` é a conexão local dentro do PC.
A autenticação do banco continua sendo a chave exigida pelo sistema.

O aplicativo atual não realiza o login interativo do Cloudflare Access.
Se adicionar essa proteção ao endereço, a conexão do aplicativo precisará de
uma integração adicional. O arquivo `.db` permanece no PC e não deve ser
publicado como arquivo para download.

## Conectar e confirmar pelo celular

1. Na tela de login, abra **Conexão com o banco**.
2. Selecione **Banco por IP ou hospedagem**.
3. Informe a URL HTTPS fornecida pelo Serve ou pelo domínio Cloudflare, sem
   acrescentar `/health` ou `/database`.
4. Informe a mesma chave do servidor do PC e toque em **Testar conexão**.
   Esse teste verifica o servidor com a chave de acesso; abrir a URL no
   navegador não substitui esse teste.
5. Ao aparecer **Conexão com o banco funcionando**, toque em
   **Salvar e voltar ao login**. Entre com o usuário e senha do banco do PC.
6. Para verificar fora da rede local, desligue o Wi-Fi do celular, ative os
   dados móveis e repita o teste. Na opção Tailscale, mantenha sua VPN ativa.

Abra um cadastro existente para confirmar que aparecem os dados do PC.
Atualize a tela para consultar alterações feitas no outro aparelho.

Se não conectar, confirme que o PC está ligado e sem suspensão, que o sistema
está aberto com o compartilhamento ativo, que a URL e a chave estão corretas
e que o Tailscale está conectado nos dois aparelhos ou o túnel Cloudflare
está **Healthy**. Caso existam regras de acesso personalizadas no Tailscale,
elas precisam permitir a conexão do celular ao PC pela porta HTTPS `443`.
Se a internet ou o PC ficar indisponível, o celular apresentará erro de conexão.

Faça backup pelo PC. Este acesso compartilha os dados do banco; fotos, logos
e arquivos armazenados separadamente no aparelho não são transferidos.
Para deixar o PC desligado e manter o acesso, use o
[guia do banco hospedado](banco_compartilhado_celular.md).
