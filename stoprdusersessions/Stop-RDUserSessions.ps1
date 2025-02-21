#Requires -RunAsAdministrator
#Requires -Modules RemoteDesktop

$script:defaultPopUpMessageTitle      = 'Maintenance'
$script:defaultPopUpMessageBody       = 'Due to maintenance your current session will be terminated in {0}. ' +
                                        'Please safe all open documents or unsafed progress may be lost.'

$script:defaultLogoutDelayMinutes     = 2
$script:defaultLogoutFrequencySeconds = 10
$script:defaultGracePeriodMinutes     = 5

$script:defaultTimeStampFormat        = 'HH:mm:ss'

<#
.SYNOPSIS
Formats a string with a timestamp.

.DESCRIPTION
The input string is returned with a timestamp in the form 'HH:mm:ss: ' preceeding it.
The format of the timestamp can be chosen or it can be omitted. In the latter case it 
will be replaced by an equal amount of spaces. An Indentation parameter can be set that
inserts additional spaces between the timestamp and the text.

.PARAMETER Message
The text to be formatted.

.PARAMETER Indentation
The amount of additional whitespaces between the timestamp and the text.

.PARAMETER TimeStampFormat
A format for the timestamp. 
A colon and a whitespace is added after the timestamp.

.PARAMETER NoTimeStamp
If set, the timestamp is replaced by an amount of spaces equal to its length.

.INPUTS
System.String
	You can pipe a string that contains the message to this cmdlet.

.OUTPUTS
System.String
	The formatted string.

.EXAMPLE
Format-LogMessage -Message 'Hello'

Retuns the text prefixed by the current time, i.e. 15:02:23: Hello

.EXAMPLE
Format-LogMessage -Message 'Hello' -TimeStampFormat 'HH'

Returns the text pefixed by the current hour, i.e. 15: Hello
#>
function Format-LogMessage {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory, ValueFromPipeline, Position = 0)]
		[string] $Message,

		[ValidateRange(0, 64)]
		[int] $Indentation = 0,

		[string] $TimeStampFormat = $($script:defaultTimeStampFormat),

		[switch] $NoTimeStamp
	)

	process {
		$timestamp = Get-Date -Format $TimeStampFormat
		$timestampPrefix = "${timestamp}: "
		if ($NoTimeStamp) {
			$timestampPrefix = ' ' * $timestampPrefix.Length
		}
		$indentationPrefix = ' ' * $Indentation
		return '{0}{1}{2}' -f $timestampPrefix, $indentationPrefix, $Message
	}
}

<#
.SYNOPSIS
Terminates a remote session.

.DESCRIPTION
Terminates the remote session given by its session ID. A delay can be provided after which the session is terminated.
In this case, the user is notified with a message about the impending logout. The logout script is run as a background
job which pauses until the delay has passed. The job object is returned to the caller.

.PARAMETER SessionID
The session ID that should be terminated.

.PARAMETER DelayMinutes
The delay in minutes after wich the session will be terminated.

.PARAMETER UserName
The username of the session.

.PARAMETER HostServer
The server which sessions should be terminated. Defaults to the local machine.

.EXAMPLE
Start-RDUserLogout -SessionID 5 -DelayMinutes 2

Notifies the user with session ID 5 about the logout and terminates the session after 2 minutes.

.EXAMPLE
2,5,7 | Start-RDUserLogut -DelayMinutes 0

Terminates the sessions of users with session IDs 2, 5 and 7.

.EXAMPLE
Get-RDUserSession | Start-RDUserLogout

Notifies every user currently logged in on the server and terminates their session after the default delay.

.NOTES
If the username of the session with the provided ID does not match the username of the session after the 
delay has passed, the session is not terminated. This may happen if the user logs out after being notified
and another session is started after that with the same ID.
#>
function Start-RDUserLogout {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'SessionID')]
		[ValidateScript({ $null -ne (Get-RDUserSession | Where-Object UnifiedSessionID -eq $_) })]
		[int] $SessionID,

		[Parameter(ParameterSetName = 'SessionID')]
		[string] $HostServer = ${env:COMPUTERNAME},

		[Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Session')]
		[ValidateNotNull()]
		$Session,

		[int] $DelayMinutes    = $script:defaultLogoutDelayMinutes,

		[string] $MessageTitle = $script:defaultPopUpMessageTitle,

		[string] $MessageBody  = $script:defaultPopUpMessageBody
	)

	process {
		if ($PSCmdlet.ParameterSetName -eq 'SessionID') {
			$Session = Get-RDUserSession | Where-Object UnifiedSessionID -eq $SessionID
		}

		$delayDisplayText = "$DelayMinutes minute"
		if($DelayMinutes -gt 1) {
			$delayDisplayText += 's'
		}

		$messageArguments = @{
			HostServer       = $Session.HostServer
			UnifiedSessionID = $Session.UnifiedSessionID
			MessageTitle     = $MessageTitle
			MessageBody      = $MessageBody -f $delayDisplayText
		}
		
		$arguments = $Session, $DelayMinutes, $messageArguments

		$logoutScript = [scriptblock] {
			param(
				$Session,
				$DelayMinutes,
				$MessageArguments
			)

			# Only show the popup if there is a delay.
			if($DelayMinutes -gt 0) {
				Send-RDUserMessage @MessageArguments
				Start-Sleep -Seconds ($DelayMinutes * 60)
			}

			$currentSession = Get-RDUserSession | Where-Object UnifiedSessionID -eq $SessionID
			if($currentSession.UserName -eq $Session.UserName) {
				Invoke-RDUserLogoff -HostServer $Session.HostServer -UnifiedSessionID $Session.UnifiedMessageID -Force
			}
		}

		Start-Job -ScriptBlock $logoutScript -ArgumentList $arguments
	}
}

