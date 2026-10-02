# Loaded after tracker-v4 shared fixtures.
function New-PracticalGoalFixture {
    $Root=New-V4Fixture
    $Context=New-V4Context -ProjectRoot $Root
    $Template=@(Get-TsvRows -Path $Context.paths.plans -Headers $script:V4PlanHeaders)[0]
    $Plans=@(foreach ($Spec in @(@('P-old','C0004','focus','S-old'),@('R-old','C0004','cycle_review','S-review'),@('P-now1','C0005','focus','S-now1'),@('P-now2','C0005','focus','S-now2'),@('R-now','C0005','cycle_review',''))) {
        $Row=ConvertFrom-StableJson (ConvertTo-CanonicalJson $Template)
        $Row.plan_item_id=$Spec[0];$Row.plan_id=$Spec[1];$Row.plan_role=$Spec[2];$Row.completed_session_id=$Spec[3];$Row.focus_goal_id='FG-test'
        $Row.status=if ($Spec[3]) {'completed'} else {'planned'}
        $Row.session_type=if ($Spec[2] -eq 'cycle_review') {'review'} else {'integrated'}
        $Row
    })
    Write-TsvRowsAtomic -Path $Context.paths.plans -Rows $Plans -Headers $script:V4PlanHeaders
    $Contract=[pscustomobject]@{schema_version=1;catalog_version='1.0.0';indicator_id='IND-1';anchor_id='A2';required_criterion_ids=@('CR-1');guardrail_criterion_ids=@();confirmation_evidence_mode='assessment'}
    $Goal=[ordered]@{};foreach($Header in $script:V4FocusGoalHeaders){$Goal[$Header]=''}
    foreach ($Pair in @{goal_id='FG-test';goal_key='explain';version='1';status='active';start_cycle_id='C0004';min_completed_cycles='2';max_completed_cycles='4';competency_id='COMP-1';activity_family='opinion_explanation';success_criteria_json=(ConvertTo-CanonicalJson $Contract)}.GetEnumerator()) {$Goal[$Pair.Key]=$Pair.Value}
    Write-TsvRowsAtomic -Path $Context.paths.focus_goals -Rows @([pscustomobject]$Goal) -Headers $script:V4FocusGoalHeaders
    $Rows=@(foreach ($Spec in @(@('P-old','S-old','C0004','2026-09-01','target_check'),@('P-now1','S-now1','C0005','2026-09-05','target_check'),@('P-now2','S-now2','C0005','2026-09-06','assessment'))) {
        $Obs=(New-SavePayload -ActivityId $Spec[0] -Stage output).observation
        $Values=[ordered]@{}; foreach ($Header in $script:V4EvidenceHeaders) {$Values[$Header]=[string](Get-ReducerValue $Obs $Header '')}
        foreach ($Pair in @{evidence_id="EV-$($Spec[0])";observation_id="O-$($Spec[0])";record_kind='observation';plan_item_id=$Spec[0];session_id=$Spec[1];day_id=$Spec[3];evidence_mode=$Spec[4];source_session_outcome='completed';attempt_no='1';focus_goal_id='FG-test';criterion_results_json='[{"criterion_id":"CR-1","importance":"essential","result":"met"}]'}.GetEnumerator()) {$Values[$Pair.Key]=$Pair.Value}
        [pscustomobject]$Values
    })
    Write-TsvRowsAtomic -Path $Context.paths.evidence -Rows $Rows -Headers $script:V4EvidenceHeaders
    $Index=(Read-DurableJson -Path $Context.paths.bootstrap_index).value
    $Index.plan_id='C0005';$Index.next_plan_item_id='R-now';$Index.plan_role='cycle_review';$Index.session_type='review';$Index.focus_goal_id='FG-test';$Index.queue_guard=Get-V4QueueGuard $Index
    $PackagePath=Join-Path $Root $Index.package_path
    $Package=(Read-DurableJson -Path $PackagePath).value
    $Package.plan_item_id='R-now';$Package.plan_id='C0005';$Package.plan_role='cycle_review';$Package.focus_goal_id='FG-test'
    [void](Write-DurableJson -Path $PackagePath -Value $Package)
    $Index.package_hash=Get-FileSha256 $PackagePath
    $Index.queue_guard=Get-V4QueueGuard $Index
    [void](Write-DurableJson -Path $Context.paths.bootstrap_index -Value $Index)
    $Start=Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='goal-review'}
    return [pscustomobject]@{root=$Root;context=$Context;start=$Start;goal=[pscustomobject]$Goal;rows=$Rows;checkpoint=(Read-DurableJson -Path $Context.paths.current_session).value}
}

