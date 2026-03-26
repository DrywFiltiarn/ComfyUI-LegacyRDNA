# install.ps1
$ErrorActionPreference = "Stop"
$Global:Installer_Debug = $true  # Set to $false for Production

# Helper function for conditional logging
Function Write-Log {
    Param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][string]$Level = "DEBUG",
        [Parameter(Mandatory=$false)][ConsoleColor]$Color = "Gray"
    )
    
    if ($Level -eq "DEBUG" -and -not $Global:Installer_Debug) { return }
    
    Write-Host "[$Level] $Message" -ForegroundColor $Color
}

# Export the logger to the global scope so modules can see it
$Global:Log = Get-Item Function:\Write-Log

Import-Module ".\installer-modules\EnvDiscovery.psm1" -Force
Import-Module ".\installer-modules\EnvVerification.psm1" -Force
Import-Module ".\installer-modules\RocmManager.psm1" -Force
Import-Module ".\installer-modules\TorchManager.psm1" -Force
Import-Module ".\installer-modules\ValidationManager.psm1" -Force
Import-Module ".\installer-modules\MenuUI.psm1" -Force

try {
    # PHASE 1: INITIAL VERIFICATION
    Clear-Host
    Assert-Elevation -IsElevated (Get-ElevationStatus)
    Assert-GitCompatibility -GitStatus (Get-GitStatus)
    $currentGPU = Get-AMDGPUStatus
    Assert-OSCompatibility -OSStatus (Get-OSStatus)
    Assert-PythonCompatibility -PyStatus (Get-PythonStatus)
    $Global:Env_GfxArch = Assert-GPUCompatibility -GPUStatus $currentGPU
    $Global:Env_VRAM = Get-VRAMSize
    
    Write-Host "`n[SUCCESS] Environment Verified. Press ENTER to enter the installer menu..." -ForegroundColor Green
    Read-Host

    # PHASE 2: MENU LOOP
    $running = $true

    while ($running) {
        $rocmVersion = Get-InstalledRocmVersion
        $torchStatus = Get-InstalledTorchVersions
        $torchVers = $torchStatus.Versions
        $valStatus = Get-ValidationStatus
        
        Assert-ValidationIntegrity -Status $valStatus

        $rocmAction = if ($rocmVersion -eq "None") { "Install" } else { "Update" }
        $hasAllTorch = $torchStatus.Success
        $torchAction = if ($hasAllTorch) { "Update" } else { "Download" }
        $valStatus = Get-ValidationStatus
        $valAction = if ($valStatus -eq "None") { "Install" } else { "Update" }
        $canRunVal = ($valStatus -eq "Ready")

        Show-Header -GPUName $currentGPU.Name -Arch $Global:Env_GfxArch -VRAM $Global:Env_VRAM `
                    -RocmVer $rocmVersion -TorchVers $torchVers -ValStatus $valStatus

        $choice = Get-MenuSelection -RocmAction $rocmAction -TorchAction $torchAction `
                                            -ValAction $valAction -CanRunVal $canRunVal
        
        switch ($choice) {
            "1" {
                $build = Get-LatestRocmBuild -Arch $Global:Env_GfxArch
                if ($build) {
                    $hasDownloaded = Sync-RocmArchive -BuildInfo $build
                    $rocmDir = Join-Path $PSScriptRoot "rocm-nightly"
                    if (($rocmAction -eq "Install") -or $hasDownloaded -or -not (Test-Path $rocmDir)) {
                        $null = Expand-RocmArchive -BuildInfo $build
                    }
                }
                Read-Host "`nPress Enter to return to menu..."
            }
            "2" {
                Write-Host "`n--- Torch WHL Sync Process Started ---" -ForegroundColor Cyan
                $build = Get-LatestTorchBuilds -Arch $Global:Env_GfxArch
                if ($build) {
                    $null = Sync-TorchArchives -BuildInfo $build
                }
                Read-Host "`nPress Enter to return to menu..."
            }
            "3" {
                Sync-ValidationRepo
                Install-ValidationDeps
                Read-Host "`nPress Enter to return to menu..."
            }
            "4" {
                if ($canRunVal) { Invoke-ValidationTests }
                else { Write-Host "Please install or repair the Validation Suite first." -ForegroundColor Yellow }
                Read-Host "`nPress Enter to return to menu..."
            }            
            "Q" { $running = $false }
        }
    }
} catch {
    Write-Host "`nInstallation aborted: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}