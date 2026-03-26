Function Get-ElevationStatus {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Function Get-OSStatus {
    $os = Get-CimInstance Win32_OperatingSystem
    $version = [version]$os.Version
    if ($version.Major -eq 10) {
        return @{ Success = $true; Name = $os.Caption }
    } else {
        return @{ Success = $false; Name = $os.Caption }
    }
}

Function Get-GitStatus {
    try {
        $gitVerRaw = & git --version 2>&1
        if ($gitVerRaw -match "git version ([\d\.]+)") {
            return @{ Success = $true; Version = $matches[1] }
        }
    } catch {
        return @{ Success = $false; Error = "Missing" }
    }
    return @{ Success = $false; Error = "Missing" }
}

Function Get-PythonStatus {
    try {
        $pyVerRaw = & python --version 2>&1
        if ($pyVerRaw -match "Python (3\.12\.\d+)") {
            return @{ Success = $true; Version = $matches[1] }
        } elseif ($pyVerRaw -match "Python (\d+\.\d+\.\d+)") {
            return @{ Success = $false; Version = $matches[1]; Error = "WrongVersion" }
        }
    } catch {
        return @{ Success = $false; Error = "Missing" }
    }
    return @{ Success = $false; Error = "Missing" }
}

Function Get-AMDGPUStatus {
    $gpus = Get-CimInstance Win32_VideoController
    $detected = $null
    
    foreach ($gpu in $gpus) {
        $name = $gpu.Name
        if ($name -match "RX (5700|5600|5500|5300)") {
            $detected = @{ Arch = "gfx101X"; Series = "RDNA1"; Name = $name; Support = "Legacy" }
            break
        }
        elseif ($name -match "RX (6950|6900|6800|6750|6700|6650|6600|6500|6400)") {
            $detected = @{ Arch = "gfx103X"; Series = "RDNA2"; Name = $name; Support = "Legacy" }
            break
        }
        elseif ($name -match "RX (7\d00|8\d00|9\d00)") {
            return @{ Support = "Official"; Series = "RDNA3/4"; Name = $name }
        }
        elseif ($name -match "(Vega|Polaris|RX (4|5)\d0|R9|R7)") {
            return @{ Support = "Unsupported"; Series = "Pre-RDNA"; Name = $name }
        }
    }

    if ($null -eq $detected) {
        return @{ Support = "None" }
    }
    return $detected
}

Function Get-VRAMSize {
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
        $adapters = Get-ChildItem $regPath -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match "^\d{4}$" }
        
        foreach ($adp in $adapters) {
            $prop = Get-ItemProperty $adp.PSPath -ErrorAction SilentlyContinue
            if ($prop.DriverDesc -match "AMD Radeon") {
                if ($prop."HardwareInformation.qwMemorySize") {
                    $totalBytes = [uint64]$prop."HardwareInformation.qwMemorySize"
                    $gb = [math]::Round($totalBytes / 1GB, 0)
                    return "$($gb) GB"
                }
            }
        }

        $gpu = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match "AMD Radeon" } | Select-Object -First 1
        if ($gpu) {
            $rawRAM = $gpu.AdapterRAM
            $bytes = if ($rawRAM -lt 0) { [uint32]$rawRAM } else { [uint64]$rawRAM }
            $gb = [math]::Round($bytes / 1GB, 0)
            return "$($gb) GB"
        }
    } catch {
        return "Unknown"
    }
    return "Unknown"
}

Export-ModuleMember -Function Get-ElevationStatus, Get-OSStatus, Get-GitStatus, Get-PythonStatus, Get-AMDGPUStatus, Get-VRAMSize