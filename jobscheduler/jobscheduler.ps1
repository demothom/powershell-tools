
$DEBUG = $false

class Job {
    [string] $JobName
    [System.Management.Automation.Job] $JobHandle

    [object[]] $Arguments
    [scriptblock] $Work
    [scriptblock] $Init

    [scriptblock] $Running
    [scriptblock] $Completed
    [scriptblock] $Failed

    Job([string]      $JobName, 
        [object[]]    $Arguments,
        [scriptblock] $Work,
        [scriptblock] $Init,
        [scriptblock] $Running,
        [scriptblock] $Completed,
        [scriptblock] $Failed
    ) {

        $parameters = @{
            JobName    = $JobName
            Arguments  = $Arguments
            Work       = $Work
            Init       = $Init
            Running    = $Running
            Completed  = $Completed
            Failed     = $Failed
        }

        $this.Init($parameters)
    }

    Job([hashtable] $Parameters) {
        $this.Init($Parameters)
    }

    hidden [void] Init([hashtable] $Parameters) {
        foreach($ParameterName in $Parameters.Keys) {
            $this.$ParameterName = $Parameters[$ParameterName]
        }     
        # switch ($Parameters.Keys) {
        #     'JobName'     { $this.JobName    = $Parameters.JobName   }
        #     'Arguments'   { $this.Arguments  = $Parameters.Arguments }
        #     'Work'        { $this.Work       = $Parameters.Work      }
        #     'Init'        { $this.Init       = $Parameters.Init      }
        #     'Running'     { $this.Running    = $Parameters.Running   }
        #     'Completed'   { $this.Completed  = $Parameters.Completed }
        #     'Failed'      { $this.Failed     = $Parameters.Failed    }
        # }
    }

    StartJob() {
        $jobParameters = @{
            Name                 = $this.JobName
            InitializationScript = $this.Init
            ScriptBlock          = $this.Work
            ArgumentList         = $this.Arguments
        }

        $this.JobHandle = Start-Job @jobParameters
    }

    [string] GetState() {
        return $this.JobHandle.State
    }

    [timespan] GetUptime() {
        $currentTime = Get-Date
        return New-TimeSpan -Start $this.JobHandle.PSBeginTime -End $currentTime
    }

    InvokeRunningScript() {
        $this.Running.Invoke($this.JobHandle)
    }

    InvokeCompletedScript() {
        $this.Completed.Invoke($this.JobHandle)
    }

    InvokeFailedScript() {
        $this.Failed.Invoke($this.JobHandle)
    }

    StopJob() {
        $this.JobHandle.StopJob()
    }

}

class JobScheduler {
    [System.Timers.Timer] $JobLogTimer
    [scriptblock]         $Logger = { param([string] $Text, [string] $Mode) Write-Host $Text }
    [hashtable]           $JobList

    hidden static [int]   $jobTimerIntervalMilliseconds = 500
    hidden static [int]   $jobTimeoutMinutes = 60
    hidden [timespan]     $jobTimeout

    hidden [scriptblock]  $checkJobs = {
        foreach($job in $this.JobList.GetEnumerator()) {
            switch ($job.GetState()) {
#                'NotStarted'   {  }
                'Running'      { $job.InvokeRunningScript()   }
                'Completed'    { $job.InvokeCompletedScript() }
                'Failed'       { $job.InvokeFailedScript()    }
#                'Stopped'      {  }
#                'Blocked'      {  }
#                'Suspended'    {  }
#                'Disconnected' {  }
#                'Suspending'   {  }
#                'Stopping'     {  }
                Default {}
            }
        }
    }

    JobScheduler() {
        $this.Init($this.Logger)
    }

    JobScheduler([scriptblock] $Logger) {
        $this.Init($Logger)
    }

    hidden [void] Init([scriptblock] $Logger) {
        $this.Logger               = $Logger
        $this.JobList              = [hashtable]::new()
        $this.jobTimeout           = New-TimeSpan -Minutes $this.jobTimeoutMinutes

        $this.JobLogTimer          = [System.Timers.Timer]::new()
        $this.JobLogTimer.Interval = $this.JobTimerIntervalMilliseconds
        $this.JobLogTimer.Start()
        Register-ObjectEvent -InputObject $this.JobLogTimer -EventName 'Elapsed' -Action $this.CheckJobs
    }

    hidden [bool] HasJobTimedout([Job] $Job) {
        return $Job.GetUptime() -gt $this.jobTimeoutMinutes
    }

    hidden [void] TerminateStuckJobs() {
        foreach($job in $this.JobList.GetEnumerator()) {
            if($this.HasJobTimedout($job)) {
                $Job.StopJob()
            }
        }
    }

    AddJob([string]      $JobName, 
           [object[]]    $Arguments,
           [scriptblock] $Work,
           [scriptblock] $Init,
           [scriptblock] $Running,
           [scriptblock] $Completed,
           [scriptblock] $Failed
    ) {
        $parameters = @{
            JobName    = $JobName
            Arguments  = $Arguments
            Work       = $Work
            Init       = $Init
            Running    = $Running
            Completed  = $Completed
            Failed     = $Failed
        }

        $this.AddJob($parameters)
    }

    AddJob([hashtable] $JobParameters) {
        $this.AddJob([Job]::new($JobParameters))
    }

    AddJob([Job] $Job) {
        $this.JobList[$Job.Name] = $Job
    }

    [string] GetJob([string] $JobName) {
        return $this.JobList[$JobName].JobHandle
    }

    StartJob([string] $JobName) {
        $this.JobList[$JobName].StartJob()
    }

    CheckJobs() {
        $this.checkJobs.Invoke()
    }

    RemoveJob([string] $JobName) {
        $this.JobList[$JobName].StopJob()
    }

    CleanupJobs() {
        foreach($jobName in $this.JobList.Keys) {
            $this.RemoveJob($jobName)
        }
    }

}
