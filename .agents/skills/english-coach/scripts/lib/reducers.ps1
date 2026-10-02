Set-StrictMode -Version Latest

function Get-ReducerValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Default = $null
    )
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary] -and $Object.Contains($Name)) { return $Object[$Name] }
    $Property = $Object.PSObject.Properties[$Name]
    if ($null -eq $Property) { return $Default }
    return $Property.Value
}

function Test-ReducerTrue {
    param([AllowNull()][object]$Value)
    if ($Value -is [bool]) { return $Value }
    return ([string]$Value).ToLowerInvariant() -eq 'true'
}

function Get-DistinctReducerCount {
    param([object[]]$Rows, [string]$Property)
    return @($Rows | ForEach-Object { [string](Get-ReducerValue $_ $Property '') } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique).Count
}

function Test-MinimumStudyDaySpan {
    param(
        [AllowEmptyCollection()][object[]]$Rows=@(),
        [int]$MinimumDays=14
    )
    $Dates=@($Rows|ForEach-Object{[string](Get-ReducerValue $_ 'study_date' '')}|Where-Object{$_-match'^\d{4}-\d{2}-\d{2}$'}|ForEach-Object{[datetime]::ParseExact($_,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture)}|Sort-Object)
    return $Dates.Count-ge2-and($Dates[-1]-$Dates[0]).TotalDays-ge$MinimumDays
}

function Resolve-TaskResult {
    param(
        [Parameter(Mandatory = $true)][object[]]$CriterionResults,
        [switch]$NotAssessable
    )
    if ($NotAssessable) { return 'not_assessable' }
    $Rows = @($CriterionResults)
    if ($Rows.Count -eq 0) { throw 'A scored activity requires at least one criterion.' }
    foreach ($Row in $Rows) {
        $Result = [string](Get-ReducerValue $Row 'result' '')
        $Importance = [string](Get-ReducerValue $Row 'importance' '')
        if ($Importance -notin @('essential', 'required')) { throw "Invalid criterion importance: $Importance" }
        if ($Result -notin @('met', 'partial', 'not_met', 'not_observed')) { throw "Invalid criterion result: $Result" }
    }
    if (@($Rows | Where-Object {
        (Get-ReducerValue $_ 'importance' '') -eq 'essential' -and
        (Get-ReducerValue $_ 'result' '') -in @('partial', 'not_met')
    }).Count -gt 0) { return 'failed' }
    if (@($Rows | Where-Object { (Get-ReducerValue $_ 'result' '') -eq 'not_observed' }).Count -gt 0) {
        return 'not_assessable'
    }
    if (@($Rows | Where-Object {
        (Get-ReducerValue $_ 'importance' '') -eq 'required' -and
        (Get-ReducerValue $_ 'result' '') -in @('partial', 'not_met')
    }).Count -gt 0) { return 'partial' }
    return 'success'
}

function Get-EvidenceClass {
    param([Parameter(Mandatory = $true)][object]$Observation)

    $RecordKind = [string](Get-ReducerValue $Observation 'record_kind' 'observation')
    $Validity = [string](Get-ReducerValue $Observation 'validity' '')
    $PrimaryResult = [string](Get-ReducerValue $Observation 'primary_result' '')
    $Outcome = [string](Get-ReducerValue $Observation 'source_session_outcome' 'completed')
    if ($RecordKind -ne 'observation' -or $Validity -ne 'valid' -or
        $PrimaryResult -in @('not_assessable', 'abandoned', '') -or $Outcome -eq 'abandoned' -or
        (Test-ReducerTrue (Get-ReducerValue $Observation 'voided' $false))) {
        return 'none'
    }
    $EvidenceKind = [string](Get-ReducerValue $Observation 'evidence_kind' 'primary')
    if ($EvidenceKind -in @('secondary', 'spontaneous_transfer', 'review_trend', 'self_report')) { return 'B' }

    $EvidenceMode = [string](Get-ReducerValue $Observation 'evidence_mode' 'training')
    $Purpose = [string](Get-ReducerValue $Observation 'purpose' 'practice')
    $Attempt = [int](Get-ReducerValue $Observation 'attempt_no' 1)
    $SupportLevel = [string](Get-ReducerValue $Observation 'support_level' 'none')
    $AEligibleMode = $EvidenceMode -in @('target_check', 'capability_probe', 'assessment', 'difficulty_probe')
    $PurposeEligible = -not ($Purpose -eq 'practice' -and $EvidenceMode -eq 'difficulty_probe')
    $IsPrimary = [string](Get-ReducerValue $Observation 'lead_or_auxiliary' 'lead') -in @('lead', 'auxiliary')
    if ($AEligibleMode -and $PurposeEligible -and $Attempt -eq 1 -and $IsPrimary -and
        (Test-ReducerTrue (Get-ReducerValue $Observation 'independent' $true)) -and
        (Test-ReducerTrue (Get-ReducerValue $Observation 'within_allowed_support' $true)) -and
        -not (Test-ReducerTrue (Get-ReducerValue $Observation 'model_exposed' $false)) -and
        $SupportLevel -notin @('guided', 'demonstration', 'answer_exposed')) {
        return 'A'
    }
    return 'C'
}

function Get-ReviewWeight {
    param([Parameter(Mandatory = $true)][string]$RecipeStage)
    switch ($RecipeStage) {
        'relearn' { return 2 }
        'recall' { return 3 }
        'constrained_transfer' { return 4 }
        default { throw "Invalid recipe_stage: $RecipeStage" }
    }
}

