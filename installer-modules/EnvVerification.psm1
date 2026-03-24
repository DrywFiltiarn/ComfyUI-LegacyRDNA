# installer-modules\EnvVerification.psm1

Function Assert-Elevation {
    Param([bool]$IsElevated)
    Write-Host "[*] Checking for Administrator privileges..." -NoNewline
    if ($IsElevated) {
        Write-Host " [OK]" -ForegroundColor Green
    } else {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Host ""
        Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
        Write-Host " ERROR: THIS INSTALLER REQUIRES ADMINISTRATOR PRIVILEGES" -ForegroundColor Red
        Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
        Write-Host " To resolve this:" -ForegroundColor White
        Write-Host " 1. Close this window." -ForegroundColor White
        Write-Host " 2. Right-click your PowerShell shortcut or Start menu icon." -ForegroundColor White
        Write-Host " 3. Select 'Run as administrator'." -ForegroundColor White
        Write-Host " 4. Navigate back to this directory and run install.ps1 again." -ForegroundColor White
        throw "Missing Administrator Privileges"
    }
}

Function Assert-OSCompatibility {
    Param([hashtable]$OSStatus)
    Write-Host "[*] Verifying OS Version..." -NoNewline
    if ($OSStatus.Success) {
        Write-Host " [OK]" -ForegroundColor Green
        Write-Host "     Detected: $($OSStatus.Name)" -ForegroundColor Gray
    } else {
        Write-Host " [FAILED]" -ForegroundColor Red
        throw "Incompatible OS: $($OSStatus.Name)"
    }
}

Function Assert-PythonCompatibility {
    Param([hashtable]$PyStatus)
    Write-Host "[*] Verifying Python 3.12..." -NoNewline
    if ($PyStatus.Success) {
        Write-Host " [OK]" -ForegroundColor Green
        Write-Host "     Detected: Python $($PyStatus.Version)" -ForegroundColor Gray
    } else {
        Write-Host " [FAILED]" -ForegroundColor Red
        $msg = if ($PyStatus.Error -eq "WrongVersion") { "Detected Python $($PyStatus.Version), but 3.12 is required." } else { "Python 3.12 not found in PATH." }
        Write-Host "     Action: Please install Python 3.12 (64-bit) from https://www.python.org/downloads/windows/" -ForegroundColor White
        throw $msg
    }
}

Function Assert-GPUCompatibility {
    Param([hashtable]$GPUStatus)
    Write-Host "[*] Verifying AMD GPU Compatibility..." -NoNewline
    switch ($GPUStatus.Support) {
        "Legacy" {
            Write-Host " [OK]" -ForegroundColor Green
            Write-Host "     Detected: $($GPUStatus.Name)" -ForegroundColor Gray
            Write-Host "     Targeting Asset Path: $($GPUStatus.Arch)" -ForegroundColor Cyan
            return $GPUStatus.Arch
        }
        "Official" {
            Write-Host " [SKIPPED]" -ForegroundColor Yellow
            throw "RDNA3/4 cards ($($GPUStatus.Name)) have official support; this legacy installer is not required."
        }
        "Unsupported" {
            Write-Host " [NOT SUPPORTED]" -ForegroundColor Red
            Write-Host "     Notice: Pre-RDNA cards (Vega, Polaris, etc.) technically cannot be supported." -ForegroundColor Red
            Write-Host "     Reason: These architectures lack the necessary AMD support in the ROCm nightly builds." -ForegroundColor Red
            throw "Pre-RDNA Architecture Unsupported"
        }
        Default {
            Write-Host " [FAILED]" -ForegroundColor Red
            throw "No compatible AMD RDNA1 or RDNA2 GPU detected."
        }
    }
}

Export-ModuleMember -Function Assert-Elevation, Assert-OSCompatibility, Assert-PythonCompatibility, Assert-GPUCompatibility