Describe 'Practical cross-cycle focus decisions' {
    It 'evaluates and commits met from persisted cross-cycle evidence and rejects a forged decision' {
        $F=New-PracticalGoalFixture
        $Result=Invoke-V4Json -Root $F.root -Arguments @{Action='EvaluateLongTermState';SessionId=$F.start.receipt.session_id}
        $Candidate=$Result.prepared_step.goal_candidates[0]
        $Candidate.decision | Should Be 'met'
        $Candidate.coverage.completed_cycles | Should Be 2
        @($Candidate.evidence_ids).Count | Should Be 3
        $Payload=@{feedback_shown=$true;session_summary='Goal confirmed across two cycles.';duration_minutes=10;goal_decision=$Candidate}
        $Candidate.decision='continue'
        $Args=@{Action='FinalizeSession';SessionId=$F.start.receipt.session_id;OwnerToken=$F.checkpoint.lease.owner_token;ExpectedRevision=$F.checkpoint.revision;IdempotencyKey='final-goal';PayloadJson=($Payload|ConvertTo-Json -Depth 20 -Compress)}
        Assert-ThrowsV4 {Invoke-V4Json -Root $F.root -Arguments $Args}
        $Candidate.decision='met';$Args.PayloadJson=$Payload|ConvertTo-Json -Depth 20 -Compress
        (Invoke-V4Json -Root $F.root -Arguments $Args).status | Should Be 'completed'
        (Invoke-V4Json -Root $F.root -Arguments $Args).reason_code | Should Be 'idempotent_replay'
        @(Get-TsvRows -Path $F.context.paths.goal_events -Headers $script:V4GoalEventHeaders).Count | Should Be 1
    }
    It 'continues without a confirmation and redesigns after a second evidence-sufficient stagnant cycle' {
        $F=New-PracticalGoalFixture
        $F.rows[2].evidence_mode='target_check'
        Write-TsvRowsAtomic -Path $F.context.paths.evidence -Rows $F.rows -Headers $script:V4EvidenceHeaders
        (Get-V4PracticalGoalDecision $F.context $F.checkpoint $F.goal).decision | Should Be 'continue'
        Write-TsvRowsAtomic -Path $F.context.paths.goal_events -Rows @([pscustomobject]@{event_id='GE-previous';goal_id='FG-test';cycle_id='C0004';decision='continue';reason='first_cycle_without_marker'}) -Headers $script:V4GoalEventHeaders
        (Get-V4PracticalGoalDecision $F.context $F.checkpoint $F.goal).decision | Should Be 'redesign'
    }
    It 'does not inflate current opportunities with old, supported, void or duplicate evidence' {
        $F=New-PracticalGoalFixture
        $F.rows[2].support_level='guided'
        Write-TsvRowsAtomic -Path $F.context.paths.evidence -Rows $F.rows -Headers $script:V4EvidenceHeaders
        (Get-V4PracticalGoalDecision $F.context $F.checkpoint $F.goal).decision | Should Be 'insufficient_evidence'
        $F.rows[2].support_level='none'
        Write-TsvRowsAtomic -Path $F.context.paths.evidence -Rows (@($F.rows)+@($F.rows[0])) -Headers $script:V4EvidenceHeaders
        (Get-V4PracticalGoalDecision $F.context $F.checkpoint $F.goal).reason | Should Be 'evidence_audit_required'
        $Void=[pscustomobject]@{record_kind='void';ref_observation_id=$F.rows[0].observation_id}
        Write-TsvRowsAtomic -Path $F.context.paths.evidence -Rows (@($F.rows)+@($Void)) -Headers $script:V4EvidenceHeaders
        (Get-V4PracticalGoalDecision $F.context $F.checkpoint $F.goal).reason | Should Be 'evidence_audit_required'
    }
    It 'keeps a legacy text contract honest rather than inventing criteria' {
        $F=New-PracticalGoalFixture
        $F.goal.success_criteria_json='["clear reason"]'
        (Get-V4PracticalGoalDecision $F.context $F.checkpoint $F.goal).reason | Should Be 'goal_contract_upgrade_required'
    }
    It 'recognizes a first cross-day improvement and does not postpone an evidence-starved goal forever' {
        $F=New-PracticalGoalFixture
        $F.rows[0].criterion_results_json='[{"criterion_id":"CR-1","result":"not_met"}]'
        Write-TsvRowsAtomic -Path $F.context.paths.evidence -Rows $F.rows -Headers $script:V4EvidenceHeaders
        (Get-V4PracticalGoalDecision $F.context $F.checkpoint $F.goal).reason | Should Be 'new_progress_marker'
        $F.goal.max_completed_cycles='2';$F.rows[2].support_level='guided'
        Write-TsvRowsAtomic -Path $F.context.paths.evidence -Rows $F.rows -Headers $script:V4EvidenceHeaders
        $Decision=Get-V4PracticalGoalDecision $F.context $F.checkpoint $F.goal
        $Decision.decision | Should Be 'redesign'
        $Decision.reason | Should Be 'maximum_cycles_without_sufficient_evidence'
    }
    It 'does not declare met after newer counterevidence or reuse an earlier goal version' {
        $F=New-PracticalGoalFixture
        $F.rows[1].day_id='2026-09-07';$F.rows[1].criterion_results_json='[{"criterion_id":"CR-1","result":"not_met"}]'
        Write-TsvRowsAtomic -Path $F.context.paths.evidence -Rows $F.rows -Headers $script:V4EvidenceHeaders
        (Get-V4PracticalGoalDecision $F.context $F.checkpoint $F.goal).decision | Should Not Be 'met'
        $F.rows[1].focus_goal_id='FG-old-version'
        Write-TsvRowsAtomic -Path $F.context.paths.evidence -Rows $F.rows -Headers $script:V4EvidenceHeaders
        (Get-V4PracticalGoalDecision $F.context $F.checkpoint $F.goal).coverage.current_opportunities | Should Be 1
    }
}

