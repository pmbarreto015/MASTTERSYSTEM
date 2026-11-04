[CmdletBinding()]
param(
    [string]$OutputDirectory = '',
    [switch]$BuildLocalBundle,
    [string]$DartExecutable = 'dart',
    [switch]$Offline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$distRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'dist'))
$templateRoot = Join-Path $projectRoot 'deploy\banco_internet'
$pathComparison = [StringComparison]::OrdinalIgnoreCase

function Assert-InDirectory {
    param([string]$Path, [string]$Parent)
    $absolutePath = [IO.Path]::GetFullPath($Path)
    $absoluteParent = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    $prefix = $absoluteParent + [IO.Path]::DirectorySeparatorChar
    if (-not $absolutePath.StartsWith($prefix, $pathComparison)) {
        throw "O destino deve estar dentro de $absoluteParent."
    }
    return $absolutePath
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $outputPath = Join-Path $distRoot 'MatterdiBancoInternet'
} elseif ([IO.Path]::IsPathRooted($OutputDirectory)) {
    $outputPath = $OutputDirectory
} else {
    $outputPath = Join-Path $projectRoot $OutputDirectory
}
$outputPath = Assert-InDirectory -Path $outputPath -Parent $distRoot
$archivePath = Assert-InDirectory -Path ($outputPath + '.zip') -Parent $distRoot
if ((Test-Path -LiteralPath $outputPath) -or
    (Test-Path -LiteralPath $archivePath)) {
    throw 'O destino ou o ZIP já existe. Escolha outro -OutputDirectory; dados e chaves existentes serão preservados.'
}

$rpcPath = Join-Path $projectRoot 'lib\services\database_rpc_server.dart'
$cliPath = Join-Path $projectRoot 'tool\servidor_banco.dart'
$renderPath = Join-Path $projectRoot 'tool\servidor_render.dart'
foreach ($requiredPath in @($templateRoot, $rpcPath, $cliPath, $renderPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Arquivo necessário não encontrado: $requiredPath"
    }
}

New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
$stagePath = Assert-InDirectory -Path (Join-Path $distRoot ('.banco-internet-' + [Guid]::NewGuid().ToString('N'))) -Parent $distRoot
$kitPath = Assert-InDirectory -Path (Join-Path $stagePath 'kit') -Parent $stagePath
$utf8 = New-Object Text.UTF8Encoding($false)
$originalAnalytics = [Environment]::GetEnvironmentVariable('DART_SUPPRESS_ANALYTICS', 'Process')

