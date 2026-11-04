# Administrador de licenças para APK e EXE

> A versão atual também oferece **ativação pela internet e chave offline com prazo**.
> Consulte [o guia das duas opções](licenciamento_internet_offline.md) para gerar os
> aplicativos, hospedar no Render e ativar clientes fora da rede local. O texto
> abaixo descreve especificamente o modo de rede local.

O administrador cria acessos de teste com prazo, controla a quantidade de dispositivos e permite renovar ou bloquear uma licença. Ele é um programa Windows separado do sistema usado pelo cliente.

## Gerar os programas

Com Flutter, as ferramentas de compilação Windows e o SDK Android configurados, execute os arquivos na pasta `tool`:

1. `compilar_servidor_licencas.bat`: gera o administrador. Você cria sua senha no próprio programa ao abri-lo pela primeira vez.
2. `compilar_cliente_rede.bat`: gera o sistema para Windows.
3. `compilar_cliente_apk.bat`: gera o sistema para Android.

Também é possível gerar os três de uma vez, no PowerShell aberto na pasta do projeto:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\compilar_licencas.ps1
```

Para gerar apenas o administrador e o cliente Windows, acrescente `-SkipAndroid`. O parâmetro `-Alvo Servidor`, `-Alvo Windows` ou `-Alvo Android` gera somente o programa escolhido.

Os resultados ficam em:

- `dist/ServidorLicencas/ServidorLicencas.exe`: administrador; mantenha no computador responsável pelas licenças.
- `dist/MastterSystemCliente/matterdisistem.exe`: cliente Windows; envie a pasta inteira, com as DLLs e a pasta `data`.
- `dist/MastterSystemCliente.apk`: cliente Android; instale nos celulares autorizados.

A compilação padrão não precisa de senha administrativa. Na primeira abertura do administrador, defina uma senha própria com pelo menos 8 caracteres; ela será guardada como hash nos dados locais do administrador. Os clientes recebem apenas a configuração de licenciamento. Opcionalmente, `-DefinirSenhaNaCompilacao` pede uma senha oculta e inclui somente seu hash no administrador; essa opção mantém o modo anterior de senha definida durante a compilação. Pacotes existentes são preservados com o sufixo `-anterior-` antes da substituição. A compilação gera também um arquivo de conferência SHA256 em `dist`.

## Criar um teste com prazo

1. Abra `ServidorLicencas.exe` no computador principal. Na primeira abertura, crie e confirme sua senha administrativa. Nas próximas aberturas, entre com ela.
2. Permita o acesso no Firewall do Windows para a rede privada usada pelos clientes. O serviço de licenças usa a porta TCP **8787**; a localização automática usa UDP **8788**.
3. Clique em **Novo acesso** e preencha nome do cliente, login e senha para instalação.
4. Em **Liberar para**, escolha **APK (Android)**, **EXE (Windows)** ou **APK e EXE (ambos)**.
5. Em **Limite de dispositivos**, informe quantos celulares e computadores podem usar esse acesso. O limite é o total dos dois tipos quando ambos estão liberados.
6. Em **Prazo da licença**, escolha um teste de 1, 7, 15 ou 30 dias. O padrão de um novo acesso é **7 dias**. Para outro prazo, escolha **Duração personalizada** e informe a quantidade em horas ou dias. Para definir o vencimento exato, escolha **Data e hora de vencimento**. A opção **Permanente (sem vencimento)** cria um acesso sem prazo.
7. Confira a data e a hora exibidas e clique em **Criar acesso**. O teste passa a valer pela data de vencimento mostrada nessa tela, sem esperar a primeira instalação.
8. Copie as informações do acesso e forneça ao cliente o endereço do servidor, o login e a senha para instalação.
9. Use o cadeado para bloquear o painel e mantenha o programa aberto. O computador principal precisa ficar ligado e acessível.

O horário exibido no administrador é o horário local desse computador. Mantenha sua data e sua hora corretas.

## Ativar no APK ou EXE

1. Conecte o celular e os computadores à rede do servidor. No celular, use o mesmo Wi-Fi.
2. Abra o cliente e, na tela de ativação, use a opção para localizar o servidor ou informe o endereço manualmente, por exemplo `192.168.1.10:8787`.
3. Digite o login e a senha para instalação criados no administrador e ative o dispositivo.
4. Entre no sistema com a conta de usuário do aplicativo.

O login de licença libera a instalação. Ele é separado dos usuários e das senhas do sistema, inclusive das contas configuradas no banco de dados. O endereço do servidor de licenças também é separado da conexão com SQLite, Supabase ou outro banco já configurado. Esta alteração não cria usuários do banco nem altera a instalação SQL existente.

## Vencimento, renovação e bloqueio

O cliente valida a licença ao abrir, ao voltar para o aplicativo e periodicamente, a cada cinco minutos. O prazo informado pelo servidor também é acompanhado enquanto o aplicativo está aberto. Quando ele vence, o acesso é bloqueado e o cliente deve solicitar a renovação.

As licenças com prazo precisam alcançar o servidor nas validações. Se ele estiver desligado ou inacessível, a validação não libera o acesso temporário. Uma alteração feita no administrador, como um bloqueio ou uma renovação, é reconhecida na próxima validação do cliente; não depende de recompilar o APK ou o EXE. Licenças permanentes mantêm a tolerância de até três dias sem conexão após uma validação bem-sucedida, desde que não tenha ocorrido uma recusa de acesso do servidor.

Para renovar, expanda o cliente e clique em **Renovar / editar licença**. Escolha o novo prazo ou a nova data e hora, confira o vencimento e salve. Confira a nova data de vencimento exibida antes de salvar. Você também pode ajustar a plataforma e o limite de dispositivos. Se o cliente estava bloqueado manualmente, reative o botão de acesso.

Para interromper o acesso manualmente, desligue o botão da licença. Para substituir um celular ou computador, libere a vaga do dispositivo antigo na lista e ative o novo. Liberar uma vaga remove a autorização daquele dispositivo.

## Rede e conservação dos dados

O uso principal é na rede local. Este projeto não inclui um serviço de licenças hospedado na internet. Para clientes em outra rede, o administrador precisa disponibilizar um endereço alcançável por VPN ou por um proxy HTTPS configurado de forma segura. A localização automática funciona na rede local; fora dela, informe o endereço manualmente.

Mantenha o administrador e os dados das licenças em um computador confiável, sob controle de quem concede os acessos. A senha do painel protege a interface, mas quem tem controle dos arquivos desse computador pode alterar os dados do servidor. Distribua aos clientes o APK ou a pasta do EXE do sistema.

Faça backup de `lan_licenses.json`, armazenado na pasta de dados do aplicativo Windows. Cadastros anteriores sem data de vencimento são mantidos como permanentes; use **Renovar / editar licença** para atribuir um prazo se necessário. Para receber o controle de validade, as instalações precisam usar os novos APK e EXE recompilados; arquivos antigos não passam a controlar o vencimento apenas porque o administrador foi atualizado.
