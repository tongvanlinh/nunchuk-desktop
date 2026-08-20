$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $true
}

function Require-EnvironmentVariable {
    param([Parameter(Mandatory = $true)][string]$Name)

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Required environment variable is missing: $Name"
    }
    return $value
}

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Operation)

    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE"
    }
}

$BuildVersion = Require-EnvironmentVariable "BUILD_VERSION"
$QtDir = Require-EnvironmentVariable "QT_DIR"
$VcpkgRoot = Require-EnvironmentVariable "VCPKG_ROOT"
$VcpkgTriplet = Require-EnvironmentVariable "VCPKG_TRIPLET"
$EventLibrary = Require-EnvironmentVariable "EVENT_LIBRARY"
$QtKeychainPath = Require-EnvironmentVariable "QTKEYCHAIN_PATH"
$OpenSsl11Bin = Require-EnvironmentVariable "OPENSSL11_BIN"
$InnoCompiler = Require-EnvironmentVariable "ISCC"
$VcRedistName = Require-EnvironmentVariable "VC_REDIST"

if ($BuildVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z]+)*$') {
    throw "Invalid build version: $BuildVersion"
}
$CMakeVersionMatch = [regex]::Match($BuildVersion, '^\d+\.\d+\.\d+')
$CMakeAppVersion = $CMakeVersionMatch.Value

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$BuildRoot = Join-Path $ProjectRoot "build-reproducible-windows"
$StageRoot = Join-Path $ProjectRoot "staging-windows"
$DistRoot = Join-Path $ProjectRoot "dist"
$QtKeychainDll = Join-Path $QtKeychainPath "bin\qt5keychain.dll"
$MainExecutable = Join-Path $BuildRoot "nunchuk-qt.exe"
$TargetMachinePattern = '8664 machine \(x64\)'

foreach ($path in @($BuildRoot, $StageRoot, $DistRoot)) {
    if (Test-Path $path) {
        Remove-Item $path -Recurse -Force
    }
}
New-Item -ItemType Directory -Path $BuildRoot, $StageRoot, $DistRoot -Force |
    Out-Null

$configureArguments = @(
    "-G", "Ninja",
    "-S", $ProjectRoot,
    "-B", $BuildRoot,
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_TOOLCHAIN_FILE=$VcpkgRoot\scripts\buildsystems\vcpkg.cmake",
    "-DVCPKG_TARGET_TRIPLET=$VcpkgTriplet",
    "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW",
    "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL",
    "-DCMAKE_C_FLAGS_RELEASE=/O2 /DNDEBUG",
    "-DCMAKE_CXX_FLAGS_RELEASE=/O2 /DNDEBUG",
    "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
    "-Devent_lib:FILEPATH=$EventLibrary",
    "-DUR__DISABLE_TESTS=ON",
    "-DNUNCHUK_VERSION=$CMakeAppVersion",
    "-DQt5_DIR=$QtDir\lib\cmake\Qt5",
    "-DCMAKE_PREFIX_PATH=$QtDir;$QtKeychainPath;C:\olmInstalled"
)
& cmake @configureArguments
Assert-LastExitCode "CMake configure"

