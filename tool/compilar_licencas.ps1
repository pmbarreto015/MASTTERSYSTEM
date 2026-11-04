[CmdletBinding()]
param(
    [ValidateSet('Todos', 'Servidor', 'Windows', 'Android')]
    [string]$Alvo = 'Todos',
    [switch]$SkipAndroid,
    [switch]$SkipPubGet,
    [switch]$UseFlutterSnapshot,
    [switch]$ReusarAotAndroid,
    [switch]$DefinirSenhaNaCompilacao,
    [Security.SecureString]$SenhaAdministrador,
    [string]$ServidorInternet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$distRoot = Join-Path $projectRoot 'dist'
$releaseRoot = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$packageStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$utf8 = New-Object Text.UTF8Encoding($false)

function Assert-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $absolutePath = [IO.Path]::GetFullPath($Path)
    $rootPrefix = $projectRoot.TrimEnd('\') + '\'
    if (-not $absolutePath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "O destino deve estar dentro do projeto: $absolutePath"
    }
    if (Test-Path -LiteralPath $absolutePath) {
        $item = Get-Item -LiteralPath $absolutePath -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Nao sera alterado um link ou uma juncao: $absolutePath"
        }
    }
    return $absolutePath
}

function Get-AdminPasswordHash {
    param([Security.SecureString]$Password)
    $providedPassword = $null -ne $Password
    $confirmation = $null
    $passwordPointer = [IntPtr]::Zero
    $confirmationPointer = [IntPtr]::Zero
    $passwordBytes = $null
    $confirmationBytes = $null
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        if (-not $providedPassword) {
            $Password = Read-Host 'Crie a senha do administrador de licencas' -AsSecureString
            $confirmation = Read-Host 'Repita a senha do administrador' -AsSecureString
        }
        if ($Password.Length -lt 8) {
            throw 'Use uma senha administrativa com pelo menos 8 caracteres.'
        }
        $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $passwordBytes = [Text.Encoding]::UTF8.GetBytes(
            [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
        )
        $passwordHash = -join ($sha256.ComputeHash($passwordBytes) | ForEach-Object { $_.ToString('x2') })
        if ($null -ne $confirmation) {
            $confirmationPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmation)
            $confirmationBytes = [Text.Encoding]::UTF8.GetBytes(
                [Runtime.InteropServices.Marshal]::PtrToStringBSTR($confirmationPointer)
            )
            $confirmationHash = -join ($sha256.ComputeHash($confirmationBytes) | ForEach-Object { $_.ToString('x2') })
            if ($passwordHash -cne $confirmationHash) {
                throw 'As senhas informadas sao diferentes. Execute novamente.'
            }
        }
        return $passwordHash
    }
    finally {
        if ($passwordPointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
        }
        if ($confirmationPointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($confirmationPointer)
        }
        if ($null -ne $passwordBytes) { [Array]::Clear($passwordBytes, 0, $passwordBytes.Length) }
        if ($null -ne $confirmationBytes) { [Array]::Clear($confirmationBytes, 0, $confirmationBytes.Length) }
        if ($null -ne $confirmation) { $confirmation.Dispose() }
        if (-not $providedPassword -and $null -ne $Password) { $Password.Dispose() }
        $sha256.Dispose()
    }
}

function Invoke-FlutterBuild {
    param([Parameter(Mandatory = $true)][string[]]$BuildArguments)
    if ($UseFlutterSnapshot) {
        & $dartSdkExecutable $flutterToolSnapshot @BuildArguments
    }
    else {
        & $flutterCommand.Source @BuildArguments
    }
    if ($LASTEXITCODE -ne 0) {
        throw 'O Flutter nao conseguiu concluir a compilacao. Confira as mensagens acima.'
    }
}

