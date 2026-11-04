# Mesmo banco no PC e no celular

O aplicativo pode acessar o banco SQLite principal por um servidor HTTP com
chave de acesso. Cadastros, pedidos, estoque e financeiro são lidos e gravados
diretamente nesse banco. O celular não precisa copiar o arquivo `.db`.

## Usar o PC como servidor na mesma rede

1. Instale a versão atualizada do sistema no PC e no celular.
2. No PC, abra **Configurações → Conexão com o banco**. Mantenha o banco local
   ou o arquivo compartilhado que já contém seus dados.
3. Ative o servidor de dados, gere uma chave e salve. A porta padrão é `8080`.
4. Copie um dos endereços exibidos, por exemplo `http://192.168.1.10:8080`.
   Se o Windows solicitar, permita o aplicativo no firewall para a rede privada.
5. No celular, na tela de login, abra **Conexão com o banco**, selecione o
   servidor e informe esse endereço e a mesma chave. Teste e salve.
6. Entre com um usuário e senha cadastrados no banco do PC.

O PC precisa permanecer ligado com o sistema aberto, e os aparelhos precisam
conseguir se comunicar na rede. Reserve o IP do PC no roteador para o endereço
não mudar. O servidor volta a iniciar quando o aplicativo do PC é aberto.
Atualize/recarregue a tela para consultar alterações feitas no outro aparelho.

O arquivo SQLite continua no PC. O modo de servidor não envia os dados que já
existem somente no celular: exporte esses registros antes de trocar a conexão.
Faça backup e restauração no PC. Desative o servidor antes de restaurar ou
trocar o arquivo do banco.

## Usar fora da mesma rede (4G/5G ou outro Wi-Fi)

O aplicativo já aceita uma URL HTTPS. O endereço `192.168.x.x` do PC é da rede
local e não funciona sozinho pela internet. Há duas formas de conectar:

| Onde fica o banco | Como acessar | O PC precisa ficar ligado? |
| --- | --- | --- |
| No PC principal | Túnel HTTPS com Tailscale Serve ou Cloudflare Tunnel | Sim, com o sistema aberto |
| Em uma VPS | Servidor de dados com HTTPS e armazenamento persistente | Não |

Para manter os dados no PC, siga [Acesso ao banco do PC pela internet](acesso_internet_pc.md).
O celular informa a URL HTTPS e a mesma chave gerada no PC. O banco do PC
continua sendo o banco principal, mesmo com o celular usando dados móveis.

## Colocar o banco em uma hospedagem

Se a hospedagem escolhida for o **Render**, siga
[o guia específico do Render](../deploy/banco_internet/RENDER.md): ele usa um
Web Service Docker pago, disco persistente e a URL HTTPS da plataforma.
O APK atual já aceita esse endereço. Os passos abaixo são para uma VPS própria.

Use uma VPS ou servidor que execute Dart e tenha armazenamento persistente.
Uma hospedagem que apenas entrega arquivos estáticos não executa o servidor.

1. Faça um backup do banco atualizado no PC e transfira esse arquivo para o
   servidor. Use uma única cópia central como banco ativo.
2. No Windows, gere o pacote de hospedagem a partir da pasta do projeto:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tool/preparar_banco_internet.ps1
   ```

   Ele cria `dist/MatterdiBancoInternet`, com o servidor Dart independente,
   Docker Compose e Caddy. O pacote não contém seu banco nem sua chave.
   Veja os passos completos em [kit de hospedagem](../deploy/banco_internet/README.md).
3. Transfira esse pacote para a VPS com Docker Compose. Configure um domínio
   apontando para o IP público da VPS e disponibilize as portas 80 e 443.
4. Coloque o backup e a chave nos arquivos indicados no README. Configure o
   domínio no `.env` e inicie os serviços. O Caddy encaminha as requisições
   para o servidor de dados e administra o certificado HTTPS.
5. No PC e no celular, selecione o modo servidor e informe a mesma URL, como
   `https://sistema.suaempresa.com.br`, e a mesma chave. Teste e salve.

O kit é uma configuração para instalar em sua VPS; a geração do pacote não
cria uma hospedagem nem publica um endereço. Confirme uma conexão pelo celular
com o Wi-Fi desligado antes de começar a usar em produção.

Na hospedagem, PC e celular precisam de internet; o PC pode ser desligado.
A chave permite acessar o banco inteiro e deve ser compartilhada somente com
os dispositivos autorizados. As permissões do login atual continuam sendo
aplicadas pelo aplicativo. O serviço é de uma única empresa; não é um servidor
multiempresa com isolamento por usuário. Para acesso pela internet, o
aplicativo exige HTTPS. HTTP é aceito somente para IP privado ou localhost.

Os backups ficam a cargo do servidor. Não disponibilize o `.db` por uma URL
pública. Fotos, logos, documentos e preferências do aparelho não são
transferidos por esta conexão; o compartilhamento cobre os dados do banco.

## Falha de conexão

Se o servidor estiver indisponível, a operação apresenta erro e não passa a
gravar em outro banco local. Abra **Conexão com o banco** na tela de login para
corrigir o endereço ou a chave. Uma perda de conexão ao confirmar uma gravação
pode deixar a confirmação incerta; consulte o registro antes de repetir a ação.
Transações abandonadas são revertidas pelo servidor após o prazo de inatividade.

Referências: [servidores HTTP em Dart](https://api.dart.dev/dart-io/HttpServer-class.html)
e [configuração de rede do Android](https://developer.android.com/privacy-and-security/security-config).
