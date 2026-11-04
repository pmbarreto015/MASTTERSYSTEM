# Cadastro de usuarios no Supabase

O cadastro pela internet usa a funcao `matterdi-users`, alem das tabelas SQL.
Quando essa funcao nao foi publicada, o Supabase responde `404 NOT_FOUND`.

1. Abra o projeto usado na conexao do aplicativo no painel do Supabase.
2. Entre em **Edge Functions > Deploy a new function > Via Editor**.
3. No campo **Function name**, substitua o nome sugerido (por exemplo,
   `quick-processor`) por **matterdi-users**, com letras minusculas e hifen.
4. Abra `supabase/functions/matterdi-users/index.ts` deste projeto e copie seu
   conteudo inteiro para o arquivo `index.ts` do editor, substituindo o exemplo.
5. Clique em **Deploy function** e mantenha a verificacao JWT ativada.
6. Volte ao sistema, entre com a conta administradora e tente salvar o usuario.

As credenciais administrativas usadas pela funcao ficam no ambiente do Supabase.
A funcao exige uma sessao valida e um perfil administrador ativo antes de criar
a conta e vincular o perfil. Se o perfil falhar, desfaz a conta que acabou de criar.

Para quem ja usa a CLI autenticada, execute na pasta deste projeto:

```powershell
supabase functions deploy matterdi-users --project-ref fxaktapjvbakbitsxbjl
```

Publicar a funcao permite usar o cadastro no EXE e APK existentes. O pacote Windows
atualizado tambem informa o erro real quando a publicacao, sessao ou permissao falha.

Guia oficial: https://supabase.com/docs/guides/functions/quickstart-dashboard
