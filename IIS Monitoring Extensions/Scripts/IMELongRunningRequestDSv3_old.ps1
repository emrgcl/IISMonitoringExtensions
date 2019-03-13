param($debug)
$SCRIPT_NAME = 'GTBLongRunningRequest.ps1'
$EVENT_LEVEL_ERROR=1
$EVENT_LEVEL_WARNING=2
$EVENT_LEVEL_INFO=4
$SCRIPT_STARTED = 901
$MODULE_LOADED = 902
$PROPERTYBAG_CREATED=903
$SCRIPT_ENDED = 910

#==================================================================================
# Sub:		LogDebugEvent
# Purpose:	Logs an informational event to the Operations Manager event log 
#			only if Debug argument is true
#==================================================================================

function Log-DebugEvent
{
param($eventNo,$message)
$message ="`n" + $message
if ($debug -eq $true) 
{
$api.LogScriptEvent($SCRIPT_NAME,$eventNo,$EVENT_LEVEL_INFO,$message)
}
}

$message='Script started'
Log-DebugEvent $MODULE_LOADED $message
$api=New-Object -ComObject 'Mom.ScriptApi'

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.Web.Administration")

$message='Script started'
Log-DebugEvent $SCRIPT_STARTED $message

$iis = new-object Microsoft.Web.Administration.ServerManager 


foreach ($wp in $iis.WorkerProcesses) {
$AppName=$wp.AppPoolName
$RequestCount = ($wp.GetRequests(0)).Count
$message= $AppName + ' has ' + $RequestCount + ' requests currently'
Log-DebugEvent $PROPERTYBAG_CREATED $message
$bag=$api.CreatePropertyBag()
$bag.AddValue('AppName',$AppName)
$bag.AddValue('RequestCount',$RequestCount)
#Return each property bag as we create and populate it.
$bag
}
Log-DebugEvent $SCRIPT_ENDED 'Script ended.'