function Publish-WindowsPackage {
    param(
        [Parameter(Mandatory = $true)][string]$PackageName,
        [string]$ExeName = 'matterdisistem.exe'
    )
    foreach ($requiredFile in @('matterdisistem.exe', 'flutter_windows.dll', 'data\app.so', 'data\icudtl.dat')) {
        if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot $requiredFile) -PathType Leaf)) {
            throw "Compilacao Windows incompleta: $requiredFile"
        }
    }
    $destination = Assert-ProjectPath (Join-Path $distRoot $PackageName)
    $staging = Assert-ProjectPath (Join-Path $distRoot ($PackageName + '-novo-' + [Guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $staging | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $releaseRoot -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination $staging -Recurse -Force
    }
    if ($PackageName -eq 'MastterSystemCliente') {
        # O install do CMake pode manter assets antigos de uma compilacao do ADM.
        $installerAssets = Assert-ProjectPath (Join-Path $staging 'data\flutter_assets\assets\admin_installers')
        if (Test-Path -LiteralPath $installerAssets) {
            foreach ($installerFile in Get-ChildItem -LiteralPath $installerAssets -Recurse -File) {
                if ($installerFile.Extension -in @('.zip', '.apk', '.exe')) {
                    $installerFilePath = Assert-ProjectPath $installerFile.FullName
                    Remove-Item -LiteralPath $installerFilePath -Force
                }
            }
        }
    }
    if ($ExeName -ne 'matterdisistem.exe') {
        Move-Item -LiteralPath (Join-Path $staging 'matterdisistem.exe') -Destination (Join-Path $staging $ExeName)
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\licenciamento_rede_local.md') -Destination (Join-Path $staging 'LEIA-ME.md')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\licenciamento_internet_offline.md') -Destination (Join-Path $staging 'licenciamento_internet_offline.md')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\atualizacao_rh.md') -Destination (Join-Path $staging 'ATUALIZACAO_RH.md')
    if (Test-Path -LiteralPath $destination) {
        $backup = Assert-ProjectPath ($destination + '-anterior-' + $packageStamp + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6))
        # Valide os caminhos absolutos antes de mover qualquer pasta completa.
        $destination = Assert-ProjectPath $destination
        Move-Item -LiteralPath $destination -Destination $backup
        Write-Host "Pacote anterior preservado em: $backup"
    }
    $staging = Assert-ProjectPath $staging
    Move-Item -LiteralPath $staging -Destination $destination
    Write-Host "Pronto: $(Join-Path $destination $ExeName)"
    Write-Host 'Copie a pasta inteira, incluindo DLLs e a pasta data.'
    return $destination
}

function Invoke-ClientBuild {
    param([Parameter(Mandatory = $true)][string[]]$BuildArguments)
    # Os instaladores pertencem ao ADM. Não os embuta novamente dentro do cliente.
    $assetPath = Assert-ProjectPath (Join-Path $projectRoot 'assets\admin_installers')
    $savedAssets = Assert-ProjectPath (Join-Path $projectRoot ('build\admin-installers-' + [Guid]::NewGuid().ToString('N')))
    $hadAssets = Test-Path -LiteralPath $assetPath
    if ($hadAssets) {
        $assetPath = Assert-ProjectPath $assetPath
        Move-Item -LiteralPath $assetPath -Destination $savedAssets
    }
    New-Item -ItemType Directory -Path $assetPath -Force | Out-Null
    $placeholder = Join-Path $assetPath 'LEIA-ME.txt'
    [IO.File]::WriteAllText($placeholder, 'Instaladores disponíveis somente no administrador.', $utf8)
    try {
        if (-not [string]::IsNullOrWhiteSpace($ServidorInternet)) {
            $BuildArguments += "--dart-define=LICENSE_DEFAULT_SERVER=$ServidorInternet"
        }
        if ($ReusarAotAndroid -and $BuildArguments[1] -eq 'apk') {
            if (-not [string]::IsNullOrWhiteSpace($ServidorInternet)) { throw 'Reuso AOT exige as mesmas definicoes da compilacao original.' }
            $flutterSdkRoot = Split-Path -Parent $flutterBin
            $toolsPackages = Join-Path $flutterSdkRoot 'packages\flutter_tools\.dart_tool\package_config.json'
            # Cache desta compilacao Android: lib/main.dart e LICENSE_MODE=lan.
            $aotCheck = Join-Path $projectRoot 'build\validacao-rh\verificar_aot_android.dart'
            New-Item -ItemType Directory -Path (Split-Path -Parent $aotCheck) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $projectRoot 'tool\verificar_aot_android.dart.template') -Destination $aotCheck -Force
            & $dartSdkExecutable "--packages=$toolsPackages" $aotCheck '50805dc96c11309f771471126c8807d3'
            if ($LASTEXITCODE -ne 0) { throw 'AOT Android nao corresponde ao codigo atual.' }
            $javaExecutable = 'E:\Nova pasta\Android Studio\jbr\bin\java.exe'
            $wrapper = Join-Path $projectRoot 'android\gradle\wrapper\gradle-wrapper.jar'
            Push-Location -LiteralPath (Join-Path $projectRoot 'android')
            try {
                & $javaExecutable '-Xmx128m' '-classpath' $wrapper 'org.gradle.wrapper.GradleWrapperMain' '--no-daemon' '--max-workers=1' '--console=plain' '-Pshrink=false' '-Ptarget-platform=android-arm,android-arm64,android-x64' '-Ptarget=lib/main.dart' '-Pbase-application-name=android.app.Application' '-Pdart-defines=TElDRU5TRV9NT0RFPWxhbg==' '-Pdart-obfuscation=false' '-Ptrack-widget-creation=true' '-Ptree-shake-icons=true' 'assembleRelease' '-x' ':app:compileFlutterBuildRelease'
                if ($LASTEXITCODE -ne 0) { throw 'A montagem Android pelo Gradle falhou.' }
            }
            finally { Pop-Location }
        }
        else { Invoke-FlutterBuild -BuildArguments $BuildArguments }
    }
    finally {
        $assetPath = Assert-ProjectPath $assetPath
        if (Test-Path -LiteralPath $placeholder) { Remove-Item -LiteralPath $placeholder -Force }
        # A pasta contém só o placeholder criado acima; recuse apagar outro conteúdo.
        [IO.Directory]::Delete($assetPath, $false)
        if ($hadAssets) {
            $savedAssets = Assert-ProjectPath $savedAssets
            Move-Item -LiteralPath $savedAssets -Destination $assetPath
        }
        else { New-Item -ItemType Directory -Path $assetPath | Out-Null }
    }
}

