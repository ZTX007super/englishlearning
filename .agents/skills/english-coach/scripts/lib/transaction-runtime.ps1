Set-StrictMode -Version Latest

function Convert-V4ObservationRow {
    param(
        [Parameter(Mandatory = $true)][object]$Observation,
        [Parameter(Mandatory = $true)][object]$Checkpoint,
        [Parameter(Mandatory = $true)][string]$Timestamp,
        [Parameter(Mandatory = $true)][string]$Disposition
    )
    $Values = [ordered]@{}
    foreach ($Header in $script:V4EvidenceHeaders) { $Values[$Header] = '' }
    $ObservationId = [string](Get-ReducerValue $Observation 'observation_id' '')
    $Values.evidence_id = New-StableIdentifier -Prefix 'E4-' -Seed "$ObservationId|evidence" -HashLength 24
    $Values.session_id = [string]$Checkpoint.session_id
    $Values.skill = [string](Get-ReducerValue $Observation 'skill' $Checkpoint.primary_skill)
    $Values.phase = 'raw'
    $Values.metric = [string](Get-ReducerValue $Observation 'metric' 'task_result')
    $Values.evidence = [string](Get-ReducerValue $Observation 'evidence' '')
    $Values.record_kind = [string](Get-ReducerValue $Observation 'record_kind' 'observation')
    $Values.event_seq = [string](Get-ReducerValue $Observation 'event_seq' 1)
    $Values.recorded_at = $Timestamp
    foreach ($Header in $script:V4EvidenceHeaders) {
        $Property = $Observation.PSObject.Properties[$Header]
        if ($null -ne $Property) {
            $Value = $Property.Value
            if ($Header.EndsWith('_json') -and $Value -isnot [string]) {
                $Values[$Header] = ConvertTo-CanonicalJson -Value $Value
            }
            elseif ($Value -is [bool]) { $Values[$Header] = $Value.ToString().ToLowerInvariant() }
            else { $Values[$Header] = [string]$Value }
        }
    }
    $Values.session_id = [string]$Checkpoint.session_id
    $Values.plan_item_id = [string]$Checkpoint.plan_item_id
    $Values.observation_id = $ObservationId
    $Values.day_id = [string]$Checkpoint.study_date
    if ($script:V4EvidenceHeaders -contains 'source_session_outcome') {
        $Values.source_session_outcome = $Disposition
    }
    return [pscustomobject]$Values
}

function Convert-V4CandidateRow {
    param(
        [Parameter(Mandatory = $true)][object]$Candidate,
        [Parameter(Mandatory = $true)][object]$Checkpoint,
        [Parameter(Mandatory = $true)][string]$Timestamp
    )
    $Values = [ordered]@{}
    foreach ($Header in $script:V4ReviewCandidateHeaders) { $Values[$Header] = '' }
    foreach ($Header in $script:V4ReviewCandidateHeaders) {
        $Property = $Candidate.PSObject.Properties[$Header]
        if ($null -ne $Property) {
            if ($Header.EndsWith('_json') -and $Property.Value -isnot [string]) {
                $Values[$Header] = ConvertTo-CanonicalJson -Value $Property.Value
            }
            elseif ($Property.Value -is [bool]) { $Values[$Header] = $Property.Value.ToString().ToLowerInvariant() }
            else { $Values[$Header] = [string]$Property.Value }
        }
    }
    if ([string]::IsNullOrWhiteSpace($Values.candidate_id)) {
        $Values.candidate_id = New-StableIdentifier -Prefix 'RC-' -Seed "$($Checkpoint.session_id)|$($Values.concept_key)" -HashLength 24
    }
    if ([string]::IsNullOrWhiteSpace($Values.first_seen_at)) { $Values.first_seen_at = $Timestamp }
    $Values.last_seen_at = $Timestamp
    $Values.source_session_id = [string]$Checkpoint.session_id
    if ([string]::IsNullOrWhiteSpace($Values.status)) { $Values.status = 'candidate' }
    return [pscustomobject]$Values
}