Describe 'Confirmed goal replacement publication' {
    foreach ($Phase in @('cycle_intent','cycle_goals','cycle_packages','cycle_plans','cycle_evidence','cycle_index','cycle_commit')) {
        It "recovers goal replacement at $Phase without rewriting its old criteria" {
            $Root=New-CyclePublicationFixture
            $Context=New-V4Context -ProjectRoot $Root
            $Checkpoint=(Read-DurableJson -Path $Context.paths.current_session).value
            $Checkpoint.focus_goal_id='FG-C0004-01'
            [void](Write-DurableJson -Path $Context.paths.current_session -Value $Checkpoint)
            $Payload=Get-Content (Join-Path $ProjectRoot 'maintenance/examples/c0005-publication.json') -Raw | ConvertFrom-Json
            $Goal=[pscustomobject]@{goal_id='FG-next';goal_key='explain';stage_id='STAGE_B1_INDEPENDENT';skill='speaking';competency_id='S_EXPLAIN.B1';competency_family='S_EXPLAIN';activity_family='opinion_explanation';quality_focus='organization';goal_text='Explain clearly';min_completed_cycles=2;max_completed_cycles=4;success_criteria_json='{"schema_version":1,"catalog_version":"1.0.0","indicator_id":"S_EXPLAIN.message_sequence.B1","anchor_id":"S_EXPLAIN.B1.ANCHOR","required_criterion_ids":["CR-S-OPEN"],"guardrail_criterion_ids":[],"confirmation_evidence_mode":"assessment"}'}
            $Payload | Add-Member next_goal $Goal
            foreach ($Item in $Payload.plan_items) { if ($Item.focus_goal_id) {$Item.focus_goal_id='FG-next'} }
            foreach ($Package in $Payload.packages) { if ($Package.focus_goal_id) {$Package.focus_goal_id='FG-next'} }
            $Json=$Payload|ConvertTo-Json -Depth 40 -Compress
            Assert-ThrowsV4 {Invoke-V4Json -Root $Root -Arguments @{Action='PublishCycle';IdempotencyKey='replace-goal';PayloadJson=$Json;FaultAfterPhase=$Phase}}
            [void](Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap'})
            (Invoke-V4Json -Root $Root -Arguments @{Action='PublishCycle';IdempotencyKey='replace-goal';PayloadJson=$Json}).receipt.status | Should Be 'committed'
            $Goals=@(Get-TsvRows -Path $Context.paths.focus_goals -Headers $script:V4FocusGoalHeaders)
            $Goals.Count | Should Be 2
            $Goals[0].status | Should Be 'superseded'
            $Goals[0].success_criteria_json | Should Be ''
            $Goals[1].status | Should Be 'active'
            $Goals[1].supersedes_goal_id | Should Be 'FG-C0004-01'
            $Goals[1].start_cycle_id | Should Be 'C0005'
            (Get-V4BootstrapIndex $Context).value.focus_goal_id | Should Be 'FG-next'
        }
    }
}