function Select-ReviewQueue {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Items,
        [ValidateSet('normal', 'recovery')][string]$Mode = 'normal'
    )

    $Capacity = if ($Mode -eq 'recovery') { 20 } else { 12 }
    $ItemLimit = if ($Mode -eq 'recovery') { 10 } else { 6 }
    $Queues = @{}
    foreach ($Lane in @('active', 'maintenance', 'legacy')) {
        $Queues[$Lane] = @($Items | Where-Object {
            [string](Get-ReducerValue $_ 'lane' '') -eq $Lane
        } | Sort-Object @{
            Expression = { [string](Get-ReducerValue $_ 'effective_due' (Get-ReducerValue $_ 'next_review' '9999-12-31')) }
        }, @{
            Expression = { [int](Get-ReducerValue $_ 'strength_level' 0) }
        }, @{
            Expression = { [string](Get-ReducerValue $_ 'review_item_id' '') }
        })
    }
    $Indexes = @{ active = 0; maintenance = 0; legacy = 0 }
    $Selected = [System.Collections.Generic.List[object]]::new()
    $Used = 0
    $Stop = $false

    foreach ($Lane in @('active', 'maintenance', 'legacy')) {
        if ($Indexes[$Lane] -ge @($Queues[$Lane]).Count) { continue }
        $Candidate = @($Queues[$Lane])[$Indexes[$Lane]]
        $Weight = Get-ReviewWeight ([string](Get-ReducerValue $Candidate 'recipe_stage' ''))
        if (($Used + $Weight) -gt $Capacity) { $Stop = $true; break }
        $Selected.Add([pscustomobject]@{ lane = $Lane; weight = $Weight; item = $Candidate })
        $Indexes[$Lane]++; $Used += $Weight
    }
    while (-not $Stop -and $Selected.Count -lt $ItemLimit) {
        $Before = $Selected.Count
        foreach ($Lane in @('active', 'legacy', 'maintenance')) {
            if ($Indexes[$Lane] -ge @($Queues[$Lane]).Count) { continue }
            $Candidate = @($Queues[$Lane])[$Indexes[$Lane]]
            $Weight = Get-ReviewWeight ([string](Get-ReducerValue $Candidate 'recipe_stage' ''))
            if (($Used + $Weight) -gt $Capacity) { $Stop = $true; break }
            $Selected.Add([pscustomobject]@{ lane = $Lane; weight = $Weight; item = $Candidate })
            $Indexes[$Lane]++; $Used += $Weight
            if ($Selected.Count -ge $ItemLimit) { break }
        }
        if ($Selected.Count -eq $Before) { break }
    }
    return [pscustomobject]@{
        mode = $Mode
        capacity_units = $Capacity / 2
        capacity_weight = $Capacity
        used_units = $Used / 2
        used_weight = $Used
        selected = @($Selected)
    }
}

function Get-NextReviewDate {
    param([datetime]$StudyDate, [int]$Strength)
    $Intervals = @(1, 3, 7, 14, 30, 60)
    return $StudyDate.AddDays($Intervals[[Math]::Max(0, [Math]::Min(5, $Strength))]).ToString('yyyy-MM-dd')
}

