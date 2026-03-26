# installer-modules\MenuUI.psm1

Function Show-Header {
    Param(
        [string]$GPUName,
        [string]$Arch,
        [string]$VRAM,
        [string]$RocmVer,
        [hashtable]$TorchVers
    )
    
    $archLower = $Arch.ToLower()
    $libKey = "rocm-sdk-libraries-$archLower-dgpu"

    Clear-Host
    Write-Host "================================================================" -ForegroundColor Gray
    Write-Host "          ComfyUI-LegacyRDNA - ROCm Nightly Manager             " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Gray
    Write-Host "  GPU: $GPUName ($Arch) | VRAM: $VRAM" -ForegroundColor White
    Write-Host "----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "  $("ROCm SDK".PadRight(15)): " -NoNewline; Write-Host "$RocmVer" -ForegroundColor Yellow
    Write-Host "----------------------------------------------------------------" -ForegroundColor Gray

    # List in order of relevance
    $items = @(
        @{ Key = "rocm-sdk-core"; Label = "ROCm SDK Core" },
        @{ Key = $libKey;         Label = "ROCm SDK Libs" },
        @{ Key = "rocm";          Label = "ROCm Python" },
        @{ Key = "torch";         Label = "PyTorch" },
        @{ Key = "torchvision";   Label = "PyTorch Vision" },
        @{ Key = "torchaudio";    Label = "PyTorch Audio" }
    )

    foreach ($item in $items) {
        $val = if ($TorchVers.ContainsKey($item.Key)) { $TorchVers[$item.Key] } else { "None" }
        Write-Host "  $($item.Label.PadRight(15)): " -NoNewline
        Write-Host "$val" -ForegroundColor Yellow
    }
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