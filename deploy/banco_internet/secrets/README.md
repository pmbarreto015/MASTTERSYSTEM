Crie aqui, somente na hospedagem, o arquivo `chave_banco` com uma chave
aleatória de pelo menos 24 caracteres. O Compose monta esse arquivo em
`/run/secrets/chave_banco` apenas no servidor de banco.

O kit distribuído não contém uma chave real. Mantenha o arquivo com permissão
`600` e a pasta com permissão `700`. O backend usa o usuário padrão da imagem
para conseguir ler esse segredo montado; não adicione `user:` ao Compose sem
ajustar também as permissões do segredo e da pasta de dados.
