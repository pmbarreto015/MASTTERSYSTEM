[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$dist = Join-Path $root 'dist'
$base = Join-Path $dist 'MatterdiSupabase-Windows'
$assets = Join-Path $root '.dart-tool-state\windows-finance-assets'
$destination = Join-Path $dist 'MatterdiFinanceiro20261009-Windows'
$kit = Join-Path $dist 'MatterdiFinanceiro20261009-Atualizacao'
$apk = Join-Path $dist 'MatterdiFinanceiro20261009.apk'
$utf8 = New-Object Text.UTF8Encoding($false)

foreach ($path in @($destination, $kit, $apk, ($destination + '.zip'), ($kit + '.zip'))) {
    if (Test-Path -LiteralPath $path) { throw "Destino já existe; preserve o pacote anterior: $path" }
}
$required = @(
    (Join-Path $assets 'windows\app.so'),
    (Join-Path $assets 'flutter_assets\NativeAssetsManifest.json'),
    (Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'),
    (Join-Path $base 'matterdisistem.exe'),
    (Join-Path $base 'data\icudtl.dat')
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Compilação incompleta: $path" }
}
$latestSource = (Get-ChildItem -LiteralPath (Join-Path $root 'lib') -Recurse -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
foreach ($artifact in @($required[0], $required[2])) {
    if ((Get-Item -LiteralPath $artifact).LastWriteTimeUtc -lt $latestSource) { throw "Compilação anterior ao código atual: $artifact" }
}
$sdkEngine = 'E:\Flutter\bin\cache\artifacts\engine\windows-x64-release\flutter_windows.dll'
if ((Get-FileHash -LiteralPath $sdkEngine).Hash -ne (Get-FileHash -LiteralPath (Join-Path $base 'flutter_windows.dll')).Hash) {
    throw 'O runner existente não corresponde ao SDK usado na compilação.'
}
New-Item -ItemType Directory -Path $destination, $kit | Out-Null
# As dependências nativas não mudaram; empacote o runner do mesmo SDK com o AOT e assets novos.
Get-ChildItem -LiteralPath $base -File | Where-Object { $_.Extension -in @('.exe', '.dll') } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $destination $_.Name)
}
$data = Join-Path $destination 'data'
New-Item -ItemType Directory -Path $data | Out-Null
Copy-Item -LiteralPath (Join-Path $base 'data\icudtl.dat') -Destination $data
Copy-Item -LiteralPath (Join-Path $assets 'windows\app.so') -Destination (Join-Path $data 'app.so')
Copy-Item -LiteralPath (Join-Path $assets 'flutter_assets') -Destination $data -Recurse
# SQLite deve ser resolvido dentro da distribuição, sem caminhos da máquina de desenvolvimento.
$manifest = '{"format-version":[1,0,0],"native-assets":{"windows_x64":{"package:sqlite3/src/ffi/libsqlite3.g.dart":["absolute","sqlite3.dll"]}}}'
[IO.File]::WriteAllText((Join-Path $destination 'native_assets.json'), $manifest, $utf8)
[IO.File]::WriteAllText((Join-Path $data 'flutter_assets\NativeAssetsManifest.json'), $manifest, $utf8)
Copy-Item -LiteralPath $required[2] -Destination $apk
$sql = "-- Atualização do projeto MatterdiSistem já instalado. Não executar a instalação inicial novamente.`r`nBEGIN;`r`n" +
    [IO.File]::ReadAllText((Join-Path $root 'supabase\migrations\20261009000000_accepted_sales.sql')) + "`r`nCOMMIT;`r`n"
[IO.File]::WriteAllText((Join-Path $kit '03_atualizar_orcamentos.sql'), $sql, $utf8)
Copy-Item -LiteralPath (Join-Path $root 'docs\financeiro_orcamentos.md') -Destination (Join-Path $kit 'README.md')
$instructions = @'
MatterdiSistem — Orçamentos e Financeiro — 09/10/2026

1. No Supabase existente, abra SQL Editor, cole 03_atualizar_orcamentos.sql
   do pacote Atualizacao e execute. Não rode 01_instalar_banco.sql novamente.
2. Extraia TODA esta pasta Windows e execute matterdisistem.exe.
   Mantenha as DLLs e a pasta data ao lado do executável.
3. Instale MatterdiFinanceiro20261009.apk no celular.
4. Preserve as configurações Supabase existentes e entre com sua conta.

Leia README.md do pacote Atualizacao para os novos recursos e os critérios
dos períodos. O pacote não inclui bancos locais, senhas ou chaves privadas.
'@
[IO.File]::WriteAllText((Join-Path $destination 'LEIA-ME.txt'), $instructions, $utf8)
Compress-Archive -LiteralPath $destination -DestinationPath ($destination + '.zip') -CompressionLevel Optimal
Compress-Archive -LiteralPath $kit -DestinationPath ($kit + '.zip') -CompressionLevel Optimal
$checksums = foreach ($path in @($apk, ($destination + '.zip'), ($kit + '.zip'))) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($path)
}
[IO.File]::WriteAllLines((Join-Path $dist 'MatterdiFinanceiro20261009-SHA256SUMS.txt'), [string[]]$checksums, $utf8)
Write-Output 'Pacotes Windows, Android e atualização SQL gerados.'