function New-V4ReviewTransactionPayload {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Checkpoint,
        [Parameter(Mandatory = $true)][string]$Disposition,
        [Parameter(Mandatory = $true)][string]$Timestamp
    )
    $ReviewItems = @(Get-TsvRows -Path $Context.paths.review_items -Headers $script:V4ReviewItemHeaders)
    $ReviewAudit = @(Get-TsvRows -Path $Context.paths.review_audit -Headers $script:V4ReviewAuditHeaders)
    $EvidenceRows = @(Get-TsvRows -Path $Context.paths.evidence -Headers $script:V4EvidenceHeaders)
    $HistoryRows = [System.Collections.Generic.List[object]]::new()
    $AuditRows = [System.Collections.Generic.List[object]]::new()
    $Updates = [System.Collections.Generic.List[object]]::new()
    $SeenItems = @{}
    foreach ($Batch in @($Checkpoint.pending_review_batches)) {
        foreach ($Staged in @($Batch.items)) {
            $ReviewItemId = [string]$Staged.review_item_id
            if ($SeenItems.ContainsKey($ReviewItemId)) { throw "Review item appears twice in one session: $ReviewItemId" }
            $SeenItems[$ReviewItemId] = $true
            $Current = @($ReviewItems | Where-Object { $_.review_item_id -eq $ReviewItemId })
            if ($Current.Count -ne 1) { throw "Pending review references unknown review item: $ReviewItemId" }
            $AuditValues = [ordered]@{}
            foreach ($Header in $script:V4ReviewAuditHeaders) { $AuditValues[$Header] = '' }
            foreach ($Pair in ([ordered]@{
                audit_id = [string]$Staged.audit_id
                event_id = [string]$Staged.event_id
                batch_id = [string]$Batch.batch_id
                question_instance_id = [string]$Staged.question_instance_id
                review_item_id = $ReviewItemId
                record_kind = 'observation'
                event_seq = '1'
                recorded_at = $Timestamp
                answered_at = [string]$Staged.answered_at
                study_date = [string]$Batch.study_date
                session_id = [string]$Checkpoint.session_id
                source_session_outcome = $Disposition
                idempotency_key = [string]$Batch.idempotency_key
                recipe_stage = [string]$Staged.recipe_stage
                lane = [string]$Staged.lane
                weight = [string]$Staged.weight
                prompt_text = [string]$Staged.prompt_text
                task_contract_json = ConvertTo-CanonicalJson -Value $Staged.task_contract
                answer_excerpt = [string]$Staged.answer_excerpt
                language_validity = [string]$Staged.language_validity
                target_demonstrated = [string]$Staged.target_demonstrated
                rating = [string]$Staged.rating
                rating_reason = [string]$Staged.rating_reason
                invalid_reason = [string]$Staged.invalid_reason
                repair_result_json = ConvertTo-CanonicalJson -Value $Staged.repair_result
                exposed = ([bool]$Staged.exposed).ToString().ToLowerInvariant()
                model_exposed = ([bool]$Staged.model_exposed).ToString().ToLowerInvariant()
            }).GetEnumerator()) { $AuditValues[$Pair.Key] = $Pair.Value }
            $AuditRows.Add([pscustomobject]$AuditValues)
            if ([string]$Staged.rating -eq 'invalid') { continue }

            $Recent = @($ReviewAudit | Where-Object {
                $_.review_item_id -eq $ReviewItemId -and $_.rating -in @('again','hard','good','easy')
            } | Sort-Object answered_at | Select-Object -Last 5)
            $Before = [pscustomobject]([ordered]@{})
            foreach ($Header in $script:V4ReviewItemHeaders) {
                $Before | Add-Member -NotePropertyName $Header -NotePropertyValue ([string]$Current[0].$Header)
            }
            $ReducerEvent = [pscustomobject]@{
                rating = [string]$Staged.rating
                study_date = [string]$Batch.study_date
                old_strength = [string]$Current[0].strength_level
            }
            $PriorFormal = foreach($Audit in @($ReviewAudit|Where-Object{
                $_.review_item_id-eq$ReviewItemId-and$_.recipe_stage-eq'constrained_transfer'-and
                $_.rating-in@('good','easy')-and$_.language_validity-in@('valid','pass')-and
                $_.target_demonstrated-in@('yes','met','true')-and$_.model_exposed-ne'true'-and
                $_.source_session_outcome-ne'abandoned'
            })){
                try{$AuditContract=ConvertFrom-StableJson -Json ([string]$Audit.task_contract_json)}catch{$AuditContract=[pscustomobject]@{}}
                [pscustomobject]@{result=[string]$Audit.rating;recipe_stage='constrained_transfer';evidence_kind='formal_review';study_date=[string]$Audit.study_date;context_id=[string](Get-ReducerValue $AuditContract 'context_id' '');productive_without_word_bank=-not(Test-ReducerTrue(Get-ReducerValue $AuditContract 'uses_word_bank' $false))}
            }
            $Spontaneous = @($EvidenceRows|Where-Object{
                $_.review_item_id-eq$ReviewItemId-and$_.record_kind-eq'observation'-and
                $_.evidence_kind-eq'spontaneous_transfer'-and$_.validity-eq'valid'-and
                $_.source_session_outcome-ne'abandoned'-and$_.model_exposed-ne'true'-and
                $_.primary_result-in@('met','success')
            }|ForEach-Object{[pscustomobject]@{result='met';recipe_stage='constrained_transfer';evidence_kind='spontaneous_transfer';study_date=[string]$_.day_id;context_id=[string]$_.context_id;productive_without_word_bank=[string]$_.support_kind-ne'word_bank'}})
            $CurrentTransfer=@()
            if([string]$Staged.recipe_stage-eq'constrained_transfer'-and[string]$Staged.rating-in@('good','easy')-and
                [string]$Staged.language_validity-in@('valid','pass')-and[string]$Staged.target_demonstrated-in@('yes','met','true')-and-not[bool]$Staged.model_exposed){
                $CurrentContract=Get-ReducerValue $Staged 'task_contract' ([pscustomobject]@{})
                $CurrentTransfer=@([pscustomobject]@{result=[string]$Staged.rating;recipe_stage='constrained_transfer';evidence_kind='formal_review';study_date=[string]$Batch.study_date;context_id=[string](Get-ReducerValue $CurrentContract 'context_id' '');productive_without_word_bank=-not(Test-ReducerTrue(Get-ReducerValue $CurrentContract 'uses_word_bank' $false))})
            }
            $TransferEvidence=@($PriorFormal)+@($Spontaneous)+@($CurrentTransfer)
            $AfterProjection = Apply-ReviewEvent -Current $Before -Event $ReducerEvent -RecentValidEvents $Recent -TransferEvidence $TransferEvidence
            $After = [ordered]@{}
            foreach ($Header in $script:V4ReviewItemHeaders) { $After[$Header] = [string](Get-ReducerValue $AfterProjection $Header '') }
            $After.updated_at = $Timestamp
            $Updates.Add([pscustomobject]@{
                review_item_id = $ReviewItemId
                before_hash = Get-PayloadHash -Payload $Before
                after = [pscustomobject]$After
            })
            $HistoryRows.Add([pscustomobject]@{
                event_id = [string]$Staged.event_id
                reviewed_at = [string]$Staged.answered_at
                study_date = [string]$Batch.study_date
                session_id = [string]$Checkpoint.session_id
                item_type = 'review_item'
                item_id = $ReviewItemId
                result = [string]$Staged.rating
                old_level = [string]$Before.strength_level
                new_level = [string]$After.strength_level
                previous_due = [string]$Before.next_review
                next_review = [string]$After.next_review
            })
        }
    }
    $Classroom=Get-ReducerValue $Checkpoint 'classroom_review' $null
    if ([int](Get-ReducerValue $Checkpoint 'classroom_version' 0) -eq 1 -and $null -ne $Classroom) {
        foreach ($Question in @($Classroom.questions | Where-Object disposition -eq 'exposed')) {
            $Values=[ordered]@{}
            foreach ($Header in $script:V4ReviewAuditHeaders) { $Values[$Header]='' }
            $Values.audit_id=New-StableIdentifier -Prefix 'RA-X-' -Seed "$($Checkpoint.session_id)|$($Question.review_item_id)" -HashLength 24
            $Values.review_item_id=$Question.review_item_id;$Values.record_kind='control';$Values.event_seq='1'
            $Values.recorded_at=$Timestamp;$Values.study_date=$Checkpoint.study_date;$Values.session_id=$Checkpoint.session_id
            $Values.source_session_outcome=$Disposition;$Values.idempotency_key=$Values.audit_id
            $Values.rating_reason='deferred_after_answer_exposure';$Values.exposed='true';$Values.model_exposed='true'
            # No question/answer/score is invented for an unasked target.
            $AuditRows.Add([pscustomobject]$Values)
        }
    }
    return [pscustomobject]@{
        history_rows = @($HistoryRows)
        audit_rows = @($AuditRows)
        item_updates = @($Updates)
    }
}

