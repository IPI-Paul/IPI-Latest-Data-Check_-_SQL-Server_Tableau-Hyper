param($hyperFile)

function Get-ScriptPath {
    # Get the full path to the currently running script
    if ($PSCommandPath) {
        $ScriptPath = $PSCommandPath
    } elseif ($MyInvocation.MyCommand.Path) {
        $ScriptPath = $MyInvocation.MyCommand.Path
    } else {
        throw "Unable to determine script path (script may not be running interactively)."
    }

    # Derived values (optional but commonly useful)
    $ScriptDirectory    = Split-Path -Parent $ScriptPath
    $ScriptName         = Split-Path -Leaf $ScriptPath

    # Output results
    [PSCustomObject]@{
        ScriptPath      = $ScriptPath
        ScriptDirectory = $ScriptDirectory
        ScriptBaseName  = (Split-Path -Parent $ScriptDirectory)
        ScriptName      = $ScriptName
    }
}

$PathVars = (Get-ScriptPath)

# Ensure relative paths work
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

Import-Module "$ScriptRoot\config\Config.psm1" -Force
$Config = Get-ScriptPaths

Import-Module $Config.IconPicker -Force

# Parameters
$Servers = @{
    LocalDB='(LocalDB)\MSSQLLocalDB'
    Development='10.0.0.1'
    Production='10.0.0.2'
}
$Database = 'tempdb'

$SQLPath    = "$($PathVars.ScriptDirectory)\SQL Scripts\SQL\"
$HyperPath  = "$($PathVars.ScriptDirectory)\SQL Scripts\Hyper\"
$SQLQueries = @{}
$HyperQueries = @{}
$Functions = @{
    ""                  = 0
    "Get Hyper Schema"  = 1
    "Run SQL Queries"   = 2
    "Author Repository" = 3
    "Clear Log"         = 4
}

# Get all .sql files
(Get-ChildItem -Path $SQLPath -Filter *.sql) | ForEach-Object {
    $FullName = (Split-Path -Leaf $_.Name)
    $Name = ($FullName -replace ".sql", "")
    $SQLQueries.Add($Name, $FullName)
}

(Get-ChildItem -Path $HyperPath -Filter *.sql) | ForEach-Object {
    $FullName = (Split-Path -Leaf $_.Name)
    $Name = ($FullName -replace ".sql", "")
    $HyperQueries.Add($Name, $FullName)
}


Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore 
Add-Type -AssemblyName WindowsBase

# XAML UI
[xml]$Xaml = (Get-Content $Config.MainWindow -Raw)

# Load XAML
$Reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [Windows.Markup.XamlReader]::Load($Reader)

$cboSvr             = $Window.FindName("cboSvr")
$cboTable           = $Window.FindName("cboTable")
$txtUser            = $Window.FindName("txtUser")
$txtPwd             = $Window.FindName("txtPwd")
$FilePathBox        = $Window.FindName("FilePathBox")
$BrowseButton       = $Window.FindName("BrowseButton")
$cboHyper           = $Window.FindName("cboHyper")
$RunFunctions       = $Window.FindName("RunFunctions")
$LogBox             = $Window.FindName("LogBox")
$StatusLabel        = $Window.FindName("StatusLabel")

$Servers.GetEnumerator() | Sort-Object -Property key | Select-Object -Property key | ForEach-Object {
    $cboSvr.Items.Add(($_.Key)) | Out-Null
}

$SQLQueries.GetEnumerator() | Sort-Object -Property name | Select-Object -Property name | ForEach-Object {
    $cboTable.Items.Add(($_.Name)) | Out-Null
}

$HyperQueries.GetEnumerator() | Sort-Object -Property name | Select-Object -Property name | ForEach-Object {
    $cboHyper.Items.Add(($_.Name)) | Out-Null
}

$Functions.GetEnumerator() | Sort-Object -Property value | Select-Object -Property key | ForEach-Object {
    $RunFunctions.Items.Add(($_.Key)) | Out-Null
}

$txtUser.Text = ($Env:USERNAME).ToLower()
$txtPwd.PasswordChar = "*"

$cboSvr.SelectedIndex = 2
$cboTable.SelectedIndex = 0
$cboHyper.SelectedIndex = 0
$FilePathBox.Text = $hyperFile
$LogBox.Document.Blocks.Clear()
# $LogBox.Cursor = [System.Windows.Input.Cursors]::Arrow

$LogBox.Add_PreviewMouseLeftButtonDown({
    param ($s, $e)

    $pointer = $LogBox.GetPositionFromPoint($e.GetPosition($LogBox), $true)
    if (-not $pointer) { return }

    # Get the inline element at the click
    $inline = $pointer.Parent
    while ($inline -and -not ($inline -is [System.Windows.Documents.Hyperlink])) {
        $inline = $inline.Parent
    }

    if ($inline -and $inline -is [System.Windows.Documents.Hyperlink]) {
        # Open the URI
        Start-Process $inline.NavigateUri.AbsoluteUri
        $e.Handled = $true
    }
})

