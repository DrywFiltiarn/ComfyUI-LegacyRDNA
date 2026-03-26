Function Get-InstalledTorchVersions {
    $cacheDir = Join-Path $PSScriptRoot "..\.cache"
    $versionFile = Join-Path $cacheDir "torch-version.txt"
    
    # Priority Order: ROCM first
    $packageNames = @("rocm", "torch", "torchvision", "torchaudio")
    $results = @{ Success = $false; Versions = @{} }
    foreach ($pkg in $packageNames) { $results.Versions[$pkg] = "None" }

    if (-not (Test-Path $versionFile)) { return $results }

    $whlFiles = Get-ChildItem $cacheDir -Filter "*.whl" -ErrorAction SilentlyContinue
    $missingAny = $false

    foreach ($pkg in $packageNames) {
        # Handle different formats: .tar.gz for rocm, .whl for others
        $pattern = if ($pkg -eq "rocm") { "^rocm-([\d\.\w\+]+a\d{8})\.tar\.gz" } 
                   else { "^$($pkg)-([\d\.\w\+]+)-cp312" }
        
        $match = $cacheFiles | Where-Object { $_.Name -match $pattern }
        if ($match) {
            $results.Versions[$pkg] = $Matches[1]
        } else {
            $missingAny = $true
            & $Global:Log -Message "DEBUG: Missing cached component: $pkg" -Level "DEBUG" -Color Yellow
        }
    }

    if (-not $missingAny) { $results.Success = $true }
    return $results
}

Function Get-LatestTorchBuilds {
    Param([string]$Arch)
    
    # Priority Order: ROCM first
    $packages = @("rocm", "torch", "torchvision", "torchaudio")
    $packageBuilds = @{} 
    $baseUrlBase = "https://rocm.nightlies.amd.com/v2-staging/$Arch-dgpu"

    foreach ($pkg in $packages) {
        $url = "$baseUrlBase/$pkg"
        & $Global:Log -Message "Querying ${pkg} index: $url" -Level "DEBUG"
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20

            # Specialized pattern for ROCm (.tar.gz) vs others (.whl)
            $pattern = if ($pkg -eq "rocm") { 'href="([^"]*rocm-[\d\.\w\+]+?a(\d{8})\.tar\.gz)"' }
                       else { 'href="([^"]*' + $pkg + '[^"]*?a(\d{8})[^"]*?cp312[^"]*?win_amd64\.whl)"' }
            
            $matches = [regex]::Matches($resp.Content, $pattern)
            
            $builds = $matches | ForEach-Object {
                [PSCustomObject]@{
                    Date     = $_.Groups[2].Value
                    RawHref  = $_.Groups[1].Value
                    FileName = ($_.Groups[1].Value -replace '^\.*\/+', '') -replace '%2B', '+'
                }
            }
            
            # [DEBUG] reporting of found versions on server
            $foundDates = ($builds.Date | Select-Object -Unique | Sort-Object -Descending) -join ", "
            & $Global:Log -Message "DEBUG: $pkg found dates on server: [$foundDates]" -Level "DEBUG" -Color Gray
            $packageBuilds[$pkg] = $builds
        } catch {
            & $Global:Log -Message "Failed to reach index for $pkg." -Level "ERROR"
            return $null
        }
    }

    # Intersection Logic: Find dates where ALL 4 exist
    $commonDates = $packageBuilds["rocm"].Date | Select-Object -Unique
    foreach ($pkg in $packages) {
        $pkgDates = $packageBuilds[$pkg].Date | Select-Object -Unique
        $commonDates = $commonDates | Where-Object { $pkgDates -contains $_ }
    }

    if ($null -eq $commonDates -or $commonDates.Count -eq 0) {
        & $Global:Log -Message "No synchronized nightly bundle (all 4 wheels) found on server." -Level "WARN"
        return $null
    }

    $latestCommonDate = ($commonDates | Sort-Object -Descending)[0]
    & $Global:Log -Message "Found synchronized bundle for date: $latestCommonDate" -Level "DEBUG" -Color Green
    
    $finalPackages = @{}
    foreach ($pkg in $packages) {
        $match = $packageBuilds[$pkg] | Where-Object { $_.Date -eq $latestCommonDate } | Select-Object -First 1
        $version = "Unknown"
        if ($match.FileName -match "^$($pkg)-([\d\.\w\+]+)-cp312") { $version = $Matches[1] }
        
        $finalPackages[$pkg] = @{
            Url      = "$baseUrlBase/$pkg/$($match.RawHref)"
            FileName = $match.FileName
            Version  = $version
        }
    }

    return @{ Packages = $finalPackages; Version = "Nightly-a$latestCommonDate" }
}

Function Sync-TorchArchives {
    Param([hashtable]$BuildInfo)
    $cacheDir = Join-Path $PSScriptRoot "..\.cache"
    $versionFile = Join-Path $cacheDir "torch-version.txt"
    $success = $true

    # Process in priority order
    $packages = @("rocm", "torch", "torchvision", "torchaudio")
    foreach ($pkg in $packages) {
        $item = $BuildInfo.Packages[$pkg]
        $targetPath = Join-Path $cacheDir $item.FileName

        if (Test-Path $targetPath) { continue }

        & $Global:Log -Message "Downloading latest $pkg wheel..." -Level "INFO"
        Get-ChildItem $cacheDir -Filter "$pkg-*.whl" | Remove-Item -Force
        & curl.exe --fail -L -# -o "$targetPath" "$($item.Url)"
        
        if ($LASTEXITCODE -ne 0) { $success = $false; break }
    }

    if ($success) {
        # Log in priority order: ROCM first
        $logContent = @(
            "ROCM: $($BuildInfo.Packages['rocm'].Version)",
            "TORCH: $($BuildInfo.Packages['torch'].Version)",
            "TORCHVISION: $($BuildInfo.Packages['torchvision'].Version)",
            "TORCHAUDIO: $($BuildInfo.Packages['torchaudio'].Version)"
        )
        $logContent | Out-File $versionFile -Force
        return $true
    }
    return $false
}

Export-ModuleMember -Function Get-InstalledTorchVersions, Get-LatestTorchBuilds, Sync-TorchArchives