function New-V4SessionTransaction {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Checkpoint,
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][ValidateSet('completed','abandoned')][string]$Disposition,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey,
        [Parameter(Mandatory = $true)][string]$PayloadHash
    )
    $Timestamp = Get-V4Timestamp -Context $Context
    $ReviewPayload = New-V4ReviewTransactionPayload -Context $Context -Checkpoint $Checkpoint -Disposition $Disposition -Timestamp $Timestamp
    $EvidenceRows = foreach ($Observation in @($Checkpoint.pending_activity_batch)) {
        Convert-V4ObservationRow -Observation $Observation -Checkpoint $Checkpoint -Timestamp $Timestamp -Disposition $Disposition
    }
    $EvidenceRows = @($EvidenceRows) + @(foreach ($Correction in @($Checkpoint.pending_corrections)) {
        Convert-V4ObservationRow -Observation $Correction -Checkpoint $Checkpoint -Timestamp $Timestamp -Disposition $Disposition
    })
    $CandidateRows = foreach ($Candidate in @($Checkpoint.pending_candidates)) {
        Convert-V4CandidateRow -Candidate $Candidate -Checkpoint $Checkpoint -Timestamp $Timestamp
    }
    $GoalRows = @()
    $GoalDecision = Get-ReducerValue $Payload 'goal_decision' $null
    if ($null -ne $GoalDecision) {
        $Decision = [string](Get-ReducerValue $GoalDecision 'decision' '')
        if ($Decision -notin @('met','continue','redesign','insufficient_evidence')) {
            throw "Invalid focus-goal decision: $Decision"
        }
        $GoalId = [string](Get-ReducerValue $GoalDecision 'goal_id' '')
        if ([string]::IsNullOrWhiteSpace($GoalId)) { throw 'goal_decision requires goal_id.' }
        $GoalRows = @([pscustomobject]@{
            event_id = New-StableIdentifier -Prefix 'GE-' -Seed "$($Checkpoint.session_id)|$IdempotencyKey|goal" -HashLength 24
            event_seq = '1'
            occurred_at = $Timestamp
            study_date = [string]$Checkpoint.study_date
            cycle_id = [string]$Checkpoint.plan_id
            goal_id = $GoalId
            decision = $Decision
            reason = [string](Get-ReducerValue $GoalDecision 'reason' '')
            evidence_ids_json = ConvertTo-CanonicalJson -Value @((Get-ReducerValue $GoalDecision 'evidence_ids' @()))
            replacement_goal_id = [string](Get-ReducerValue $GoalDecision 'replacement_goal_id' '')
            catalog_version = [string](Get-ReducerValue $GoalDecision 'catalog_version' '')
            goal_contract_version = [string](Get-ReducerValue $GoalDecision 'goal_contract_version' '')
            idempotency_key = $IdempotencyKey
        })
    }
    $TransactionId = New-StableIdentifier -Prefix 'TX-' -Seed "$($Checkpoint.session_id)|$IdempotencyKey|$Disposition" -HashLength 28
    return [pscustomobject]@{
        schema_version = 4
        transaction_id = $TransactionId
        operation = $(if ($Disposition -eq 'completed') { 'FinalizeSession' } else { 'AbandonSession' })
        disposition = $Disposition
        status = 'pending'
        phase = 'intent'
        idempotency_key = $IdempotencyKey
        payload_hash = $PayloadHash
        session_id = [string]$Checkpoint.session_id
        plan_item_id = [string]$Checkpoint.plan_item_id
        queue_guard = [string]$Checkpoint.queue_guard
        checkpoint_revision = [int]$Checkpoint.revision
        created_at = $Timestamp
        updated_at = $Timestamp
        committed_at = ''
        receipt = $null
        next_plan_item_id = ''
        duration_minutes = [int](Get-ReducerValue $Payload 'duration_minutes' 0)
        session_summary = [string](Get-ReducerValue $Payload 'session_summary' '')
        teaching_outcomes = @($Checkpoint.activity_records | Where-Object { $null -ne (Get-ReducerValue $_ 'followup_state' $null) } | ForEach-Object {
            [pscustomobject]@{activity_id=$_.activity_id;first_result=$_.task_result;followup_result=$_.followup_state.result;support_level=$_.followup_state.support_level;model_exposed=$_.followup_state.model_exposed}
        })
        goal_decision = $GoalDecision
        recovery_mode = [bool]$Checkpoint.review_state.recovery_mode
        facts = [pscustomobject]@{
            evidence_rows = @($EvidenceRows)
            review_history_rows = @($ReviewPayload.history_rows)
            review_audit_rows = @($ReviewPayload.audit_rows)
            candidate_rows = @($CandidateRows)
            goal_event_rows = @($GoalRows)
        }
        projection_updates = [pscustomobject]@{
            review_item_updates = @($ReviewPayload.item_updates)
        }
        error = $null
    }
}

