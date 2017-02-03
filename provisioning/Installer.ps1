<#
  This script create the Windows installer based on WiX for GPII-App.
#>

param (
    [string]$provisioningDir = (Split-Path -parent $PSCommandPath) # Default to script path.
)

# Turn verbose on, change to "SilentlyContinue" for default behaviour.
$VerbosePreference = "continue"

# Store the project folder of the script (root of the repo) as $projectDir.
$projectDir = (Get-Item $provisioningDir).parent.FullName

Import-Module (Join-Path $provisioningDir 'Provisioning.psm1') -Force

$installerRepo = "https://github.com/gloob/gpii-wix-installer"
$installerBranch = "HST"

# Obtaining useful tools location.
$installerDir = Join-Path $env:SystemDrive "installer" # a.k.a. C:\installer\
$npm = "npm" -f $env:SystemDrive
$git = "git" -f $env:SystemDrive
$node = Get-Command "node.exe" | Select -expandproperty Path

# If $installerDir exists delete it and clone current branch of installer.
if ((Test-Path -Path $installerDir)){
    rm $installerDir -Recurse -Force
}
Invoke-Command $git "clone --branch $($installerBranch) $($installerRepo) $($installerDir)"

$stagingWindowsDir = [io.path]::combine($installerDir, "staging", "windows")
if (Test-Path -Path $stagingWindowsDir) {
    rm $stagingWindowsDir -Recurse -Force
}
md $stagingWindowsDir

$appDir = Join-Path $stagingWindowsDir "app"

# Npm install the application, this needs to be done for packaging.
Invoke-Command $npm "install" $projectDir

$packagerMetadata = "--app-copyright=`"Raising the Floor - International Association`" --win32metadata.CompanyName=`"Raising the Floor - International Association`" --win32metadata.FileDescription=`"GPII-App`" --win32metadata.OriginalFilename=`"gpii.exe`" --win32metadata.ProductName=`"GPII-App`" --win32metadata.InternalName=`"GPII-App`""

$packagerDir = Join-Path $installerDir "packager"
md $packagerDir
Invoke-Command "electron-packager.cmd" "$projectDir --platform=win32 --arch=x64 --overwrite --out=$packagerDir $packagerMetadata"

# Copying the packaged GPII-App content to staging/.
$packagedAppDir = (Join-Path $packagerDir "gpii-app-win32-x64")
Copy-Item "$packagedAppDir\*" $stagingWindowsDir -Recurse

# We are exiting with as a successful value if robocopy error is less or equal to 3
# to avoid interruption. http://ss64.com/nt/robocopy-exit.html
Invoke-Command "robocopy" "..\node_modules\gpii-windows\listeners $(Join-Path $stagingWindowsDir "listeners") /job:gpii-app.rcj *.*" $provisionginDir -errorLevel 3

# Compile listeners.
# TODO: This should be a function in Provisioning.psm1
Invoke-Environment "C:\Program Files (x86)\Microsoft Visual C++ Build Tools\vcbuildtools_msbuild.bat"
$msbuild = Get-MSBuild "4.0"
$listenersDir = Join-Path $stagingWindowsDir "listeners"
Invoke-Command $msbuild "listeners.sln /nodeReuse:false /p:Configuration=Release /p:FrameworkPathOverride=`"C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.5.1`"" $listenersDir

md (Join-Path $installerDir "output")
md (Join-Path $installerDir "temp")

Invoke-Environment "C:\Program Files (x86)\Microsoft Visual C++ Build Tools\vcbuildtools_msbuild.bat"
$setupDir = Join-Path $installerDir "setup"
$msbuild = Get-MSBuild "4.0"
Invoke-Command $msbuild "setup.msbuild" $setupDir
