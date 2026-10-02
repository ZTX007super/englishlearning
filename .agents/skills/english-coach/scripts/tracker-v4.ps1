[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Bootstrap','StartSession','PrepareActivity','PrepareReviewQuestions','SaveReviewAnswer','SaveActivityCheckpoint','StageReviewBatch','FinalizeSession','AbandonSession','EvaluateLongTermState','PublishCycle','MigrationPlan','ActivateV4','Validate')]
    [string]$Action,
    [string]$ProjectRoot,
    [datetime]$Date,
    [string]$SessionId,
    [string]$PlanItemId,
    [string]$OwnerToken,
    [int]$ExpectedRevision = -1,
    [string]$IdempotencyKey,
    [string]$PayloadJson,
    [ValidateSet('network','user-provided','fallback','none')][string]$SourceType = 'none',
    [string]$FaultAfterPhase,
    [switch]$ConfirmActivation,
    [switch]$EnterSession
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RequestTimer = [Diagnostics.Stopwatch]::StartNew()
if ($EnterSession -and $Action -ne 'Bootstrap') { throw 'EnterSession is only valid with Bootstrap.' }
$RequestedStudyDate = $Date
$DateWasBound = $PSBoundParameters.ContainsKey('Date')

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..')).Path
}
else { $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path }

$Libraries=@(
    'lib\state-io.ps1',
    'lib\reducers.ps1',
    'lib\v4-schema.ps1',
    'lib\session-runtime.ps1',
    'lib\transaction-runtime.ps1',
    'lib\maintenance-runtime.ps1'
    'lib\cycle-runtime.ps1'
    'lib\classroom-runtime.ps1'
)
if($Action-in@('Bootstrap','ActivateV4')){$Libraries+='lib\migration-runtime.ps1'}
foreach ($Library in $Libraries) { . (Join-Path $PSScriptRoot $Library) }

$ContextParameters = @{ ProjectRoot = $ProjectRoot }
if ($DateWasBound) { $ContextParameters.Date = $RequestedStudyDate }
$Context = New-V4Context @ContextParameters