# Convert String to date
function Convert-ToDate {
    param (
        [Parameter(Mandatory)]
        [string]$DateString
    )

    switch -regex ($DateString) {
        '^\d{4}-\d{2}-\d{2}$' {
            [datetime]::ParseExact($DateString, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)
        }
        '^\d{2}/\d{2}/\d{4}$' {
            [datetime]::ParseExact($DateString, 'dd/MM/yyyy', [cultureinfo]::InvariantCulture)
        }
        '^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}$' {
            [datetime]::ParseExact($DateString, 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture)
        }
        '^\d{2}/\d{2}/\d{4}\s+\d{2}:\d{2}:\d{2}$' {
            [datetime]::ParseExact($DateString, 'dd/MM/yyyy HH:mm:ss', [cultureinfo]::InvariantCulture)
        }
        default {
            throw "Unsupported date format: $DateString"
        }
    }
}

# Logging Timer
function Get-Duration {
    param (
        $startTime
    )
    $endTime = Get-Date
    $duration = $endTime - $startTime
    return "{0:00}:{1:00}:{2:00}" -f $duration.Hours, $duration.Minutes, $duration.Seconds
}

function Get-MyRunspace {
    param (
        [int]$RunType
    )
    # Path to the Tableau Hyper API .Net DLL
    $HyperDllPath = "$($PathVars.ScriptDirectory)\API\get_hyper_file_data.dll"
    [System.Environment]::CurrentdIRECTORY = (Split-Path $HyperDllPath)

    if (-not [string]::IsNullOrWhiteSpace($FilePathBox.Text)) {
        if (-not (Test-Path $FilePathBox.Text)) {
            Write-Log -Text "Error: Please select a valid file." -Color "DarkRed" -Bold:$true
            Reset-Status
            return ""
        }
    }

    $StatusLabel.Content = "Status: Running..."

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $pathEntry = New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList "PATH", "$(Split-Path $HyperDllPath);$($env:PATH)", "Updated PATH"
    $iss.EnvironmentVariables.Add($pathEntry)

    # Explicitly add the variable so that the module can see it upon import
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList "Config", $Config, "Global variable for module"))

    $iss.ImportPSModule(@(
        $Config.SqlServer
        $Config.TableauHyper
    ))

    $Runspace = [runspacefactory]::CreateRunspace($iss)
    $Runspace.ApartmentState = "STA"
    $Runspace.ThreadOptions = "ReuseThread"
    $Runspace.Open()

    $PowerShell = [powershell]::Create()
    $PowerShell.Runspace = $Runspace

    $params = [PSCustomObject]@{
        Svr             = $Servers[$cboSvr.Text]
        Table           = $cboTable.Text
        Database        = $Database
        SQLPath         = $SQLPath
        SQLQueries      = $SQLQueries
        User            = $txtUser.Text
        Password        = $txtPwd.SecurePassword
        HyperFile       = $FilePathBox.Text
        Hyper           = $cboHyper.Text
        HyperDllPath    = $HyperDllPath
        HyperPath       = $HyperPath
        HyperQueries    = $HyperQueries
        LogCallback     = $null
        ToDate          = $null
        RunType         = $RunType
        PowerShell      = $PowerShell
    }
    
    return $params
}
function Reset-Status {
    $StatusLabel.Content = "Status: Idle"
}

# Logging Helper
function Write-Log {
    param (
        [string]$Text,
        [string]$Color = "Black",
        [switch]$Bold,
        [switch]$Italic
    )

    $Window.Dispatcher.Invoke([action]{
        $Paragraph = New-Object System.Windows.Documents.Paragraph
        $Paragraph.Margin = "0"     # Removes extra spacing
        $Paragraph.LineHeight = 12  # Adjust as needed (12-15 works well)

        if ($Text -match "https://") {
            # Create Hyperlink
            $hyperlink = New-Object System.Windows.Documents.Hyperlink
            $hyperlink.NavigateUri = [Uri]$Text
            $hyperlink.Inlines.Add($Text)
            $hyperlink.Cursor = [System.Windows.Input.Cursors]::Hand
            $hyperlink.Foreground = [System.Windows.Media.Brushes]::Blue
            $hyperlink.TextDecorations = [System.Windows.TextDecorations]::Underline

            $Paragraph.Inlines.Add($hyperlink)
        } else {
            $Run = New-Object System.Windows.Documents.Run($Text)
            $Run.Foreground = $Color
            if ($Bold) { $Run.FontWeight = "Bold" }
            if ($Italic) { $Run.FontStyle = "Italic" }

            $Paragraph.Inlines.Add($Run)
        }

        $LogBox.Document.Blocks.Add($Paragraph)
        $LogBox.ScrollToEnd()
    })
}

