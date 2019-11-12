﻿<#
.SYNOPSIS
    Zips and Archives IIS logs to destination location. 
.DESCRIPTION
    Script does Robust operation supporting scenarios like network outage and process terminationation (like server restarts)
.EXAMPLE
    PS C:\> .\Archive-IISLogs.ps1 -LocalDays 7 -ArchiveDays 30 -ArchivePath '\\emreg-om16ms1\c$\ArchiveIISLogs' -TempFolder c:\ArchiveIISLLogsTemp -Verbose
    
    The above example zips the log files those are older than 7 days and once the compression operation completes copies the files to the Archive path folder and removes the files older than 30 in this Archive folder.
    The working directory is set to  c:\ArchiveIISLLogsTemp
.PARAMETER LocalDays
    Specifies the number of days to be kept locally on the IIS Server. 
    Log files older than this threshold will be compressed and moved.
    Default is set to 7.
.PARAMETER ArchiveDays
    Specifies the number of days for the zip files to be kept on the ArchivePath.
    Zip files older than this threshold will be removed.
    Default is set to 400
.PARAMETER ArchivePath
    Specficies the path to be archived. 
    A folder with the source servername will be created and zip files.
    Zip files will be saved into subfolders with the web site names.
.PARAMETER Tempfolder
    Specifies the working folder which includes
    1. Zip files (.zip)
    2. Operation Log (.log)
    3. Snapshots (.xml)
    Please do not delete this folder and add to Antivirus Exclusions.
.PARAMETER Logging
    Only required if script is used in the SCOM Management pack.
    SCOM does not support swtich paramters. This logging parameter is used as an alternative to -verbose in the management pack.
.INPUTS
    Inputs (if any)
.OUTPUTS
    Output (if any)
.NOTES
    General notes
#>
[CmdLetBinding()]
Param(
    [string]$LocalDays = 7,
    [string]$ArchiveDays = 400,
    [string]$ArchivePath = '\\emreg-om16ms1\c$\ArchiveIISLogs',
    [string]$TempFolder = 'C:\ArchiveIISLLogsTemp',
    $Logging = $true
)

class NotEnoughFreeSpaceException : System.Exception {
    
    NotEnoughFreeSpaceException ([String]$Message) : base($Message) {

    }

    NotEnoughFreeSpaceException() {

    }
}
function Backup-OperationLogs {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $True)]
        [string]$ArchivePath,
        [Parameter(Mandatory = $True)]
        [string]$LocalLogPath
    )

    process {

        $ArchiveServerPath = "$ArchivePath\\$($Env:ComputerName)\"
        $ServerLogFolder = "$ArchiveServerPath\OperationLogs"
        # create log folder if not exists
        if (!(Test-Path -path $ServerLogFolder)) {
            try {
            
                New-Item -ItemType Directory -Path $ServerLogFolder -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Log -Message "Could not create foldr $ServerLogFolder Error: $($Error[0].Exception.Message)" -Level Error 
            }
            
        }
        # copy all files under the Local logPath
        
        try {
            $FileItems = get-childitem -File -Path $LocalLogPath | Where-Object { $_.Fullname -match '\.Log' }
            $FileItems | Where-Object { $_.Name -like '*.log' } | Move-Item -Destination  $ServerLogFolder -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Log -Message "Could not create foldr $ServerLogFolder Error: $($Error[0].Exception.Message)" -Level Error 
        }
        
    }
    
}
Function Remove-OldZips {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$DefaultSettings,
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Collections.Hashtable]$OverrideSettings
    
    )
        
    $ArchiveServerPath = "$ArchivePath\\$($Env:ComputerName)\"
    
    $ZipFileItems = Get-ChildItem -Path $ArchiveServerPath -Recurse -File | Where-Object { $_.Name -match '\.(?<ComputerName>\S+)\.,(?<WebSite>(\s|\S)+),(?<Date>\S+)\.zip' }
    
    Foreach ($ZipFileItem in $ZipFileItems) {
        $ZipFileItem -match '\.(?<ComputerName>\S+)\.,(?<WebSite>(\s|\S)+),(?<Date>\S+)\.zip' | Out-Null
        $ArchiveDays = Get-Setting -DefaultSettings $DefaultSettings -OverrideSettings $OverrideSettings -Key "$($Matches['WebSite'])" -Setting ArchiveDays -Verbose
    
        if (((Get-date) - (Get-ZipDate -FileName ($ZipFileItem.FullName))).TotalDays -gt $ArchiveDays) {
        
            try {
        
                Remove-Item -Path $ZipFileItem.FullName -ErrorAction Stop        
                Write-Log -Message "Removed $($ZipFileItem.FullName) which is older than $ArchiveDays."
        
            }
            catch {
                Write-Log -Message "Could not Remove $($ZipFileItem.FullName) Error: $($Error[0].Exception.Message)" -Level Error            
            }
        
        }
    }
    
}

