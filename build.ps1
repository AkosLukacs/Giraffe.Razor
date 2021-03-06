# ----------------------------------------------
# Build script
# ----------------------------------------------

param
(
    [switch] $Release,
    [switch] $ExcludeSamples,
    [switch] $Pack,
    [switch] $Run,
    [switch] $OnlyNetStandard,
    [switch] $ClearOnly
)

$ErrorActionPreference = "Stop"

# ----------------------------------------------
# Helper functions
# ----------------------------------------------

function Test-IsWindows
{
    [environment]::OSVersion.Platform -ne "Unix"
}

function Invoke-Cmd ($cmd)
{
    Write-Host $cmd -ForegroundColor DarkCyan
    if (Test-IsWindows) { $cmd = "cmd.exe /C $cmd" }
    Invoke-Expression -Command $cmd
    if ($LastExitCode -ne 0) { Write-Error "An error occured when executing '$cmd'."; return }
}

function Write-DotnetVersion
{
    $dotnetVersion = Invoke-Cmd "dotnet --version"
    Write-Host ".NET Core runtime version: $dotnetVersion" -ForegroundColor Cyan
}

function dotnet-restore ($project, $argv) { Invoke-Cmd "dotnet restore $project $argv" }
function dotnet-build   ($project, $argv) { Invoke-Cmd "dotnet build $project $argv" }
function dotnet-run     ($project, $argv) { Invoke-Cmd "dotnet run --project $project $argv" }
function dotnet-test    ($project, $argv) { Invoke-Cmd "dotnet test $project $argv" }
function dotnet-pack    ($project, $argv) { Invoke-Cmd "dotnet pack $project $argv" }

function Test-Version ($project)
{
    if ($env:APPVEYOR_REPO_TAG -eq $true)
    {
        Write-Host "Matching version against git tag..." -ForegroundColor Magenta

        [xml] $xml = Get-Content $project
        [string] $version = $xml.Project.PropertyGroup.Version
        [string] $gitTag  = $env:APPVEYOR_REPO_TAG_NAME

        Write-Host "Project version: $version" -ForegroundColor Cyan
        Write-Host "Git tag version: $gitTag" -ForegroundColor Cyan

        if (!$gitTag.EndsWith($version))
        {
            Write-Error "Version and Git tag do not match."
        }
    }
}

function Update-AppVeyorBuildVersion ($project)
{
    if ($env:APPVEYOR -eq $true)
    {
        Write-Host "Updating AppVeyor build version..." -ForegroundColor Magenta

        [xml]$xml = Get-Content $project
        $version = $xml.Project.PropertyGroup.Version
        $buildVersion = "$version-$env:APPVEYOR_BUILD_NUMBER"
        Write-Host "Setting AppVeyor build version to $buildVersion."
        Update-AppveyorBuild -Version $buildVersion
    }
}

function Remove-OldBuildArtifacts
{
    Write-Host "Deleting old build artifacts..." -ForegroundColor Magenta

    Get-ChildItem -Include "bin", "obj" -Recurse -Directory `
    | ForEach-Object {
        Write-Host "Removing folder $_" -ForegroundColor DarkGray
        Remove-Item $_ -Recurse -Force }
}

function Get-TargetFrameworks ($projFile)
{
    [xml]$proj = Get-Content $projFile
    ($proj.Project.PropertyGroup.TargetFrameworks).Split(";")
}

function Get-NetCoreTargetFramework ($projFile)
{
    Get-TargetFrameworks $projFile  | where { $_ -like "netstandard*" -or $_ -like "netcoreapp*" }
}

function Get-FrameworkArg ($projFile)
{
    if ($OnlyNetStandard.IsPresent) {
        $fw = Get-NetCoreTargetFramework $projFile
        "-f $fw"
    }
    else { "" }
}

# ----------------------------------------------
# Main
# ----------------------------------------------

if ($ClearOnly.IsPresent) {
    Remove-OldBuildArtifacts
    return
}

$giraffeRazor = ".\src\Giraffe.Razor\Giraffe.Razor.fsproj"
$sampleApp    = ".\samples\GiraffeRazorSample\GiraffeRazorSample.fsproj"
$sampleAppMiniProfiler    = ".\samples\GiraffeRazorSampleWithMiniProfiler\GiraffeRazorSampleWithMiniProfiler.fsproj"

Update-AppVeyorBuildVersion $giraffeRazor
Test-Version $giraffeRazor
Write-DotnetVersion
Remove-OldBuildArtifacts

$configuration = if ($Release.IsPresent) { "Release" } else { "Debug" }

Write-Host "Building Giraffe.Razor..." -ForegroundColor Magenta
$framework = Get-FrameworkArg $giraffeRazor
dotnet-restore $giraffeRazor
dotnet-build   $giraffeRazor "-c $configuration $framework"

if (!$ExcludeSamples.IsPresent -and !$Run.IsPresent)
{
    Write-Host "Building and testing samples..." -ForegroundColor Magenta

    dotnet-restore $sampleApp
    dotnet-build   $sampleApp
    dotnet-restore $sampleAppMiniProfiler
    dotnet-build   $sampleAppMiniProfiler
}

if ($Run.IsPresent)
{
    Write-Host "Launching sample application..." -ForegroundColor Magenta
    dotnet-restore $sampleApp
    dotnet-build   $sampleApp
    dotnet-run     $sampleApp
}

if ($Pack.IsPresent)
{
    Write-Host "Packaging all NuGet packages..." -ForegroundColor Magenta
    dotnet-pack $giraffeRazor "-c $configuration"
}