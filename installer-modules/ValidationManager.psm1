Function Get-ValidationStatus {
    $valPath = Join-Path $PSScriptRoot "..\rocm-validation"
    $venvPath = Join-Path $valPath "venv"
    $isRepo = Test-Path (Join-Path $valPath ".git")
    $hasVenv = Test-Path (Join-Path $venvPath "Scripts\python.exe")
    
    if (-not $isRepo) { return "None" }
    if (-not $hasVenv) { return "MissingVenv" }
    return "Ready"
}

Function Sync-ValidationRepo {
    $valPath = Join-Path $PSScriptRoot "..\rocm-validation"
    $repoUrl = "https://github.com/DrywFiltiarn/ROCm-PyTorch-Win-Validation-for-gfx10xx"
    
    if (-not (Test-Path $valPath)) {
        & $Global:Log -Message "Cloning validation repository..." -Level "INFO"
        & git clone -q $repoUrl $valPath
    } else {
        & $Global:Log -Message "Updating validation repository..." -Level "INFO"
        & git -C $valPath pull -q
    }
}

Function Update-ValidationPip {
    $valPath = Join-Path $PSScriptRoot "..\rocm-validation"
    $python = Join-Path $valPath "venv\Scripts\python.exe"
    
    if (Test-Path $python) {
        & $Global:Log -Message "Upgrading Pip in validation venv..." -Level "DEBUG" -Color Gray
        & $python -m pip install --upgrade pip --quiet
    }
}

Function Install-ValidationDeps {
    $valPath = Join-Path $PSScriptRoot "..\rocm-validation"
    $cacheDir = Join-Path $PSScriptRoot "..\.cache"
    $versionFile = Join-Path $cacheDir "torch-version.txt"
    $venvPath = Join-Path $valPath "venv"
    $python = Join-Path $venvPath "Scripts\python.exe"

    if (-not (Test-Path $venvPath)) {
        & $Global:Log -Message "Creating local venv for validation..." -Level "INFO"
        & python -m venv $venvPath
    }
    
    & $python -m pip install --upgrade pip --quiet

    & $Global:Log -Message "Installing baseline dependencies (numpy, pillow, soundfile)..." -Level "INFO"
    & $python -m pip install numpy pillow soundfile --quiet

    if (-not (Test-Path $versionFile)) {
        throw "Manifest 'torch-version.txt' missing. Please sync Torch archives first."
    }
    $manifestLines = Get-Content $versionFile
    
    $ArchSuffix = $Global:Env_GfxArch.ToLower()
    $LibKey = "ROCM-SDK-LIBRARIES-$ArchSuffix-DGPU"
    
    $order = @(
        "ROCM-SDK-CORE",
        $LibKey,
        "ROCM",
        "TORCH",
        "TORCHVISION",
        "TORCHAUDIO"
    )

    & $Global:Log -Message "Installing ROCm Nightly components via Uninstall/Install cycle..." -Level "INFO"
    
    foreach ($key in $order) {
        $line = $manifestLines | Where-Object { $_ -match "^${key}:\s+(.*)" }
        
        if ($line) {
            $fileName = $Matches[1]
            $filePath = Join-Path $cacheDir $fileName
            $packageName = $key.ToLower()

            & $Global:Log -Message "Processing $packageName..." -Level "DEBUG" -Color Gray
            & $python -m pip uninstall $packageName -y --quiet
            & $python -m pip install "$filePath" --quiet
        }
    }
    
    $reqFile = Join-Path $valPath "requirements.txt"
    if (Test-Path $reqFile) {
        & $python -m pip install -r $reqFile --quiet
    }
    
    & $Global:Log -Message "Validation environment setup complete." -Level "SUCCESS" -Color Green
}

Function Invoke-ValidationTests {
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ExtraArgs
    )

    $valStatus = Get-ValidationStatus
    if ($valStatus -eq "None") {
        & $Global:Log -Message "Validation Suite not found. Please run Option 3 first." -Level "ERROR"
        return
    }

    $valPath = Join-Path $PSScriptRoot "..\rocm-validation"
    $suiteScript = Join-Path $valPath "run_suite.ps1"
    
    $rocmNightlyPath = Resolve-Path (Join-Path $PSScriptRoot "..\rocm-nightly") -ErrorAction SilentlyContinue
    
    if (-not (Test-Path $suiteScript)) {
        & $Global:Log -Message "run_suite.ps1 missing in validation directory." -Level "ERROR"
        return
    }

    if (-not $rocmNightlyPath) {
        & $Global:Log -Message "rocm-nightly directory not found. Cannot set HIP_PATH." -Level "ERROR"
        return
    }

    & $Global:Log -Message "Preparing Validation Environment..." -Level "INFO"
    & $Global:Log -Message "Setting HIP_PATH to: $($rocmNightlyPath.Path)" -Level "DEBUG" -Color Gray

    $env:HIP_PATH = $rocmNightlyPath.Path
    $env:PATH = "$(Join-Path $env:HIP_PATH 'bin');$env:PATH"

    & $Global:Log -Message "Invoking Validation Suite..." -Level "INFO" -Color Cyan
    
    Push-Location $valPath
    try {
        if ($ExtraArgs) {
            & .\run_suite.ps1 -Unattended @ExtraArgs
        } else {
            & .\run_suite.ps1 -Unattended
        }

        if ($LASTEXITCODE -eq 0) {
            & $Global:Log -Message "Validation Suite completed: ALL TESTS PASSED." -Level "SUCCESS" -Color Green
        } else {
            & $Global:Log -Message "Validation Suite completed: TEST FAILURES DETECTED (Exit Code: $LASTEXITCODE)." -Level "ERROR" -Color Red
        }
    } catch {
        & $Global:Log -Message "An unexpected error occurred during test invocation: $_" -Level "ERROR"
    } finally {
        Pop-Location
    }
}

Function Assert-ValidationIntegrity {
    Param([string]$Status)
    if ($Status -eq "MissingVenv") {
        & $Global:Log -Message "Validation Suite detected but environment is broken/missing." -Level "WARN" -Color Yellow
    }
}
Export-ModuleMember -Function Get-ValidationStatus, Assert-ValidationIntegrity, Sync-ValidationRepo, Install-ValidationDeps, Invoke-ValidationTests