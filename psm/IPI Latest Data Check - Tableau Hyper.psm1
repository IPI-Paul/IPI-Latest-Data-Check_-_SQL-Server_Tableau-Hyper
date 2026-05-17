function Show-Object {
    param (
        [object]$Object,
        [int]$Indent = 0,
        [scriptblock]$LogCallback
    )

    $pad = ' ' * $Indent

    if ($Object -is [System.Collections.IEnumerable] -and -not ($Object -is [string])) {
        foreach ($item in $Object) {
            Show-Object $item $Indent $LogCallback
        }
        return
    }

    if ($Object -is [psobject]) {
        foreach ($prop in $Object.PSObject.Properties) {
            if ($prop.Value -is [psobject] -or ($prop.Value -is [System.Collections.IEnumerable] -and -not ($prop.Value -is [string]))) {
                & $LogCallback "$pad$($prop.Name):" "Green" -Bold:$true
                Show-Object $prop.Value ($Indent + 2) $LogCallback
            } else {
                if ($prop.Name -match "Column") {
                    & $LogCallback "$pad$($prop.Name): $($prop.Value)" "DarkGreen" -Italic:$true
                } elseif ($prop.Name -match "Table") {
                    & $LogCallback "$pad$($prop.Name): $($prop.Value)" "Brown" -Italic:$true
                } else {
                    & $LogCallback "$pad$($prop.Name): $($prop.Value)" "DarkSeaGreen" -Italic:$true
                }
            }
        }
    }
}

function Start-Hyper($params) {
    $HyperDllPath       = $params.HyperDllPath
    $HyperFile          = $params.HyperFile
    $Hyper              = $params.Hyper
    $HyperPath          = $params.HyperPath
    $HyperQueries       = $params.HyperQueries
    $LogCallback        = $params.LogCallback
    $ToDate             = $params.ToDate
    $RunType            = $params.RunType
    
    $hyperDate  = $null
    $sql        = ""
    $sqlScript     = ""

    if ($RunType -ne 3) {
        try {
            $sqlScript = $HyperQueries[$Hyper]
        }
        catch {
            & $LogCallback "Hyper`t: $Hyper `nError`t: The Queries object does not have an item matching $Hyper. Please update the GUI script." "DarkRed" -Bold:$true
            return
        }

        # SQL to get the max date
        if ("$sqlScript" -ne "") {
            try {
                $sql = Get-Content -Path ($HyperPath + $sqlScript) -ErrorAction Stop
            }
            catch {
                & $LogCallback "Hyper`t: $Hyper `nError`t: $($_.Exception.Message)" "DarkRed" -Bold:$true
                return
            }
        }
    }

    try {
        # Load Hyper API
        $dllPath = ($HyperDllPath -replace "\\", "\\")

        # Prevent multiple Add-Type calls
        if (-not ('HyperAPIWrapper' -as [type])) {        
            # Define the function using Add-Type
            Add-Type -TypeDefinition ((Get-Content $Config.HyperAPI -Raw) -replace '\$dllPath', $dllPath) -PassThru | Out-Null
        }

        # Call the DLL function and get pointer 
        $ptr = [HyperAPIWrapper]::read_hyper_file($HyperFile, $sql, $RunType)

        # Get the result string
        $result = [Runtime.InteropServices.Marshal]::PtrToStringAnsi($ptr)

        # Free unmanaged memory
        [HyperAPIWrapper]::FreeResult($ptr)

        if ($RunType -eq 1) {
            $obj = $result | ConvertFrom-Json 
            Show-Object $obj -Logcallback $LogCallback
        } elseif ($RunType -eq 2) {
            # Convert result to date and if Month Start change to Month End
            $hyperDate = (& $ToDate $result)
            if ($hyperDate.Day -eq 1) {
                $hyperDate = $hyperDate.AddMonths(1).AddDays(-1)
            }

            # Output
            & $LogCallback "Hyper`t: $Hyper `nResult`t: $($hyperDate.ToString('dd/MM/yyyy'))" "Green" -Italic:$true
            return $hyperDate
        } else {
            # Output
            & $LogCallback $result "Green" -Italic:$true
            return $result
        }
    }
    catch {
        & $LogCallback "Hyper`t: $Hyper `nError`t: $($_.Exception.Message)" "DarkRed" -Bold:$true
    }
}