function Apply-ReviewEvent {
    param(
        [Parameter(Mandatory = $true)][object]$Current,
        [Parameter(Mandatory = $true)][object]$Event,
        [object[]]$RecentValidEvents = @(),
        [object[]]$TransferEvidence = @()
    )

    $Result = [string](Get-ReducerValue $Event 'rating' (Get-ReducerValue $Event 'result' ''))
    if ($Result -notin @('again', 'hard', 'good', 'easy', 'invalid')) { throw "Invalid review rating: $Result" }
    $Projection = [ordered]@{}
    foreach ($Property in $Current.PSObject.Properties) { $Projection[$Property.Name] = $Property.Value }
    if ($Result -eq 'invalid') {
        $Projection.last_event_effect = 'none'
        return [pscustomobject]$Projection
    }

    $Stage = [string](Get-ReducerValue $Current 'recipe_stage' 'relearn')
    $Strength = [int](Get-ReducerValue $Current 'strength_level' 0)
    $Status = [string](Get-ReducerValue $Current 'status' 'active')
    $StudyDate = [datetime]::ParseExact(
        [string](Get-ReducerValue $Event 'study_date' ''),
        'yyyy-MM-dd',
        [Globalization.CultureInfo]::InvariantCulture
    )
    if ($Status -eq 'legacy_unverified') {
        switch ($Result) {
            'again' { $Status = 'active'; $Stage = 'relearn'; $Strength = 0 }
            'hard' { $Status = 'active'; $Stage = 'recall'; $Strength = 0 }
            'good' { $Status = 'active'; $Stage = 'constrained_transfer'; $Strength = 1 }
            'easy' { throw 'Legacy positioning does not allow easy.' }
        }
    }
    elseif ($Status -eq 'maintenance') {
        switch ($Result) {
            'again' { $Status = 'active'; $Strength = 0; $Projection.next_review = $StudyDate.AddDays(1).ToString('yyyy-MM-dd') }
            'hard' { $Status = 'active'; $Strength = 4; $Projection.next_review = $StudyDate.AddDays(30).ToString('yyyy-MM-dd') }
            'good' {
                $Interval = [int](Get-ReducerValue $Current 'maintenance_interval_days' 60)
                $Interval = if ($Interval -lt 120) { 120 } else { 180 }
                $Projection.maintenance_interval_days = $Interval
                $Projection.next_review = $StudyDate.AddDays($Interval).ToString('yyyy-MM-dd')
            }
            'easy' {
                $Projection.maintenance_interval_days = 180
                $Projection.next_review = $StudyDate.AddDays(180).ToString('yyyy-MM-dd')
            }
        }
    }
    else {
        switch ($Result) {
            'again' {
                $Strength = 0
                $PreviousAgain = @($RecentValidEvents | Where-Object {
                    [string](Get-ReducerValue $_ 'rating' (Get-ReducerValue $_ 'result' '')) -eq 'again' -and
                    [string](Get-ReducerValue $_ 'study_date' '') -ne $StudyDate.ToString('yyyy-MM-dd')
                } | Select-Object -Last 1)
                if ($PreviousAgain.Count -eq 1) {
                    if ($Stage -eq 'constrained_transfer') { $Stage = 'recall' }
                    elseif ($Stage -eq 'recall') { $Stage = 'relearn' }
                }
            }
            'hard' { $Strength = [Math]::Max(0, $Strength - 1) }
            'good' {
                if ($Stage -eq 'relearn') { $Stage = 'recall'; $Strength = 1 }
                elseif ($Stage -eq 'recall') { $Stage = 'constrained_transfer'; $Strength = 1 }
                else { $Strength = [Math]::Min(5, $Strength + 1) }
            }
            'easy' {
                if ($Stage -ne 'constrained_transfer') { throw 'easy is only valid in constrained_transfer.' }
                $Strength = [Math]::Min(5, $Strength + 2)
            }
        }
        $Projection.next_review = Get-NextReviewDate -StudyDate $StudyDate -Strength $Strength
    }

    $ValidWithCurrent = @($RecentValidEvents) + @($Event)
    $AgainDays = @($ValidWithCurrent | Where-Object {
        [string](Get-ReducerValue $_ 'rating' (Get-ReducerValue $_ 'result' '')) -eq 'again'
    } | ForEach-Object { [string](Get-ReducerValue $_ 'study_date' '') } | Sort-Object -Unique)
    $StrengthZeroAttempts = @($ValidWithCurrent | Where-Object {
        [int](Get-ReducerValue $_ 'old_strength' (Get-ReducerValue $_ 'old_level' 0)) -eq 0
    } | Select-Object -Last 5)
    $ZeroHasSuccess = @($StrengthZeroAttempts | Where-Object {
        [string](Get-ReducerValue $_ 'rating' (Get-ReducerValue $_ 'result' '')) -in @('good', 'easy')
    }).Count -gt 0
    if ($AgainDays.Count -ge 3 -or ($StrengthZeroAttempts.Count -ge 5 -and -not $ZeroHasSuccess)) {
        $Status = 'needs_reteach'
        $Projection.next_review = ''
    }

    $TransferSuccess = @($TransferEvidence | Where-Object {
        [string](Get-ReducerValue $_ 'result' '') -in @('good', 'easy', 'met') -and
        [string](Get-ReducerValue $_ 'recipe_stage' 'constrained_transfer') -eq 'constrained_transfer'
    })
    $HasFormalTransfer = @($TransferSuccess | Where-Object {
        [string](Get-ReducerValue $_ 'evidence_kind' 'formal_review') -eq 'formal_review'
    }).Count -gt 0
    $MaintenanceReady = $Stage -eq 'constrained_transfer' -and $Strength -eq 5 -and
        (Get-DistinctReducerCount $TransferSuccess 'study_date') -ge 2 -and
        (Get-DistinctReducerCount $TransferSuccess 'context_id') -ge 2 -and
        (Test-MinimumStudyDaySpan -Rows $TransferSuccess -MinimumDays 14) -and $HasFormalTransfer
    if ([string](Get-ReducerValue $Current 'review_family' '') -like 'productive_*') {
        $MaintenanceReady = $MaintenanceReady -and @($TransferSuccess | Where-Object {
            Test-ReducerTrue (Get-ReducerValue $_ 'productive_without_word_bank' $false)
        }).Count -gt 0
    }
    if ($MaintenanceReady -and $Result -in @('good', 'easy') -and $Stage -eq 'constrained_transfer') {
        $Status = 'maintenance'
        $Projection.maintenance_interval_days = 60
        $Projection.next_review = $StudyDate.AddDays(60).ToString('yyyy-MM-dd')
    }

    $Projection.recipe_stage = $Stage
    $Projection.strength_level = $Strength
    $Projection.status = $Status
    $Projection.last_review = $StudyDate.ToString('yyyy-MM-dd')
    $Projection.maintenance_ready = [bool]$MaintenanceReady
    $Projection.last_event_effect = 'applied'
    return [pscustomobject]$Projection
}

function New-AdaptationProjection {
    param(
        [Parameter(Mandatory = $true)][string]$AdaptationKey,
        [Parameter(Mandatory = $true)][string]$TargetStep,
        [Parameter(Mandatory = $true)][string]$LoadAxisId
    )
    return [pscustomobject]@{
        adaptation_key = $AdaptationKey
        target_step = $TargetStep
        proposed_step = ''
        load_axis_id = $LoadAxisId
        progress_state = 'target_building'
        required_next = ''
        target_unstable = $false
        resume_progress_state = ''
        hold_phase = ''
        user_hold = $false
        ceiling_reached = $false
        migration_review_required = $false
        target_window = @()
        probe_window = @()
        recovery_window = @()
        first_probe = $null
        intermediate_target = $null
        needs_consolidation = $false
        projection_revision = 0
    }
}

function Test-DiverseSuccesses {
    param(
        [object[]]$Rows,
        [int]$Minimum = 2,
        [int]$MinimumNormal = 1
    )
    $Successes = @($Rows | Where-Object {
        [string](Get-ReducerValue $_ 'core_result' (Get-ReducerValue $_ 'primary_result' '')) -eq 'met'
    })
    return $Successes.Count -ge $Minimum -and
        (Get-DistinctReducerCount $Successes 'day_id') -ge $Minimum -and
        (Get-DistinctReducerCount $Successes 'context_id') -ge 2 -and
        @($Successes | Where-Object { [string](Get-ReducerValue $_ 'cost_signal' '') -eq 'normal' }).Count -ge $MinimumNormal
}

