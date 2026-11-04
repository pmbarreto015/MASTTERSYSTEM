[CmdletBinding()]
param([string]$SavedAssets)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$logRoot = Join-Path $projectRoot 'build\validacao-rh'
$java = 'E:\Nova pasta\Android Studio\jbr\bin\java.exe'
$buildTools = 'E:\Android\Sdk\build-tools\36.1.0'
$apkSigner = Join-Path $buildTools 'lib\apksigner.jar'
$dart = 'E:\Flutter\bin\cache\dart-sdk\bin\dart.exe'
$toolPackages = 'E:\Flutter\packages\flutter_tools\.dart_tool\package_config.json'
$python = 'C:\Python314\python.exe'

function Assert-ProjectPath([string]$Path) {
    $absolute = [IO.Path]::GetFullPath($Path)
    if (-not $absolute.StartsWith($projectRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Caminho fora do projeto.' }
    if (Test-Path -LiteralPath $absolute) {
        if (((Get-Item -LiteralPath $absolute -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Link ou juncao nao permitido.' }
    }
    return $absolute
}

Push-Location -LiteralPath $projectRoot
try {
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
    $check = Join-Path $logRoot 'verificar_aot_android.dart'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'verificar_aot_android.dart.template') -Destination $check -Force
    & $dart "--packages=$toolPackages" $check '50805dc96c11309f771471126c8807d3'
    if ($LASTEXITCODE -ne 0) { throw 'AOT divergente do codigo atual.' }

    $published = Join-Path $projectRoot 'dist\MastterSystemCliente.apk'
    $base = Join-Path $logRoot 'MastterSystemCliente-base-20261016.apk'
    if (-not (Test-Path -LiteralPath $base)) {
        $baseTime = (Get-Item -LiteralPath $published).LastWriteTime
        Copy-Item -LiteralPath $published -Destination $base
        (Get-Item -LiteralPath $base).LastWriteTime = $baseTime
    }
    $unsigned = Join-Path $logRoot 'cliente-atualizado-sem-assinatura.apk'
    $aligned = Join-Path $logRoot 'cliente-atualizado-alinhado.apk'
    $signed = Join-Path $logRoot 'cliente-atualizado-assinado.apk'
    & $python -u (Join-Path $PSScriptRoot 'reempacotar_android_base.py') $base $unsigned
    if ($LASTEXITCODE -ne 0) { throw 'A base nativa nao pode ser reutilizada.' }
    $alignLog = Join-Path $logRoot 'alinhamento-apk.log'
    & (Join-Path $buildTools 'zipalign.exe') '-P' '16' '-f' '4' $unsigned $aligned *> $alignLog
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao alinhar APK.' }
    if (Select-String -LiteralPath $alignLog -Pattern 'header mismatch' -Quiet) { throw 'Cabecalhos ZIP incompativeis.' }
    $baseInfo = & $java '-Xmx128m' '-jar' $apkSigner 'verify' '--print-certs' $base
    if ($LASTEXITCODE -ne 0) { throw 'Assinatura da base invalida.' }
    # Mesma identidade debug utilizada pela configuracao release original.
    & $java '-Xmx128m' '-jar' $apkSigner 'sign' '--ks' (Join-Path $env:USERPROFILE '.android\debug.keystore') '--ks-key-alias' 'androiddebugkey' '--ks-pass' 'pass:android' '--key-pass' 'pass:android' '--v4-signing-enabled' 'false' '--out' $signed $aligned
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao assinar APK.' }
    $signedInfo = & $java '-Xmx128m' '-jar' $apkSigner 'verify' '--verbose' '--print-certs' $signed
    if ($LASTEXITCODE -ne 0) { throw 'Assinatura do APK final invalida.' }
    $baseCert = @($baseInfo | Select-String '^Signer #1 certificate SHA-256 digest:')
    $signedCert = @($signedInfo | Select-String '^Signer #1 certificate SHA-256 digest:')
    if ($baseCert.Count -ne 1 -or $signedCert.Count -ne 1 -or $baseCert[0].Line -ne $signedCert[0].Line) { throw 'Identidade de assinatura diferente da base.' }
    [IO.File]::WriteAllLines((Join-Path $logRoot 'assinatura-apk.log'), [string[]]$signedInfo)
    & (Join-Path $buildTools 'zipalign.exe') '-c' '-P' '16' '4' $signed
    if ($LASTEXITCODE -ne 0) { throw 'Alinhamento do APK final invalido.' }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($signed)
    try {
        foreach ($abi in @('armeabi-v7a', 'arm64-v8a', 'x86_64')) {
            $entry = $archive.GetEntry("lib/$abi/libapp.so")
            if ($null -eq $entry) { throw "AOT ausente no APK: $abi" }
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $actual = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
            finally { $stream.Dispose(); $sha.Dispose() }
            $expected = (Get-FileHash -LiteralPath (Join-Path $projectRoot "build\app\intermediates\flutter\release\$abi\app.so") -Algorithm SHA256).Hash
            if ($actual -ne $expected) { throw "AOT divergente no APK assinado: $abi" }
        }
    }
    finally { $archive.Dispose() }

    $assets = Assert-ProjectPath (Join-Path $projectRoot 'assets\admin_installers')
    $items = @(Get-ChildItem -LiteralPath $assets -Force)
    if ($items.Count -eq 1 -and $items[0].Name -eq 'LEIA-ME.txt') {
        if ([string]::IsNullOrWhiteSpace($SavedAssets)) { throw 'Informe a pasta de instaladores salva pela compilacao cancelada.' }
        $saved = Assert-ProjectPath (Join-Path $projectRoot $SavedAssets)
        $savedItems = @(Get-ChildItem -LiteralPath $saved -Force)
        if ($savedItems.Count -ne 3) { throw 'Conteudo inesperado nos instaladores salvos.' }
        foreach ($item in $savedItems) {
            if ($item.PSIsContainer -or $item.Name -notin @('MastterSystemCliente.apk', 'MastterSystemCliente_Windows.zip', 'README.md') -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Instalador salvo inesperado.' }
        }
        Remove-Item -LiteralPath $items[0].FullName -Force
        [IO.Directory]::Delete($assets, $false)
        Move-Item -LiteralPath $saved -Destination $assets
    }
    Copy-Item -LiteralPath $signed -Destination $published -Force
    Copy-Item -LiteralPath $signed -Destination (Join-Path $assets 'MastterSystemCliente.apk') -Force
    Copy-Item -LiteralPath (Join-Path $projectRoot 'dist\MastterSystemCliente_Windows.zip') -Destination (Join-Path $assets 'MastterSystemCliente_Windows.zip') -Force
    Write-Host "Pronto: $published"
    Write-Host 'Assinatura identica a base, alinhamento e tres AOT conferidos.'
}
finally { Pop-Location }