$compileDatabasePath = Join-Path $BuildRoot "compile_commands.json"
if (!(Test-Path $compileDatabasePath -PathType Leaf)) {
    throw "Compile database is missing: $compileDatabasePath"
}
$compileDatabase = Get-Content $compileDatabasePath -Raw
if ($compileDatabase -match '(?i)(?:^|[\s"])[/-]MTd?(?=[\s"]|$)') {
    throw "Windows build still contains static CRT /MT compiler flags"
}
if ($compileDatabase -notmatch '(?i)(?:^|[\s"])[/-]MD(?=[\s"]|$)') {
    throw "Windows build does not contain dynamic CRT /MD compiler flags"
}
& python.exe "$ProjectRoot\reproducible-builds\verify_optimization.py" `
    --compile-database $compileDatabasePath `
    --project-root $ProjectRoot `
    --family msvc
Assert-LastExitCode "Windows /O2 verification"
$ninjaFiles = @(Get-ChildItem $BuildRoot -Recurse -File -Filter "*.ninja")
$forbiddenLinkFlags = Select-String -Path $ninjaFiles.FullName `
    -Pattern '(?i)[/-]NODEFAULTLIB(?::[A-Za-z0-9_.-]+)?|(?:^|\s)[/-]Zl(?=\s|$)' `
    -AllMatches
if ($forbiddenLinkFlags) {
    throw "Windows build graph suppresses the default MSVC runtime"
}

& cmake --build $BuildRoot
Assert-LastExitCode "Windows application build"
if (!(Test-Path $MainExecutable -PathType Leaf)) {
    throw "Nunchuk executable is missing: $MainExecutable"
}

$Windeployqt = Join-Path $QtDir "bin\windeployqt.exe"
if (!(Test-Path $Windeployqt -PathType Leaf)) {
    throw "windeployqt is missing: $Windeployqt"
}
if (!(Test-Path $QtKeychainDll -PathType Leaf)) {
    throw "qt5keychain.dll is missing: $QtKeychainDll"
}

Copy-Item $MainExecutable -Destination $StageRoot -Force
Copy-Item $QtKeychainDll -Destination $StageRoot -Force

# windeployqt mistakes qt5keychain.dll for an official Qt module. Mirror it
# into Qt's bin directory only while the dependency scanner runs.
$ScannerKeychain = Join-Path $QtDir "bin\qt5keychain.dll"
$ScannerShimCreated = $false
if (Test-Path $ScannerKeychain -PathType Leaf) {
    $existingHash = (Get-FileHash $ScannerKeychain -Algorithm SHA256).Hash
    $sourceHash = (Get-FileHash $QtKeychainDll -Algorithm SHA256).Hash
    if ($existingHash -ne $sourceHash) {
        throw "Qt bin contains a different qt5keychain.dll"
    }
} else {
    Copy-Item $QtKeychainDll -Destination $ScannerKeychain -Force
    $ScannerShimCreated = $true
}

try {
    $env:PATH = "$StageRoot;$(Split-Path $QtKeychainDll -Parent);$QtDir\bin;$env:PATH"
    & $Windeployqt `
        --release `
        --verbose 2 `
        --qmldir $ProjectRoot `
        (Join-Path $StageRoot "nunchuk-qt.exe")
    Assert-LastExitCode "windeployqt"
} finally {
    if ($ScannerShimCreated -and (Test-Path $ScannerKeychain)) {
        Remove-Item $ScannerKeychain -Force
    }
}

$VcpkgBin = Join-Path $VcpkgRoot "installed\$VcpkgTriplet\bin"
if (Test-Path $VcpkgBin -PathType Container) {
    Get-ChildItem $VcpkgBin -Filter "*.dll" -File | ForEach-Object {
        Copy-Item $_.FullName -Destination $StageRoot -Force
    }
}

foreach ($dll in @("libcrypto-1_1-x64.dll", "libssl-1_1-x64.dll")) {
    $source = Join-Path $OpenSsl11Bin $dll
    if (!(Test-Path $source -PathType Leaf)) {
        throw "OpenSSL runtime is missing: $source"
    }
    Copy-Item $source -Destination $StageRoot -Force
}

$GraphicalEffectsSource = Join-Path $QtDir "qml\QtGraphicalEffects"
$GraphicalEffectsDestination = Join-Path $StageRoot "qml\QtGraphicalEffects"
if (!(Test-Path $GraphicalEffectsSource -PathType Container)) {
    throw "QtGraphicalEffects is missing from Qt"
}
if (Test-Path $GraphicalEffectsDestination) {
    Remove-Item $GraphicalEffectsDestination -Recurse -Force
}
New-Item -ItemType Directory -Path $GraphicalEffectsDestination -Force | Out-Null
Copy-Item "$GraphicalEffectsSource\*" `
    -Destination $GraphicalEffectsDestination -Recurse -Force
foreach ($debugDll in @(
    "$GraphicalEffectsDestination\qtgraphicaleffectsplugind.dll",
    "$GraphicalEffectsDestination\private\qtgraphicaleffectsprivated.dll"
)) {
    if (Test-Path $debugDll) {
        Remove-Item $debugDll -Force
    }
}