Function Get-WebSiteFromZip {
    [CmdletBinding()]
    Param(
    
        [string]$FileName
    
    )
    
    if ($FileName -match '\.(?<ComputerName>\S+)\.,(?<WebSite>(\s|\S)+),(?<Date>\S+)\.zip') {
    
        $Matches["WebSite"]
    
    }
    else {
    
        Write-Error "Could not get WebSite name from $FileName"
    
    }
    
}

Function Get-ZipDate {
    [CmdletBinding()]
    Param(
    
        [string]$FileName
    
    )
    
    if ($FileName -match '\.(?<ComputerName>\S+)\.,(?<WebSite>(\s|\S)+),(?<Date>\S+)\.zip') {
    
        $Date = $Matches["Date"] -as [DateTime]
    
        if (!$Date) {
    
            Write-Error "Cannot cast $($Matches["Date"]) as [DateTime]"
    
        }
        else {
    
            $Date
    
        }
    }
    
}
    

<#
.Synopsis
    Resumes existing compression queues using the xml paths provided.
.DESCRIPTION
    Resumes existing compression queues using the xml paths provided. Function will look for each compression xml in each path, imports them as a queue and then starts processing the queues.

#>
function Resume-CompressionQueue {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$QueuePaths
    )
    
    process {
        Write-Log "Starting resuming process for $($QueuePaths.Count) paths." -Level 'Info' -Tag 'Resume'
        foreach ($QueuePath in $QueuePaths) {
            try {
            
                $QueueItems = (Get-ChildItem -Path $QueuePath -ErrorAction Stop).Where( { $_.Name -match 'CompressQueue_(\S{8})-((\S{4})-){3}(\S{12})\.xml' })
              
            }
            catch {

                Write-Log -Message "Could not get QueueItem under $QueuePath Error: $($Error[0].Exception.Message)" -Level Error  

            }
            
            foreach ($QueueItem in $QueueItems) {
            
                try {
                    $ResumeQueue = new-object -TypeName System.Collections.Queue
                
                    Import-Clixml -Path "$($QueueItem.FullName)" -ErrorAction Stop | ForEach-Object { $ResumeQueue.Enqueue($_) }
                                   
                    Start-CompressionQueue -Queue $ResumeQueue -TempFolder $QueuePath -RemoveEmptySnapshot -ErrorAction stop

                    Remove-Item $QueueItem.FullName

                    Write-Log -Message "Processed and deleted existing $($QueueItem.FullName)  under $QueuePath and returning the Queue with $($ResumeQueue.Count) items."
                }
                catch {
                    Write-Log -Message "Could not import $($QueueItem.FullName) Error: $($Error[0].Exception.Message)" -Level Error
                }

            }
            
            
        }
        Write-Log "Ending resuming process" -Level 'Info' -Tag 'Resume'   
    }
    
}

<#
.Synopsis
   Gets settings comparing two hashtables. If setting is not avaialble in OverrideSettings then it falbacks to the DefaultSettings
.DESCRIPTION
   Gets settings comparing two hashtables. If setting is not avaialble in OverrideSettings then it falbacks to the DefaultSettings
.EXAMPLE
   Get-Setting -DefaultSettings $DefaultSettings -OverrideSettings $OverrideSettings -Key 'Default Web Site' -Setting LocalDays -Verbose
   
   5
   VERBOSE: [9/24/2019 11:25:56 AM][Info] Found Overidde Settings for LocalDays for Default Web Site: 5

#>
Function Get-Setting {
    [Cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$DefaultSettings,
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Collections.Hashtable]$OverrideSettings,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [string]$Setting
    )
    
    if ($OverrideSettings."$Key"."$Setting") {
        $OverrideSettings."$Key"."$Setting"
        Write-Log -Message "Found Overidde Settings for $Setting` for $Key`: $($OverrideSettings."$Key"."$Setting")"
    }
    else {
        $DefaultSettings.Default."$Setting"
        Write-Log  -Message "Will use defeault settings $Setting` for $Key`: $($DefaultSettings.Default."$Setting")"
    }
    
    
    
}
    