<#
.SYNOPSIS
Terminates remotesessions on a server.

.DESCRIPTION
Terminates every remotesession except the session of the user running the script. A delay can be provided after wich the sessions will
be terminated. In this case a popup message will be shown to the users to notify them about the impending logout.
Additionally, a grace period can be provided, after wich the users will be logged out immediately.
The script will run indefinately and check for new connections which will be terminated immediately as soon as the grace period has passed. 
This can be avoided by providing the switch parameter LogoutOnce. In this case the script terminates if no active connections are detected.

.PARAMETER LogoutDelayMinutes
The delay in minutes after which sessions will be terminated. It is bound by the GracePeriodMinutes parameter. The default value is 2 minutes.

.PARAMETER LogoutFrequencySeconds
The time in seconds after which the script will check for new connections. The default value is 10 seconds.

.PARAMETER GracePeriodMinutes
The time in minutes after which the users are logged out immediately. The default value is 5 minutes.

.PARAMETER LogoutOnce
Causes the script to terminate as soon as no active sessions are detected.

.EXAMPLE
Stop-RDUserSessions

Terminates every user session execpt the callers session. The delay, grace period and frequency will be provided by the default values.
The users will be notified about the logout and their session will be terminated after the delay. After the grace period has passed,
new sessions will be terminated immediately.

.EXAMPLE
Stop-RDUserSessions -LogoutDelayMinutes 2 -GracePeriodMinutes 0

Terminates every user session execpt the callers session. Sessions will be terminated immediately and users will not be notified, 
because the grace period has been set to zero.

.EXAMPLE
Stop-RDUserSessions -LogoutOnce

Terminates every user session execpt the callers. The script will terminate after no sessions execept the callers session is detected.

