[CmdletBinding()]
param(
    [ValidateSet('Todos', 'Validar', 'Gerar', 'Navegacao', 'Retorno', 'Distribuir', 'RetomarDistribuicao', 'AotDistribuicao', 'ConferirDistribuicao')]
    [string]$Etapa = 'Todos'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$flutterBin = Split-Path -Parent (Get-Command flutter.bat -CommandType Application -ErrorAction Stop).Source
$dartExecutable = Join-Path $flutterBin 'cache\dart-sdk\bin\dart.exe'
$flutterSnapshot = Join-Path $flutterBin 'cache\flutter_tools.snapshot'
$logRoot = Join-Path $projectRoot 'build\validacao-rh'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

function Invoke-SdkCheck {
    param([string]$Name, [string[]]$SdkArguments)
    $log = Join-Path $logRoot ($Name + '.log')
    Write-Host "Executando $Name..."
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $dartExecutable @SdkArguments *> $log
        $taskExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    Get-Content -LiteralPath $log -Tail 12
    if ($taskExitCode -ne 0) {
        throw "$Name falhou (codigo $taskExitCode). Confira $log"
    }
}

Push-Location -LiteralPath $projectRoot
try {
    if ($Etapa -in @('Todos', 'Validar')) {
        $sources = @(
            'lib/core/background_refresh_mixin.dart',
            'lib/constants/system_permissions.dart',
            'lib/screens/main_screen.dart',
            'lib/screens/quote/quote_screen.dart',
            'lib/screens/employees/employees_screen.dart',
            'lib/screens/employees/employee_ponto_report.dart',
            'lib/models/ponto_report.dart',
            'lib/services/ponto_report_pdf_service.dart',
            'lib/screens/customers/customer_list_screen.dart',
            'lib/screens/suppliers/fornecedores_screen.dart',
            'lib/screens/sales/vendedores_screen.dart',
            'lib/screens/products/product_list_screen.dart',
            'lib/screens/quote/quote_approval_screen.dart',
            'lib/screens/production/production_screen.dart',
            'lib/screens/production/apontamento_producao_screen.dart',
            'lib/screens/corte_laser/retalhos_screen.dart',
            'lib/screens/corte_laser/maquinas_screen.dart',
            'test/main_navigation_test.dart',
            'test/background_refresh_mixin_test.dart',
            'test/ponto_report_test.dart',
            'test/employee_ponto_report_test.dart'
        )
        Invoke-SdkCheck -Name 'formatacao' -SdkArguments (@('format') + $sources)
        Invoke-SdkCheck -Name 'analise' -SdkArguments (@(
            $flutterSnapshot, '--no-version-check', 'analyze', '--no-pub',
            '--no-fatal-infos', '--no-fatal-warnings'
        ) + $sources)
        Invoke-SdkCheck -Name 'ponto-e-atualizacao' -SdkArguments @(
            $flutterSnapshot, '--no-version-check', 'test', '--no-pub',
            '--concurrency=1', '--no-test-assets', '--no-track-widget-creation',
            'test/background_refresh_mixin_test.dart',
            'test/ponto_report_test.dart', 'test/employee_ponto_report_test.dart'
        )
        Invoke-SdkCheck -Name 'rascunhos' -SdkArguments @(
            $flutterSnapshot, '--no-version-check', 'test', '--no-pub',
            '--concurrency=1', '--no-test-assets', '--no-track-widget-creation',
            '--name', 'sections mount|sale draft',
            'test/main_navigation_test.dart'
        )
        [IO.File]::WriteAllText((Join-Path $logRoot 'validado.txt'),
            'Validacao concluida: ' + (Get-Date -Format 's'))
    }
    if ($Etapa -eq 'Navegacao') {
        Invoke-SdkCheck -Name 'rascunhos' -SdkArguments @(
            $flutterSnapshot, '--no-version-check', 'test', '--no-pub',
            '--concurrency=1', '--no-test-assets', '--no-track-widget-creation',
            '--name', 'sections mount|sale draft',
            'test/main_navigation_test.dart'
        )
    }
    if ($Etapa -eq 'Retorno') {
        $resumeSources = @(
            'lib/main.dart', 'lib/screens/auth/license_access_gate.dart',
            'test/license_access_gate_test.dart'
        )
        Invoke-SdkCheck -Name 'formatacao-retorno' -SdkArguments (@('format') + $resumeSources)
        Invoke-SdkCheck -Name 'analise-retorno' -SdkArguments (@(
            $flutterSnapshot, '--no-version-check', 'analyze', '--no-pub'
        ) + $resumeSources)
        Invoke-SdkCheck -Name 'retorno-aplicativo' -SdkArguments @(
            $flutterSnapshot, '--no-version-check', 'test', '--no-pub',
            '--concurrency=1', '--no-test-assets', '--no-track-widget-creation',
            'test/license_access_gate_test.dart'
        )
    }
    if ($Etapa -in @('Distribuir', 'RetomarDistribuicao', 'AotDistribuicao', 'ConferirDistribuicao')) {
        if ($Etapa -eq 'ConferirDistribuicao') {
            Write-Host 'Conferindo os pacotes ja montados...'
        }
        elseif ($Etapa -in @('RetomarDistribuicao', 'AotDistribuicao')) {
            & (Join-Path $PSScriptRoot 'compilar_licencas.ps1') -Alvo Android -SkipPubGet -UseFlutterSnapshot -ReusarAotAndroid:($Etapa -eq 'AotDistribuicao')
            & (Join-Path $PSScriptRoot 'compilar_licencas.ps1') -Alvo Servidor -SkipPubGet -UseFlutterSnapshot
        }
        else {
            & (Join-Path $PSScriptRoot 'compilar_licencas.ps1') -Alvo Todos -SkipPubGet -UseFlutterSnapshot
        }
        if ($Etapa -ne 'ConferirDistribuicao' -and $LASTEXITCODE -ne 0) { throw 'A compilacao dos aplicativos nao foi concluida.' }

        $distDirectory = Get-Item -LiteralPath (Join-Path $projectRoot 'dist') -Force
        if (($distDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'A pasta dist nao pode ser um link ou uma juncao.'
        }
        $distRoot = $distDirectory.FullName.TrimEnd('\')
        $distPrefix = $distRoot + '\'
        $adminRoot = Join-Path $distRoot 'ServidorLicencas'
        $adminZip = Join-Path $distRoot 'AdministradorLicencas_Windows.zip'
        $adminZipStaging = Join-Path $distRoot ('AdministradorLicencas-novo-' + [Guid]::NewGuid().ToString('N') + '.zip')
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::CreateFromDirectory($adminRoot, $adminZipStaging)
        Move-Item -LiteralPath $adminZipStaging -Destination $adminZip -Force

        $artifacts = @(
            'MastterSystemCliente\matterdisistem.exe',
            'MastterSystemCliente\data\app.so',
            'MastterSystemCliente_Windows.zip',
            'MastterSystemCliente.apk',
            'MastterSystem_Supabase_Completo.sql',
            'ServidorLicencas\ServidorLicencas.exe',
            'ServidorLicencas\data\app.so',
            'AdministradorLicencas_Windows.zip'
        )
        $hashes = @{}
        $lines = foreach ($artifact in $artifacts) {
            $artifactPath = Join-Path $distRoot $artifact
            $hashes[$artifact] = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $hashes[$artifact] + '  ' + $artifact
        }
        foreach ($package in @(
            @{ Zip = 'MastterSystemCliente_Windows.zip'; Folder = 'MastterSystemCliente'; Exe = 'matterdisistem.exe' },
            @{ Zip = 'AdministradorLicencas_Windows.zip'; Folder = 'ServidorLicencas'; Exe = 'ServidorLicencas.exe' }
        )) {
            $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $distRoot $package.Zip))
            try {
                foreach ($relative in @($package.Exe, 'data/app.so')) {
                    $entry = $archive.Entries | Where-Object { $_.FullName.Replace('\', '/') -eq $relative }
                    if ($null -eq $entry) { throw "Arquivo ausente no pacote: $relative" }
                    $stream = $entry.Open()
                    try { $entryHash = (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash.ToLowerInvariant() }
                    finally { $stream.Dispose() }
                    $key = $package.Folder + '\' + $relative.Replace('/', '\')
                    if ($entryHash -ne $hashes[$key]) { throw "Arquivo divergente no pacote: $relative" }
                }
                foreach ($entry in $archive.Entries) {
                    if ($entry.Length -eq 0) { continue }
                    $stream = $entry.Open()
                    try { $stream.CopyTo([IO.Stream]::Null) }
                    finally { $stream.Dispose() }
                }
            }
            finally { $archive.Dispose() }
        }
        $apk = [IO.Compression.ZipFile]::OpenRead((Join-Path $distRoot 'MastterSystemCliente.apk'))
        try {
            # O APK de distribuição é gerado para Android ARM64, arquitetura dos
            # aparelhos Android atuais usados pelo cliente.
            foreach ($requiredEntry in @('AndroidManifest.xml', 'classes.dex',
                'lib/arm64-v8a/libapp.so')) {
                if (-not ($apk.Entries | Where-Object { $_.FullName -eq $requiredEntry })) {
                    throw "APK incompleto: $requiredEntry"
                }
            }
            if ($apk.Entries | Where-Object { $_.FullName -match 'admin_installers/.*\.(zip|apk|exe)$' }) {
                throw 'O APK cliente contem instaladores administrativos.'
            }
            foreach ($entry in $apk.Entries) {
                if ($entry.Length -eq 0) { continue }
                $stream = $entry.Open()
                try { $stream.CopyTo([IO.Stream]::Null) }
                finally { $stream.Dispose() }
            }
        }
        finally { $apk.Dispose() }
        foreach ($installer in @('MastterSystemCliente.apk', 'MastterSystemCliente_Windows.zip')) {
            $embeddedPath = Join-Path $adminRoot ('data\flutter_assets\assets\admin_installers\' + $installer)
            $embeddedHash = (Get-FileHash -LiteralPath $embeddedPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($embeddedHash -ne $hashes[$installer]) { throw "O ADM contem um instalador desatualizado: $installer" }
        }
        [IO.File]::WriteAllLines((Join-Path $distRoot 'SHA256SUMS.txt'), [string[]]$lines)

        # Limpeza solicitada: somente o ADM e os clientes Windows/Android atuais.
        # Valide todos os alvos absolutos antes de excluir qualquer pasta.
        $keep = @('MastterSystemCliente', 'ServidorLicencas', 'MastterSystemCliente.apk',
            'MastterSystemCliente_Windows.zip', 'AdministradorLicencas_Windows.zip',
            'MastterSystem_Supabase_Completo.sql', 'SHA256SUMS.txt')
        $obsolete = @(Get-ChildItem -LiteralPath $distRoot -Force | Where-Object { $_.Name -notin $keep })
        foreach ($item in $obsolete) {
            $absolute = [IO.Path]::GetFullPath($item.FullName)
            if (-not $absolute.StartsWith($distPrefix, [StringComparison]::OrdinalIgnoreCase) -or
                [IO.Path]::GetDirectoryName($absolute) -ne $distRoot) {
                throw "Destino de limpeza fora de dist: $absolute"
            }
            $tree = @($item)
            if ($item.PSIsContainer) { $tree += @(Get-ChildItem -LiteralPath $absolute -Recurse -Force) }
            if ($tree | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }) {
                throw "A limpeza nao atravessa links ou juncoes: $absolute"
            }
            if ($tree | Where-Object { -not $_.PSIsContainer -and
                ($_.Extension -in @('.db', '.sqlite', '.sqlite3') -or
                 $_.Name -in @('.env', 'lan_licenses.json', 'licenses.json')) }) {
                throw "Encontrados dados locais em um pacote antigo: $absolute"
            }
        }
        $obsolete | Select-Object Name, FullName |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logRoot 'pacotes-antigos-removidos.json') -Encoding UTF8
        foreach ($item in $obsolete) {
            $absolute = [IO.Path]::GetFullPath($item.FullName)
            if ($item.PSIsContainer) { Remove-Item -LiteralPath $absolute -Recurse -Force }
            else { Remove-Item -LiteralPath $absolute -Force }
        }
        Write-Host "Distribuicao conferida. Removidos $($obsolete.Count) pacotes/arquivos antigos."
        Get-ChildItem -LiteralPath $distRoot | Select-Object Name, Length
    }
    if ($Etapa -in @('Todos', 'Gerar')) {
        & (Join-Path $PSScriptRoot 'compilar_licencas.ps1') -Alvo Windows -SkipPubGet -UseFlutterSnapshot
        $packageRoot = Join-Path $projectRoot 'dist\MastterSystemCliente'
        $unexpected = Get-ChildItem -LiteralPath $packageRoot -Recurse -File |
            Where-Object {
                $_.Name -match 'issuer_private|build_defines_admin|^ServidorLicencas.*\.exe$' -or
                ($_.DirectoryName -match 'admin_installers' -and $_.Extension -in @('.zip', '.apk', '.exe'))
            }
        if ($unexpected) { throw 'O pacote cliente contem um arquivo administrativo inesperado.' }
        $checksum = Join-Path $projectRoot 'dist\MastterSystemCliente_RH_SHA256SUMS.txt'
        $artifacts = @(
            'MastterSystemCliente\matterdisistem.exe',
            'MastterSystemCliente\data\app.so',
            'MastterSystemCliente_Windows.zip'
        )
        $lines = foreach ($artifact in $artifacts) {
            (Get-FileHash -LiteralPath (Join-Path $projectRoot ('dist\' + $artifact)) -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $artifact
        }
        [IO.File]::WriteAllLines($checksum, [string[]]$lines)
        Write-Host "Cliente e ZIP finalizados. SHA256: $checksum"
    }
}
finally {
    Pop-Location
}