Function Get-ArchiveFolder {
    [CmdletBinding()]
    Param(
        [string]$ArchivePath
    )
    try {
        if (!((Get-PSDrive).Where{ $_.Name -eq 'ArchiveIISLogs' } )) {
            New-PSDrive -Name ArchiveIISLogs -PSProvider FileSystem -Root $ArchivePath  -ErrorAction Stop  -Scope Script | Out-Null
        }
    }
    Catch {
        $Message = "Cannot map to drive $ArchivePath. $($Error[0].Exception.Message)"
        throw $Message
        Write-Log -Message $Message -Level Error
    } 
    
    if (!(Test-Path -Path "ArchiveIISLogs:\$($env:COMPUTERNAME)")) {
        try {
            New-Item -Path "ArchiveIISLogs:\" -Name ($env:COMPUTERNAME) -ItemType "directory" -ErrorAction Stop
            Write-Log  -Message  "Created $($env:COMPUTERNAME) Folder in $ArchivePath"
        }
        Catch {
            $Message = "Cannot create $($env:COMPUTERNAME) Folder in $ArchivePath"
            throw $Message
            Write-Log -Message $Message -Level Error
        }
    }
    else { Get-Item -Path "ArchiveIISLogs:\$($env:COMPUTERNAME)" }
}
    

Function Start-CompressionQueue {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true)]    
        [System.Collections.Queue]$Queue,
        [Parameter(Mandatory = $true)]
        [string]$TempFolder,
        [switch]$RemoveEmptySnapshot,
        [int32]$RetryThreshold = 3
    )
    Write-Log "Starting Compression process" -Level 'Info' -Tag 'Compression'
    $QueuePath = "$TempFolder\CompressQueue_$((New-Guid).Guid).xml" 
    $QueueSize = $Queue.Count
    Write-Log -Message "Intial Taking Snapshot with $Quesize items in $QueuePath"
    try {
        Export-Clixml -Path $QueuePath -InputObject $Queue    
    }
    catch {
        Write-Log -Message "Could not take initial snapshow for $Queuepath Error: $($Error[0].Exception.Message)" -Level Error
        
    }
    
    $ItemsProcessed = 0
    do {
        Write-Log "Current number of items in the Queue: $($Queue.Count)"
        $LogToCompress = $Queue.Peek()
        Write-Log -Message "Working on $($LogToCompress.ZipName)"
        #Move-Item -Path $FileToMove.FullName  C:\temp\Target | Out-Null
        try {
        
            Compress-Files -FileItems ($LogToCompress.FileItems) -zipFilePath "$TempFolder\$($LogtoCompress.zipName)" -CompressionLevel "Optimal" -ErrorAction Stop
            Remove-Item -Path $LogToCompress.FileItems -ErrorAction Stop
            Write-Log -Message "Deleted $($LogToCompress.FileItems)"
            $queue.Dequeue() | out-null
            Write-Log -Message "Successfully compressed $($LogToCompress.ZipName)"
        
        }
        catch {
            ++$LogToCompress.RetryCount
            Write-Log -Message "$($Error[0].Exception.Message)" -Level Error
            if ($LogToCompress.RetryCount -gt $RetryThreshold) {
                $Queue.Dequeue() | Out-Null
                Write-Log -Message "Retrcount exceeded threshold. Removing $($LogToCompress.ZipName). This file will never be retried!. Error:  $($Error[0].Exception.Message)" -Level Error
            }
            else {
                #Send the error log item to the end of the queue by requeing
                $Queue.Dequeue() | Out-Null
                $Queue.Enqueue($LogToCompress)
            }
        }
        Finally {
            
            $Queue | Export-Clixml -Path $QueuePath
            ++$ItemsProcessed
            Write-Log -Message "Taking Snapshot QueueCount = $($Queue.Count), ItemsPRocessed = $($ItemsProcessed)"
        }
 
    } until (($Queue.Count -eq 0) -or ($QueueSize -eq $ItemsProcessed))

    #Remove the Snapshot once finished
    if ($Queue.Count -eq 0 -and $RemoveEmptySnapshot) {

        Remove-Item $QueuePath
        
    }

    Write-Log "Ending Compression process" -Level 'Info' -Tag 'Compression'
}

