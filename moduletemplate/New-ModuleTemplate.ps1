<#
.SYNOPSIS
    Creates the folder structure and manifest file for a Powershell module.
.DESCRIPTION
    Creates the folder structure and manifest file for a Powershell module.
    The resulting folder structure is depicted below and also described here:  https://benheater.com/creating-a-powershell-module/

    ModuleName
    |___ModuleName.psd1
    |___ModuleName.psm1
    |___Private
    |   |___ps1
    |       |___Verb-Noun.ps1
    |       |___Verb-Noun.ps1
    |
    |___Public
        |___ps1
            |___Verb-Noun.ps1
            |___Verb-Noun.ps1
.EXAMPLE
    Example of how to use this cmdlet
.EXAMPLE
    Another example of how to use this cmdlet
.INPUTS
    Inputs to this cmdlet (if any)
.OUTPUTS
    None
.NOTES
    All credit goes to 0xBEN: https://github.com/0xBEN.
    The following code was taken from their blog post about Powershell modules at https://benheater.com/creating-a-powershell-module/.
    It was modified to 
#>

function New-ModuleTemplate {

    param(
        [string] $Path = $PWD,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
            [string] $ModuleName,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
            [string] $Author,
        [string] $Company,
        [string] $Description
    )

    $moduleRootFolder = $Path

    # Variables
    $year = (Get-Date).Year
    $moduleVersion = '1.0'

    # Create the "ModuleName" top-level directory
    New-Item -ItemType Directory -Name $moduleName

    # Create subdirectories
    #    ModuleName
    #    |___ ...
    #    |___ ...
    #    |___Private
    #    |   |___ps1
    #    |___ ...

    New-Item -Path "$moduleRootFolder\$moduleName\Private\ps1" -ItemType Directory -Force

    # Create subdirectories
    #    ModuleName
    #    |___ ...
    #    |___ ...
    #    |___ ...
    #    |___Public
    #        |___ps1

    New-Item -Path "$moduleRootFolder\$moduleName\Public\ps1" -ItemType Directory -Force

    # Create the script module
    #    ModuleName
    #    |___ ...
    #    |___ ModuleName.psm1

    New-Item -Path "$moduleRootFolder\$moduleName\$moduleName.psm1" -ItemType File

    # Create the module manifest
    #    ModuleName
    #    |___ModuleName.psd1
    #    |___ ...

    $moduleManifestParameters = @{
        Path = "$moduleRootFolder\$moduleName\$moduleName.psd1" 
        Author = $author
        CompanyName = $company
        Copyright = "$year $author"
        ModuleVersion = $moduleVersion
        Description = $Description
        RootModule = "$moduleName.psm1"
    }
    New-ModuleManifest @moduleManifestParameters
}