try {
    New-Item -ItemType Directory -Path $kitPath -Force | Out-Null
    $kitFiles = @(
        'Dockerfile', '.dockerignore', 'compose.yaml', 'Caddyfile',
        '.env.example', 'README.md', 'data\README.md', 'secrets\README.md',
        'Dockerfile.render', 'render.yaml', 'RENDER.md', '.gitignore'
    )
    foreach ($relativePath in $kitFiles) {
        $destination = Join-Path $kitPath $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $templateRoot $relativePath) -Destination $destination
    }

    $sourcePath = Join-Path $kitPath 'source'
    New-Item -ItemType Directory -Path (Join-Path $sourcePath 'bin') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $sourcePath 'lib\services') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $templateRoot 'pubspec.yaml') -Destination (Join-Path $sourcePath 'pubspec.yaml')
    $kitFiles += 'source\pubspec.yaml'
    $templateLock = Join-Path $templateRoot 'pubspec.lock'
    if (Test-Path -LiteralPath $templateLock) {
        Copy-Item -LiteralPath $templateLock -Destination (Join-Path $sourcePath 'pubspec.lock')
        $kitFiles += 'source\pubspec.lock'
    }

    $rpcSource = [IO.File]::ReadAllText($rpcPath)
    $rpcSource = $rpcSource.Replace('package:sqflite/sqlite_api.dart', 'package:sqflite_common/sqlite_api.dart')
    $cliSource = [IO.File]::ReadAllText($cliPath)
    $cliSource = $cliSource.Replace('package:masttersystem/', 'package:matterdi_banco_internet/')
    $cliSource = $cliSource.Replace('../lib/services/database_rpc_server.dart', 'package:matterdi_banco_internet/services/database_rpc_server.dart')
    $cliSource = $cliSource.Replace('tool/servidor_banco.dart', 'bin/servidor_banco.dart')
    if ($rpcSource.Contains('package:flutter/') -or $cliSource.Contains('package:flutter/') -or
        $rpcSource.Contains('package:sqflite/') -or $cliSource.Contains('package:masttersystem/')) {
        throw 'O servidor passou a depender do aplicativo Flutter. Revise a extração do pacote antes de distribuí-lo.'
    }
    [IO.File]::WriteAllText((Join-Path $sourcePath 'lib\services\database_rpc_server.dart'), $rpcSource, $utf8)
    [IO.File]::WriteAllText((Join-Path $sourcePath 'bin\servidor_banco.dart'), $cliSource, $utf8)
    $kitFiles += @('source\lib\services\database_rpc_server.dart', 'source\bin\servidor_banco.dart')
    Copy-Item -LiteralPath $renderPath -Destination (Join-Path $sourcePath 'bin\servidor_render.dart')
    $kitFiles += 'source\bin\servidor_render.dart'

    if ($BuildLocalBundle) {
        $resolvedDart = (Get-Command $DartExecutable -ErrorAction Stop).Source
        $workPath = Join-Path $stagePath 'build-work'
        New-Item -ItemType Directory -Path $workPath -Force | Out-Null
        foreach ($relativePath in $kitFiles | Where-Object { $_.StartsWith('source\') }) {
            $workFile = Join-Path $workPath $relativePath.Substring(7)
            New-Item -ItemType Directory -Path (Split-Path -Parent $workFile) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $kitPath $relativePath) -Destination $workFile
        }
        $env:DART_SUPPRESS_ANALYTICS = 'true'
        Push-Location $workPath
        try {
            $pubArguments = @('--suppress-analytics', 'pub', 'get')
            if ($Offline) { $pubArguments += '--offline' }
            & $resolvedDart @pubArguments
            if ($LASTEXITCODE -ne 0) { throw 'Falha ao resolver as dependências do pacote Dart.' }
            foreach ($entryPoint in @('servidor_banco', 'servidor_render')) {
                & $resolvedDart --suppress-analytics build cli "--target=bin/$entryPoint.dart" "--output=compiled/$entryPoint"
                if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar o bundle $entryPoint." }
            }
        } finally {
            Pop-Location
        }
        $runtimePath = Join-Path $kitPath 'local-runtime'
        New-Item -ItemType Directory -Path $runtimePath -Force | Out-Null
        foreach ($entryPoint in @('servidor_banco', 'servidor_render')) {
            $bundlePath = Join-Path $workPath "compiled\$entryPoint\bundle"
            if (-not (Test-Path -LiteralPath (Join-Path $bundlePath 'bin'))) {
                throw "O SDK não gerou o bundle esperado para $entryPoint."
            }
            foreach ($bundleFile in Get-ChildItem -LiteralPath $bundlePath -File -Recurse -Force) {
                $relativeBundleFile = $bundleFile.FullName.Substring($bundlePath.Length + 1)
                $runtimeFile = Assert-InDirectory -Path (Join-Path $runtimePath $relativeBundleFile) -Parent $runtimePath
                if (Test-Path -LiteralPath $runtimeFile) {
                    if ((Get-FileHash -LiteralPath $runtimeFile).Hash -ne (Get-FileHash -LiteralPath $bundleFile.FullName).Hash) {
                        throw "Os bundles produziram bibliotecas diferentes com o mesmo nome: $relativeBundleFile"
                    }
                } else {
                    New-Item -ItemType Directory -Path (Split-Path -Parent $runtimeFile) -Force | Out-Null
                    Copy-Item -LiteralPath $bundleFile.FullName -Destination $runtimeFile
                }
            }
        }
        $generatedLock = Join-Path $workPath 'pubspec.lock'
        Copy-Item -LiteralPath $generatedLock -Destination (Join-Path $sourcePath 'pubspec.lock') -Force
        if ($kitFiles -notcontains 'source\pubspec.lock') { $kitFiles += 'source\pubspec.lock' }
        foreach ($bundleFile in Get-ChildItem -LiteralPath $runtimePath -File -Recurse -Force) {
            $kitFiles += $bundleFile.FullName.Substring($kitPath.Length + 1)
        }
    }

    # A lista de arquivos vem exclusivamente do template, dos dois Dart extraídos
    # e do bundle compilado em staging. Nenhuma pasta de dados é enumerada.
    Add-Type -AssemblyName System.IO.Compression
    $stageArchive = Join-Path $stagePath 'MatterdiBancoInternet.zip'
    $stream = [IO.File]::Open($stageArchive, [IO.FileMode]::CreateNew)
    $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($relativePath in $kitFiles) {
            if ($relativePath -match '(?i)(\.db(?:$|-)|(?:^|[\\/])\.env$|(?:^|[\\/])chave_banco$|(?:^|[\\/])\.dart_tool[\\/])') {
                throw "Arquivo não permitido no pacote: $relativePath"
            }
            $entry = $archive.CreateEntry($relativePath.Replace('\', '/'))
            $input = [IO.File]::OpenRead((Join-Path $kitPath $relativePath))
            $entryStream = $entry.Open()
            try { $input.CopyTo($entryStream) } finally { $entryStream.Dispose(); $input.Dispose() }
        }
    } finally {
        $archive.Dispose()
        $stream.Dispose()
    }

    if ((Test-Path -LiteralPath $outputPath) -or (Test-Path -LiteralPath $archivePath)) {
        throw 'O destino foi criado por outro processo. Escolha outro -OutputDirectory.'
    }
    Assert-InDirectory -Path $kitPath -Parent $stagePath | Out-Null
    Assert-InDirectory -Path $outputPath -Parent $distRoot | Out-Null
    # Copie os arquivos permitidos para um destino novo: indexadores da IDE
    # podem manter diretórios do staging abertos e impedir sua renomeação.
    New-Item -ItemType Directory -Path $outputPath | Out-Null
    foreach ($relativePath in $kitFiles) {
        $sourceFile = Assert-InDirectory -Path (Join-Path $kitPath $relativePath) -Parent $kitPath
        $outputFile = Assert-InDirectory -Path (Join-Path $outputPath $relativePath) -Parent $outputPath
        New-Item -ItemType Directory -Path (Split-Path -Parent $outputFile) -Force | Out-Null
        Copy-Item -LiteralPath $sourceFile -Destination $outputFile
    }
    Assert-InDirectory -Path $stageArchive -Parent $stagePath | Out-Null
    Assert-InDirectory -Path $archivePath -Parent $distRoot | Out-Null
    Move-Item -LiteralPath $stageArchive -Destination $archivePath
    Write-Host "Kit criado: $outputPath"
    Write-Host "ZIP criado: $archivePath"
    Write-Host 'O banco real e a chave devem ser colocados apenas na hospedagem.'
} finally {
    [Environment]::SetEnvironmentVariable('DART_SUPPRESS_ANALYTICS', $originalAnalytics, 'Process')
    if (Test-Path -LiteralPath $stagePath) {
        try {
            # Resolve e confere o alvo antes de excluir recursivamente o staging.
            $checkedStage = Assert-InDirectory -Path (Resolve-Path -LiteralPath $stagePath).Path -Parent $distRoot
            Remove-Item -LiteralPath $checkedStage -Recurse -Force
        } catch {
            # Um arquivo em uso pelo SDK/IDE não deve esconder a falha original
            # da geração, nem transformar um kit pronto em uma falha de build.
            Write-Warning "Não foi possível limpar o staging $stagePath. Ele foi preservado para inspeção: $($_.Exception.Message)"
        }
    }
}