function Update-AdaptationTarget {
    param(
        [Parameter(Mandatory = $true)][hashtable]$State,
        [Parameter(Mandatory = $true)][object]$Observation,
        [switch]$RecoveryMode
    )
    $Window = @($State.target_window) + @($Observation)
    if ($Window.Count -gt 3) { $Window = @($Window | Select-Object -Last 3) }
    $State.target_window = $Window
    $Core = [string](Get-ReducerValue $Observation 'core_result' '')

    if (Test-ReducerTrue $State.target_unstable) {
        if ($Core -eq 'not_met') { $State.recovery_window = @() }
        elseif ($Core -eq 'met') {
            $State.recovery_window = @($State.recovery_window) + @($Observation)
            if (@($State.recovery_window).Count -gt 3) {
                $State.recovery_window = @($State.recovery_window | Select-Object -Last 3)
            }
            if ((Test-DiverseSuccesses -Rows @($State.recovery_window) -Minimum 2) -and -not $RecoveryMode) {
                $HadHold = [string]$State.resume_progress_state -eq 'promotion_hold'
                $State.target_unstable = $false
                if ($HadHold) {
                    $State.progress_state = 'promotion_hold'
                    $State.hold_phase = 'recovering'
                }
                else {
                    $State.progress_state = 'target_building'
                    $State.required_next = 'post_unstable_target_check'
                    $State.probe_window = @()
                }
                $State.last_transition = 'target_stability_restored'
            }
        }
        return [pscustomobject]$State
    }

    $RecentFailures = @($Window | Where-Object {
        [string](Get-ReducerValue $_ 'core_result' '') -eq 'not_met'
    })
    if ($RecentFailures.Count -ge 2 -and (Get-DistinctReducerCount $RecentFailures 'day_id') -ge 2) {
        $State.target_unstable = $true
        $State.resume_progress_state = [string]$State.progress_state
        if ([string]$State.progress_state -eq 'promotion_hold') { $State.hold_phase = 'recovering' }
        $State.recovery_window = @()
        $State.last_transition = 'target_unstable'
        return [pscustomobject]$State
    }

    if ([string]$State.progress_state -eq 'promotion_hold' -and [string]$State.hold_phase -eq 'recovering') {
        if ($Core -eq 'not_met') { $State.recovery_window = @() }
        elseif ($Core -eq 'met') {
            $State.recovery_window = @($State.recovery_window) + @($Observation)
            if (@($State.recovery_window).Count -gt 3) {
                $State.recovery_window = @($State.recovery_window | Select-Object -Last 3)
            }
            if (Test-DiverseSuccesses -Rows @($State.recovery_window) -Minimum 3 -MinimumNormal 2) {
                $State.hold_phase = 'release_ready'
                $State.last_transition = 'hold_release_ready'
            }
        }
        return [pscustomobject]$State
    }
    if ([string]$State.progress_state -eq 'promotion_hold' -and [string]$State.hold_phase -eq 'first_probe_met' -and $Core -eq 'met') {
        $State.intermediate_target = $Observation
        $State.hold_phase = 'confirmation_ready'
        $State.last_transition = 'hold_confirmation_ready'
        return [pscustomobject]$State
    }
    if ([string]$State.progress_state -eq 'confirmation_building' -and [string]$State.required_next -eq 'target_check' -and $Core -eq 'met') {
        $State.intermediate_target = $Observation
        $State.required_next = 'difficulty_probe'
        $State.last_transition = 'promotion_confirmation_ready'
        return [pscustomobject]$State
    }
    if ([string]$State.required_next -eq 'post_unstable_target_check' -and $Core -eq 'met') {
        $State.required_next = ''
        $State.target_window = @($Observation)
        $State.last_transition = 'post_unstable_confirmed'
        return [pscustomobject]$State
    }
    if (Test-ReducerTrue $State.needs_consolidation -and $Core -eq 'met') {
        $State.needs_consolidation = $false
        $State.required_next = ''
        $State.target_window = @($Observation)
        $State.last_transition = 'new_target_consolidated'
        return [pscustomobject]$State
    }
    if ([string]$State.progress_state -eq 'target_building' -and
        -not (Test-ReducerTrue $State.needs_consolidation) -and
        (Test-DiverseSuccesses -Rows $Window -Minimum 2) -and
        [string](Get-ReducerValue $Window[-1] 'cost_signal' '') -eq 'normal') {
        $State.progress_state = 'probe_ready'
        $State.last_transition = 'probe_ready'
    }
    else { $State.last_transition = 'target_recorded' }
    return [pscustomobject]$State
}