$RuntimeFiles = @(
    @("$QtDir\bin\Qt5Svg.dll", "$StageRoot\Qt5Svg.dll"),
    @("$QtDir\plugins\imageformats\qgif.dll", "$StageRoot\imageformats\qgif.dll"),
    @("$QtDir\plugins\imageformats\qjpeg.dll", "$StageRoot\imageformats\qjpeg.dll"),
    @("$QtDir\plugins\imageformats\qsvg.dll", "$StageRoot\imageformats\qsvg.dll"),
    @("$QtDir\plugins\iconengines\qsvgicon.dll", "$StageRoot\iconengines\qsvgicon.dll"),
    @("$QtDir\plugins\audio\qtaudio_wasapi.dll", "$StageRoot\audio\qtaudio_wasapi.dll"),
    @("$QtDir\plugins\audio\qtaudio_windows.dll", "$StageRoot\audio\qtaudio_windows.dll"),
    @("$QtDir\plugins\mediaservice\dsengine.dll", "$StageRoot\mediaservice\dsengine.dll"),
    @("$QtDir\plugins\mediaservice\qtmedia_audioengine.dll", "$StageRoot\mediaservice\qtmedia_audioengine.dll"),
    @("$QtDir\plugins\mediaservice\wmfengine.dll", "$StageRoot\mediaservice\wmfengine.dll"),
    @("$QtDir\plugins\playlistformats\qtmultimedia_m3u.dll", "$StageRoot\playlistformats\qtmultimedia_m3u.dll")
)
foreach ($item in $RuntimeFiles) {
    $source = $item[0]
    $destination = $item[1]
    if (!(Test-Path $source -PathType Leaf)) {
        throw "Required Qt runtime is missing: $source"
    }
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force |
        Out-Null
    Copy-Item $source -Destination $destination -Force
}

$SqlDrivers = Join-Path $StageRoot "sqldrivers"
$SqliteDriver = Join-Path $SqlDrivers "qsqlite.dll"
if (!(Test-Path $SqliteDriver -PathType Leaf)) {
    throw "Qt SQLite driver is missing from staging"
}
Get-ChildItem $SqlDrivers -Filter "*.dll" -File | Where-Object {
    $_.Name -ne "qsqlite.dll"
} | Remove-Item -Force
$PositionPlugins = Join-Path $StageRoot "position"
if (Test-Path $PositionPlugins) {
    Remove-Item $PositionPlugins -Recurse -Force
}

$Vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (!(Test-Path $Vswhere -PathType Leaf)) {
    throw "vswhere.exe is missing"
}
$VsInstall = & $Vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
Assert-LastExitCode "vswhere"
$VcRedist = Get-ChildItem "$VsInstall\VC\Redist\MSVC" -Recurse -File `
    -Filter $VcRedistName | Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $VcRedist) {
    throw "$VcRedistName was not found in the MSVC installation"
}
Copy-Item $VcRedist.FullName (Join-Path $StageRoot $VcRedistName) -Force

$HwiArchive = Join-Path $env:RUNNER_TEMP "hwi-windows-x86_64.zip"
$HwiExtracted = Join-Path $env:RUNNER_TEMP "hwi-windows-x86_64"
$HwiSha256 = "936b57ed68d6f949fbade7b6e4352c6fef5a851d341052ceaefd050abf317644"
Invoke-WebRequest `
    -Uri "https://github.com/nogibi/HWI/releases/download/3.2.0-displayaddress/hwi-3.2.0-windows-x86_64.zip" `
    -OutFile $HwiArchive
$ActualHwiHash = (Get-FileHash $HwiArchive -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ActualHwiHash -cne $HwiSha256) {
    throw "HWI checksum mismatch: $ActualHwiHash"
}
if (Test-Path $HwiExtracted) {
    Remove-Item $HwiExtracted -Recurse -Force
}
Expand-Archive $HwiArchive -DestinationPath $HwiExtracted -Force
$HwiExecutable = Get-ChildItem $HwiExtracted -Recurse -File -Filter "hwi.exe" |
    Select-Object -First 1
if ($null -eq $HwiExecutable) {
    throw "hwi.exe was not found in the HWI archive"
}
Copy-Item $HwiExecutable.FullName $StageRoot -Force

$SslProbeRoot = Join-Path $env:RUNNER_TEMP "qt5-ssl-probe"
if (Test-Path $SslProbeRoot) {
    Remove-Item $SslProbeRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $SslProbeRoot -Force | Out-Null
@'
cmake_minimum_required(VERSION 3.16)
project(qt5_ssl_probe LANGUAGES CXX)
find_package(Qt5 5.15.2 EXACT REQUIRED COMPONENTS Core Network)
add_executable(qt5-ssl-probe main.cpp)
target_link_libraries(qt5-ssl-probe PRIVATE Qt5::Core Qt5::Network)
'@ | Set-Content (Join-Path $SslProbeRoot "CMakeLists.txt") -Encoding ASCII
@'
#include <QCoreApplication>
#include <QSslSocket>
#include <iostream>
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    std::cout << QSslSocket::sslLibraryBuildVersionString().toStdString()
              << std::endl;
    return QSslSocket::supportsSsl() ? 0 : 1;
}
'@ | Set-Content (Join-Path $SslProbeRoot "main.cpp") -Encoding ASCII
& cmake -S $SslProbeRoot -B "$SslProbeRoot\build" -G Ninja `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_PREFIX_PATH=$QtDir `
    -DCMAKE_POLICY_DEFAULT_CMP0091=NEW `
    -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL
