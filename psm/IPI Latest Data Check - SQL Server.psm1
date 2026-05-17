function ConvertFrom-SecureStringPlain {
    param ([securestring]$SecureString)

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Start-SQL($params) {
    $Svr                    = $params.Svr
    $Table                  = $params.Table
    $Database               = $params.Database
    $SQLPath                = $params.SQLPath
    $SQLQueries             = $params.SQLQueries
    $User                   = $params.User
    [securestring]$Password = $params.Password
    $LogCallback            = $params.LogCallback
    
    $res    = ""
    $sql    = ""
    $sqlScript = ""

    try {
        $sqlScript = $SQLQueries[$Table]
    }
    catch {
        & $LogCallback "Server`t: $Svr `nTable`t: $Table `nError`t: The Queries object does not have an item matching $Table. Please update the GUI script." "DarkRed" -Bold:$true
        return
    }

    if ("$sqlScript" -ne "") {
        try {
            $sql = Get-Content -Path ($SQLPath + $sqlScript) -ErrorAction Stop
        }
        catch {
            & $LogCallback "Server`t: $Svr `nTable`t: $Table `nError`t: $($_.Exception.Message)" "DarkRed" -Bold:$true
            return
        }
    }

    if (-not ($Svr -match "LocalDB") -and ("$User" -eq "" -or "$(ConvertFrom-SecureStringPlain $Password)" -eq "")) {
        & $LogCallback "Server`t: $Svr `nTable`t: $Table `nError`t: User Name or Password not entered!" "DarkRed" -Bold:$true
    }

    if("$User" -ne "" -and -not ($Svr -match "LocalDB")) {
        $conn = New-Object System.Data.SqlClient.SqlConnection "Server=$Svr;Database=$Database;Trusted_Connection=yes;Integrated Security=False;User ID=$User;Password=$(ConvertFrom-SecureStringPlain $Password);"
    } else {
        $conn = New-Object System.Data.SqlClient.SqlConnection "Server=$Svr;Database=$Database;Trusted_Connection=yes;"
    }

    try {
        $conn.Open()
    }
    catch {
        & $LogCallback "Server`t`t: $Svr `nDatabase`t: $Database `nUser`t`t: $User `nError`t`t: $($_.Exception.Message)" "DarkRed" -Bold:$true
    }

    $cmd = $conn.CreateCommand()
    $cmd.CommandTimeout = 180
    $dt = New-Object System.Data.DataTable

    if ("$sql" -ne "" -and $conn.State -eq 1) {
        $cmd.CommandText = $sql
        $rdr = $cmd.ExecuteReader()
        $dt.Load($rdr)
        try {
            $res = $dt.Rows[0][0]
            & $LogCallback "Server`t: $Svr `nTable`t: $Table `nResult`t: $($res.ToString("dd/MM/yyyy"))" "DarkGreen" -Italic:$true
        }
        catch {
            & $LogCallback "Server`t: $Svr `nTable`t: $Table `nError`t: $($_.Exception.Message)" "DarkRed" -Bold:$true
        }
    }
    $conn.Close()
    $conn.Dispose()

    return $res
}