function Apply-V4ReviewItemUpdates {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Updates
    )
    if (@($Updates).Count -eq 0) { return }
    $Rows = @(Get-TsvRows -Path $Context.paths.review_items -Headers $script:V4ReviewItemHeaders)
    foreach ($Update in $Updates) {
        $Match = @($Rows | Where-Object { $_.review_item_id -eq [string]$Update.review_item_id })
        if ($Match.Count -ne 1) { throw "Review projection item disappeared: $($Update.review_item_id)" }
        $CurrentComparable = [ordered]@{}
        $AfterComparable = [ordered]@{}
        foreach ($Header in $script:V4ReviewItemHeaders) {
            $CurrentComparable[$Header] = [string]$Match[0].$Header
            $AfterComparable[$Header] = [string]$Update.after.$Header
        }
        $CurrentHash = Get-PayloadHash -Payload ([pscustomobject]$CurrentComparable)
        $AfterHash = Get-PayloadHash -Payload ([pscustomobject]$AfterComparable)
        if ($CurrentHash -eq $AfterHash) { continue }
        if ($CurrentHash -ne [string]$Update.before_hash) {
            throw "Review projection conflict for $($Update.review_item_id)"
        }
        foreach ($Header in $script:V4ReviewItemHeaders) {
            $Match[0].$Header = [string]$Update.after.$Header
        }
    }
    Write-TsvRowsAtomic -Path $Context.paths.review_items -Rows $Rows -Headers $script:V4ReviewItemHeaders
}

function Apply-V4AdaptationUpdates {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$EvidenceRows,
        [switch]$RecoveryMode
    )
    $Relevant = @($EvidenceRows | Where-Object {
        [string]$_.record_kind -eq 'observation' -and
        -not [string]::IsNullOrWhiteSpace([string]$_.adaptation_key) -and
        $_.evidence_mode -in @('target_check','difficulty_probe')
    })
    if ($Relevant.Count -eq 0) { return }
    $Read = Read-DurableJson -Path $Context.paths.adaptation -AllowMissing
    if ($null -eq $Read) {
        $Projection = [pscustomobject]@{ schema_version = 4; projection_revision = 0; states = @() }
    }
    elseif ($Read.status -ne 'valid') { throw 'Adaptation projection is invalid.' }
    else { $Projection = $Read.value }
    $States = @($Projection.states)
    foreach ($Observation in $Relevant) {
        $State = @($States | Where-Object { $_.adaptation_key -eq [string]$Observation.adaptation_key })
        if ($State.Count -eq 0) {
            $New = New-AdaptationProjection -AdaptationKey ([string]$Observation.adaptation_key) -TargetStep (
                [string]$Observation.target_step
            ) -LoadAxisId ([string]$Observation.load_axis_id)
            $States += $New
            $State = @($New)
        }
        $Updated = Update-AdaptationProjection -Current $State[0] -Observation $Observation -RecoveryMode:$RecoveryMode -CycleProbeAuthorized
        for ($Index = 0; $Index -lt $States.Count; $Index++) {
            if ([string]$States[$Index].adaptation_key -eq [string]$Observation.adaptation_key) {
                $States[$Index] = $Updated
                break
            }
        }
    }
    $Projection.states = @($States)
    $Projection.projection_revision = [int](Get-ReducerValue $Projection 'projection_revision' 0) + 1
    [void](Write-DurableJson -Path $Context.paths.adaptation -Value $Projection)
}

function Apply-V4CycleEvidence {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$EvidenceRows
    )
    $NewRefs = @($EvidenceRows | Where-Object {
        [string]$_.record_kind -eq 'observation' -and
        -not [string]::IsNullOrWhiteSpace([string]$_.observation_id)
    } | ForEach-Object {
        [pscustomobject]@{
            observation_id = [string]$_.observation_id
            competency_id = [string]$_.competency_id
            indicator_id = [string]$_.indicator_id
            evidence_mode = [string]$_.evidence_mode
            primary_result = [string]$_.primary_result
            day_id = [string]$_.day_id
            context_id = [string]$_.context_id
            evidence_id = [string]$_.evidence_id
        }
    })
    if ($NewRefs.Count -eq 0) { return }
    $Read = Read-DurableJson -Path $Context.paths.current_cycle_evidence -AllowMissing
    if ($null -eq $Read) {
        $Projection = [pscustomobject]@{ schema_version = 4; projection_revision = 0; evidence_refs = @(); review_batch_refs = @() }
    }
    elseif ($Read.status -ne 'valid') { throw 'Current-cycle evidence projection is invalid.' }
    else { $Projection = $Read.value }
    $Known = @{}
    foreach ($Ref in @($Projection.evidence_refs)) { $Known[[string]$Ref.observation_id] = $true }
    foreach ($Ref in $NewRefs) {
        if (-not $Known.ContainsKey([string]$Ref.observation_id)) {
            $Projection.evidence_refs = @($Projection.evidence_refs) + @($Ref)
            $Known[[string]$Ref.observation_id] = $true
        }
    }
    if (@($Projection.evidence_refs).Count -gt 18) {
        throw 'Current-cycle evidence projection exceeds 18 bounded references.'
    }
    $Projection.projection_revision = [int](Get-ReducerValue $Projection 'projection_revision' 0) + 1
    [void](Write-DurableJson -Path $Context.paths.current_cycle_evidence -Value $Projection -MaximumBytes 65536)
}