function Update-AdaptationProbe {
    param(
        [Parameter(Mandatory = $true)][hashtable]$State,
        [Parameter(Mandatory = $true)][object]$Observation,
        [switch]$CycleProbeAuthorized
    )
    if (Test-ReducerTrue $State.target_unstable) {
        $State.last_transition = 'probe_blocked_unstable'
        return [pscustomobject]$State
    }
    $Challenge = [string](Get-ReducerValue $Observation 'challenge_result' '')
    $ProbeWindow = @($State.probe_window) + @($Observation)
    if ($ProbeWindow.Count -gt 3) { $ProbeWindow = @($ProbeWindow | Select-Object -Last 3) }
    $State.probe_window = $ProbeWindow
    if ($Challenge -eq 'stretch_overload') {
        $State.progress_state = 'promotion_hold'
        $State.hold_phase = 'recovering'
        $State.recovery_window = @()
        $State.last_transition = 'promotion_hold_overload'
        return [pscustomobject]$State
    }
    if ($Challenge -eq 'stretch_not_ready') {
        $Failures = @($ProbeWindow | Where-Object {
            [string](Get-ReducerValue $_ 'challenge_result' '') -eq 'stretch_not_ready'
        })
        if ($Failures.Count -ge 2) {
            $State.progress_state = 'promotion_hold'
            $State.hold_phase = 'recovering'
            $State.recovery_window = @()
            $State.last_transition = 'promotion_hold_repeated_probe_failure'
        }
        else {
            $State.progress_state = 'target_building'
            $State.target_window = @()
            $State.last_transition = 'probe_not_ready'
        }
        return [pscustomobject]$State
    }
    if ($Challenge -ne 'stretch_met') {
        $State.last_transition = 'probe_not_assessable'
        return [pscustomobject]$State
    }

    if ([string]$State.progress_state -eq 'promotion_hold') {
        if (-not $CycleProbeAuthorized -or [string]$State.hold_phase -notin @('release_ready', 'confirmation_ready')) {
            $State.last_transition = 'hold_probe_not_authorized'
            return [pscustomobject]$State
        }
        if ([string]$State.hold_phase -eq 'release_ready') {
            $State.first_probe = $Observation
            $State.hold_phase = 'first_probe_met'
            $State.last_transition = 'hold_first_probe_met'
            return [pscustomobject]$State
        }
        $First = $State.first_probe
        $Intermediate = $State.intermediate_target
        $Diverse = $null -ne $First -and $null -ne $Intermediate -and
            [string](Get-ReducerValue $First 'day_id' '') -ne [string](Get-ReducerValue $Observation 'day_id' '') -and
            [string](Get-ReducerValue $First 'context_id' '') -ne [string](Get-ReducerValue $Observation 'context_id' '')
        $Normal = [string](Get-ReducerValue $First 'cost_signal' '') -eq 'normal' -or
            [string](Get-ReducerValue $Observation 'cost_signal' '') -eq 'normal'
        if ($Diverse -and $Normal) {
            $State.target_step = [string](Get-ReducerValue $Observation 'presented_step' $State.proposed_step)
            $State.progress_state = 'target_building'
            $State.hold_phase = ''
            $State.required_next = 'new_target_consolidation'
            $State.needs_consolidation = $true
            $State.target_window = @()
            $State.probe_window = @()
            $State.recovery_window = @()
            $State.last_transition = 'promoted_from_hold'
        }
        return [pscustomobject]$State
    }

    if ([string]$State.progress_state -eq 'probe_ready') {
        $State.first_probe = $Observation
        $State.progress_state = 'confirmation_building'
        $State.required_next = 'target_check'
        $State.proposed_step = [string](Get-ReducerValue $Observation 'presented_step' '')
        $State.last_transition = 'first_probe_met'
        return [pscustomobject]$State
    }
    if ([string]$State.progress_state -eq 'confirmation_building' -and [string]$State.required_next -eq 'difficulty_probe') {
        $First = $State.first_probe
        $Intermediate = $State.intermediate_target
        $Diverse = $null -ne $First -and $null -ne $Intermediate -and
            [string](Get-ReducerValue $First 'day_id' '') -ne [string](Get-ReducerValue $Observation 'day_id' '') -and
            [string](Get-ReducerValue $First 'context_id' '') -ne [string](Get-ReducerValue $Observation 'context_id' '')
        $Normal = [string](Get-ReducerValue $First 'cost_signal' '') -eq 'normal' -or
            [string](Get-ReducerValue $Observation 'cost_signal' '') -eq 'normal'
        if ($Diverse -and $Normal) {
            $State.target_step = [string](Get-ReducerValue $Observation 'presented_step' $State.proposed_step)
            $State.progress_state = 'target_building'
            $State.required_next = 'new_target_consolidation'
            $State.needs_consolidation = $true
            $State.target_window = @()
            $State.probe_window = @()
            $State.last_transition = 'promoted'
        }
        return [pscustomobject]$State
    }
    $State.last_transition = 'probe_ignored_wrong_state'
    return [pscustomobject]$State
}

function Update-AdaptationProjection {
    param(
        [Parameter(Mandatory = $true)][object]$Current,
        [Parameter(Mandatory = $true)][object]$Observation,
        [switch]$RecoveryMode,
        [switch]$CycleProbeAuthorized
    )

    $State = @{}
    foreach ($Property in $Current.PSObject.Properties) { $State[$Property.Name] = $Property.Value }
    $State.projection_revision = [int](Get-ReducerValue $Current 'projection_revision' 0) + 1
    if ((Get-EvidenceClass $Observation) -ne 'A' -or
        [string](Get-ReducerValue $Observation 'validity' '') -ne 'valid') {
        $State.last_transition = 'ignored_non_a'
        return [pscustomobject]$State
    }
    if ([string](Get-ReducerValue $Observation 'adaptation_key' '') -ne [string]$State.adaptation_key) {
        throw 'Observation adaptation_key does not match the projection.'
    }
    $Mode = [string](Get-ReducerValue $Observation 'evidence_mode' '')
    if ($Mode -notin @('target_check', 'difficulty_probe')) {
        $State.last_transition = 'ignored_non_adaptation_mode'
        return [pscustomobject]$State
    }
    if ((Test-ReducerTrue $State.user_hold) -and $Mode -eq 'difficulty_probe') {
        $State.last_transition = 'probe_blocked_user_hold'
        return [pscustomobject]$State
    }
    if ($RecoveryMode -and $Mode -eq 'difficulty_probe') {
        $State.last_transition = 'probe_blocked_recovery'
        return [pscustomobject]$State
    }
    $Day = [string](Get-ReducerValue $Observation 'day_id' '')
    $UsedToday = @(@($State.target_window) + @($State.probe_window) | Where-Object {
        [string](Get-ReducerValue $_ 'day_id' '') -eq $Day
    }).Count -gt 0
    if ($UsedToday) {
        $State.last_transition = 'ignored_same_day'
        return [pscustomobject]$State
    }
    if ($Mode -eq 'target_check') {
        return Update-AdaptationTarget -State $State -Observation $Observation -RecoveryMode:$RecoveryMode
    }
    return Update-AdaptationProbe -State $State -Observation $Observation -CycleProbeAuthorized:$CycleProbeAuthorized
}

