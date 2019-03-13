param($debug)
$SCRIPT_NAME = 'GTBLongRunningRequest.ps1'
$EVENT_LEVEL_ERROR=1
$EVENT_LEVEL_WARNING=2
$EVENT_LEVEL_INFO=4
$SCRIPT_STARTED = 901
$PROPERTYBAG_CREATED=902
$SCRIPT_ENDED = 910

Import-Module WebAdministration

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

$api=New-Object -ComObject 'Mom.ScriptApi'
$message='Script started'
Log-DebugEvent $SCRIPT_STARTED $message

foreach ($app in (Get-ChildItem –Path IIS:\AppPools) )
{
$AppName=$app.Name
$RequestCount = ($app | Get-WebRequest).Count
$message= $AppName + ' has ' + $RequestCount + ' requests currently'
Log-DebugEvent $PROPERTYBAG_CREATED $message
$bag=$api.CreatePropertyBag()
$bag.AddValue('AppName',$AppName)
$bag.AddValue('RequestCount',$RequestCount)
#Return each property bag as we create and populate it.
$bag
}
Remove-Module WebAdministration
Log-DebugEvent $SCRIPT_ENDED 'Script ended.'