<#
.SYNOPSIS
    Writes Log to specified file if not logs to a file under User temp.
.DESCRIPTION
    Writes Log to specified file if not logs to a file under User temp. Function also writes the log to the Verbose stream if -Verbose used.
.EXAMPLE
    PS C:\> Write-Log -LogFile c:\temp\mylog.txt -Message "Error Occured $($Error[0].Exception.Message)" -Tag "Script Start" -Level Error
    VERBOSE: [8/1/2019 7:21:13 AM][Error][EMREG-DSC][Script Start] Error Occured Cannot bind argument to parameter 'Message' because it is an empty string.
    
    The above example Writes the message to the LogFile specifed with the Level Type error and the Optional Tag used "ScriptStart"
.EXAMPLE
    PS C:\> Write-Log -Message "Script Started" -Tag "Script Start" -Level Info
    VERBOSE: [8/1/2019 7:22:43 AM][Info][EMREG-DSC][Script Start] Script Started
    
    The above example Writes the message ehich is the only require parameter. The file is save to users temp folder with the format Write-Log-yyyy-M-d.log
.INPUTS
    String
.OUTPUTS
    Output (if any)
.NOTES
    Author: Emre Güçlü
    Version: 1.0
    Release Date:1 August 2019
#>
function Write-Log {
    [CmdletBinding()]
    param (
        # setting Default path the User Temp.
        [Parameter(Mandatory = $true)]
        [String]$Message,
        [ValidateSet("Error", "Warning", "Info")] 
        [string]$Level = "Info", 
        [String]$LogFile, #"$($Env:Temp)\Write-Log-$(Get-Date -Format yyyy-M-d).log",
        [string]$Tag 

    )
    if (!$LogFile) {
        if ($Global:LogFile) {
           
            $LogFile = ($Global:LogFile)
        
        }
        else {
            $LogFile = "$($Env:Temp)\Write-Log-$(Get-Date -Format yyyy-M-d).log"
        }
    }
    if ($Tag) {
        $Log = "[$(Get-Date -Format G)][$Level][$($env:ComputerName)][$Tag] $Message"
    }
    else {
        $Log = "[$(Get-Date -Format G)][$Level] $Message"
    }
    if ($VerbosePreference = 'Continue') {
        $Log | Out-File -FilePath $LogFile -Append
    }
    Write-Verbose -Message  $Log
    
}


<#
.SYNOPSIS
    Copies files with retry support.
.DESCRIPTION
    Copies files with retry support.
.EXAMPLE
    PS C:\> Copy-Files -FilesToCopy $files -Destination $Destination -RetryCount 5 -RetryInterval 30 -Verbose
.INPUTS
    String
.OUTPUTS
    Output (if any)
.NOTES
    Author: Emre Güçlü
    Version: 1.0
    Release Date:1 August 2019
#>

Function Copy-Files {


    [CmdletBinding()]
    param(
    
        [string[]]$FilesToCopy,
        [string]$Destination,
        [int32]$RetryCount = 15,
        [int32]$RetryInterval = 60,
        [switch]$Move
    )
    
   
    #Copy Files
    Foreach ($File in $FilesToCopy) {
        $CurrentRetry = 1
    
        #Set target Path to test
        $TargetFile = "$Destination\$($file | split-path -Leaf )"
    
        do {
    
            if ($CurrentRetry -eq $RetryCount) {
    
                $Message = "Retry limit has reached after $RetryCount retries. Exiting script."
    
                Write-Log -Message $Message -Level Error
                Throw $Message
    

            }
    
            Try {
                Write-Log -Message "Copying $File to to $Destination."
                #try copying
                Copy-Item -Path $File -Destination $TargetFile -Force -ErrorAction Stop
                Write-Log -Message "Copied $File to to $Destination after retrying $CurrentRetry times."
                if ($Move) {
                    Remove-Item -Path $File -ErrorAction Stop
                    Write-Log -Message "-Move is used. Deleted $File."
                    
                }
                else {

                    Write-Log -Message "-Move is not used. Will not delete $File."

                }
    
            }
            Catch {
    
                $ErrorOccured = $true
    
                Write-Log -Message "Retry Count: $CurrentRetry. Could not Copy $File to $Destination. $($_.Exception.GetType().FullName), Message:$($_.Exception.Message)"
                Write-Log -Message "Waiting for $RetryInterval Seconds." 
    
                # if error occurs sleep
                Start-Sleep -Seconds $RetryInterval | out-null
    
                ++$CurrentRetry
    
            }
            Finally {
    
                if (!$ErrorOccured) {
    
                    Write-Log -Message "Copied $File to to $Destination after retrying $CurrentRetry times."
    
                }
    
            }
    
        } 
    
        until (test-path -Path $TargetFile)
    
    }
}