function Update-V4SessionTerminal {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Transaction
    )
    $CheckpointRead = Get-V4CurrentSession -Context $Context
    if ($null -eq $CheckpointRead -or $CheckpointRead.status -ne 'valid') { throw 'Cannot commit terminal state without a valid checkpoint.' }
    $Checkpoint = $CheckpointRead.value
    $Path = Join-Path $Context.root ([string]$Checkpoint.session_file).Replace('/', '\')
    $Text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $Text = [regex]::Replace($Text, '(?m)^status: .*$', ('status: ' + [string]$Transaction.disposition), 1)
    $Text = [regex]::Replace($Text, '(?m)^duration_minutes: .*$', ('duration_minutes: ' + [string]$Transaction.duration_minutes), 1)
    $Text = [regex]::Replace($Text, '(?m)^transaction_id: .*$', ('transaction_id: ' + [string]$Transaction.transaction_id), 1)
    $Text = [regex]::Replace($Text, '(?m)^finalization_id: .*$', ('finalization_id: ' + [string]$Transaction.finalization_id), 1)
    $StartMarker = '<!-- V4:SUMMARY:START -->'
    $EndMarker = '<!-- V4:SUMMARY:END -->'
    $Summary = [string]$Transaction.session_summary
    if ($Summary.Length -gt 2400) { throw 'session_summary exceeds 2400 characters.' }
    foreach ($Outcome in @((Get-ReducerValue $Transaction 'teaching_outcomes' @()))) {
        $Summary += "`r`n- 活动 $($Outcome.activity_id)：首答=$($Outcome.first_result)；后续=$($Outcome.followup_result)；最高帮助=$($Outcome.support_level)；示范暴露=$($Outcome.model_exposed)。"
    }
    $Block = "$StartMarker`r`n## 课程总结`r`n`r`n$Summary`r`n$EndMarker"
    if ($Text.Contains($StartMarker) -and $Text.Contains($EndMarker)) {
        $Text = [regex]::Replace($Text, '(?s)<!-- V4:SUMMARY:START -->.*?<!-- V4:SUMMARY:END -->', [Text.RegularExpressions.MatchEvaluator]{ param($Match) $Block }, 1)
    }
    else { $Text = $Text.TrimEnd() + "`r`n`r`n$Block`r`n" }
    Write-DurableText -Path $Path -Text $Text

    $Checkpoint.status = [string]$Transaction.disposition
    $Checkpoint.updated_at = Get-V4Timestamp -Context $Context
    $Checkpoint.waiting_action = 'none'
    $Checkpoint.pending_persistence = [pscustomobject]@{ phase = 'terminal_written'; reason_code = '' }
    $Checkpoint | Add-Member -NotePropertyName terminal_receipt -NotePropertyValue ([pscustomobject]@{
        transaction_id = [string]$Transaction.transaction_id
        finalization_id = [string]$Transaction.finalization_id
        effective_when = 'transaction_committed'
    }) -Force
    [void](Write-DurableJson -Path $Context.paths.current_session -Value $Checkpoint)
}

function Apply-V4PlanDisposition {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Transaction
    )
    $Plans = @(Get-TsvRows -Path $Context.paths.plans -Headers $script:V4PlanHeaders)
    $Target = @($Plans | Where-Object { $_.plan_item_id -eq [string]$Transaction.plan_item_id })
    if ($Target.Count -ne 1) { throw 'Session transaction plan item is missing.' }
    if ([string]$Transaction.disposition -eq 'completed') {
        if ($Target[0].status -eq 'completed' -and $Target[0].completed_session_id -eq [string]$Transaction.session_id) {
            return $Plans
        }
        if ($Target[0].status -ne 'in_progress') { throw "Cannot complete plan item in status $($Target[0].status)." }
        $Target[0].status = 'completed'
        $Target[0].completed_session_id = [string]$Transaction.session_id
    }
    else {
        if ($Target[0].status -eq 'planned' -and [string]::IsNullOrWhiteSpace($Target[0].completed_session_id)) {
            return $Plans
        }
        if ($Target[0].status -ne 'in_progress') { throw "Cannot abandon plan item in status $($Target[0].status)." }
        $Target[0].status = 'planned'
        $Target[0].completed_session_id = ''
    }
    Write-TsvRowsAtomic -Path $Context.paths.plans -Rows $Plans -Headers $script:V4PlanHeaders
    return $Plans
}