.NOTES
This script has to be run with administrative privileges.
#>
function Stop-RDUserSessions {
	[CmdletBinding()]
	param(
		[ValidateRange(0, 10)]
		[int] $LogoutDelayMinutes = $script:defaultLogoutDelayMinutes,

		[ValidateRange(1, 240)]
		[int] $LogoutFrequencySeconds = $script:defaultLogoutFrequencySeconds,

		[ValidateRange(0, 30)]
		[int] $GracePeriodMinutes = $script:defaultGracePeriodMinutes,

		[switch] $LogoutOnce
	)
	
	$cutOffTime = (Get-Date).AddMinutes($GracePeriodMinutes)
	$queuedSessions = [hashtable]::new()
	$exitProgram = $false
	$gracePeriodPassed = $false

	$message = 'Logging out users.'
	$message = Format-LogMessage -Message $message
	Write-Output $message
	$message = "Active sessions will be terminated after $LogoutDelayMinutes Minutes."
	$message = Format-LogMessage -Message $message
	Write-Verbose -Message $message
	$message = 'Disconnected sessions will be terminated instantly.'
	$message = Format-LogMessage -Message $message
	Write-Verbose -Message $message
	$message = "The grace period is $GracePeriodMinutes minutes, it lasts until $($cutOffTime.ToString('HH:mm:ss'))."
	$message = Format-LogMessage -Message $message
	Write-Verbose -Message $message
	$message = 'After that sessions will be terminated immediately.'
	$message = Format-LogMessage -Message $message -NoTimeStamp
	Write-Verbose -Message $message

	while (-not $exitProgram) {
		
		$minutesToCutoffTime = New-TimeSpan -Start (Get-Date) -End $cutOffTime.AddSeconds(1) | Select-Object -ExpandProperty Minutes
	
		$message = 'Grace period has passed. Sessions will be terminated immediately.'
		$message = Format-LogMessage -Message $message
		if ($gracePeriodPassed) {
			Write-Verbose -Message $message
		} elseif ($minutesToCutoffTime -le 0) {
			Write-Output $message
			$gracePeriodPassed = $true
		}

		# Query sessions.
		$sessions = Get-RDUserSession | Where-Object UserName -ne ${Env:USERNAME}
		
		if (($sessions | Measure-Object).Count -eq 0) {
			$message = 'No sessions were detected.'
			$message = Format-LogMessage -Message $message
			Write-Verbose -Message $message
		} else {
			$message = "The following sessions where detected:"
			$message = Format-LogMessage -Message $message
			Write-Verbose -Message $message
			foreach($session in $sessions) {
				$message = "SessionID: [$($session.UnifiedSessionID)] Username: [$($session.UserName)]."
				$message = Format-LogMessage -Message $message -NoTimeStamp -Indentation 4
				Write-Verbose -Message $message
			}
		}

		# Remove sessions from queue that do not exist anymore.
		foreach($id in $queuedSessions.GetEnumerator().Name) {
			if ($id -notin ($sessions | Select-Object -ExpandProperty UnifiedSessionID)) {
				$message = "The session with SessionID [$id] and " +
				           "UserName [$($queuedSessions[$id].UserName)] does not exist anymore."
				$message = Format-LogMessage -Message $message
				Write-Verbose -Message $message
				$message = 'Removing the session from the queue.'
				$message = Format-LogMessage -Message $message -NoTimeStamp
				Write-Verbose -Message $message
				$message = "The session with SessionID [$id] and " +
				           "UserName [$($queuedSessions[$id].UserName)] has been terminated."
				$message = Format-LogMessage -Message $message -NoTimeStamp
				Write-Output $message
							
				$queuedSessions[$id].JobHandle.StopJob()
				$queuedSessions.Remove($id)
			}
		}

		# Remove sessions from queue where sessionID and UserName do not match.
		foreach($session in $sessions | Where-Object UnifiedSessionID -in $queuedSessions.Keys) {
			if($queuedSessions[$session.UnifiedSessionID].UserName -ne $session.UserName) {
				$message = "The UserName for SessionID [$($sessions.UnifiedSessionID)] " + 
				           "does not match the UserName of the queued session."			
				$message = Format-LogMessage -Message $message
				Write-Output $message
				$message = "The queued UserName is: [$($queuedSessions[$session.UnifiedSessionID].UserName)]. " +
				           "The current UserName for the session is: [$($session.UserName)]."
				$message = Format-LogMessage -Message $message -NoTimeStamp
				Write-Output $message
				$message = "Removing the sessionfrom the queue, the session with [$($sessions.UnifiedSessionID)] " +
				           "will be queued again."
				$message = Format-LogMessage -Message $message -NoTimeStamp
				Write-Output $message

				$queuedSessions[$session.UnifiedSessionID].JobHandle.StopJob()
				$queuedSessions.Remove($session.UnifiedSessionID)
			}
		}

		# Queue sessions that were not queued yet.
		foreach($session in ($sessions | Where-Object UnifiedSessionID -notin $queuedSessions.Keys)) {			
			$message = "Adding session to the queue. SessionID: [$($session.UnifiedSessionID)], UserName: [$($session.UserName)]"
			$message = Format-LogMessage -Message $message
			Write-Output $message

			if ($gracePeriodPassed) {
				$delay = 0
				$message = 'Grace period has passed. The session will be terminated immediately.'
			} elseif ($session.SessionState -eq 'STATE_DISCONNECTED') {
				$delay = 0
				$message = 'The session is disconnected. It will be terminated immediately.'
			} else {
				$delay = [math]::min($minutesToCutoffTime, $LogoutDelayMinutes)
				$message = "The session is active, it will be terminated at: [$((Get-Date).AddMinutes($delay).ToString('HH:mm:ss'))]."
			}
			$message = Format-LogMessage -Message $message -NoTimeStamp
			Write-Output $message

			$queuedSessions[$session.UnifiedSessionID] = @{
				UserName   = $session.UserName
				LogoutTime = (Get-Date).AddMinutes($delay)
				JobHandle  = Start-RDUserLogout -Session $session -DelayMinutes $delay
			}
		}

		# Log information.
		if ($queuedSessions.Count -eq 0) {
			$message = 'No sessions to terminate.'
			$message = Format-LogMessage -Message $message
			Write-Output $message
		} else {
			$longestLastingSession = $queuedSessions.Values.LogoutTime | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
			$message = "$($queuedSessions.Count) sessions are queued to be terminated. " +
			           "The last session will be terminated at [$($longestLastingSession.ToString('HH:mm:ss'))]."
			$message = Format-LogMessage -Message $message
			Write-Output $message

			$message = 'The following sessions are quequed to be terminated:'
			$message = Format-LogMessage -Message $message
			Write-Verbose -Message $message
			foreach($id in $queuedSessions.Keys) {
				$message = "SessionID: [$id] UserName: [$($queuedSessions[$id].UserName)] " +
				           "LogoutTime: [$($queuedSessions[$id].LogoutTime.ToString('HH:mm:ss'))]"
				$message = Format-LogMessage -Message $message -NoTimeStamp -Indentation 4
				Write-Verbose -Message $message
			}
		}

		$exitProgram = $LogoutOnce -and $sessions.Count -eq 0
		if (-not $exitProgram) {
			Start-Sleep -Seconds $LogoutFrequencySeconds
		}
	}
	$message = 'Currently there are no active sessions. Exiting script.'
	$message = Format-LogMessage -Message $message
	Write-Output $message
}