<#
.SYNOPSIS
    Compresses files using System.IO.Compression.Zip type.
.DESCRIPTION
    Writes Log to specified file if not logs to a file under User temp. Function also writes the log to the Verbose stream if -Verbose used.

    INMPORTANT: System.IO.Compression.Zip type may not compress files over 4gb due to a limitation of .Net. 
.EXAMPLE
    $FileItems = (Get-ChildItem -Path C:\temp\compresstest\2GbLogs).FullName
    Compress-Files -FileItems $FileItems -zipFilePath 'c:\temp\compresstest\2gb.zip' -Verbose -compressionLevel Fastest
    

    VERBOSE: Size of Files to Zip: 11513.54 Mbs
    VERBOSE: Created zip: c:\temp\compresstest\1gb.zip
    VERBOSE: CompressionLevel: Optimal
    VERBOSE: Working on C:\temp\compresstest\1GbLogs\1.Log. File Size: 1151.35 Mbs
    VERBOSE: Updated zip: c:\temp\compresstest\1gb.zip, Added C:\temp\compresstest\1GbLogs\1.Log
    VERBOSE: Working on C:\temp\compresstest\1GbLogs\10.Log. File Size: 1151.35 Mbs
    VERBOSE: Updated zip: c:\temp\compresstest\1gb.zip, Added C:\temp\compresstest\1GbLogs\10.Log
    VERBOSE: Working on C:\temp\compresstest\1GbLogs\2.Log. File Size: 1151.35 Mbs
    VERBOSE: Updated zip: c:\temp\compresstest\1gb.zip, Added C:\temp\compresstest\1GbLogs\2.Log
    VERBOSE: Working on C:\temp\compresstest\1GbLogs\3.Log. File Size: 1151.35 Mbs
    VERBOSE: Updated zip: c:\temp\compresstest\1gb.zip, Added C:\temp\compresstest\1GbLogs\3.Log
    VERBOSE: Working on C:\temp\compresstest\1GbLogs\4.Log. File Size: 1151.35 Mbs
    VERBOSE: Updated zip: c:\temp\compresstest\1gb.zip, Added C:\temp\compresstest\1GbLogs\4.Log
    VERBOSE: Working on C:\temp\compresstest\1GbLogs\5.Log. File Size: 1151.35 Mbs
    VERBOSE: Updated zip: c:\temp\compresstest\1gb.zip, Added C:\temp\compresstest\1GbLogs\5.Log
    VERBOSE: Working on C:\temp\compresstest\1GbLogs\6.Log. File Size: 1151.35 Mbs
    VERBOSE: Updated zip: c:\temp\compresstest\1gb.zip, Added C:\temp\compresstest\1GbLogs\6.Log
    VERBOSE: Working on C:\temp\compresstest\1GbLogs\7.Log. File Size: 1151.35 Mbs
    VERBOSE: Updated zip: c:\temp\compresstest\1gb.zip, Added C:\temp\compresstest\1GbLogs\7.Log
    VERBOSE: Working on C:\temp\compresstest\1GbLogs\8.Log. File Size: 1151.35 Mbs
    VERBOSE: Updated zip: c:\temp\compresstest\1gb.zip, Added C:\temp\compresstest\1GbLogs\8.Log
    VERBOSE: Working on C:\temp\compresstest\1GbLogs\9.Log. File Size: 1151.35 Mbs
    VERBOSE: Updated zip: c:\temp\compresstest\1gb.zip, Added C:\temp\compresstest\1GbLogs\9.Log
    VERBOSE: Compression Duration = 400.0986761 Seconds
    VERBOSE: ZipFile = c:\temp\compresstest\1gb.zip Size: 288.29 Mbs
    VERBOSE: Compression Ratio : 40 Times
    VERBOSE: Compression Percent : 97%

    The above example compresses the files with the specified compression method passed to Compress-Files