function Update-V4BootstrapIndexAfterTransaction {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Transaction,
        [Parameter(Mandatory = $true)][object[]]$Plans
    )
    $Read = Get-V4BootstrapIndex -Context $Context
    if ($Read.status -ne 'valid') { throw "Cannot update invalid bootstrap index: $($Read.reason_code)" }
    $Old = $Read.value
    $ExposureIds=@()
    $ExposureDay=$Context.study_date.ToString('yyyy-MM-dd')
    $OldExposure=Get-ReducerValue $Old 'review_exposures' $null
    if ($null -ne $OldExposure -and $OldExposure.study_date -eq $ExposureDay) { $ExposureIds=@($OldExposure.item_ids) }
    $ExposureIds=@($ExposureIds)+@($Transaction.facts.review_audit_rows | Where-Object {
        $_.record_kind -eq 'control' -and $_.rating_reason -eq 'deferred_after_answer_exposure' -and $_.study_date -eq $ExposureDay
    } | Select-Object -ExpandProperty review_item_id)
    $ExposureIds=@($ExposureIds | Select-Object -Unique)
    if ($ExposureIds.Count -gt 128) { throw 'Daily exposure guard exceeds the bounded index capacity.' }
    if ([string]$Transaction.queue_guard -ne (Get-V4QueueGuard -Index $Old)) {
        throw 'Session transaction queue guard conflicts with bootstrap index.'
    }
    $Next = @($Plans | Where-Object { $_.status -in @('planned','in_progress') } |
        Sort-Object plan_id, { [int]$_.sequence } | Select-Object -First 1)
    $Descriptor = $null
    if ($Next.Count -eq 1) {
        $Descriptor = @((Get-ReducerValue $Old 'next_package_descriptors' @()) | Where-Object {
            [string](Get-ReducerValue $_ 'plan_item_id' '') -eq [string]$Next[0].plan_item_id
        } | Select-Object -First 1)
        if (@($Descriptor).Count -eq 1) { $Descriptor = $Descriptor[0] } else { $Descriptor = $null }
    }

    $ReviewItems = @(Get-TsvRows -Path $Context.paths.review_items -Headers $script:V4ReviewItemHeaders)
    $Due = foreach ($Item in $ReviewItems) {
        $Status = [string]$Item.status
        if ($Status -notin @('active','maintenance','legacy_unverified')) { continue }
        $Dates = @(@($Item.next_review, $Item.recheck_due) | Where-Object {
            $_ -match '^\d{4}-\d{2}-\d{2}$'
        } | Sort-Object)
        if ($Dates.Count -eq 0 -or [datetime]::ParseExact($Dates[0], 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) -gt $Context.study_date) {
            continue
        }
        [pscustomobject]@{
            review_item_id = [string]$Item.review_item_id
            lane = $(if ($Status -eq 'legacy_unverified') { 'legacy' } else { $Status })
            recipe_stage = [string]$Item.recipe_stage
            strength_level = [int]$Item.strength_level
            effective_due = $Dates[0]
            review_family = [string]$Item.review_family
            target_scope = [string]$Item.target_scope
        }
    }
    $Recovery = [bool](Get-ReducerValue $Old 'recovery_mode' $false)
    $Selection = Select-ReviewQueue -Items @($Due) -Mode $(if ($Recovery) { 'recovery' } else { 'normal' })
    $Selected = @($Selection.selected | ForEach-Object {
        [pscustomobject]@{
            review_item_id = [string]$_.item.review_item_id
            lane = [string]$_.lane
            recipe_stage = [string]$_.item.recipe_stage
            weight = [int]$_.weight
            effective_due = [string]$_.item.effective_due
            review_family = [string]$_.item.review_family
            target_scope = [string]$_.item.target_scope
        }
    })

    $Index = [pscustomobject]@{
        schema_version = 4
        index_revision = [int](Get-ReducerValue $Old 'index_revision' 0) + 1
        review_exposures = [pscustomobject]@{study_date=$ExposureDay;item_ids=$ExposureIds}
        queue_revision = [int](Get-ReducerValue $Old 'queue_revision' 0) + 1
        generated_at = Get-V4Timestamp -Context $Context
        plan_id = $(if ($Next.Count -eq 1) { [string]$Next[0].plan_id } else { '' })
        next_plan_item_id = $(if ($Next.Count -eq 1) { [string]$Next[0].plan_item_id } else { '' })
        next_title = $(if ($Next.Count -eq 1) { [string]$Next[0].title } else { '' })
        session_type = $(if ($Next.Count -eq 1) { [string]$Next[0].session_type } else { '' })
        primary_skill = $(if ($Next.Count -eq 1) { [string]$Next[0].primary_skill } else { '' })
        plan_role = $(if ($Next.Count -eq 1) { [string]$Next[0].plan_role } else { '' })
        focus_goal_id = $(if ($Next.Count -eq 1) { [string]$Next[0].focus_goal_id } else { '' })
        package_path = $(if ($null -ne $Descriptor) { [string](Get-ReducerValue $Descriptor 'package_path' '') } else { '' })
        package_hash = $(if ($null -ne $Descriptor) { [string](Get-ReducerValue $Descriptor 'package_hash' '') } else { '' })
        fallback_package_path = $(if ($null -ne $Descriptor) { [string](Get-ReducerValue $Descriptor 'fallback_package_path' '') } else { '' })
        fallback_package_hash = $(if ($null -ne $Descriptor) { [string](Get-ReducerValue $Descriptor 'fallback_package_hash' '') } else { '' })
        compatible_previous_package_path = ''
        compatible_previous_package_hash = ''
        next_package_descriptors = @((Get-ReducerValue $Old 'next_package_descriptors' @()) | Where-Object {
            [string](Get-ReducerValue $_ 'plan_item_id' '') -ne [string]$Transaction.plan_item_id
        })
        preload_pending = $null -eq $Descriptor
        rebuild_required = $false
        recovery_mode = $Recovery
        review_revision = [int](Get-ReducerValue $Old 'review_revision' 0) + $(if (@($Transaction.projection_updates.review_item_updates).Count -gt 0) { 1 } else { 0 })
        review_due_counts = [pscustomobject]@{
            active = @($Due | Where-Object lane -eq 'active').Count
            maintenance = @($Due | Where-Object lane -eq 'maintenance').Count
            legacy = @($Due | Where-Object lane -eq 'legacy').Count
            total = @($Due).Count
        }
        review_candidates = $Selected
        preauthorized_probe_candidate = $(if ($null -ne $Descriptor) { Get-ReducerValue $Descriptor 'preauthorized_probe_candidate' $null } else { $null })
        adaptation_projection_revision = [int](Get-ReducerValue $Old 'adaptation_projection_revision' 0) + $(if (@($Transaction.facts.evidence_rows | Where-Object { $_.evidence_mode -in @('target_check','difficulty_probe') }).Count -gt 0) { 1 } else { 0 })
        long_term_projection_revision = [int](Get-ReducerValue $Old 'long_term_projection_revision' 0)
        policy_version = [string](Get-ReducerValue $Old 'policy_version' '4.0.0')
        catalog_version = [string](Get-ReducerValue $Old 'catalog_version' '')
        ladder_version = [string](Get-ReducerValue $Old 'ladder_version' '')
        contract_version = [string](Get-ReducerValue $Old 'contract_version' '4.0.0')
        protocol_refs = @((Get-ReducerValue $Old 'protocol_refs' @('references/runtime-protocol-v4.md')))
        last_transaction_id = [string]$Transaction.transaction_id
        request_started_at = ''
        bootstrap_latency_ms = 0
        queue_guard = ''
    }
    $Index.queue_guard = Get-V4QueueGuard -Index $Index
    [void](Write-DurableJson -Path $Context.paths.bootstrap_index -Value $Index -MaximumBytes 65536)
    return $Index
}

