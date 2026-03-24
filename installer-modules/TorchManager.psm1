Function Get-InstalledTorchVersions {
    $cacheDir = Join-Path $PSScriptRoot "..\.cache"
    $versionFile = Join-Path $cacheDir "torch-version.txt"
    $results = @{ torch = "None"; torchvision = "None"; torchaudio = "None" }

    if (-not (Test-Path $versionFile)) { return $results }

    $whlFiles = Get-ChildItem $cacheDir -Filter "*.whl" -ErrorAction SilentlyContinue
    $packageNames = @("torch", "torchvision", "torchaudio")
    
    foreach ($pkg in $packageNames) {
        # Iterate and match to ensure $Matches is captured correctly in the loop scope (PS 5.1)
        foreach ($file in $whlFiles) {
            if ($file.Name -match "^$($pkg)-([\d\.\w\+]+)-cp312") {
                $results[$pkg] = $Matches[1]
                break
            }
        }
    }
    return $results
}

Function Get-LatestTorchBuilds {
    Param([string]$Arch)
    
    $packages = @("torch", "torchvision", "torchaudio", "rocm")
    $results = @{}
    $globalDate = "00000000"

    foreach ($pkg in $packages) {
        $baseUrl = "https://rocm.nightlies.amd.com/v2-staging/$Arch-dgpu/$pkg"
        & $Global:Log -Message "Querying ${pkg} index: $baseUrl" -Level "DEBUG"

        try {
            $response = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing -TimeoutSec 20
            $content = $response.Content
            $pattern = 'href="([^"]*' + $pkg + '[^"]*?a(\d{8})[^"]*?cp312[^"]*?win_amd64\.whl)"'
            $matches = [regex]::Matches($content, $pattern)

            if ($matches.Count -eq 0) { continue }

            $latestFile = $matches | ForEach-Object { 
                $rawHref = $_.Groups[1].Value
                $localName = ($rawHref -replace '^\.*\/+', '') -replace '%2B', '+'

                # NEW: Extract specific version string (e.g., 2.12.0a0+rocm7.13)
                $versionStr = "Unknown"
                if ($localName -match "^$($pkg)-([\d\.\w\+]+)-cp312") {
                    $versionStr = $Matches[1]
                }

                [PSCustomObject]@{
                    RawHref  = $rawHref
                    FileName = $localName
                    Date     = $_.Groups[2].Value
                    Version  = $versionStr
                }
            } | Sort-Object Date -Descending | Select-Object -First 1

            if ($latestFile) {
                $results[$pkg] = @{
                    Url      = "$($baseUrl.TrimEnd('/'))/$($latestFile.RawHref)"
                    FileName = $latestFile.FileName
                    Version  = $latestFile.Version
                }
                if ([int]$latestFile.Date -gt [int]$globalDate) { $globalDate = $latestFile.Date }
            }
        } catch {
            & $Global:Log -Message "Failed to reach ${pkg} index." -Level "ERROR"
        }
    }

    if ($results.Count -eq 3) {
        return @{ Packages = $results; Version = "Nightly-a$globalDate" }
    }
    return $null
}

Function Sync-TorchArchives {
    Param([hashtable]$BuildInfo)
    $cacheDir = Join-Path $PSScriptRoot "..\.cache"
    $versionFile = Join-Path $cacheDir "torch-version.txt"
    $success = $true

    foreach ($pkg in $BuildInfo.Packages.Keys) {
        $item = $BuildInfo.Packages[$pkg]
        $targetPath = Join-Path $cacheDir $item.FileName

        if (Test-Path $targetPath) { continue }

        Get-ChildItem $cacheDir -Filter "$pkg-*.whl" | Remove-Item -Force
        & curl.exe --fail -L -# -o "$targetPath" "$($item.Url)"
        
        if ($LASTEXITCODE -ne 0) { $success = $false; break }
    }

    if ($success) {
        # NEW: Log in specific order with explicit version strings
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