.INPUTS
    String
.OUTPUTS
    Output (if any)
.NOTES
    Author: Emre Güçlü
    Version: 1.0
    Release Date:1 August 2019
    Support Note: System.IO.Compression.Zip type may not compress files over 4gb due to a limitation of .Net.  
#>

Function Compress-Files {
    [CmdletBinding()]
    Param(
        [string]$zipFilePath = 'c:\temp\compresstest\1gb.zip',
        [string[]]$FileItems,
        [ValidateSet("Optimal", "Fastest", "NoCompression")]
        [string]$CompressionLevel
    )
    $Timer = Get-Date
    Add-Type -Assembly 'System.IO.Compression.FileSystem'
    $TotalFileSize = [Math]::Round((($FileItems | Get-ChildItem | Measure-Object -Property Length -Sum).Sum / 1mb), 2)
    Write-Log -Message "Size of Files to Zip: $TotalFileSize Mbs"
    #Create Empty zip
    try {
        $zip = [System.IO.Compression.ZipFile]::Open($zipFilePath, 'create')
    }
    Catch {
        Write-Log -Message "$($_.Exception.GetType().FullName), Message:$($_.Exception.Message)"
        $ErrorOccured = $true
        Throw
    }
    Finally {
        if ($ErrorOccured) {
            $Zip.Dispose()
        }
        else {
            Write-Log -Message "Created zip: $zipFilePath"
            $zip.dispose()
        }
    }
    
    #Set the Compression Level
    Write-Log -Message "CompressionLevel: $CompressionLevel"
    $compressionLevel = [System.IO.Compression.CompressionLevel]::($CompressionLevel)
    
    
    Foreach ($File in $FileItems) {
    
        Write-Log -Message "Working on $File. File Size: $([Math]::Round((($File | Get-ChildItem | Measure-Object -Property Length -Sum).Sum /1mb),2)) Mbs"
    
        try {
            #Open the zip file
            $zip = [System.IO.Compression.ZipFile]::Open($zipFilePath, 'update')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file, (Split-Path $file -Leaf), $compressionLevel) | out-null
        }
        catch {
    
            Write-Log -Message "$($_.Exception.GetType().FullName), Message:$($_.Exception.Message)"
            $ErrorOccured = $true
    
        }
        finally {
    
            if ($ErrorOccured) {
                $Zip.Dispose()
            }
            else {
                Write-Log -Message "Updated zip: $zipFilePath, Added $File"
                $zip.dispose()
    
            }
        }
    }
    
    Write-Log -Message "Compression Duration = $(((Get-Date) - $Timer).TotalSeconds) Seconds"
    Write-Log -Message "ZipFile = $zipFilePath Size: $([Math]::Round((($zipFilePath | Get-ChildItem | Measure-Object -Property Length -Sum).Sum /1mb),2)) Mbs"
    Write-Log -Message "Compression Ratio : $( [Math]::Round($TotalFileSize / (($zipFilePath | Get-ChildItem | Measure-Object -Property Length -Sum).Sum /1mb))) Times"
    Write-Log -Message "Compression Percent : $([Math]::Round(100 - [Math]::Round((($zipFilePath | Get-ChildItem | Measure-Object -Property Length -Sum).Sum /1mb),2) / $TotalFileSize * 100))%"
    
}

function Convert-ByteToMb {
    [CmdletBinding()]
    param (
        [double]$Byte
    )
    
    [Math]::Round($Byte / 1mb)
}

function Backup-Logs {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipelineByPropertyName = $True, ValueFromPipeline = $True)]
        [string[]]$Path
    )
  
    process {
        foreach ($item in $Path) {
            if ((test-path -path $item)) {

                Get-ChildItem -Path $item -File | Where-Object { $_.Name -match '\.(?<ComputerName>\S+)\.,(?<WebSite>(\s|\S)+),(?<Date>\S+)\.zip' } | ForEach-Object {
                    $ComputerName = $matches['ComputerName']
                    $WebSite = $matches['WebSite']
                    Write-Log -Message "ComputerName = $ComputerName ,Web Site = $WebSite ,Date = $($matches['Date'])"
                    # Generate the actual path including servername
                    $ArchiveServerPath = "$ArchivePath\\$ComputerName\"
                    Write-Log -Message "Path to copy = $ArchiveServerPath"
                    New-Item -Path $ArchiveServerPath -Name $WebSite -Force  -ItemType Directory | out-null
                         
                    Copy-Files -FilesToCopy $_.FullName -Destination "$ArchiveServerPath\$Website" -Move
                    Write-Log -Message ("Found $($_.FullName) under $item. Copied to $ArchiveServerPath" + $WebSite + " and deleted.")
                }    
                
            
            
            }
        }

    }
    

}

