<#
.SYNOPSIS
    Updates the manifest file of a Powershell module.
.DESCRIPTION
    Updates the manifest file of a Powershell module. Adds or removes public and private functions and their aliases.
    The folder structure of the module must match the following structure as described here:  https://benheater.com/creating-a-powershell-module/

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
    Update-ManifestFile
.EXAMPLE
    Update-ManifestFile -Path $moduleRootFolder
.INPUTS
    Path: the root folder of the Module. Defaults to the current dircetory.
.OUTPUTS
    None
.NOTES
    All credit goes to 0xBEN: https://github.com/0xBEN.
    The following code was taken from their blog post about Powershell modules at https://benheater.com/creating-a-powershell-module/.
    It has been slightly modified to be able to be able to pass the root folder of the module as well as to provide some feedback and error handling.
#>

function Update-ManifestFile {

    param (
        [string] $Path = $PWD
    )

    $moduleRootFolder = $Path

    if(-not (Test-Path -Path $moduleRootFolder)) {
        Write-Output "Did not find the folder [$moduleRootFolder]."
        return
    }
    Write-Output 'Updating the manifest file.'
    Write-Output "Working directory is [$moduleRootFolder]."

    $directorySeparator = [System.IO.Path]::DirectorySeparatorChar
    $moduleName = $moduleRootFolder.Split($directorySeparator) | Select-Object -Last 1
    if([string]::IsNullOrEmpty($moduleName)) {
        Write-Output 'Error getting the module name.'
        return
    }
    Write-Output "The module name is [$moduleName]."

    $moduleManifest = $moduleRootFolder + $directorySeparator + $moduleName + '.psd1'
    if(-not (Test-Path -Path $moduleManifest)) {
        Write-Output "The module manifest file [$moduleManifest] was not found."
        return
    }

    $publicFunctionsPath = $moduleRootFolder + $directorySeparator + 'Public' + $directorySeparator + 'ps1'
    if(-not (Test-Path -Path $publicFunctionsPath)) {
        Write-Output "The public functions folder [$publicFunctionsPath] was not found."
        return
    }

    $privateFunctionsPath = $moduleRootFolder + $directorySeparator + 'Private' + $directorySeparator + 'ps1'
    if(-not (Test-Path -Path $privateFunctionsPath)) {
        Write-Output "The private functions folder [$privateFunctionsPath] was not found."
        return
    }

    Write-Output "Checking module manifest [$moduleManifest]."
    $currentManifest = Test-ModuleManifest $moduleManifest
    Write-Output 'Gathering data...'

    $aliases = @()
    $publicFunctions = Get-ChildItem -Path $publicFunctionsPath | Where-Object {$_.Extension -eq '.ps1'}
    $privateFunctions = Get-ChildItem -Path $privateFunctionsPath | Where-Object {$_.Extension -eq '.ps1'}
    
    $publicFunctions | ForEach-Object { 
        Write-Output "Importing file [$($_.FullName)]."
        try {
            . $_.FullName 
        } catch {
            Write-Output "Error while dotsourcing file [$($_.FullName)]."
            return
        }
    }
    $privateFunctions | ForEach-Object {
        Write-Output "Importing file [$($_.FullName)]."
        try {
            . $_.FullName 
        } catch {
            Write-Output "Error while dotsourcing file [$($_.FullName)]."
            return
        }
    }
    $publicFunctions | ForEach-Object { # Export all of the public functions from this module

        try {
            # The command has already been sourced in above. Query any defined aliases.
            $alias = Get-Alias -Definition $_.BaseName -ErrorAction SilentlyContinue
            if ($alias) {
                $aliases += $alias
                Export-ModuleMember -Function $_.BaseName -Alias $alias
            }
            else {
                Export-ModuleMember -Function $_.BaseName
            }
        } catch {
            Write-Output "Error exporting module members while processing file [$($_.Name)]."
            $_ | Write-Error
            return
        }

    }

    $functionsAdded = $publicFunctions | Where-Object {$_.BaseName -notin $currentManifest.ExportedFunctions.Keys}
    $functionsRemoved = $currentManifest.ExportedFunctions.Keys | Where-Object {$_ -notin $publicFunctions.BaseName}
    $aliasesAdded = $aliases | Where-Object {$_ -notin $currentManifest.ExportedAliases.Keys}
    $aliasesRemoved = $currentManifest.ExportedAliases.Keys | Where-Object {$_ -notin $aliases}

    if ($functionsAdded -or $functionsRemoved -or $aliasesAdded -or $aliasesRemoved) {
        Write-Output 'Updating the manifest file...'
        try {

            $updateModuleManifestParams = @{}
            $updateModuleManifestParams.Add('Path', $moduleManifest)
            $updateModuleManifestParams.Add('ErrorAction', 'Stop')
            if ($aliases.Count -gt 0) { $updateModuleManifestParams.Add('AliasesToExport', $aliases) }
            if ($publicFunctions.Count -gt 0) { $updateModuleManifestParams.Add('FunctionsToExport', $publicFunctions.BaseName) }

            Update-ModuleManifest @updateModuleManifestParams

        } catch {
            Write-Output 'Error while modifying the manifest file.'
            $_ | Write-Error
            return
        }

        if ($functionsAdded) {
            $functionNames = $functionsAdded | Select-Object -ExpandProperty BaseName  
            Write-Output "Added the following functions: [$($functionNames -join ', ')]"
        }

        if ($functionsRemoved) {
            $functionNames = $functionsRemoved | Select-Object -ExpandProperty BaseName  
            Write-Output "Removed the following functions: [$($functionNames -join ', ')]"
        }

        if ($aliasesAdded) {
            $aliasNames = $aliasesAdded | Select-Object -ExpandProperty Name
            Write-Output "Added the following functions: [$($aliasNames -join ', ')]"
        }

        if ($aliasesRemoved) {
            $aliasNames = $aliasesRemoved | Select-Object -ExpandProperty Name
            Write-Output "Added the following functions: [$($aliasNames -join ', ')]"
        }
    } else {
        Write-Output 'No changes to functions or aliases detected. The manifest file was not modified.'
    }

    Write-Output 'Done. Have a nice rest of your day =)'
}