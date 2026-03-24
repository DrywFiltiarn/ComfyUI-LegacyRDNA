Function Get-InstalledRocmVersion {
    $cacheDir = Join-Path $PSScriptRoot "..\.cache"
    $versionFile = Join-Path $cacheDir "rocm-version.txt"
    $rocmPath = Join-Path $PSScriptRoot "..\rocm-nightly"
    
    $hasVersionInfo = Test-Path $versionFile
    $hasArchive = (Get-ChildItem $cacheDir -Filter "therock-dist-windows-*.tar.gz" -ErrorAction SilentlyContinue).Count -gt 0
    $hasFolderContents = (Test-Path $rocmPath) -and ((Get-ChildItem $rocmPath -ErrorAction SilentlyContinue).Count -gt 0)

    if ($hasVersionInfo -and $hasArchive -and $hasFolderContents) {
        try {
            return (Get-Content $versionFile -Raw).Trim()
        } catch {
            return "None"
        }
    }
    return "None"
}

Function Get-LatestRocmBuild {
    Param([string]$Arch)
    $baseUrl = "https://therock-nightly-tarball.s3.amazonaws.com"
    $indexUrl = "$baseUrl/index.html"
    
    & $Global:Log -Message "Querying S3 Index: $indexUrl" -Level "DEBUG"
    
    try {
        $response = Invoke-WebRequest -Uri $indexUrl -UseBasicParsing -TimeoutSec 20
        if ($response.Content -match 'const files = (\[.*?\]);') {
            $jsonRaw = $matches[1]
            $fileList = $jsonRaw | ConvertFrom-Json
            $pattern = "therock-dist-windows-$Arch"
            
            $latestEntry = $fileList | Where-Object { $_.name -match $pattern } | Select-Object *, @{
                Name = 'BuildDate'
                Expression = { if ($_.name -match '(\d{8})\.tar\.gz$') { $matches[1] } else { "00000000" } }
            } | Sort-Object BuildDate -Descending | Select-Object -First 1
            
            if ($latestEntry) {
                $fileName = $latestEntry.name
                $prefix = "therock-dist-windows-$Arch-dgpu-"
                $versionStr = ($fileName -replace $prefix, "" -replace ".tar.gz", "")
                
                return @{ Url = "$baseUrl/$fileName"; FileName = $fileName; Version = $versionStr }
            }
        }
    } catch { 
        & $Global:Log -Message "Discovery failed: $($_.Exception.Message)" -Level "ERROR" -Color Red
    }
    return $null
}

Function Sync-RocmArchive {
    Param([hashtable]$BuildInfo)
    $cacheDir = Join-Path $PSScriptRoot "..\.cache"
    # Capture New-Item to prevent "DirectoryInfo" object output
    if (-not (Test-Path $cacheDir)) { $null = New-Item -ItemType Directory $cacheDir -Force }

    $targetPath = Join-Path $cacheDir $BuildInfo.FileName
    $versionFile = Join-Path $cacheDir "rocm-version.txt"
    
    if (Test-Path $targetPath) {
        & $Global:Log -Message "ROCm achive already cached." -Level "INFO" -Color Cyan
        $BuildInfo.Version | Out-File $versionFile -Force
        return $false # Return boolean for logic, but caller MUST capture it
    }

    & $Global:Log -Message "Cleaning .cache..." -Level "DEBUG"
    Get-ChildItem $cacheDir -Filter "therock-dist-windows-*.tar.gz" | Remove-Item -Force

    Write-Host "[!] Initiating High-Speed Download (curl.exe): $($BuildInfo.FileName)" -ForegroundColor Cyan
    
    try {
        & curl.exe --fail -L -# -o "$targetPath" "$($BuildInfo.Url)"
        if ($LASTEXITCODE -ne 0) { throw "curl failed." }
        
        $BuildInfo.Version | Out-File $versionFile -Force
        return $true
    } catch {
        & $Global:Log -Message "Download failed." -Level "ERROR" -Color Red
        if (Test-Path $targetPath) { Remove-Item $targetPath -Force }
        return $false
    }
}

Function Expand-RocmArchive {
    Param([hashtable]$BuildInfo)
    $archivePath = Join-Path $PSScriptRoot "..\.cache\$($BuildInfo.FileName)"
    $targetDir = Join-Path $PSScriptRoot "..\rocm-nightly"

    if (Test-Path $targetDir) {
        & $Global:Log -Message "Purging rocm-nightly..." -Level "DEBUG"
        Remove-Item -Path $targetDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Capture directory creation
    $null = New-Item -ItemType Directory $targetDir -Force

    Write-Host "[!] Extracting ROCm SDK via tar.exe..." -ForegroundColor Cyan
    try {
        tar.exe -xzf "$archivePath" -C "$targetDir"
        Write-Host "[OK] Extraction complete." -ForegroundColor Green
        return $true
    } catch {
        & $Global:Log -Message "Extraction failed." -Level "ERROR" -Color Red
        return $false
    }
}

Export-ModuleMember -Function Get-InstalledRocmVersion, Get-LatestRocmBuild, Sync-RocmArchive, Expand-RocmArchive