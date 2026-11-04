[CmdletBinding()]
param([string]$OutputDirectory = '', [string]$ExportBundleDirectory = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$distRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'dist'))
$utf8 = New-Object Text.UTF8Encoding($false)

function Assert-ChildPath {
    param([string]$Path, [string]$Parent)
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $resolvedParent = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    $prefix = $resolvedParent + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "O destino deve estar dentro de $resolvedParent."
    }
    return $resolvedPath
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $distRoot 'MatterdiSupabase'
} elseif (-not [IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot $OutputDirectory
}
$outputPath = Assert-ChildPath -Path $OutputDirectory -Parent $distRoot
$archivePath = Assert-ChildPath -Path ($outputPath + '.zip') -Parent $distRoot
if ((Test-Path -LiteralPath $outputPath) -or (Test-Path -LiteralPath $archivePath)) {
    throw 'O destino ou o ZIP ja existe. Escolha outro -OutputDirectory; o pacote anterior sera preservado.'
}

$migrations = @(
    '20261003000000_initial_schema.sql',
    '20261006000000_auth_permissions.sql',
    '20261006010000_data_api.sql',
    '20261006020000_business_rpc.sql',
    '20261009000000_accepted_sales.sql',
    '20261024000000_erp_modules.sql'
)
$sourceFiles = [ordered]@{
    'tool\supabase_bootstrap_admin.sql' = '02_criar_admin.sql'
    'supabase\config.toml' = 'supabase\config.toml'
    'supabase\functions\matterdi-users\index.ts' = 'supabase\functions\matterdi-users\index.ts'
    'docs\supabase_nuvem.md' = 'docs\supabase_nuvem.md'
    'docs\supabase_primeiro_admin.md' = 'docs\supabase_primeiro_admin.md'
    'tool\exportar_sqlite_supabase.dart' = 'exportador\bin\exportar_sqlite_supabase.dart'
}
foreach ($relativePath in @($sourceFiles.Keys) + @($migrations | ForEach-Object { 'supabase\migrations\' + $_ })) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath) -PathType Leaf)) {
        throw "Arquivo necessario ausente: $relativePath"
    }
}

$nativeFiles = @()
if (-not [string]::IsNullOrWhiteSpace($ExportBundleDirectory)) {
    if (-not [IO.Path]::IsPathRooted($ExportBundleDirectory)) {
        $ExportBundleDirectory = Join-Path $projectRoot $ExportBundleDirectory
    }
    $ExportBundleDirectory = Assert-ChildPath -Path $ExportBundleDirectory -Parent $projectRoot
    $nativeFiles = @(
        @{ Source = 'bin\exportar_sqlite_supabase.exe'; Destination = 'exportador_windows\bin\exportar_sqlite_supabase.exe' },
        @{ Source = 'lib\sqlite3.dll'; Destination = 'exportador_windows\lib\sqlite3.dll' }
    )
    foreach ($entry in $nativeFiles) {
        $entry.Source = Join-Path $ExportBundleDirectory $entry.Source
        if (-not (Test-Path -LiteralPath $entry.Source -PathType Leaf)) {
            throw "Bundle do exportador incompleto: $($entry.Source)"
        }
    }
}

New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
$stagePath = Assert-ChildPath -Path (Join-Path $distRoot ('.supabase-kit-' + [Guid]::NewGuid().ToString('N'))) -Parent $distRoot
$kitPath = Assert-ChildPath -Path (Join-Path $stagePath 'MatterdiSupabase') -Parent $stagePath
$stageArchive = Assert-ChildPath -Path (Join-Path $stagePath 'MatterdiSupabase.zip') -Parent $stagePath

try {
    New-Item -ItemType Directory -Path $kitPath | Out-Null
    foreach ($entry in $sourceFiles.GetEnumerator()) {
        $destination = Join-Path $kitPath $entry.Value
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $projectRoot $entry.Key) -Destination $destination
    }

    $combined = New-Object Text.StringBuilder
    [void]$combined.AppendLine('-- MatterdiSistem: instalacao inicial em um projeto Supabase vazio.')
    [void]$combined.AppendLine('-- Revise antes de executar no SQL Editor. Nenhuma conta ou senha padrao e criada.')
    [void]$combined.AppendLine('BEGIN;')
    foreach ($migration in $migrations) {
        $sourcePath = Join-Path (Join-Path $projectRoot 'supabase\migrations') $migration
        $sql = [IO.File]::ReadAllText($sourcePath)
        if ($sql -match '(?im)^\s*(BEGIN|COMMIT|ROLLBACK)\s*;') {
            throw "A migracao $migration possui controle de transacao proprio. Revise a combinacao."
        }
        [void]$combined.AppendLine('')
        [void]$combined.AppendLine('-- MIGRACAO: ' + $migration)
        [void]$combined.AppendLine($sql.Trim())
        $destination = Join-Path $kitPath ('supabase\migrations\' + $migration)
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destination
    }
    [void]$combined.AppendLine('COMMIT;')
    [IO.File]::WriteAllText((Join-Path $kitPath '01_instalar_banco.sql'), $combined.ToString(), $utf8)

    $exportPubspec = @'
name: matterdi_exportador_supabase
description: Exportador SQLite para PostgreSQL do MatterdiSistem.
publish_to: none
environment:
  sdk: '>=3.11.0 <4.0.0'
dependencies:
  sqlite3: 3.5.1
  path: ^1.9.1
'@
    [IO.File]::WriteAllText((Join-Path $kitPath 'exportador\pubspec.yaml'), $exportPubspec + [Environment]::NewLine, $utf8)
    foreach ($entry in $nativeFiles) {
        $destination = Join-Path $kitPath $entry.Destination
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $entry.Source -Destination $destination
    }

    $readme = @'
# MatterdiSistem no Supabase

Este pacote prepara o mesmo banco PostgreSQL para PC e celular pela internet.
Projeto: https://fxaktapjvbakbitsxbjl.supabase.co

A instalacao no Supabase ainda precisa ser feita pelo dono do projeto. A chave
publica recebida identifica o aplicativo, mas nao permite instalar tabelas,
criar o administrador ou publicar funcoes. O pacote nao contem banco de dados,
senhas nem chaves privadas.

## 1. Instalar o banco

Entre no painel do projeto, abra SQL Editor, cole 01_instalar_banco.sql e
execute. Use um projeto vazio para a instalacao inicial. As seis migracoes
sao reunidas em uma transacao: um erro cancela a instalacao inteira. Nao apague
tabelas existentes para contornar erros; revise os dados ou use outro projeto.

## 2. Trazer os dados atuais (opcional)

Abra o banco na versao atual do MatterdiSistem (SQLite versao 28), feche o
aplicativo e trabalhe com uma copia de seguranca. Com o exportador Windows,
se essa pasta estiver incluida:

    .\exportador_windows\bin\exportar_sqlite_supabase.exe --database "C:\caminho\matterdi_sistem.db" --output "importar_dados.sql"

Mantenha bin e lib juntas. Como alternativa, com Dart 3.11 ou maior:

    cd exportador
    dart pub get
    dart run bin/exportar_sqlite_supabase.dart --database "C:\caminho\matterdi_sistem.db" --output "importar_dados.sql"

O exportador abre o SQLite somente para leitura, preserva os IDs e gera uma
transacao SQL. Revise o arquivo e execute-o no SQL Editor depois do passo 1.
O banco central deve estar sem dados: conflitos cancelam toda a importacao.
system_users, senhas e hashes nao sao exportados; contas usam Supabase Auth.

## 3. Criar o primeiro administrador

Em Authentication > Users, crie uma conta com e-mail confirmado e senha nova.
Em 02_criar_admin.sql, troque ALTERE_PARA_O_EMAIL_DO_ADMINISTRADOR por esse
e-mail e execute no SQL Editor. O script vincula a conta Auth ao administrador
e recusa conflitos. Em Authentication > Providers > Email, desative a criacao
publica de contas. Funcionarios sao cadastrados pelo administrador no sistema.

## 4. Publicar a funcao de usuarios

Pelo painel, abra **Edge Functions > Deploy a new function > Via Editor**,
use o nome `matterdi-users`, substitua o conteúdo de `index.ts` pelo arquivo
`supabase/functions/matterdi-users/index.ts` deste pacote e publique. Mantenha
a validação JWT habilitada. Esse caminho usa o
[editor oficial do Supabase](https://supabase.com/docs/guides/functions/quickstart-dashboard).

Como alternativa, com a CLI oficial do Supabase instalada, abra um terminal nesta pasta:

    supabase login
    supabase link --project-ref fxaktapjvbakbitsxbjl
    supabase functions deploy matterdi-users

A CLI precisa da sua sessao administrativa. A chave Publishable nao serve
para administrar o projeto. supabase/config.toml mantem a validacao JWT;
a funcao tambem confirma a sessao e o perfil administrador antes de administrar
outros usuarios. As chaves privadas ficam no ambiente gerenciado da funcao,
nunca no aplicativo.

O aplicativo envia a chave publica no cabecalho apikey e o JWT do usuario no
cabecalho Authorization. A funcao exige a sessao confirmada no Supabase Auth
e um administrador ativo. Essa configuracao segue a referencia oficial:
https://supabase.com/docs/guides/functions/auth-headers

Se houver erro 401 da plataforma mesmo depois de entrar com uma sessao valida,
confira os logs da funcao e o diagnostico oficial antes de mudar configuracoes:
https://supabase.com/docs/guides/troubleshooting/edge-function-401-error-response
A validacao da sessao e do administrador dentro da funcao deve permanecer.

## 5. Usar no PC e no celular

Instale as versoes com suporte ao Supabase fornecidas separadamente. Abra
Conexao com o banco, escolha Supabase (internet), use a URL deste projeto e a
chave publica Publishable, toque em Testar Supabase e salve. Entre com o e-mail
e a senha do passo 3 nos dois aparelhos.

Os aparelhos precisam de internet e podem estar em redes diferentes. O PC
pode ficar desligado. Cada aparelho tem sua propria sessao de usuario e acessa
os mesmos dados do banco central. Use os recursos do projeto Supabase para
backup; o backup local .db atende somente ao modo SQLite.

Se o teste disser que o banco nao foi instalado, conclua o passo 1. Se o login
nao encontrar perfil ativo, conclua o passo 3. Para erros ao administrar
usuarios, confira a publicacao do passo 4. Os guias em docs detalham o fluxo
no projeto fonte; este README usa os caminhos do pacote distribuido.
SHA256SUMS.txt lista os hashes dos arquivos para conferencia.
'@
    [IO.File]::WriteAllText((Join-Path $kitPath 'README.md'), $readme + [Environment]::NewLine, $utf8)

    $manifest = New-Object Text.StringBuilder
    $kitPrefix = $kitPath.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    foreach ($file in (Get-ChildItem -LiteralPath $kitPath -Recurse -File | Sort-Object FullName)) {
        $relativePath = $file.FullName.Substring($kitPrefix.Length).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        [void]$manifest.AppendLine($hash + '  ' + $relativePath)
    }
    [IO.File]::WriteAllText((Join-Path $kitPath 'SHA256SUMS.txt'), $manifest.ToString(), $utf8)
    Compress-Archive -LiteralPath $kitPath -DestinationPath $stageArchive -CompressionLevel Optimal
    Move-Item -LiteralPath $kitPath -Destination $outputPath
    Move-Item -LiteralPath $stageArchive -Destination $archivePath
    Write-Output "Pacote criado: $outputPath"
    Write-Output "ZIP criado: $archivePath"
} finally {
    if (Test-Path -LiteralPath $stagePath) {
        $verifiedStage = Assert-ChildPath -Path $stagePath -Parent $distRoot
        Remove-Item -LiteralPath $verifiedStage -Recurse -Force
    }
}