function Get-FocusGoalDecision {
    param(
        [Parameter(Mandatory = $true)][object]$Goal,
        [Parameter(Mandatory = $true)][object[]]$Evidence,
        [Parameter(Mandatory = $true)][int]$CompletedCycles,
        [int]$NoEffectiveProgressStreak = 0
    )

    $GoalId = [string](Get-ReducerValue $Goal 'goal_id' '')
    $A = @($Evidence | Where-Object {
        (Get-EvidenceClass $_) -eq 'A' -and
        [string](Get-ReducerValue $_ 'focus_goal_id' '') -eq $GoalId
    })
    $Opportunities = @($A | Where-Object {
        Test-ReducerTrue (Get-ReducerValue $_ 'prearranged_focus_opportunity' $true)
    })
    if ($Opportunities.Count -lt 2) {
        return [pscustomobject]@{
            decision = 'insufficient_evidence'
            reason_code = 'fewer_than_two_valid_opportunities'
            evidence_ids = @($Opportunities | ForEach-Object { Get-ReducerValue $_ 'observation_id' '' })
            no_effective_progress_streak = $NoEffectiveProgressStreak
        }
    }
    $Success = @($A | Where-Object {
        [string](Get-ReducerValue $_ 'primary_result' (Get-ReducerValue $_ 'core_result' '')) -eq 'met'
    })
    $Criteria = @((Get-ReducerValue $Goal 'required_criterion_ids' @()))
    $CriteriaCovered = $true
    foreach ($Criterion in $Criteria) {
        if (@($Success | Where-Object {
            @((Get-ReducerValue $_ 'criterion_ids' @())) -contains [string]$Criterion
        }).Count -lt 2) { $CriteriaCovered = $false }
    }
    $Confirmation = @($Success | Where-Object {
        (Test-ReducerTrue (Get-ReducerValue $_ 'focus_confirmation' $false)) -and
        ([string](Get-ReducerValue $_ 'cost_signal' '') -eq 'normal')
    }).Count -gt 0
    $UnresolvedCounter = @($A | Where-Object {
        ([string](Get-ReducerValue $_ 'primary_result' (Get-ReducerValue $_ 'core_result' '')) -eq 'not_met') -and
        (Test-ReducerTrue (Get-ReducerValue $_ 'unresolved_counterevidence' $true))
    }).Count -gt 0
    $GuardrailFailure = @($A | Where-Object {
        Test-ReducerTrue (Get-ReducerValue $_ 'guardrail_regressed' $false)
    }).Count -gt 0
    $Met = $CompletedCycles -ge [int](Get-ReducerValue $Goal 'min_completed_cycles' 2) -and
        $Success.Count -ge 3 -and (Get-DistinctReducerCount $Success 'day_id') -ge 2 -and
        (Get-DistinctReducerCount $Success 'context_id') -ge 2 -and $CriteriaCovered -and
        $Confirmation -and -not $UnresolvedCounter -and -not $GuardrailFailure
    if ($Met) {
        return [pscustomobject]@{
            decision = 'met'
            reason_code = 'goal_contract_satisfied'
            evidence_ids = @($Success | ForEach-Object { Get-ReducerValue $_ 'observation_id' '' } | Select-Object -Unique)
            no_effective_progress_streak = 0
        }
    }
    $Markers = @($A | Where-Object {
        [string](Get-ReducerValue $_ 'progress_marker' '') -in @('criterion_acquired', 'support_withdrawal', 'context_transfer')
    })
    if ($Markers.Count -gt 0) {
        return [pscustomobject]@{
            decision = 'continue'
            reason_code = 'new_progress_marker'
            evidence_ids = @($Markers | ForEach-Object { Get-ReducerValue $_ 'observation_id' '' } | Select-Object -Unique)
            no_effective_progress_streak = 0
        }
    }
    $NextStreak = $NoEffectiveProgressStreak + 1
    $Maximum = [int](Get-ReducerValue $Goal 'max_completed_cycles' 4)
    if ($NextStreak -ge 2 -or $CompletedCycles -ge $Maximum) {
        return [pscustomobject]@{
            decision = 'redesign'
            reason_code = $(if ($CompletedCycles -ge $Maximum) { 'maximum_cycle_window_reached' } else { 'two_cycles_without_progress' })
            evidence_ids = @($A | ForEach-Object { Get-ReducerValue $_ 'observation_id' '' } | Select-Object -Unique)
            no_effective_progress_streak = $NextStreak
        }
    }
    return [pscustomobject]@{
        decision = 'continue'
        reason_code = 'first_cycle_without_marker'
        evidence_ids = @($A | ForEach-Object { Get-ReducerValue $_ 'observation_id' '' } | Select-Object -Unique)
        no_effective_progress_streak = $NextStreak
    }
}