switch ($Action) {
    'PublishCycle' {
        $Response=Invoke-V4PublishCycle -Context $Context -Payload (ConvertFrom-V4Payload -PayloadJson $PayloadJson) -IdempotencyKey $IdempotencyKey -FaultAfterPhase $FaultAfterPhase
    }
    'Bootstrap' {
        if ($EnterSession) {
            $Response = Invoke-V4ClassroomBootstrap -Context $Context -IdempotencyKey $IdempotencyKey -FaultAfterPhase $FaultAfterPhase
        } else {
            $Response = Invoke-V4Bootstrap -Context $Context -FaultAfterPhase $FaultAfterPhase
            $Read = Get-V4CurrentSession -Context $Context
            if ($Response.status -eq 'resume' -and $null -ne $Read -and $Read.status -eq 'valid' -and (Test-V4Classroom $Read.value)) {
                $Response = Get-V4ClassroomResponse -Context $Context -Checkpoint $Read.value -Receipt $Response.receipt
            }
        }
    }
    'PrepareReviewQuestions' {
        $Response = Invoke-V4PrepareReviewQuestions -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken `
            -ExpectedRevision $ExpectedRevision -IdempotencyKey $IdempotencyKey -Payload (ConvertFrom-V4Payload -PayloadJson $PayloadJson)
    }
    'SaveReviewAnswer' {
        $Response = Invoke-V4SaveReviewAnswer -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken `
            -ExpectedRevision $ExpectedRevision -IdempotencyKey $IdempotencyKey -Payload (ConvertFrom-V4Payload -PayloadJson $PayloadJson) -FaultAfterPhase $FaultAfterPhase
    }
    'StartSession' {
        $Response = Invoke-V4StartSession -Context $Context -IdempotencyKey $IdempotencyKey `
            -PlanItemId $PlanItemId -SourceType $SourceType -FaultAfterPhase $FaultAfterPhase
    }
    'PrepareActivity' {
        $Payload = ConvertFrom-V4Payload -PayloadJson $PayloadJson
        $Response = Invoke-V4PrepareActivity -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken `
            -ExpectedRevision $ExpectedRevision -IdempotencyKey $IdempotencyKey -Payload $Payload
        $Current=(Get-V4CurrentSession -Context $Context).value
        if (Test-V4Classroom $Current) { $Response=Get-V4ClassroomResponse -Context $Context -Checkpoint $Current -Status 'prepared' -Receipt $Response.receipt }
    }
    'SaveActivityCheckpoint' {
        $Payload = ConvertFrom-V4Payload -PayloadJson $PayloadJson
        $Response = Invoke-V4SaveActivityCheckpoint -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken `
            -ExpectedRevision $ExpectedRevision -IdempotencyKey $IdempotencyKey -Payload $Payload
        $Current=(Get-V4CurrentSession -Context $Context).value
        if (Test-V4Classroom $Current) { $Response=Get-V4ClassroomResponse -Context $Context -Checkpoint $Current -Status 'saved' -Receipt $Response.receipt }
    }
    'StageReviewBatch' {
        $Payload = ConvertFrom-V4Payload -PayloadJson $PayloadJson
        $Response = Invoke-V4StageReviewBatch -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken `
            -ExpectedRevision $ExpectedRevision -IdempotencyKey $IdempotencyKey -Payload $Payload
    }
    'FinalizeSession' {
        $Payload = ConvertFrom-V4Payload -PayloadJson $PayloadJson
        $Response = Invoke-V4EndSession -Context $Context -Disposition completed -SessionId $SessionId `
            -OwnerToken $OwnerToken -ExpectedRevision $ExpectedRevision -IdempotencyKey $IdempotencyKey `
            -Payload $Payload -FaultAfterPhase $FaultAfterPhase
        if ($Response.status -eq 'completed') {
            try {
                $NextIndex=Get-V4BootstrapIndex -Context $Context
                if ($NextIndex.status -eq 'valid' -and -not [string]::IsNullOrWhiteSpace([string]$NextIndex.value.package_path)) {
                    Publish-V4ClassroomTemplate -Context $Context -PackagePath (Join-Path $Context.root $NextIndex.value.package_path)
                }
            } catch { Write-Verbose "Next classroom template preload pending: $($_.Exception.Message)" }
        }
    }
    'AbandonSession' {
        $Payload = ConvertFrom-V4Payload -PayloadJson $PayloadJson
        $Response = Invoke-V4EndSession -Context $Context -Disposition abandoned -SessionId $SessionId `
            -OwnerToken $OwnerToken -ExpectedRevision $ExpectedRevision -IdempotencyKey $IdempotencyKey `
            -Payload $Payload -FaultAfterPhase $FaultAfterPhase
    }
    'EvaluateLongTermState' {
        [void](Assert-V4Active -Context $Context)
        if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
            $Response = Invoke-V4CycleReviewEvaluation -Context $Context -SessionId $SessionId
            break
        }
        $Payload = ConvertFrom-V4Payload -PayloadJson $PayloadJson
        $Evaluation = Evaluate-LongTermState -Trigger ([string](Get-ReducerValue $Payload 'trigger' '')) `
            -CurrentCycleNumber ([int](Get-ReducerValue $Payload 'current_cycle_number' 0)) `
            -Gates @((Get-ReducerValue $Payload 'gates' @())) `
            -Evidence @((Get-ReducerValue $Payload 'evidence' @())) `
            -CurrentCompetencies @((Get-ReducerValue $Payload 'current_competencies' @())) `
            -Goals @((Get-ReducerValue $Payload 'goals' @())) `
            -GapCandidates @((Get-ReducerValue $Payload 'gap_candidates' @())) `
            -InsightSignals @((Get-ReducerValue $Payload 'insight_signals' @()))
        $Response = New-V4Response -Status 'evaluated' -NextAction 'present_cycle_review_candidates' `
            -Receipt ([pscustomobject]@{operation='EvaluateLongTermState';generated_state_only=$true}) `
            -ReasonCode 'plan_confirmation_required' -PreparedStep $Evaluation
    }
    'MigrationPlan' {
        $Response = Get-V4MigrationPlan -Context $Context
    }
    'ActivateV4' {
        $Payload = ConvertFrom-V4Payload -PayloadJson $PayloadJson
        $Response = Invoke-V4ActivateMigration -Context $Context -Payload $Payload -IdempotencyKey $IdempotencyKey `
            -ConfirmActivation:$ConfirmActivation -FaultAfterPhase $FaultAfterPhase
    }
    'Validate' {
        [void](Assert-V4Active -Context $Context)
        $Report = Invoke-V4Validation -Context $Context
        $Response = New-V4Response -Status $Report.status -NextAction $(if ($Report.status -eq 'valid') { 'bootstrap' } else { 'repair_v4_state' }) `
            -Receipt ([pscustomobject]@{ operation = 'validate'; error_count = $Report.error_count; warning_count = $Report.warning_count }) `
            -ReasonCode $(if ($Report.status -eq 'valid') { 'ok' } else { 'validation_failed' }) -PreparedStep $Report
    }
}

$RequestTimer.Stop()
$Response | Add-Member -NotePropertyName metrics -NotePropertyValue ([pscustomobject]@{
    action=$Action;script_elapsed_ms=$RequestTimer.ElapsedMilliseconds
    response_bytes_without_metrics=[Text.Encoding]::UTF8.GetByteCount(($Response | ConvertTo-Json -Depth 30 -Compress))
    model_wait_ms=$null;user_visible_wait_ms=$null
})
$Response | ConvertTo-Json -Depth 30 -Compress