function Complete-V4SessionTransaction {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Transaction,
        [string]$FaultAfterPhase
    )
    try {
        if ([string]$Transaction.phase -eq 'intent') {
            $CheckpointRead = Get-V4CurrentSession -Context $Context
            if ($null -eq $CheckpointRead -or $CheckpointRead.status -ne 'valid') {
                throw 'Transaction validation requires a valid current-session checkpoint.'
            }
            $Checkpoint = $CheckpointRead.value
            if ([string]$Checkpoint.session_id -ne [string]$Transaction.session_id -or
                [int]$Checkpoint.revision -ne [int]$Transaction.checkpoint_revision -or
                [string]$Checkpoint.queue_guard -ne [string]$Transaction.queue_guard) {
                throw 'Session transaction checkpoint guard does not match.'
            }
            $Transaction.phase = 'validated'
            $Transaction.updated_at = Get-V4Timestamp -Context $Context
            $Transaction = Write-DurableJson -Path $Context.paths.session_transaction -Value $Transaction
            Invoke-FaultPoint -Name 'transaction_validated' -RequestedFault $FaultAfterPhase
        }

        if ([string]$Transaction.phase -eq 'validated') {
            if (@($Transaction.facts.evidence_rows).Count -gt 0) {
                [void](Add-TsvRowsIdempotent -Path $Context.paths.evidence -Rows @($Transaction.facts.evidence_rows) -Headers $script:V4EvidenceHeaders -IdColumn 'evidence_id')
            }
            if (@($Transaction.facts.review_history_rows).Count -gt 0) {
                [void](Add-TsvRowsIdempotent -Path $Context.paths.review_history -Rows @($Transaction.facts.review_history_rows) -Headers $script:V4ReviewHistoryHeaders -IdColumn 'event_id')
            }
            if (@($Transaction.facts.review_audit_rows).Count -gt 0) {
                [void](Add-TsvRowsIdempotent -Path $Context.paths.review_audit -Rows @($Transaction.facts.review_audit_rows) -Headers $script:V4ReviewAuditHeaders -IdColumn 'audit_id')
            }
            if (@($Transaction.facts.candidate_rows).Count -gt 0) {
                [void](Add-TsvRowsIdempotent -Path $Context.paths.review_candidates -Rows @($Transaction.facts.candidate_rows) -Headers $script:V4ReviewCandidateHeaders -IdColumn 'candidate_id')
            }
            if (@($Transaction.facts.goal_event_rows).Count -gt 0) {
                [void](Add-TsvRowsIdempotent -Path $Context.paths.goal_events -Rows @($Transaction.facts.goal_event_rows) -Headers $script:V4GoalEventHeaders -IdColumn 'event_id')
            }
            $Transaction.phase = 'facts_appended'
            $Transaction.updated_at = Get-V4Timestamp -Context $Context
            $Transaction = Write-DurableJson -Path $Context.paths.session_transaction -Value $Transaction
            Invoke-FaultPoint -Name 'transaction_facts' -RequestedFault $FaultAfterPhase
        }

        if ([string]$Transaction.phase -eq 'facts_appended') {
            Apply-V4ReviewItemUpdates -Context $Context -Updates @($Transaction.projection_updates.review_item_updates)
            Apply-V4AdaptationUpdates -Context $Context -EvidenceRows @($Transaction.facts.evidence_rows) -RecoveryMode:([bool]$Transaction.recovery_mode)
            Apply-V4CycleEvidence -Context $Context -EvidenceRows @($Transaction.facts.evidence_rows)
            $Transaction.phase = 'projections_updated'
            $Transaction.updated_at = Get-V4Timestamp -Context $Context
            $Transaction = Write-DurableJson -Path $Context.paths.session_transaction -Value $Transaction
            Invoke-FaultPoint -Name 'transaction_projections' -RequestedFault $FaultAfterPhase
        }

        if ([string]$Transaction.phase -eq 'projections_updated') {
            Update-V4SessionTerminal -Context $Context -Transaction $Transaction
            $Transaction.phase = 'terminal_written'
            $Transaction.updated_at = Get-V4Timestamp -Context $Context
            $Transaction = Write-DurableJson -Path $Context.paths.session_transaction -Value $Transaction
            Invoke-FaultPoint -Name 'transaction_terminal' -RequestedFault $FaultAfterPhase
        }

        if ([string]$Transaction.phase -eq 'terminal_written') {
            $Plans = @(Apply-V4PlanDisposition -Context $Context -Transaction $Transaction)
            $Transaction.phase = 'plan_updated'
            $Transaction.updated_at = Get-V4Timestamp -Context $Context
            $Transaction = Write-DurableJson -Path $Context.paths.session_transaction -Value $Transaction
            Invoke-FaultPoint -Name 'transaction_plan' -RequestedFault $FaultAfterPhase
        }
        else {
            $Plans = @(Get-TsvRows -Path $Context.paths.plans -Headers $script:V4PlanHeaders)
        }

        if ([string]$Transaction.phase -eq 'plan_updated') {
            $Index = Update-V4BootstrapIndexAfterTransaction -Context $Context -Transaction $Transaction -Plans $Plans
            $Transaction.phase = 'index_updated'
            $Transaction.updated_at = Get-V4Timestamp -Context $Context
            $Transaction | Add-Member -NotePropertyName next_plan_item_id -NotePropertyValue ([string]$Index.next_plan_item_id) -Force
            $Transaction = Write-DurableJson -Path $Context.paths.session_transaction -Value $Transaction
            Invoke-FaultPoint -Name 'transaction_index' -RequestedFault $FaultAfterPhase
        }

        if ([string]$Transaction.phase -eq 'index_updated') {
            $Transaction.phase = 'committed'
            $Transaction.status = 'committed'
            $Transaction.committed_at = Get-V4Timestamp -Context $Context
            $Transaction.receipt = [pscustomobject]@{
                operation = [string]$Transaction.operation
                transaction_id = [string]$Transaction.transaction_id
                finalization_id = [string]$Transaction.finalization_id
                idempotency_key = [string]$Transaction.idempotency_key
                payload_hash = [string]$Transaction.payload_hash
                session_id = [string]$Transaction.session_id
                disposition = [string]$Transaction.disposition
                next_plan_item_id = [string](Get-ReducerValue $Transaction 'next_plan_item_id' '')
            }
            $Transaction = Write-DurableJson -Path $Context.paths.session_transaction -Value $Transaction
            Invoke-FaultPoint -Name 'transaction_commit' -RequestedFault $FaultAfterPhase
        }
        return $Transaction
    }
    catch {
        try {
            $Transaction.error = [pscustomobject]@{
                phase = [string]$Transaction.phase
                message = $_.Exception.Message
                recorded_at = Get-V4Timestamp -Context $Context
            }
            $Transaction.updated_at = Get-V4Timestamp -Context $Context
            [void](Write-DurableJson -Path $Context.paths.session_transaction -Value $Transaction)
        }
        catch { }
        throw
    }
}

