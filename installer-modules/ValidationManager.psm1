Function Get-ValidationStatus {
    $valPath = Join-Path $PSScriptRoot "..\rocm-validation"
    $venvPath = Join-Path $valPath "venv"
    $isRepo = Test-Path (Join-Path $valPath ".git")
    $hasVenv = Test-Path (Join-Path $venvPath "Scripts\python.exe")
    
    if (-not $isRepo) { return "None" }
    if (-not $hasVenv) { return "MissingVenv" }
    return "Ready"
}

Function Assert-ValidationIntegrity {
    Param([string]$Status)
    if ($Status -eq "MissingVenv") {
        & $Global:Log -Message "Validation Suite detected but environment is broken/missing." -Level "WARN" -Color Yellow
    }
}

Function Sync-ValidationRepo {
    $valPath = Join-Path $PSScriptRoot "..\rocm-validation"
    $repoUrl = "https://github.com/DrywFiltiarn/ROCm-PyTorch-Win-Validation-for-gfx10xx"
    
    if (-not (Test-Path $valPath)) {
        & $Global:Log -Message "Cloning validation repository..." -Level "INFO"
        & git clone $repoUrl $valPath
    } else {
        & $Global:Log -Message "Updating validation repository..." -Level "INFO"
        & git -C $valPath pull
    }
}

Function Update-ValidationPip {
    $valPath = Join-Path $PSScriptRoot "..\rocm-validation"
    $python = Join-Path $valPath "venv\Scripts\python.exe"
    
    if (Test-Path $python) {
        & $Global:Log -Message "Checking for Pip updates in validation venv..." -Level "DEBUG" -Color Gray
        & $python -m pip install --upgrade pip --quiet
    }
}

Function Install-ValidationDeps {
    $valPath = Join-Path $PSScriptRoot "..\rocm-validation"
    $cacheDir = Join-Path $PSScriptRoot "..\.cache"
    $venvPath = Join-Path $valPath "venv"
    $python = Join-Path $venvPath "Scripts\python.exe"

    # 1. Ensure VENV exists
    if (-not (Test-Path $venvPath)) {
        & $Global:Log -Message "Creating local venv for validation..." -Level "INFO"
        & python -m venv $venvPath
    }

    Update-ValidationPip

    # 2. Identify latest wheels from cache
    $wheels = Get-ChildItem $cacheDir -Filter "*.whl" | Select-Object -ExpandProperty FullName
    if ($wheels.Count -lt 3) {
        throw "Required Torch wheels missing from .cache. Please download them first."
    }

    # 3. Install/Update wheels into the venv
    & $Global:Log -Message "Syncing dependencies to validation venv..." -Level "INFO"
    foreach ($whl in $wheels) {
        & $python -m pip install --force-reinstall "$whl"
    }
    
    # 4. Final dependencies (requirements.txt if present)
    if (Test-Path (Join-Path $valPath "requirements.txt")) {
        & $python -m pip install -r (Join-Path $valPath "requirements.txt")
    }
}

Function Invoke-ValidationTests {
    $valStatus = Get-ValidationStatus
    if ($valStatus -ne "Ready") {
        & $Global:Log -Message "Cannot run tests: Validation environment is not Ready." -Level "ERROR"
        return
    }

    $valPath = Join-Path $PSScriptRoot "..\rocm-validation"
    $python = Join-Path $valPath "venv\Scripts\python.exe"
    
    # ... execution logic ...
}

Export-ModuleMember -Function Get-ValidationStatus, Assert-ValidationIntegrity, Sync-ValidationRepo, Install-ValidationDeps, Invoke-ValidationTests