Assert-LastExitCode "TLS probe configure"
& cmake --build "$SslProbeRoot\build"
Assert-LastExitCode "TLS probe build"
$SslProbe = Join-Path $SslProbeRoot "build\qt5-ssl-probe.exe"
$SavedPath = $env:PATH
try {
    $env:PATH = "$StageRoot;$env:WINDIR\System32;$env:WINDIR"
    & $SslProbe
    Assert-LastExitCode "Staged Qt TLS runtime probe"
} finally {
    $env:PATH = $SavedPath
}

$RequiredFiles = @(
    "nunchuk-qt.exe",
    "hwi.exe",
    "qt5keychain.dll",
    "Qt5Core.dll",
    "Qt5Gui.dll",
    "Qt5Network.dll",
    "Qt5NetworkAuth.dll",
    "Qt5Qml.dll",
    "Qt5Quick.dll",
    "Qt5Multimedia.dll",
    "Qt5Svg.dll",
    "Qt5WebEngineCore.dll",
    "Qt5WebEngineWidgets.dll",
    "libcrypto-1_1-x64.dll",
    "libssl-1_1-x64.dll",
    "platforms\qwindows.dll",
    "imageformats\qgif.dll",
    "imageformats\qjpeg.dll",
    "imageformats\qsvg.dll",
    "iconengines\qsvgicon.dll",
    "sqldrivers\qsqlite.dll",
    "qml\QtGraphicalEffects\qmldir",
    "qml\QtGraphicalEffects\qtgraphicaleffectsplugin.dll",
    "qml\QtGraphicalEffects\private\qmldir",
    "qml\QtGraphicalEffects\private\qtgraphicaleffectsprivate.dll",
    $VcRedistName
)
foreach ($relativePath in $RequiredFiles) {
    if (!(Test-Path (Join-Path $StageRoot $relativePath))) {
        throw "Staging is missing required runtime: $relativePath"
    }
}
foreach ($pattern in @(
    "QtWebEngineProcess.exe",
    "qtwebengine_resources.pak",
    "qtwebengine_resources_100p.pak",
    "qtwebengine_resources_200p.pak",
    "icudtl.dat"
)) {
    if ($null -eq (Get-ChildItem $StageRoot -Recurse -File -Filter $pattern |
        Select-Object -First 1)) {
        throw "Staging is missing Qt WebEngine runtime: $pattern"
    }
}
$WebEngineLocale = Join-Path $StageRoot `
    "translations\qtwebengine_locales\en-US.pak"
if (!(Test-Path $WebEngineLocale -PathType Leaf)) {
    throw "Staging is missing the Qt WebEngine en-US locale"
}

$Dumpbin = (Get-Command dumpbin.exe -ErrorAction Stop).Source
$TargetPeFiles = Get-ChildItem $StageRoot -Recurse -File | Where-Object {
    $_.Extension -eq ".dll" -or
    ($_.Extension -eq ".exe" -and $_.Name -notmatch '^vc_redist\..+\.exe$')
}
foreach ($file in $TargetPeFiles) {
    $headers = & $Dumpbin /HEADERS $file.FullName 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $headers -notmatch $TargetMachinePattern) {
        throw "$($file.FullName) is not a valid x64 PE file"
    }
}

$PeFiles = Get-ChildItem $StageRoot -Recurse -File | Where-Object {
    $_.Extension -in @(".exe", ".dll") -and
    $_.Name -notmatch '^vc_redist\..+\.exe$'
}
$StagedNames = @{}
foreach ($file in $PeFiles) {
    $StagedNames[$file.Name.ToLowerInvariant()] = $true
}
$MissingDependencies = [System.Collections.Generic.HashSet[string]]::new()
foreach ($file in $PeFiles) {
    $output = & $Dumpbin /DEPENDENTS $file.FullName 2>&1
    if ($LASTEXITCODE -ne 0) {
        [void]$MissingDependencies.Add("$($file.Name): dumpbin failed")
        continue
    }
    foreach ($line in $output) {
        if ($line -notmatch '^\s+([A-Za-z0-9_.+\-]+\.dll)\s*$') {
            continue
        }
        $dependency = $Matches[1]
        $dependencyKey = $dependency.ToLowerInvariant()
        if ($StagedNames.ContainsKey($dependencyKey) -or
            $dependencyKey.StartsWith("api-ms-win-") -or
            $dependencyKey.StartsWith("ext-ms-win-")) {
            continue
        }
        if (!(Test-Path (Join-Path "$env:WINDIR\System32" $dependency)) -and
            !(Test-Path (Join-Path $env:WINDIR $dependency))) {
            [void]$MissingDependencies.Add("$($file.Name) -> $dependency")
        }
    }
}
if ($MissingDependencies.Count -gt 0) {
    $MissingDependencies | Sort-Object | ForEach-Object { Write-Host $_ }
    throw "Windows runtime dependency closure is incomplete"
}

$DebugDlls = @(Get-ChildItem $StageRoot -Recurse -File -Filter "*.dll" |
    Where-Object {
        if (!$_.BaseName.EndsWith("d", [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        $releaseName = $_.BaseName.Substring(0, $_.BaseName.Length - 1) + $_.Extension
        return Test-Path (Join-Path $_.DirectoryName $releaseName) -PathType Leaf
    })
if ($DebugDlls.Count -gt 0) {
    throw "Release staging contains debug DLLs: $($DebugDlls.FullName -join ', ')"
}

$AppVersionMatch = [regex]::Match($BuildVersion, '\d+(\.\d+){2,3}')
$AppVersion = if ($AppVersionMatch.Success) { $AppVersionMatch.Value } else { "0.0.0" }
$InstallerBaseName = "nunchuk-windows-v$BuildVersion-setup-unsigned"
$InstallerScript = Join-Path $ProjectRoot "nunchuk-reproducible.iss"
$InstallerDefinition = @"
#define MyAppName "Nunchuk"
#define MyAppVersion "$AppVersion"
#define MyAppExeName "nunchuk-qt.exe"

[Setup]
AppId={{8F1B9C2A-4D3E-4A21-9C7B-1E2F3A4B5C6D}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Nunchuk
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
OutputDir=$DistRoot
OutputBaseFilename=$InstallerBaseName
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0
PrivilegesRequired=admin
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "$StageRoot\*"; Excludes: "$VcRedistName"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "$StageRoot\$VcRedistName"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{tmp}\$VcRedistName"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ Runtime..."; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
"@
Set-Content $InstallerScript -Value $InstallerDefinition -Encoding UTF8
& $InnoCompiler $InstallerScript
Assert-LastExitCode "Inno Setup"

$Installer = Join-Path $DistRoot "$InstallerBaseName.exe"
if (!(Test-Path $Installer -PathType Leaf)) {
    throw "Installer was not produced: $Installer"
}

$InstallDirectory = Join-Path $env:RUNNER_TEMP "NunchukInstallerSmoke"
$InstallLog = Join-Path $env:RUNNER_TEMP "nunchuk-installer-smoke.log"
if (Test-Path $InstallDirectory) {
    Remove-Item $InstallDirectory -Recurse -Force
}
$InstallerArguments = @(
    "/VERYSILENT",
    "/SUPPRESSMSGBOXES",
    "/NORESTART",
    "/NOCANCEL",
    "/SP-",
    "/NOICONS",
    "/DIR=`"$InstallDirectory`"",
    '/TASKS=""',
    "/LOG=`"$InstallLog`""
)
$InstallerProcess = Start-Process -FilePath $Installer `
    -ArgumentList $InstallerArguments -Wait -PassThru
