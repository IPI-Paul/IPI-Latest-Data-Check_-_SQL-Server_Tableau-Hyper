function Get-LiteralPath {
    param ([string]$path)

    (Get-Item -LiteralPath "$PSScriptRoot\$path")
}


function Get-ScriptPaths {

    [PSCustomObject]@{
        HyperAPI        = (Get-LiteralPath "..\cs\IPI Hyper API Wrapper.cs")
        IconHelper      = (Get-LiteralPath "..\cs\IPI Windows Icon Helper.cs")
        SqlServer       = (Get-LiteralPath "..\psm\IPI Latest Data Check - SQL Server.psm1")
        TableauHyper    = (Get-LiteralPath "..\psm\IPI Latest Data Check - Tableau Hyper.psm1")
        IconPicker      = (Get-LiteralPath "..\psm\IPI Windows Icon Picker - Icons.psm1")
        MainWindow      = (Get-LiteralPath "..\xaml\IPI Latest Data Check.xaml")
    }
}

Export-ModuleMember -Function Get-ScriptPaths