#Region ScriptMain
#Requires -Module WebAdministration
#Requires -PSEdition Desktop
#Requires -Version 5

# Lets set teh counter on
$StartDate = Get-Date

# Setting Verobse if $Logging set to $true - used for managementpack
if ($Logging) {
    $VerbosePreference = "continue"
}

# Initilizing LogFile Variable
$Global:LogFile = "$TempFolder\Archive-IISLogs-Log-$(Get-Date -Format yyyy-M-d_hhmmss).log"

$Message = "Script started. Username: $($env:USERDOMAIN)\$($env:USERNAME)"
Write-Log -Message $Message -Level Info
Write-Information -MessageData $Message
# Preparing and getting the registry key
if (!(Test-path -Path HKLM:\SOFTWARE\Archive-IISLogs)) {
    Write-Log -Message "HKLM:\SOFTWARE\Archive-IISLogs does not exist creating it"
    New-item -Path HKLM:\SOFTWARE -Name Archive-IISLogs
    New-ItemProperty -Path HKLM:\SOFTWARE\Archive-IISLogs -Name TempFolder -Type string -Value $TempFolder
}
else {
    Write-Log -Message "HKLM:\SOFTWARE\Archive-IISLogs exists." 
    $RegSettings = Get-ItemProperty -Path HKLM:\SOFTWARE\Archive-IISLogs\
    
    # if the tempfolder and registry is different grab the previous one to check later
    if ($RegSettings.TempFolder -ne $TempFolder) {
        $PreviousTempFolder = $RegSettings.TempFolder
        Write-Log -Message "Copied previous TempFolder settings for later use and set the current temp folder to TempFolder"       
    }

    # we have previous folder now we can set the current value to registry. 
    Set-ItemProperty -Path HKLM:\SOFTWARE\Archive-IISLogs -Name TempFolder -Type string -Value $TempFolder
}


# Create $TempFolder
if (!(Test-path -path $TempFolder)) {

    try {
        new-item -Path (Split-Path -Path $TempFolder -Parent) -Name (Split-Path -Path $TempFolder -Leaf) -ItemType Directory -ErrorAction Stop
        Write-Log -Message "Successfully Created $TempFolder" 
    }
    catch {
        Write-Log -Message "Could not Create $TempFolder Exception Type: $($_.Exception.GetType().FullName), Message:$($_.Exception.Message)" -LogFile "$($Env:Temp)\Write-Log-$(Get-Date -Format yyyy-M-d).log"
        Throw
    }

}



Write-Log -Message "Script Started" 

Write-Log -Message "Current TempFolder : $TempFolder"


# Resume Compresssion files if theres an existing snapshot in previous or current folders.
Resume-CompressionQueue -QueuePaths $TempFolder, $PreviousTempFolder

# Backup the files under Previous and existing temp folders before starting to compress

if (![string]::IsNullOrEmpty($PreviousTempFolder)) {

    Backup-Logs -Path $TempFolder, $PreviousTempFolder
}
else { 
    
    Backup-Logs -Path $TempFolder 

}

# Get the free space before compression
$TempDriveFreeSpace = (get-item -Path $TempFolder).PsDrive.Free

# Script Start
Import-Module WebAdministration -Verbose:$false


# set the default settings using Paremeters supplied
$DefaultSettings = @{Default = @{LocalDays = $LocalDays; ArchiveDays = $ArchiveDays } }

#Map to ArchivePath
try {
    $ArchiveFolder = Get-ArchiveFolder -ArchivePath $ArchivePath  -ErrorAction Stop
}
Catch {
    $Message = "Cannot get Archive folder. $($Error[0].Exception.Message)"
    Write-Log -Message $Message -Level Error
    throw $Message
}

#Get the settings file if exists
$OverrideSettings = Import-PowerShellDataFile -Path  "$($ArchiveFolder.FullName)\Archive-IISLogs.psd1" -ErrorAction SilentlyContinue

