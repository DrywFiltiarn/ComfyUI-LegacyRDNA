Function Get-InstalledTorchVersions {
    $cacheDir = Join-Path $PSScriptRoot "..\.cache"
    $versionFile = Join-Path $cacheDir "torch-version.txt"
    
    $ArchSuffix = $Global:Env_GfxArch.ToLower()
    $LibPkg = "rocm-sdk-libraries-$ArchSuffix-dgpu"
    
    # Define packages to look for
    $packageNames = @("rocm-sdk-core", $LibPkg, "rocm", "torch", "torchvision", "torchaudio")
    
    $results = @{ Success = $false; Versions = @{} }
    foreach ($pkg in $packageNames) { $results.Versions[$pkg] = "None" }

    if (-not (Test-Path $versionFile)) { return $results }

    # Read the manifest directly
    $lines = Get-Content $versionFile
    $missingAny = $false

    foreach ($pkg in $packageNames) {
        # Match the line format "PACKAGE: filename" created by Sync-TorchArchives
        $line = $lines | Where-Object { $_ -match "^$($pkg.ToUpper()):\s+(.*)" }
        if ($line) {
            $fileName = $Matches[1]
            # Extract the date-based version (e.g., 7.13.0a20260326)
            if ($fileName -match "(\d+\.\d+\.\d+a\d{8})") {
                $results.Versions[$pkg] = $Matches[1]
            }
        }
        
        if ($results.Versions[$pkg] -eq "None") { $missingAny = $true }
    }

    $results.Success = -not $missingAny
    return $results
}

Function Get-LatestTorchBuilds {
    $Arch = $Global:Env_GfxArch
    $ArchSuffix = $Arch.ToLower()
    $LibPkg = "rocm-sdk-libraries-$ArchSuffix-dgpu"
    
    $packages = @(
        "rocm-sdk-core", 
        $LibPkg, 
        "rocm", 
        "torch", 
        "torchvision", 
        "torchaudio"
    )
    
    $packageBuilds = @{} 
    $baseUrlBase = "https://rocm.nightlies.amd.com/v2-staging/$Arch-dgpu"

    foreach ($pkg in $packages) {
        $url = "$baseUrlBase/$pkg/"
        & $Global:Log -Message "Querying ${pkg} index: $url" -Level "DEBUG"
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20
            
            $pattern = 'href="([^"]*?(\d+\.\d+\.\d+a\d{8})[^"]*?\.(whl|tar\.gz))"'
            $matches = [regex]::Matches($resp.Content, $pattern)
            
            $builds = $matches | ForEach-Object {
                $fName = ($_.Groups[1].Value -replace '^\.*\/+', '') -replace '%2B', '+'
                $fullVer = $_.Groups[2].Value
                
                if ($pkg -eq "rocm") {
                    if ($fName -notmatch "\.tar\.gz$") { return }
                } else {
                    if ($fName -notmatch "win_amd64") { return }
                    if ($pkg -match "torch" -and $fName -notmatch "cp312") { return }
                    if ($pkg -eq "torchvision" -and $fName -notmatch "torchvision-0\.25\.") { return }
                }

                [PSCustomObject]@{
                    Version  = $fullVer
                    RawHref  = $_.Groups[1].Value
                    FileName = $fName
                }
            }
            
            $packageBuilds[$pkg] = $builds
        } catch {
            & $Global:Log -Message "Failed to reach index for $pkg." -Level "ERROR"
            return $null
        }
    }

    # Intersection: Find common versions across all 6 repos
    $commonVersions = $packageBuilds["rocm-sdk-core"].Version | Select-Object -Unique
    foreach ($pkg in $packages) {
        $pkgVersions = $packageBuilds[$pkg].Version | Select-Object -Unique
        $commonVersions = $commonVersions | Where-Object { $_ -in $pkgVersions }
    }

    if ($null -eq $commonVersions -or $commonVersions.Count -eq 0) {
        & $Global:Log -Message "No synchronized win_amd64 bundle found for $Arch." -Level "WARN"
        return $null
    }

    $latestVersion = ($commonVersions | Sort-Object -Descending)[0]
    $finalPackages = @{}
    foreach ($pkg in $packages) {
        $match = $packageBuilds[$pkg] | Where-Object { $_.Version -eq $latestVersion } | Select-Object -First 1
        $finalPackages[$pkg] = @{
            Url      = "$baseUrlBase/$pkg/$($match.RawHref)"
            FileName = $match.FileName
            Version  = $latestVersion
        }
    }

    return @{ Packages = $finalPackages; Version = $latestVersion }
}

Function Sync-TorchArchives {
    Param([hashtable]$BuildInfo)
    $cacheDir = Join-Path $PSScriptRoot "..\.cache"
    $versionFile = Join-Path $cacheDir "torch-version.txt"
    
    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir | Out-Null }

    # Keys are derived from the matched BuildInfo
    $packages = $BuildInfo.Packages.Keys
    $success = $true

    foreach ($pkg in $packages) {
        $item = $BuildInfo.Packages[$pkg]
        $targetPath = Join-Path $cacheDir $item.FileName

        if (Test-Path $targetPath) { continue }

        & $Global:Log -Message "Syncing: $($item.FileName)" -Level "INFO"
        
        # IMPROVED SURGICAL CLEANUP:
        # 1. Escapes the package name for regex and handles dash/underscore flexibility.
        # 2. Anchors to the start of the string (^) so 'rocm' doesn't match 'torch-...+rocm'.
        # 3. Ensures the package name is followed by a separator and a digit (the version start).
        $escapedPkg = [regex]::Escape($pkg) -replace '-', '[-_]'
        $cleanupRegex = "^$($escapedPkg)[-_](?=\d)"

        Get-ChildItem $cacheDir | Where-Object { 
            $_.Name -match $cleanupRegex -and 
            $_.Name -match "\.(whl|tar\.gz)$" -and 
            $_.Name -ne $item.FileName 
        } | Remove-Item -Force -ErrorAction SilentlyContinue
        
        & curl.exe --fail -L -# -o "$targetPath" "$($item.Url)"
        if ($LASTEXITCODE -ne 0) { $success = $false; break }
    }

    if ($success) {
        $manifest = foreach ($pkg in $packages) { 
            "$($pkg.ToUpper()): $($BuildInfo.Packages[$pkg].FileName)" 
        }
        $manifest | Out-File $versionFile -Force
        return $true
    }
    return $false
}

Export-ModuleMember -Function Get-InstalledTorchVersions, Get-LatestTorchBuilds, Sync-TorchArchives