function Invoke-V4EndSession {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('completed','abandoned')][string]$Disposition,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][string]$OwnerToken,
        [Parameter(Mandatory = $true)][int]$ExpectedRevision,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey,
        [Parameter(Mandatory = $true)][object]$Payload,
        [string]$FaultAfterPhase
    )
    [void](Assert-V4Active -Context $Context)
    if ([string]::IsNullOrWhiteSpace($IdempotencyKey)) { throw 'Session finalization requires -IdempotencyKey.' }
    return Invoke-WithFileLock -LockPath $Context.paths.lock -Script {
        $PayloadHash = Get-PayloadHash -Payload $Payload
        $ExistingRead = Read-DurableJson -Path $Context.paths.session_transaction -AllowMissing
        if ($null -ne $ExistingRead -and $ExistingRead.status -eq 'valid') {
            $Existing = $ExistingRead.value
            if ([string]$Existing.phase -ne 'committed') {
                if ([string]$Existing.idempotency_key -ne $IdempotencyKey -or
                    [string]$Existing.payload_hash -ne $PayloadHash -or
                    [string]$Existing.session_id -ne $SessionId) {
                    throw 'A different session transaction is pending and must be recovered first.'
                }
                $Completed = Complete-V4SessionTransaction -Context $Context -Transaction $Existing -FaultAfterPhase $FaultAfterPhase
                return New-V4Response -Status ([string]$Completed.disposition) -NextAction 'bootstrap' -Receipt $Completed.receipt -ReasonCode 'transaction_recovered'
            }
            if ([string]$Existing.idempotency_key -eq $IdempotencyKey) {
                if ([string]$Existing.payload_hash -ne $PayloadHash) {
                    throw 'Idempotency key was reused with a different terminal payload.'
                }
                return New-V4Response -Status ([string]$Existing.disposition) -NextAction 'bootstrap' -Receipt $Existing.receipt -ReasonCode 'idempotent_replay'
            }
        }
        $Checkpoint = Get-V4CheckpointForWrite -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken -ExpectedRevision $ExpectedRevision
        if ($Disposition -eq 'completed') {
            if ($Checkpoint.plan_role -eq 'cycle_review') {
                $Goals=@(Get-TsvRows -Path $Context.paths.focus_goals -Headers $script:V4FocusGoalHeaders | Where-Object goal_id -eq $Checkpoint.focus_goal_id)
                if ($Goals.Count -ne 1) { throw 'Cycle review requires exactly one recorded focus goal.' }
                if ($Goals.Count -eq 1) {
                    $Expected=Get-V4PracticalGoalDecision -Context $Context -Checkpoint $Checkpoint -Goal $Goals[0]
                    $Submitted=Get-ReducerValue $Payload 'goal_decision' $null
                    foreach ($Name in @('goal_id','decision','reason','evidence_ids','catalog_version','goal_contract_version')) {
                        if ((Get-PayloadHash (Get-ReducerValue $Submitted $Name $null)) -ne (Get-PayloadHash (Get-ReducerValue $Expected $Name $null))) { throw "Goal decision differs from current persisted evidence: $Name" }
                    }
                }
            }
            if (-not (Test-ReducerTrue (Get-ReducerValue $Payload 'feedback_shown' $false))) {
                throw 'Final feedback or summary must be shown before FinalizeSession.'
            }
            $Required = @(Get-V4RequiredStages -SessionType ([string]$Checkpoint.session_type) `
                -PrimarySkill ([string]$Checkpoint.primary_skill) -PlanRole ([string]$Checkpoint.plan_role))
            if ($null -ne $Checkpoint.prepared_activity -and [string]$Checkpoint.prepared_activity.status -eq 'awaiting_followup') {
                throw 'Finish or explicitly stop the pending main activity followup before finalizing.'
            }
            $CompletedStages = @($Checkpoint.completed_stages) + @('feedback') | Select-Object -Unique
            foreach ($Stage in $Required) {
                if ($Stage -notin $CompletedStages) { throw "FinalizeSession requires completed stage: $Stage" }
            }
            if ([string]$Checkpoint.session_type -eq 'daily' -and @($Checkpoint.pending_activity_batch).Count -lt 1) {
                throw 'A completed daily session requires at least one structured first-answer observation.'
            }
            if ([string]$Checkpoint.plan_role -eq 'focus' -and @($Checkpoint.pending_activity_batch | Where-Object {
                [string](Get-ReducerValue $_ 'focus_goal_id' '') -eq [string]$Checkpoint.focus_goal_id
            }).Count -lt 1) {
                throw 'A completed focus session requires evidence linked to its active focus goal.'
            }
            if ([string]$Checkpoint.plan_role -eq 'cycle_review' -and $null -eq (Get-ReducerValue $Payload 'goal_decision' $null)) {
                throw 'A cycle review requires one frozen focus-goal decision.'
            }
            if ([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Payload 'session_summary' ''))) {
                throw 'FinalizeSession requires a concise session_summary.'
            }
        }
        $Duration = [int](Get-ReducerValue $Payload 'duration_minutes' 0)
        if ($Duration -lt 0 -or $Duration -gt 600) { throw 'duration_minutes must be between 0 and 600.' }
        $Transaction = New-V4SessionTransaction -Context $Context -Checkpoint $Checkpoint -Payload $Payload -Disposition $Disposition -IdempotencyKey $IdempotencyKey -PayloadHash $PayloadHash
        $Transaction | Add-Member -NotePropertyName finalization_id -NotePropertyValue (
            New-StableIdentifier -Prefix 'F-' -Seed "$SessionId|$IdempotencyKey|$Disposition" -HashLength 24
        ) -Force
        $Transaction = Write-DurableJson -Path $Context.paths.session_transaction -Value $Transaction
        Invoke-FaultPoint -Name 'transaction_intent' -RequestedFault $FaultAfterPhase
        $Completed = Complete-V4SessionTransaction -Context $Context -Transaction $Transaction -FaultAfterPhase $FaultAfterPhase
        return New-V4Response -Status $Disposition -NextAction 'bootstrap' -Receipt $Completed.receipt
    }
}