# Browse for File
$BrowseButton.Add_Click({
    $Dialog = New-Object Microsoft.Win32.OpenFileDialog
    $Dialog.Multiselect = $false

    if ($Dialog.ShowDialog()) {
        $FilePathBox.Text = $Dialog.FileName
    }
})

# Background Runspace
$RunFunctions.Add_SelectionChanged({
    if ($this.SelectedIndex -ne 0) {
        if ($this.SelectedIndex -eq 4) {
            $LogBox.Document.Blocks.Clear()
            Reset-Status
            $this.SelectedIndex = 0
            return
        }
        $RunType = $this.SelectedIndex
        $params = (Get-MyRunspace -RunType $RunType)
        if ("$params" -ne "") {
            $FilePath = $params.HyperFile

            $PowerShell = $params.PowerShell

            $PowerShell.AddScript({
                param ($SelectedIndex, $Path, $LogCallback, $StatusCallback, $params, $GetDuration, $ConvertToDate)
                
                $handler = [System.Windows.Navigation.RequestNavigateEventHandler] {
                    param ($s, $e)
                    Write-Host "Navigated"
                    Start-Process $e.Uri.AbsoluteUri
                    $e.Handled = $true
                }

                $LogBox.AddHandler(
                    [System.Windows.Documents.Hyperlink]::RequestNavigateEvent,
                    $handler   
                )
                $params.LogCallback = $LogCallback
                $params.ToDate      = $ConvertToDate

                $startTime = Get-Date
                if ($SelectedIndex -eq 1) {
                    & $LogCallback "Sarted processing Hyper file:" "DarkBlue" -Bold:$true
                    & $LogCallback "$Path" "Blue" -Italic:$true
                    
                    (Start-Hyper $params) | Out-Null
                    $durationStr = (& $GetDuration $startTime)
                    & $LogCallback "Duration to retrieve data from Hyper file: $durationStr" "Purple" -Bold:$true
                } elseif ($SelectedIndex -eq 2){
                    & $LogCallback "Sarted processing SQL file:" "DarkBlue" -Bold:$true
                    & $LogCallback "$($params.SQLPath)$($params.SQLQueries[$params.Table])" "Blue" -Italic:$true

                    $sqlResult = (Start-SQL $params)

                    if ("$sqlResult" -ne "") {
                        $durationStr = (& $GetDuration $startTime)
                        & $LogCallback "Duration to retrieve data from SQL Server: $durationStr" "Purple" -Bold:$true

                        if ("$($params.HyperFile)" -ne "" -and "$($params.Hyper)" -ne "") {
                            $startTime1 = Get-Date
                            & $LogCallback "Started processing hyper file:" "DarkBlue" -Bold:$true
                            & $LogCallback "$($params.HyperFile)" "Blue" -Italic:$true

                            $hyperResult = (Start-Hyper $params)

                            if ("$hyperResult" -ne "") {
                                $durationStr = (& $GetDuration $startTime1)
                                & $LogCallback "Duration to retrieve data from Hyper file: $durationStr" "Purple" -Bold:$true

                                if ($sqlResult.Date -gt $hyperResult.Date) {
                                    & $LogCallback "The Hyper file $($params.HyperFile) is out of date!" "Red" -Italic:$true
                                } else {
                                    & $LogCallback "The Hyper file $($params.HyperFile) is up to date!" "Green" -Italic:$true
                                }

                                $durationStr = (& $GetDuration $startTime)
                                & $LogCallback "Total Duration to retrieve data from SQL Server and Hyper file: $durationStr" "DarkRed" -Bold:$true
                            }
                        }
                    }
                } elseif ($SelectedIndex -eq 3) {
                    & $LogCallback "Author Repository:" "DarkBlue" -Bold:$true

                    (Start-Hyper $params) | Out-Null
                    $durationStr = (& $GetDuration $startTime)
                    & $LogCallback "Duration to retrieve data from Hyper file: $durationStr" "Purple" -Bold:$true
                }

                & $StatusCallback "Status: Completed"
            }).AddArgument($this.SelectedIndex).AddArgument($FilePath).AddArgument({
                param($msg, $color, $bold, $italic)
                Write-Log -Text $msg -Color $color -Bold:$bold -Italic:$italic
            }).AddArgument({
                param($text)
                $Window.Dispatcher.Invoke([action]{
                    $StatusLabel.Content = $text
                })
            }).AddArgument($params).AddArgument({
                param ($startTime)
                Get-Duration -startTime $startTime
            }).AddArgument({
                param ($result)
                Convert-ToDate -DateString $result
            })

            $PowerShell.Begininvoke()
        }
        $this.SelectedIndex = 0
    }
})

# Set Window icon
$Window.Icon = Get-Shell32Icon 213

# Set Window Top Most
$Window.Topmost = $true

# Show Window
$Window.ShowDialog() | Out-Null