function Get-CompetencyCandidate {
    param(
        [Parameter(Mandatory = $true)][object]$Gate,
        [Parameter(Mandatory = $true)][object[]]$Evidence,
        [string]$CurrentStatus = 'not_evidenced',
        [string[]]$CurrentFlags = @(),
        [int]$CurrentCycleNumber = 0
    )
    $CompetencyId = [string](Get-ReducerValue $Gate 'competency_id' (Get-ReducerValue $Gate 'gate_id' ''))
    $Indicators = @((Get-ReducerValue $Gate 'required_indicator_ids' @()))
    if ($Indicators.Count -eq 0) {
        $Indicators = @((Get-ReducerValue $Gate 'indicators' @()) | ForEach-Object {
            [string](Get-ReducerValue $_ 'indicator_id' '')
        })
    }
    $A = @($Evidence | Where-Object {
        (Get-EvidenceClass $_) -eq 'A' -and
        [string](Get-ReducerValue $_ 'competency_id' '') -eq $CompetencyId
    })
    $Flags = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($Flag in $CurrentFlags) { [void]$Flags.Add([string]$Flag) }
    $StableEligible = $Indicators.Count -gt 0
    foreach ($Indicator in $Indicators) {
        $Success = @($A | Where-Object {
            [string](Get-ReducerValue $_ 'indicator_id' '') -eq [string]$Indicator -and
            [string](Get-ReducerValue $_ 'primary_result' (Get-ReducerValue $_ 'core_result' '')) -eq 'met'
        })
        if ($Success.Count -lt 2 -or (Get-DistinctReducerCount $Success 'day_id') -lt 2 -or
            (Get-DistinctReducerCount $Success 'context_id') -lt 2 -or
            @($Success | Where-Object { [string](Get-ReducerValue $_ 'cost_signal' '') -eq 'normal' }).Count -lt 1) {
            $StableEligible = $false
        }
        if ($CurrentStatus -eq 'stable') {
            $Recent = @($A | Where-Object {
                [string](Get-ReducerValue $_ 'indicator_id' '') -eq [string]$Indicator
            } | Sort-Object { [int](Get-ReducerValue $_ 'cycle_number' 0) } | Select-Object -Last 3)
            $Failures = @($Recent | Where-Object {
                [string](Get-ReducerValue $_ 'primary_result' (Get-ReducerValue $_ 'core_result' '')) -eq 'not_met'
            })
            if ($Failures.Count -ge 1) { [void]$Flags.Add('watch') }
            if ($Failures.Count -ge 2 -and (Get-DistinctReducerCount $Failures 'day_id') -ge 2 -and
                (Get-DistinctReducerCount $Failures 'context_id') -ge 2) {
                [void]$Flags.Add('confirmation_due')
            }
        }
    }
    $RecentConfirmation = @($A | Where-Object {
        [string](Get-ReducerValue $_ 'evidence_mode' '') -in @('capability_probe', 'assessment') -and
        $CurrentCycleNumber - [int](Get-ReducerValue $_ 'cycle_number' 0) -le 4
    }).Count -gt 0
    if (-not $RecentConfirmation) { $StableEligible = $false }
    $LastACycle = @($A | ForEach-Object { [int](Get-ReducerValue $_ 'cycle_number' 0) } |
        Measure-Object -Maximum).Maximum
    if ($CurrentStatus -eq 'stable' -and $null -ne $LastACycle -and
        ($CurrentCycleNumber - [int]$LastACycle) -ge 4) {
        [void]$Flags.Add('maintenance_due')
    }
    $Candidate = if ($StableEligible -and $Flags.Count -eq 0) {
        'stable'
    }
    elseif ($A.Count -gt 0) { 'developing' } else { 'not_evidenced' }
    if ($CurrentStatus -eq 'stable' -and $Candidate -ne 'stable') { $Candidate = 'stable' }
    return [pscustomobject]@{
        competency_id = $CompetencyId
        current_status = $CurrentStatus
        candidate_status = $Candidate
        flags = @($Flags | Sort-Object)
        evidence_ids = @($A | ForEach-Object { Get-ReducerValue $_ 'observation_id' '' } | Select-Object -Unique)
        stable_candidate = $StableEligible -and $Flags.Count -eq 0
    }
}

function Test-CycleAllocation {
    param(
        [Parameter(Mandatory = $true)][object[]]$PlanItems,
        [Parameter(Mandatory = $true)][string]$FocusSkill,
        [string[]]$PreviousCycleLeadSkills = @()
    )
    $Training = @($PlanItems | Where-Object {
        [string](Get-ReducerValue $_ 'plan_role' '') -ne 'cycle_review' -and
        [string](Get-ReducerValue $_ 'session_type' '') -ne 'review'
    })
    $Errors = [System.Collections.Generic.List[string]]::new()
    if ($Training.Count -ne 6) { $Errors.Add('A cycle must contain exactly six training items.') }
    $FocusLead = @($Training | Where-Object {
        [string](Get-ReducerValue $_ 'primary_skill' '') -eq $FocusSkill -and
        [string](Get-ReducerValue $_ 'plan_role' '') -eq 'focus'
    }).Count
    if ($FocusLead -lt 2 -or $FocusLead -gt 4) {
        $Errors.Add('Focus lead allocation must be between two and four.')
    }
    foreach ($Skill in @('listening', 'speaking', 'reading', 'writing')) {
        if (@($Training | Where-Object {
            @((Get-ReducerValue $_ 'scored_skills' @())) -contains $Skill -or
            [string](Get-ReducerValue $_ 'primary_skill' '') -eq $Skill
        }).Count -eq 0) {
            $Errors.Add("Cycle lacks a scored $Skill opportunity.")
        }
        if ($Skill -ne $FocusSkill -and $Skill -notin $PreviousCycleLeadSkills -and
            @($Training | Where-Object {
                [string](Get-ReducerValue $_ 'primary_skill' '') -eq $Skill
            }).Count -eq 0) {
            $Errors.Add("Non-focus skill $Skill has no lead across the rolling two-cycle window.")
        }
    }
    return [pscustomobject]@{
        valid = $Errors.Count -eq 0
        errors = @($Errors)
        focus_lead_count = $FocusLead
    }
}