if ($InstallerProcess.ExitCode -ne 0) {
    if (Test-Path $InstallLog) {
        Get-Content $InstallLog -Tail 250
    }
    throw "Silent installer smoke test failed with exit code $($InstallerProcess.ExitCode)"
}
foreach ($relativePath in @(
    "nunchuk-qt.exe",
    "hwi.exe",
    "Qt5NetworkAuth.dll",
    "Qt5WebEngineCore.dll",
    "libcrypto-1_1-x64.dll",
    "libssl-1_1-x64.dll",
    "platforms\qwindows.dll",
    "unins000.exe"
)) {
    if (!(Test-Path (Join-Path $InstallDirectory $relativePath))) {
        throw "Installed application is missing: $relativePath"
    }
}
$SavedPath = $env:PATH
try {
    $env:PATH = "$InstallDirectory;$env:WINDIR\System32;$env:WINDIR"
    & $SslProbe
    Assert-LastExitCode "Installed Qt TLS runtime probe"
} finally {
    $env:PATH = $SavedPath
}

$PortableArchive = Join-Path $DistRoot "nunchuk-windows-portable-v$BuildVersion.zip"
Compress-Archive -Path "$StageRoot\*" -DestinationPath $PortableArchive -Force
if (!(Test-Path $PortableArchive -PathType Leaf)) {
    throw "Portable Windows archive was not produced"
}

Write-Host "Windows installer created: $Installer"
Write-Host "Windows portable archive created: $PortableArchive"
