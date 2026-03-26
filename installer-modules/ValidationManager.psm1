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

    # 1. Environment Preparation
    if (-not (Test-Path $venvPath)) {
        & $Global:Log -Message "Creating local venv for validation..." -Level "INFO"
        & python -m venv $venvPath
    }
    
    # Update Pip quietly
    & $python -m pip install --upgrade pip --quiet

    # 2. Install Generic Dependencies
    & $Global:Log -Message "Installing baseline dependencies (numpy, pillow, soundfile)..." -Level "INFO"
    & $python -m pip install numpy pillow soundfile --quiet

    # 3. Manifest Verification
    if (-not (Test-Path $versionFile)) {
        throw "Manifest 'torch-version.txt' missing. Please sync Torch archives first."
    }
    $manifestLines = Get-Content $versionFile
    
    # 4. Strict Ordered Installation Sequence
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
        # Braced variable ${key} prevents PowerShell scope-mapping errors with the colon
        $line = $manifestLines | Where-Object { $_ -match "^${key}:\s+(.*)" }
        
        if ($line) {
            $fileName = $Matches[1]
            $filePath = Join-Path $cacheDir $fileName
            # Map manifest key to pip package name (e.g., TORCH -> torch)
            $packageName = $key.ToLower()

            & $Global:Log -Message "Processing $packageName..." -Level "DEBUG" -Color Gray
            
            # Step A: Explicit Uninstall
            # -y auto-confirms; --quiet hides "Skipping package... not installed" warnings
            & $python -m pip uninstall $packageName -y --quiet
            
            # Step B: Fresh Install
            # Dependencies are allowed to resolve naturally against already-installed packages
            & $python -m pip install "$filePath" --quiet
        }
    }
    
    # 5. Finalize Validation Suite
    $reqFile = Join-Path $valPath "requirements.txt"
    if (Test-Path $reqFile) {
        & $python -m pip install -r $reqFile --quiet
    }
    
    & $Global:Log -Message "Validation environment setup complete." -Level "SUCCESS" -Color Green
}

Function Invoke-ValidationTests {
    $valStatus = Get-ValidationStatus
    if ($valStatus -ne "Ready") {
        & $Global:Log -Message "Cannot run tests: Validation environment is not Ready." -Level "ERROR"
        return
    }

    $valPath = Join-Path $PSScriptRoot "..\rocm-validation"
    $python = Join-Path $valPath "venv\Scripts\python.exe"
    
    & $Global:Log -Message "Starting ROCm Pytorch Validation Suite..." -Level "INFO" -Color Cyan
    
    # Navigate and run (assuming run_validation.py is the entry point)
    Push-Location $valPath
    try {
        & $python "run_validation.py"
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