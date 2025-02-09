
$script:defaultPopUpMessageTitle      = 'Maintenance'
$script:defaultPopUpMessageBody       = 'Due to maintenance your current session will be terminated in {0}. ' +
                                        'Please safe all open documents or unsafed progress may be lost.'

$script:defaultLogoutDelayMinutes     = 2
$script:defaultLogoutFrequencySeconds = 10
$script:defaultGracePeriodMinutes     = 5

$script:defaultTimeStampFormat        = 'HH:mm:ss'

<#
.SYNOPSIS
Outputs messages to the console with a timestamp.

.DESCRIPTION
The provided text is prefixed with a timestamp and written to the console. The timestamp has the
format 'HH:mm:ss', followed by a colon and a space.
The default Write-[Stream] commandlets are used to output the text. These can be chosen with the
parameter Mode. The default output stream used is the Write-Output commandlet. More than one
stream can be chosen for the Mode parameter. In this case the text is put to each of them.

.PARAMETER Message
The text to be written.

.PARAMETER Mode
The stream to which the text should be written. Possible values are 'Output', 'Information', 'Verbose', 
'Debug', 'Warning', 'Error', 'Host'. More than one stream can be provided. In this case, he text is
written to each chosen stream.

.PARAMETER Indentation
An optional paramter to indent the text by Indentation times of spaces. The spaces are inserted
between the timestamp and the text.

.PARAMETER TimeStampFormat
An optional paramter to format the timestamp. If an invalid format is given, the default format
'HH:mm:ss' is used.

.PARAMETER NoTimeStamp
If provided the timestamp is replaced by an equal amount of spaces, in the default case the
text is indentet by 10 spaces.

.EXAMPLE
Write-Log -Message 'This is a message.'

Writes a message into the output stream.

.EXAMPLE
Write-Log -Message 'This is another message.' -Mode 'Verbose'

Writes a text into the verbose stream.

.EXAMPLE
Write-Log -Message 'This is a header. Here are some more lines:'     -Mode 'Output', 'Verbose'
Write-Log -Message 'This is some more text, but writte without the ' -Mode 'Output', 'Verbose' -NoTimeStamp
Write-Log -Message 'timestamp, so it is clear, that this is a text'  -Mode 'Output', 'Verbose' -NoTimeStamp
Write-Log -Message 'spanning multiple lines.                         -Mode 'Output', 'Verbose' -NoTimeStamp

This example omits the timestamp for each but the first line to show that it is a multiline text. The
messages are written to Write-Output and Write-Verbose.

.NOTES
If called directly, the -Verbose, -Debug and -InformationAction Continue parameters have to be provided.
Those messages are printet, if the switches or preferences have been set in the calling function.
#>
function Write-Log {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string] $Message,

		[ValidateSet('Output', 'Information', 'Verbose', 'Debug', 'Warning', 'Error', 'Host')]
		[string[]] $Mode = 'Output',

		[ValidateRange(0, 64)]
		[int] $Indentation = 0,

		[string] $TimeStampFormat = $script:defaultTimeStampFormat,

		[switch] $NoTimeStamp
	)

	try {
		$timestamp = Get-Date -Format $TimeStampFormat
	} catch {
		$timestamp = Get-Date -Format $script:defaultTimeStampFormat
	}
	$timestampPrefix = "${timestamp}: "
	if ($NoTimeStamp) {
		$timestampPrefix = ' ' * $timestampPrefix.Length
	}
	$indentationPrefix = ' ' * $Indentation
	$text = "$timestampPrefix" + "$indentationPrefix" + "$Message"
	
	foreach($logMode in $Mode) {
		Invoke-Expression -Command "Write-$logMode ""$text"""
	}
}

<#
.SYNOPSIS
Terminates a remote session.

