# installer-modules\MenuUI.psm1

Function Show-Header {
    Param($GPUName, $Arch, $VRAM, $RocmVer, $TorchVers)
    Clear-Host
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host "   ComfyUI-LegacyRDNA Project | Milestone 2.9.0" -ForegroundColor White
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host "  Hardware        : $GPUName ($Arch) | VRAM: $VRAM" -ForegroundColor Gray
    Write-Host "  ROCm SDK        : $RocmVer" -ForegroundColor Yellow
    Write-Host "---------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  PyTorch         : $($TorchVers.torch)" -ForegroundColor Yellow
    Write-Host "  PyTorch Vision  : $($TorchVers.torchvision)" -ForegroundColor Yellow
    Write-Host "  PyTorch Audio   : $($TorchVers.torchaudio)" -ForegroundColor Yellow
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host ""
}

Function Get-MenuSelection {
    Param([string]$RocmActionLabel, [string]$TorchActionLabel)
    
    Write-Host "  1) " -NoNewline -ForegroundColor Green; Write-Host "$RocmActionLabel ROCm SDK Nightly"
    Write-Host "  2) " -NoNewline -ForegroundColor Green; Write-Host "$TorchActionLabel Torch/Vision/Audio WHLs"
    Write-Host "  Q) " -NoNewline -ForegroundColor Red; Write-Host "Quit"
    Write-Host ""
    return Read-Host "Select an option"
}

Export-ModuleMember -Function Show-Header, Get-MenuSelection