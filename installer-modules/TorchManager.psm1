Function Get-InstalledTorchVersions {
    $cacheDir = Join-Path $PSScriptRoot "..\.cache"
    $versionFile = Join-Path $cacheDir "torch-version.txt"
    
    # Initialize a fixed hashtable
    $results = @{
        torch       = "None"
        torchvision = "None"
        torchaudio  = "None"
    }

    if (-not (Test-Path $versionFile)) { return $results }

    $whlFiles = Get-ChildItem $cacheDir -Filter "*.whl" -ErrorAction SilentlyContinue
    
    # FIX: Loop through a static list of keys, NOT the hashtable itself
    $packageNames = @("torch", "torchvision", "torchaudio")
    
    foreach ($pkg in $packageNames) {
        # Regex refined: Captures everything between the package name and the -cp312 marker
        # Example: torch-2.12.0a0+rocm7.13.0a20260324-cp312... 
        # Captures: 2.12.0a0+rocm7.13.0a20260324
        $match = $whlFiles | Where-Object { $_.Name -match "^$($pkg)-([\d\.\w\+]+)-cp312" }
        if ($match) {
            $results[$pkg] = $Matches[1]
        }
    }

    return $results
}

Function Get-LatestTorchBuilds {
    Param([string]$Arch)
    
    $packages = @("torch", "torchvision", "torchaudio")
    $results = @{}
    $globalDate = "00000000"

    foreach ($pkg in $packages) {
        $baseUrl = "https://rocm.nightlies.amd.com/v2-staging/$Arch-dgpu/$pkg"
        & $Global:Log -Message "Querying ${pkg} index: $baseUrl" -Level "DEBUG"

        try {
            $response = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing -TimeoutSec 20
            $content = $response.Content

            # Match the href exactly as it appears (including the ../)
            $pattern = 'href="([^"]*' + $pkg + '[^"]*?a(\d{8})[^"]*?cp312[^"]*?win_amd64\.whl)"'
            $matches = [regex]::Matches($content, $pattern)

            if ($matches.Count -eq 0) {
                & $Global:Log -Message "No cp312 matches found for ${pkg}." -Level "DEBUG" -Color Yellow
                continue
            }

            $latestFile = $matches | ForEach-Object { 
                $rawHref = $_.Groups[1].Value
                
                # SANITIZATION:
                # Local filename: Strip dots/slashes and decode %2B
                $localName = ($rawHref -replace '^\.*\/+', '') -replace '%2B', '+'

                [PSCustomObject]@{
                    RawHref   = $rawHref # KEEP the ../ for the URL construction
                    FileName  = $localName
                    Date      = $_.Groups[2].Value
                }
            } | Sort-Object Date -Descending | Select-Object -First 1

            if ($latestFile) {
                $results[$pkg] = @{
                    # Construct URL by appending the RAW href (preserving ../) to the base
                    Url      = "$($baseUrl.TrimEnd('/'))/$($latestFile.RawHref)"
                    FileName = $latestFile.FileName
                    Date     = $latestFile.Date
                }
                
                if ([int]$latestFile.Date -gt [int]$globalDate) { $globalDate = $latestFile.Date }
                & $Global:Log -Message "Matched ${pkg}: $($latestFile.FileName)" -Level "DEBUG" -Color Green
            }
        } catch {
            & $Global:Log -Message "Failed to reach ${pkg} index." -Level "ERROR" -Color Red
        }
    }

    if ($results.Count -eq 3) {
        return @{ Packages = $results; Version = "Nightly-a$globalDate" }
    } else {
        $missing = @("torch", "torchvision", "torchaudio") | Where-Object { -not $results.ContainsKey($_) }
        Write-Host "[ERROR] Could not find all required WHL files. Missing: $($missing -join ', ')" -ForegroundColor Red
        return $null
    }
}

Function Sync-TorchArchives {
    Param([hashtable]$BuildInfo)
    $cacheDir = Join-Path $PSScriptRoot "..\.cache"
    if (-not (Test-Path $cacheDir)) { $null = New-Item -ItemType Directory $cacheDir -Force }
    
    $versionFile = Join-Path $cacheDir "torch-version.txt"
    $success = $true

    foreach ($pkg in $BuildInfo.Packages.Keys) {
        $item = $BuildInfo.Packages[$pkg]
        $targetPath = Join-Path $cacheDir $item.FileName

        if (Test-Path $targetPath) {
            & $Global:Log -Message "$pkg archive already cached." -Level "INFO" -Color Cyan
            continue
        }

        # Purge only mismatched versions of this specific package
        Get-ChildItem $cacheDir -Filter "$pkg-*.whl" | Remove-Item -Force

        Write-Host "[!] Downloading $pkg (curl.exe)..." -ForegroundColor Cyan
        & $Global:Log -Message "Source: $($item.Url)" -Level "DEBUG"
        
        # Execute curl.exe
        & curl.exe --fail -L -# -o "$targetPath" "$($item.Url)"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Failed to download $pkg via curl (Exit: $LASTEXITCODE)." -ForegroundColor Red
            if (Test-Path $targetPath) { Remove-Item $targetPath -Force }
            $success = $false
            break # Halt all downloads if one fails
        }
    }

    if ($success) {
        $BuildInfo.Version | Out-File $versionFile -Force
        return $true
    }
    
    return $false
}

Export-ModuleMember -Function Get-InstalledTorchVersions, Get-LatestTorchBuilds, Sync-TorchArchives