$buildServer = $Alvo -in @('Todos', 'Servidor')
$buildWindows = $Alvo -in @('Todos', 'Windows')
$buildAndroid = $Alvo -in @('Todos', 'Android') -and -not $SkipAndroid
if ($Alvo -eq 'Android' -and $SkipAndroid) { throw 'Escolha Android ou SkipAndroid, sem combinar os dois.' }
$flutterCommand = Get-Command flutter.bat -CommandType Application -ErrorAction Stop
$flutterBin = Split-Path -Parent $flutterCommand.Source
$dartSdkExecutable = Join-Path $flutterBin 'cache\dart-sdk\bin\dart.exe'
$flutterToolSnapshot = Join-Path $flutterBin 'cache\flutter_tools.snapshot'
if ($UseFlutterSnapshot -and
    (-not (Test-Path -LiteralPath $dartSdkExecutable -PathType Leaf) -or
     -not (Test-Path -LiteralPath $flutterToolSnapshot -PathType Leaf))) {
    throw 'O SDK Flutter precisa estar preparado antes de usar UseFlutterSnapshot.'
}
$distRoot = Assert-ProjectPath $distRoot
if (-not (Test-Path -LiteralPath $distRoot)) { New-Item -ItemType Directory -Path $distRoot | Out-Null }
$adminHashValue = $null
$generatedArtifacts = @()