.DESCRIPTION
Terminates the remote session given by its session ID. A delay can be provided after which the session is terminated.
In this case, the user is notified with a message about the impending logout. The logout script is run as a background
job wich pauses until the delay has passed. The job object is returned to the caller

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
		[Parameter(Mandatory, ValueFromPipeline)]
		[Parameter(ParameterSetName = 'SessionID')]
		[ValidateScript({ $null -ne (Get-RDUserSession | Where-Object UnifiedSessionID -eq $_) })]
		[int] $SessionID,

		[Parameter(ParameterSetName = 'SessionID')]
		[string] $HostServer = ${env:COMPUTERNAME},

		[Parameter(Mandatory, ValueFromPipeline)]
		[Parameter(ParameterSetName = 'Session')]
		[ValidateNotNull()]
		[Microsoft.RemoteDesktopServices.Management.RDUserSession] $Session,

		[int] $DelayMinutes    = $script:defaultLogoutDelayMinutes,

		[string] $MessageTitle = $script:defaultPopUpMessageTitle,

		[string] $MessageBody  = $script:defaultPopUpMessageBody
	)

	process {
		if ($PSCmdlet.ParameterSetName -eq 'SessionID') {
			$Session = Get-RDUserSession | Where-Object UnifiedSessionID -eq $SessionID
		}
		
		$arguments = $Session.UnifiedSessionID, $Session.UserName, $DelayMinutes, $Session.HostServer

		$logoutScript = [scriptblock] {
			param(
				$SessionID,
				$UserName,
				$DelayMinutes,
				$HostServer
			)

			if($DelayMinutes -gt 0) {
				$delayDisplayText = "$DelayMinutes minute"
				if($DelayMinutes -gt 1) {
					$delayDisplayText += 's'
				}

				$title = $MessageTitle
				$body  = $MessageBody -f $delayDisplayText
				Send-RDUserMessage -HostServer $HostServer -UnifiedSessionID $SessionID -MessageTitle $title -MessageBody $body
				Start-Sleep -Seconds ($DelayMinutes * 60)
			}

			$Session = Get-RDUserSession | Where-Object UnifiedSessionID -eq $SessionID
			if($Session.UserName -eq $UserName) {
				Invoke-RDUserLogoff -HostServer $HostServer -UnifiedSessionID $SessionID
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
	
	$cutOffTime = Get-Date.AddMinutes($GracePeriodMinutes)
	$queuedSessions = [hashtable]::new()
	$exitProgram = $false

	$message = 'Logging out users.'
	Write-Log -Message $message -Mode 'Output', 'Verbose'
	$message = "Active sessions will be terminated after $LogoutDelayMinutes Minutes."
	Write-Log -Message $message -Mode 'Verbose'
	$message = 'Disconnected sessions will be terminated instantly.'
	Write-Log -Message $message -Mode 'Verbose'
	$message = "The grace period is $GracePeriodMinutes minutes, it lasts until $($cutOffTime.ToString('HH:mm:ss'))."
	Write-Log -Message $message -Mode 'Verbose'
	$message = 'After that sessions will be terminated immediately.'
	Write-Log -Message $message -Mode 'Verbose' -NoTimeStamp

	while (-not $exitProgram) {
		
		$minutesToCutoffTime = New-TimeSpan -Start (Get-Date) -End $cutOffTime.AddSeconds(1) | Select-Object -ExpandProperty Minutes
		if ($minutesToCutoffTime -le 0) {
			$message = 'Grace period reached. Sessions will be terminated immediately.'
			Write-Log -Message $message -Mode 'Verbose'
		}

		# Query sessions.
		$sessions = Get-RDUserSession | Where-Object UserName -ne ${Env:USERNAME}

		if (($sessions | Measure-Object).Count -eq 0) {
			$message = 'No sessions were detected.'
			Write-Log -Message $message 'Verbose'
		} else {
			$message = "The following sessions where detected:"
			Write-Log -Message $message -Mode 'Verbose'
			foreach($session in $sessions) {
				$message = "SessionID: [$($session.UnifiedSessionID)] Username: [$($session.UserName)]."
				Write-Log -Message $message -Mode 'Verbose' -NoTimeStamp -Indentation 4
			}
		}

		# Remove sessions from queue that do not exist anymore.
		foreach($id in $queuedSessions.Keys) {
			if ($id -notin ($sessions | Select-Object -ExpandProperty UnifiedSessionID)) {
				$message = "The session with SessionID [$id] and " +
				           "UserName [$($queuedSessions[$id].UserName)] does not exist anymore."
				Write-Log -Message $message -Mode 'Verbose'
				$message = 'Removing the session from the queue.'
				Write-Log -Message $message -Mode 'Verbose' -NoTimeStamp
							
				$queuedSessions[$session.UnifiedSessionID].JobHandle.Stop()
				$queuedSessions.Remove($id)
			}
		}

		# Remove sessions from queue where sessionID and UserName do not match.
		foreach($session in $sessions) {
			if($queuedSessions[$session.UnifiedSessionID].UserName -ne $session.UserName) {
				$message = "The UserName for SessionID [$($sessions.UnifiedSessionID)] does not match queued UserName."				
				Write-Log -Message $message -Mode 'Verbose'
				$message = "The queued UserName is: [$($queuedSessions[$session.UnifiedSessionID].UserName)]. " +
				           "The current UserName for the session is: [$($session.UserName)]."
				Write-Log -Message $message -Mode 'Verbose' -NoTimeStamp
				$message = 'Removing the sessionfrom the queue'
				Write-Log -Message $message -Mode 'Verbose' -NoTimeStamp

				$queuedSessions[$session.UnifiedSessionID].JobHandle.Stop()
				$queuedSessions.Remove($session.UnifiedSessionID)
			}
		}

		# Queue sessions that were not queued yet.
		foreach($session in ($sessions | Where-Object UnifiedSessionID -notin $queuedSessions.Keys)) {			
			$message = "Adding session to the queue. SessionID: [$($session.UnifiedSessionID)], UserName: [$($session.UserName)]"
			Write-Log -Message $message -Mode 'Output', 'Verbose'

			if ($session.SessionState -eq 'STATE_DISCONNECTED') {
				$delay = 0

				$message = 'The session is disconnected. It will be terminated immediately.'
				Write-Log -Message $message -Mode 'Verbose' -NoTimeStamp
			} else {
				$delay = [math]::min($minutesToCutoffTime, $LogoutDelayMinutes)

				$message = "The session is active, it will be terminated at: [$((Get-Date).AddMinutes($delay).ToString('HH:mm:ss'))]."
				Write-Log -Message $message -Mode 'Verbose' -NoTimeStamp
			}

			$queuedSessions[$session.UnifiedSessionID] = @{
				UserName  = $session.UserName
				LogoutTime = (Get-Date).AddMinutes($delay)
				JobHandle = Start-RDUserLogout -Session $session -DelayMinutes $delay
			}
		}

		# Log information.
		if ($sessions.Count -eq 0) {
			$message = 'No sessions to terminate.'
			Write-Log -Message $message -Mode 'Output', 'Verbose'
		} else {
			$longestLastingSession = $sessions.Values.LogoutTime | Measure-Object -Maximum
			$message = "$($sessions.Count) sessions are queued to be terminated. " +
			           "The last session will be terminated at [$($longestLastingSession.ToString('HH:mm:ss'))]."
			Write-Log -Message $message -Mode 'Output', 'Verbose'

			$message = 'The following sessions are quequed to be terminated:'
			Write-Log -Message $message -Mode 'Verbose'
			foreach($id in $queuedSessions.Keys) {
				$message = "SessionID: [$id] UserName: [$($queuedSessions[$id].UserName)] " +
				           "LogoutTime: [$($queuedSessions[$id].LogoutTime.ToString('HH:mm:ss'))]"
				Write-Log -Message $message -Mode 'Verbose' -NoTimeStamp
			}
		}

		$exitProgram = $LogoutOnce -and $sessions.Count -eq 0
		if (-not $exitProgram) {
			Start-Sleep -Seconds $LogoutFrequencySeconds
		}
	}
	$message = 'Currently there are no active sessions. Exiting script.'
	Write-Log -Message $message -Mode 'Output', 'Verbose'
}