# get the site information including site name and Log Directory
$WebSiteInfos = Get-Website | Select-Object -Property Name, ID, @{Name = 'LogDirectory'; Expression = { "$($_.LogFile.Directory)\W3SVC$($_.ID)" -Replace "%SystemDrive%", "$($env:SystemDrive)" } }

# If we dont have enough space exit the script before compression
$TotalLogSize = (get-childitem -Path $WebSiteInfos.LogDirectory -File | Measure-Object -Property Length -Sum).Sum

if (($TotalLogSize / 5) -gt $TempDriveFreeSpace) {

    $Message = "Not Enough free space. Exiting script Total log size of is $(Convert-ByteToMb -Byte $TotalLogSize) Mbs. Current Free for $TempFolder drive is $(Convert-ByteToMb -Byte $TempDriveFreeSpace) Mbs."
    Write-Log -Message $Message -Level Error
    throw $Message   
}

# Initilize Queue for compression
$Queue = New-Object -TypeName System.Collections.Queue

foreach ($WebSiteInfo in $WebSiteInfos) {
    Write-Log -Message "Working on Site: $($WebSiteInfo.Name), SiteID:  $($WebSiteInfo.ID), LogDirectory: $($WebSiteInfo.LogDirectory)"

    #Getting LocalDays Setting
    $LocalDays = Get-Setting -DefaultSettings $DefaultSettings -OverrideSettings $OverrideSettings -Key "$($WebSiteInfo.Name)" -Setting LocalDays
    
    #Formatting and Grouping based on dates. The Result group will be including all we need to loop in.
    $DatesGroup = (Get-ChildItem -path ($WebSiteInfo.LogDirectory) -File).Where( { $_.LastWriteTime -lt (Get-Date).AddDays(-1 * $LocalDays) }) | Select-Object -Property FullName, Length, @{Name = 'Date'; Expression = { $_.LastWriteTime.ToString('yyyy-MM-dd') } } | Group-Object -Property Date
    $TotalLogSizeToZip = [Math]::Round(($DatesGroup.Group | ForEach-Object { $_.Length } | Measure-Object -Sum).Sum / 1mb, 2)
    Write-Log -Message " Total Log Size to zip: $TotalLogSizeToZip Mbs."
    Foreach ($DateGroup in $DatesGroup) {

        # out "." cannot be used in ComputerNames and also "," cannot be used in websites therefore we are using as seperators in filenames
        $ZipName = ".$($env:COMPUTERNAME).,$($WebSiteInfo.Name),$($DateGroup.Name).zip"
    
        $QueueItem = [PSCustomObject]@{
            ZipName      = $ZipName
            FileItems    = $DateGroup.Group.FullName
            WebSite      = $WebSiteInfo.Name
            Date         = $DateGroup.Name
            LogSizeMb    = [Math]::Round((($DateGroup.Group.Length | Measure-Object -Sum).Sum / 1mb), 2)
            LogDirectory = $WebSiteInfo.LogDirectory
            RetryCount   = 0
        }
        $Queue.Enqueue($QueueItem)
        Write-Log -Message "Enqueued $($QueueItem.FileItems.Count) files for $($QueueItem.Website) in $($QueueItem.ZipName) under $($QueueItem.LogDirectory) Log size for Date: $($QueueItem.Logsize) Mbs"  
    }
    
}
if ($Queue.Count -gt 0) {
    Write-Information -MessageData "Number of items to be compressed and zipped: $($Queue.Count)"
    Start-CompressionQueue -Queue $Queue -TempFolder $TempFolder -RemoveEmptySnapshot
    # Copy zips to Archive Folder now
    Backup-Logs -Path $TempFolder
} else {
    Write-Information  -MessageData 'Nothing to compress.'
}



# Removing old zips
Remove-OldZips -OverrideSettings $OverrideSettings -DefaultSettings $DefaultSettings -ArchivePath $ArchivePath
$Message = "Script ended. Duration = $([Math]::Round((((Get-Date) - $startdate).TotalSeconds),2)) seconds"
Write-Log $Message -Level Info
Write-Information -MessageData $Message
# Backup Logs
Backup-OperationLogs -ArchivePath $ArchivePath -LocalLogPath $TempFolder -Verbose:$false -ErrorAction Stop
    

# Cleanup
Remove-PSDrive -Name ArchiveIISLogs


#Endregion