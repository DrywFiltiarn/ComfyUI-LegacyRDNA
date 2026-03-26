Function Show-Header {
    Param(
        [string]$GPUName,
        [string]$Arch,
        [string]$VRAM,
        [string]$RocmVer,
        [hashtable]$TorchVers,
        [string]$ValStatus
    )
    
    $archLower = $Arch.ToLower()
    $libKey = "rocm-sdk-libraries-$archLower-dgpu"

    Clear-Host
    Write-Host "================================================================" -ForegroundColor Gray
    Write-Host "          ComfyUI-LegacyRDNA - ROCm Nightly Manager             " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Gray
    Write-Host "  GPU: $GPUName ($Arch) | VRAM: $VRAM" -ForegroundColor White
    Write-Host "----------------------------------------------------------------" -ForegroundColor Gray
    Write-Host "  $("ROCm SDK".PadRight(15)) : " -NoNewline; Write-Host "$RocmVer" -ForegroundColor Yellow
    Write-Host "----------------------------------------------------------------" -ForegroundColor Gray

    $sdkLibsVal = if ($TorchVers.ContainsKey($libKey)) { $TorchVers[$libKey] } else { "None" }
    if ($sdkLibsVal -ne "None" -and $sdkLibsVal -notmatch "\|") {
        $sdkLibsVal = "$sdkLibsVal | $archLower"
    }

    $displayItems = @(
        @{ Label = "ROCm SDK Core"  ; Value = $TorchVers['rocm-sdk-core'] }
        @{ Label = "ROCm SDK Libs"  ; Value = $sdkLibsVal }
        @{ Label = "ROCm Python"    ; Value = $TorchVers['rocm'] }
        @{ Label = "PyTorch"        ; Value = $TorchVers['torch'] }
        @{ Label = "PyTorch Vision" ; Value = $TorchVers['torchvision'] }
        @{ Label = "PyTorch Audio"  ; Value = $TorchVers['torchaudio'] }
    )

    foreach ($item in $displayItems) {
        $val = if ($item.Value) { $item.Value } else { "None" }
        Write-Host "  $($item.Label.PadRight(15)) : " -NoNewline
        Write-Host "$val" -ForegroundColor Yellow
    }

    Write-Host "----------------------------------------------------------------" -ForegroundColor Gray
    $valColor = switch ($ValStatus) {
        "Ready" { "Green" }
        "None"  { "Red" }
        Default { "Yellow" }
    }
    Write-Host "  Validation Suite: " -NoNewline
    Write-Host "$ValStatus" -ForegroundColor $valColor

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