function Select-FocusGap {
    param([Parameter(Mandatory = $true)][object[]]$Candidates)
    $Rank = @{
        confirmed_regression = 1
        blocking_prerequisite = 2
        confirmed_ability_gap = 3
        evidence_gap = 4
        breadth = 5
        authorized_extension = 6
    }
    $Eligible = @($Candidates | Where-Object {
        $Kind = [string](Get-ReducerValue $_ 'gap_kind' '')
        $Kind -ne 'extension' -and $Rank.ContainsKey($Kind)
    } | Sort-Object @{
        Expression = { $Rank[[string](Get-ReducerValue $_ 'gap_kind' '')] }
    }, @{
        Expression = { -[int](Get-ReducerValue $_ 'communication_impact' 0) }
    }, @{
        Expression = { -[int](Get-ReducerValue $_ 'blocked_required_count' 0) }
    }, @{
        Expression = { -[int](Get-ReducerValue $_ 'recurrence_breadth' 0) }
    }, @{
        Expression = { -[int](Get-ReducerValue $_ 'waiting_cycles' 0) }
    }, @{
        Expression = { [int](Get-ReducerValue $_ 'curriculum_order' 999) }
    }, @{
        Expression = { [string](Get-ReducerValue $_ 'competency_id' '') }
    })
    return [pscustomobject]@{
        primary = $(if ($Eligible.Count -gt 0) { $Eligible[0] } else { $null })
        alternative = $(if ($Eligible.Count -gt 1) { $Eligible[1] } else { $null })
    }
}

function Get-StageAttainmentCandidates {
    param(
        [Parameter(Mandatory = $true)][object[]]$Gates,
        [Parameter(Mandatory = $true)][object[]]$CompetencyCandidates
    )
    $Result = [System.Collections.Generic.List[object]]::new()
    foreach ($Group in @($Gates | Where-Object {
        [string](Get-ReducerValue $_ 'role' '') -eq 'required'
    } | Group-Object {
        [string](Get-ReducerValue $_ 'skill' '') + '|' + [string](Get-ReducerValue $_ 'stage_id' '')
    })) {
        $Ids = @($Group.Group | ForEach-Object {
            [string](Get-ReducerValue $_ 'competency_id' (Get-ReducerValue $_ 'gate_id' ''))
        })
        $Projected = @($CompetencyCandidates | Where-Object {
            [string](Get-ReducerValue $_ 'competency_id' '') -in $Ids
        })
        $Blocked = @($Projected | Where-Object {
            [string](Get-ReducerValue $_ 'candidate_status' '') -ne 'stable' -or
            @((Get-ReducerValue $_ 'flags' @())).Count -gt 0
        }).Count -gt 0
        if ($Projected.Count -eq $Ids.Count -and -not $Blocked) {
            $Parts = $Group.Name -split '`|', 2
            $Result.Add([pscustomobject]@{
                skill = $Parts[0]
                stage_id = $Parts[1]
                event_type = 'stage_attained_candidate'
                prerequisite_gate_ids = $Ids
            })
        }
    }
    return @($Result)
}

function Evaluate-LongTermState {
    param(
        [object[]]$Goals = @(),
        [object[]]$Gates = @(),
        [object[]]$Evidence = @(),
        [object[]]$CurrentCompetencies = @(),
        [object[]]$GapCandidates = @(),
        [object[]]$InsightSignals = @(),
        [int]$CurrentCycleNumber,
        [ValidateSet('cycle_review', 'assessment')][string]$Trigger
    )
    $DistinctPrimary = @($Evidence | Where-Object {
        [string](Get-ReducerValue $_ 'observation_id' '') -ne ''
    } | Group-Object { [string](Get-ReducerValue $_ 'observation_id' '') } | ForEach-Object {
        $_.Group | Select-Object -First 1
    })
    if ($DistinctPrimary.Count -gt 12) { throw 'Long-term evidence packet exceeds 12 unique primary observations.' }
    if (@($Evidence).Count -gt 18) { throw 'Long-term evidence packet exceeds 18 projections.' }

    $GoalCandidates = foreach ($Goal in @($Goals | Where-Object {
        [string](Get-ReducerValue $_ 'status' '') -eq 'active'
    })) {
        Get-FocusGoalDecision -Goal $Goal -Evidence $Evidence -CompletedCycles (
            [int](Get-ReducerValue $Goal 'completed_cycles' 0)
        ) -NoEffectiveProgressStreak (
            [int](Get-ReducerValue $Goal 'no_effective_progress_streak' 0)
        )
    }
    $CompetencyCandidates = foreach ($Gate in $Gates) {
        $Id = [string](Get-ReducerValue $Gate 'competency_id' (Get-ReducerValue $Gate 'gate_id' ''))
        $Current = @($CurrentCompetencies | Where-Object {
            [string](Get-ReducerValue $_ 'competency_id' '') -eq $Id
        } | Select-Object -First 1)
        Get-CompetencyCandidate -Gate $Gate -Evidence $Evidence -CurrentStatus $(
            if ($Current.Count -eq 1) {
                [string](Get-ReducerValue $Current[0] 'status' 'not_evidenced')
            }
            else { 'not_evidenced' }
        ) -CurrentFlags $(
            if ($Current.Count -eq 1) { @((Get-ReducerValue $Current[0] 'flags' @())) } else { @() }
        ) -CurrentCycleNumber $CurrentCycleNumber
    }
    $FocusSelection = Select-FocusGap -Candidates $GapCandidates
    $StageCandidates = Get-StageAttainmentCandidates -Gates $Gates -CompetencyCandidates @($CompetencyCandidates)
    return [pscustomobject]@{
        trigger = $Trigger
        goal_candidates = @($GoalCandidates)
        competency_candidates = @($CompetencyCandidates)
        stage_candidates = @($StageCandidates)
        focus_recommendation = $FocusSelection
        insight_candidates = @($InsightSignals | Select-Object -First 3)
        generated_state_only = $true
        requires_plan_confirmation = $true
    }
}