Push-Location -LiteralPath $projectRoot
try {
    if (-not $SkipPubGet) { Invoke-FlutterBuild -BuildArguments @('pub', 'get') }
    if ($UseFlutterSnapshot) {
        & $dartSdkExecutable run tool/prepare_license_keys.dart
    }
    else {
        $dartCommand = Get-Command dart.bat -CommandType Application -ErrorAction Stop
        & $dartCommand.Source run tool/prepare_license_keys.dart
    }
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel preparar o par de chaves das licencas offline.' }
    $adminDefinesPath = Assert-ProjectPath (Join-Path $projectRoot 'data\licensing\build_defines_admin.json')
    if ($buildServer) {
        Write-Host 'O administrador sera compilado depois dos pacotes para inclui-los no programa.'
    }
    if ($buildWindows) {
        Write-Host 'Compilando o cliente EXE com licenciamento...'
        Invoke-ClientBuild -BuildArguments @('build', 'windows', '--release', '--no-pub', '--target', 'lib/main.dart', '--dart-define=LICENSE_MODE=lan')
        $windowsPackage = Publish-WindowsPackage -PackageName 'MastterSystemCliente'
        $generatedArtifacts += Join-Path $windowsPackage 'matterdisistem.exe'
        $assetDirectory = Join-Path $projectRoot 'assets\admin_installers'
        if (-not (Test-Path -LiteralPath $assetDirectory)) { New-Item -ItemType Directory -Path $assetDirectory | Out-Null }
        $windowsZip = Join-Path $distRoot 'MastterSystemCliente_Windows.zip'
        if (Test-Path -LiteralPath $windowsZip) {
            $backupZip = Assert-ProjectPath (Join-Path $distRoot ('MastterSystemCliente_Windows-anterior-' + $packageStamp + '.zip'))
            Copy-Item -LiteralPath $windowsZip -Destination $backupZip
        }
        if (Test-Path -LiteralPath $windowsZip) { Remove-Item -LiteralPath $windowsZip -Force }
        Compress-Archive -Path (Join-Path $windowsPackage '*') -DestinationPath $windowsZip -CompressionLevel Optimal
        Copy-Item -LiteralPath $windowsZip -Destination (Join-Path $assetDirectory 'MastterSystemCliente_Windows.zip') -Force
        $generatedArtifacts += $windowsZip
    }
    if ($buildAndroid) {
        Write-Host 'Compilando o cliente APK com licenciamento...'
        Invoke-ClientBuild -BuildArguments @('build', 'apk', '--release', '--no-pub', '--target', 'lib/main.dart', '--dart-define=LICENSE_MODE=lan')
        $sourceApk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
        if (-not (Test-Path -LiteralPath $sourceApk -PathType Leaf)) { throw 'O APK de release nao foi gerado.' }
        $destinationApk = Assert-ProjectPath (Join-Path $distRoot 'MastterSystemCliente.apk')
        if (Test-Path -LiteralPath $destinationApk) {
            $backupApk = Assert-ProjectPath (Join-Path $distRoot ('MastterSystemCliente-anterior-' + $packageStamp + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 6) + '.apk'))
            Copy-Item -LiteralPath $destinationApk -Destination $backupApk
            Write-Host "APK anterior preservado em: $backupApk"
        }
        Copy-Item -LiteralPath $sourceApk -Destination $destinationApk -Force
        $assetDirectory = Join-Path $projectRoot 'assets\admin_installers'
        if (-not (Test-Path -LiteralPath $assetDirectory)) { New-Item -ItemType Directory -Path $assetDirectory | Out-Null }
        Copy-Item -LiteralPath $destinationApk -Destination (Join-Path $assetDirectory 'MastterSystemCliente.apk') -Force
        $generatedArtifacts += $destinationApk
        Write-Host "Pronto: $destinationApk"
    }
    if ($buildServer) {
        Write-Host 'Compilando o administrador de licencas com os pacotes cliente embutidos...'
        $serverBuildArguments = @('build', 'windows', '--release', '--no-pub', '--target', 'lib/license_server_main.dart', "--dart-define-from-file=$adminDefinesPath")
        if ($DefinirSenhaNaCompilacao -or $null -ne $SenhaAdministrador) {
            $adminHashValue = Get-AdminPasswordHash $SenhaAdministrador
            $serverBuildArguments += "--dart-define=LICENSE_ADMIN_HASH=$adminHashValue"
        }
        Invoke-FlutterBuild -BuildArguments $serverBuildArguments
        $serverPackage = Publish-WindowsPackage -PackageName 'ServidorLicencas' -ExeName 'ServidorLicencas.exe'
        $generatedArtifacts += Join-Path $serverPackage 'ServidorLicencas.exe'
        $adminHashValue = $null
        $serverBuildArguments = $null
        if (-not $DefinirSenhaNaCompilacao -and $null -eq $SenhaAdministrador) {
            Write-Host 'Na primeira abertura do administrador, crie sua senha no proprio programa.'
        }
    }
    $checksumPath = Assert-ProjectPath (Join-Path $distRoot ('Licencas-' + $Alvo + '-' + $packageStamp + '-SHA256SUMS.txt'))
    $checksumLines = foreach ($artifact in $generatedArtifacts) {
        (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $artifact.Substring($distRoot.Length + 1)
    }
    [IO.File]::WriteAllLines($checksumPath, [string[]]$checksumLines, $utf8)
    Write-Host "Compilacao concluida. Conferencia SHA256: $checksumPath"
}
finally {
    $adminHashValue = $null
    $serverBuildArguments = $null
    Pop-Location
}
