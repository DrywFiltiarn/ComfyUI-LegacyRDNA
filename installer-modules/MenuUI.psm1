# installer-modules\MenuUI.psm1

Function Show-Header {
    Param(
        [string]$GPUName,
        [string]$Arch,
        [string]$VRAM,
        [string]$RocmVer,     # The ROCm SDK Version
        [hashtable]$TorchVers # Contains torch, torchvision, torchaudio, and rocm
    )
    
    Clear-Host
    Write-Host "================================================================" -ForegroundColor Gray
    Write-Host "          ComfyUI-LegacyRDNA - ROCm Nightly Manager             " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Gray
    Write-Host "  GPU: $GPUName ($Arch) | VRAM: $VRAM" -ForegroundColor White
    Write-Host "----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "  ROCm SDK: " -NoNewline; Write-Host "$RocmVer" -ForegroundColor Yellow
    Write-Host "----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "  ROCm Py:  " -NoNewline; Write-Host "$($TorchVers.rocm)" -ForegroundColor Yellow
    Write-Host "  Torch:    " -NoNewline; Write-Host "$($TorchVers.torch)" -ForegroundColor Yellow
    Write-Host "  Vision:   " -NoNewline; Write-Host "$($TorchVers.torchvision)" -ForegroundColor Yellow
    Write-Host "  Audio:    " -NoNewline; Write-Host "$($TorchVers.torchaudio)" -ForegroundColor Yellow
    Write-Host "----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host ""
}

Function Get-MenuSelection {
    Param(
        [string]$RocmAction, 
        [string]$TorchAction, 
        [string]$ValAction, 
        [bool]$CanRunVal
    )
    
    Write-Host "  1) " -NoNewline -ForegroundColor Green; Write-Host "$RocmAction ROCm SDK Nightly"
    Write-Host "  2) " -NoNewline -ForegroundColor Green; Write-Host "$TorchAction Torch/Vision/Audio WHLs"
    Write-Host "  3) " -NoNewline -ForegroundColor Green; Write-Host "$ValAction ROCm Validation Suite"
    
    if ($CanRunVal) {
        Write-Host "  4) " -NoNewline -ForegroundColor Green; Write-Host "Run ROCm Validation Tests"
    }

    Write-Host "  Q) " -NoNewline -ForegroundColor Red; Write-Host "Quit"
    Write-Host ""
    return Read-Host "Select an option"
}

Export-ModuleMember -Function Show-Header, Get-MenuSelection