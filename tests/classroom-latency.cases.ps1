function New-ClassroomFixture {
    param([int]$ReviewCount=2)
    $Root=New-V4Fixture -WithReview:($ReviewCount -gt 0)
    $Context=New-V4Context -ProjectRoot $Root -Date ([datetime]'2026-09-05T12:00:00')
    $AssetRoot=Join-Path $Root '.agents/skills/english-coach/assets'
    $ReferenceRoot=Join-Path $Root '.agents/skills/english-coach/references'
    [void](New-Item -ItemType Directory -Force -Path $AssetRoot,$ReferenceRoot)
    Copy-Item -LiteralPath (Join-Path $ProjectRoot '.agents/skills/english-coach/references/difficulty-ladders.json') -Destination $ReferenceRoot
    $Core=[pscustomobject]@{
        plan_item_id='P4-01';stage='output';activity_family='opinion_explanation';modality='speech';purpose='practice';mode='fluency'
        primary_construct='State an opinion with a reason';prompt_text='Explain which time of day you prefer for study and give a reason.'
        criteria=@([pscustomobject]@{criterion_id='CR-1';importance='essential';description='Opinion with a relevant reason'})
        semantic_scope=[pscustomobject]@{required_meaning_units=@('opinion','reason')};content_id='MAIN-CONTENT';context_id='MAIN-CONTEXT'
    }
    $CorePath=Join-Path $AssetRoot 'classroom-core.json'
    [IO.File]::WriteAllText($CorePath,(@{blueprints=@($Core)}|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
    $PackagePath=Join-Path $Root '.state/packages/P4-01.json'
    $Package=(Read-DurableJson -Path $PackagePath).value
    $Package | Add-Member blueprint_path '.agents/skills/english-coach/assets/classroom-core.json' -Force
    $Package | Add-Member blueprint_sha256 (Get-FileSha256 $CorePath) -Force
    $Package.activity_skeletons=@([pscustomobject]@{
        competency_id='S_EXPLAIN.B1';competency_family='S_EXPLAIN';activity_family='opinion_explanation'
        indicator_id='S_EXPLAIN.message_sequence.B1';anchor_id='S_EXPLAIN.B1.ANCHOR';template_id='spoken_monologue';max_evidence_mode='training'
    })
    [void](Write-DurableJson -Path $PackagePath -Value $Package)
    $Plans=@(Get-TsvRows -Path $Context.paths.plans -Headers $script:V4PlanHeaders)
    $Plans[0].session_type='integrated'
    Write-TsvRowsAtomic -Path $Context.paths.plans -Rows $Plans -Headers $script:V4PlanHeaders
    $Index=(Read-DurableJson -Path $Context.paths.bootstrap_index).value
    $Index.session_type='integrated';$Index.package_hash=Get-FileSha256 $PackagePath
    $Index.next_package_descriptors=@([pscustomobject]@{
        plan_item_id='P4-01';package_path=$Index.package_path;package_hash=$Index.package_hash
        fallback_package_path='';fallback_package_hash='';preauthorized_probe_candidate=$null
    })
    if ($ReviewCount -gt 0) {
        $Original=@(Get-TsvRows -Path $Context.paths.review_items -Headers $script:V4ReviewItemHeaders)[0]
        $Rows=@();$Candidates=@()
        for ($i=1;$i -le $ReviewCount;$i++) {
            $Row=ConvertFrom-StableJson -Json (ConvertTo-CanonicalJson $Original)
            $Row.review_item_id="RI-$i";$Row.concept_id="C-$i";$Row.review_family='productive_pattern';$Row.target_scope='pattern'
            $Rows+=@($Row)
            $Candidates+=@([pscustomobject]@{review_item_id="RI-$i";lane='active';recipe_stage='recall';weight=3;effective_due='2026-09-05'})
        }
        Write-TsvRowsAtomic -Path $Context.paths.review_items -Rows $Rows -Headers $script:V4ReviewItemHeaders
        $Index.review_candidates=$Candidates
    }
    $Index.queue_guard=Get-V4QueueGuard $Index
    [void](Write-DurableJson -Path $Context.paths.bootstrap_index -Value $Index)
    return $Root
}

function Enter-ClassroomFixture {
    param([string]$Root)
    return Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap';EnterSession=$true;IdempotencyKey='classroom-start';Date=[datetime]'2026-09-05T12:00:00'}
}

function Freeze-ClassroomQuestions {
    param([string]$Root,[object]$Response)
    $Questions=@(foreach ($Item in $Response.prepared_step.review_items) {
        $Q=New-TestReviewResult
        $Q.review_item_id=$Item.review_item_id
        $Q.task_contract.content_id="CONTENT-$($Item.review_item_id)"
        $Q.task_contract.context_id="CONTEXT-$($Item.review_item_id)"
        [pscustomobject]@{review_item_id=$Q.review_item_id;prompt_text=$Q.prompt_text;task_contract=$Q.task_contract}
    })
    return Invoke-V4Json -Root $Root -Arguments @{
        Action='PrepareReviewQuestions';SessionId=$Response.receipt.session_id;OwnerToken=$Response.receipt.owner_token
        ExpectedRevision=$Response.receipt.revision;IdempotencyKey='freeze-review';PayloadJson=(@{questions=$Questions}|ConvertTo-Json -Depth 20 -Compress)
    }
}

function Save-ClassroomAnswer {
    param([string]$Root,[object]$Response,[string]$Key='answer-1',[hashtable]$Overrides=@{},[string]$Fault='')
    $Payload=@{
        question_instance_id=$Response.prepared_step.question.question_instance_id
        feedback_shown=$true;feedback_text='Correct use of the pattern.';answer_excerpt='by practicing'
        language_validity='pass';target_demonstrated='demonstrated';rating='good';rating_reason='Independent recall';followup='advance'
    }
    foreach ($Name in $Overrides.Keys) { if ($null -eq $Overrides[$Name]) { $Payload.Remove($Name) } else { $Payload[$Name]=$Overrides[$Name] } }
    return Invoke-V4Json -Root $Root -Arguments @{
        Action='SaveReviewAnswer';SessionId=$Response.receipt.session_id;OwnerToken=$Response.receipt.owner_token
        ExpectedRevision=$Response.receipt.revision;IdempotencyKey=$Key;PayloadJson=($Payload|ConvertTo-Json -Depth 20 -Compress);FaultAfterPhase=$Fault
    }
}

Describe 'Classroom latency paths and durable per-question recovery' {
    It 'resumes same-activity repair for an existing non-classroom V4 session' {
        $Root=New-V4Fixture
        $Start=Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='old-main';Date=[datetime]'2026-09-05T12:00:00'}
        $CP=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        $Contract=New-TestContract -Checkpoint $CP
        $Prepared=Invoke-V4Json -Root $Root -Arguments @{Action='PrepareActivity';SessionId=$Start.receipt.session_id;OwnerToken=$Start.receipt.owner_token;ExpectedRevision=$Start.receipt.revision;IdempotencyKey='old-prepare';PayloadJson=($Contract|ConvertTo-Json -Depth 20 -Compress)}
        $Payload=New-SavePayload -ActivityId $Contract.activity_id -Stage input -NextAction repair
        $Payload.stage_complete=$false
        foreach ($Pair in @{feedback_text='Improve this wording.';followup_prompt='Try another expression.';support_level='light_hint';support_kind=@('word_choice')}.GetEnumerator()) { $Payload | Add-Member $Pair.Key $Pair.Value -Force }
        $Saved=Invoke-V4Json -Root $Root -Arguments @{Action='SaveActivityCheckpoint';SessionId=$Start.receipt.session_id;OwnerToken=$Start.receipt.owner_token;ExpectedRevision=$Prepared.receipt.revision;IdempotencyKey='old-first';PayloadJson=($Payload|ConvertTo-Json -Depth 20 -Compress)}
        $Resume=Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap';Date=[datetime]'2026-09-05T12:00:00'}
        $Resume.next_action | Should Be 'repair'
        $Resume.prepared_step.first_result.task_result | Should Be 'success'
        $Resume.prepared_step.followup_state.followup_prompt | Should Be 'Try another expression.'
        $Follow=@{activity_id=$Contract.activity_id;feedback_shown=$true;answer_excerpt='Revised wording';followup_result='repaired';feedback_text='Clearer now.';support_level='none';support_kind=@();next_action='prepare_activity';stage_complete=$true}
        $Result=Invoke-V4Json -Root $Root -Arguments @{Action='SaveActivityCheckpoint';SessionId=$Start.receipt.session_id;OwnerToken=$Start.receipt.owner_token;ExpectedRevision=$Saved.receipt.revision;IdempotencyKey='old-repaired';PayloadJson=($Follow|ConvertTo-Json -Depth 20 -Compress)}
        $Result.next_action | Should Be 'prepare_activity'
        $CP=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        @($CP.pending_activity_batch).Count | Should Be 1
        @($CP.activity_records).Count | Should Be 1
    }

    It 'resumes main repair, preserves its first answer, replays once and commits the outcome' {
        $Root=New-ClassroomFixture -ReviewCount 0
        $Main=Enter-ClassroomFixture $Root
        $Args=@{Action='SaveActivityCheckpoint';SessionId=$Main.receipt.session_id;OwnerToken=$Main.receipt.owner_token;ExpectedRevision=$Main.receipt.revision;IdempotencyKey='main-first'}
        $First=@{activity_id=$Main.prepared_step.activity_id;feedback_shown=$true;first_answer_excerpt='Morning.';criterion_results=@(@{criterion_id='CR-1';result='not_met'});task_result='failed';selected_issues=@();next_action='repair';feedback_text='Add a reason.';followup_prompt='Why do you prefer mornings?';support_level='light_hint';support_kind=@('prompt')}
        $First.observation=(New-SavePayload -ActivityId $First.activity_id -Stage output).observation
        $First.observation.primary_result='failed';$First.observation.criterion_result='not_met';$First.observation.core_result='failed'
        $Args.PayloadJson=$First|ConvertTo-Json -Depth 20 -Compress
        $Repair=Invoke-V4Json -Root $Root -Arguments $Args
        $Repair.next_action | Should Be 'repair'
        $Repair.next_action_contract.kind | Should Be 'interaction'
        $Before=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        $FrozenObservation=ConvertTo-CanonicalJson $Before.pending_activity_batch
        $Resumed=Enter-ClassroomFixture $Root
        $Resumed.prepared_step.followup_state.followup_prompt | Should Be 'Why do you prefer mornings?'
        $Resumed.prepared_step.first_result.answer_excerpt | Should Be 'Morning.'
        Assert-ThrowsV4 { Invoke-V4Json -Root $Root -Arguments @{Action='FinalizeSession';SessionId=$Args.SessionId;OwnerToken=$Args.OwnerToken;ExpectedRevision=$Repair.receipt.revision;IdempotencyKey='too-early';PayloadJson='{"feedback_shown":true,"session_summary":"Not ready","duration_minutes":10}'} }
        Assert-ThrowsV4 { Invoke-V4Json -Root $Root -Arguments @{Action='PrepareActivity';SessionId=$Args.SessionId;OwnerToken=$Args.OwnerToken;ExpectedRevision=$Repair.receipt.revision;IdempotencyKey='skip-repair';PayloadJson=($Main.prepared_step.contract|ConvertTo-Json -Depth 30 -Compress)} }
        $Follow=@{activity_id=$First.activity_id;feedback_shown=$true;answer_excerpt='I prefer mornings because I can focus.';followup_result='repaired';feedback_text='Your reason is clear now.';support_level='none';support_kind=@();next_action='finalize_session';stage_complete=$true}
        $Args.ExpectedRevision=$Repair.receipt.revision;$Args.IdempotencyKey='main-repair';$Args.PayloadJson=$Follow|ConvertTo-Json -Depth 20 -Compress
        $Saved=Invoke-V4Json -Root $Root -Arguments $Args
        $Replay=Invoke-V4Json -Root $Root -Arguments $Args
        $Replay.receipt.revision | Should Be $Saved.receipt.revision
        $Args.IdempotencyKey='stale-followup'
        Assert-ThrowsV4 { Invoke-V4Json -Root $Root -Arguments $Args }
        $CP=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        @($CP.activity_records).Count | Should Be 1
        $CP.activity_records[0].task_result | Should Be 'failed'
        $CP.activity_records[0].followup_state.support_level | Should Be 'light_hint'
        @($CP.activity_records[0].followup_state.history).Count | Should Be 1
        @($CP.pending_activity_batch).Count | Should Be 1
        (ConvertTo-CanonicalJson $CP.pending_activity_batch) | Should Be $FrozenObservation
        $Final=Invoke-V4Json -Root $Root -Arguments @{Action='FinalizeSession';SessionId=$Args.SessionId;OwnerToken=$Args.OwnerToken;ExpectedRevision=$Saved.receipt.revision;IdempotencyKey='main-final';PayloadJson='{"feedback_shown":true,"session_summary":"Practised giving a reason.","duration_minutes":20}'}
        $Final.status | Should Be 'completed'
        $Context=New-V4Context -ProjectRoot $Root
        $Evidence=@(Get-TsvRows -Path $Context.paths.evidence -Headers $script:V4EvidenceHeaders)
        $Evidence.Count | Should Be 1
        $Evidence[0].task_result | Should Be 'failed'
        $Text=Get-Content -LiteralPath (Join-Path $Root $CP.session_file) -Raw
        $Text | Should Match 'followup|repaired'
        $Text | Should Match 'light_hint'
    }

    It 'bounds main repair retries, refuses regrading and prepares transfer under a new ID' {
        $Root=New-ClassroomFixture -ReviewCount 0
        $Main=Enter-ClassroomFixture $Root
        $Args=@{Action='SaveActivityCheckpoint';SessionId=$Main.receipt.session_id;OwnerToken=$Main.receipt.owner_token;ExpectedRevision=$Main.receipt.revision;IdempotencyKey='clarify-first'}
        $First=@{activity_id=$Main.prepared_step.activity_id;feedback_shown=$true;first_answer_excerpt='Morning.';criterion_results=@(@{criterion_id='CR-1';result='not_met'});task_result='failed';selected_issues=@();next_action='clarify';feedback_text='Which time do you mean?';followup_prompt='Morning or evening?';support_level='none';support_kind=@()}
        $Args.PayloadJson=$First|ConvertTo-Json -Depth 20 -Compress
        $Response=Invoke-V4Json -Root $Root -Arguments $Args
        (Enter-ClassroomFixture $Root).next_action | Should Be 'clarify'
        $Follow=@{activity_id=$First.activity_id;feedback_shown=$true;answer_excerpt='Morning.';followup_result='clarified';feedback_text='Please add a reason.';followup_prompt='Add because and a reason.';support_level='light_hint';support_kind=@('prompt');next_action='repair'}
        $Args.ExpectedRevision=$Response.receipt.revision;$Args.IdempotencyKey='clarified';$Args.PayloadJson=$Follow|ConvertTo-Json -Depth 20 -Compress
        $Response=Invoke-V4Json -Root $Root -Arguments $Args
        $Follow.task_result='success';$Args.ExpectedRevision=$Response.receipt.revision;$Args.IdempotencyKey='regrade';$Args.PayloadJson=$Follow|ConvertTo-Json -Depth 20 -Compress
        Assert-ThrowsV4 { Invoke-V4Json -Root $Root -Arguments $Args }
        $Follow.Remove('task_result');$Follow.followup_result='needs_help';$Follow.support_level='model';$Follow.feedback_text='Use this model: because I can focus.';$Follow.followup_prompt='Try the reason again.'
        $Args.IdempotencyKey='repair-1';$Args.PayloadJson=$Follow|ConvertTo-Json -Depth 20 -Compress
        $Response=Invoke-V4Json -Root $Root -Arguments $Args
        $Args.ExpectedRevision=$Response.receipt.revision;$Args.IdempotencyKey='repair-2'
        Assert-ThrowsV4 { Invoke-V4Json -Root $Root -Arguments $Args }
        $Follow.next_action='show_transfer';$Follow.followup_result='stopped';$Follow.support_level='none';$Args.PayloadJson=$Follow|ConvertTo-Json -Depth 20 -Compress
        $Response=Invoke-V4Json -Root $Root -Arguments $Args
        $Response.next_action_contract.action | Should Be 'PrepareActivity'
        $CP=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        $CP.activity_records[0].followup_state.model_exposed | Should Be $true
        $CP.activity_records[0].followup_state.support_level | Should Be 'model'
        @($CP.activity_records[0].followup_state.history | Where-Object action -eq 'repair').Count | Should Be 2
        $Contract=$Main.prepared_step.contract
        $Prepare=@{Action='PrepareActivity';SessionId=$Args.SessionId;OwnerToken=$Args.OwnerToken;ExpectedRevision=$Response.receipt.revision;IdempotencyKey='transfer';PayloadJson=($Contract|ConvertTo-Json -Depth 30 -Compress)}
        Assert-ThrowsV4 { Invoke-V4Json -Root $Root -Arguments $Prepare }
        $Contract.activity_id='A-new-transfer';$Prepare.PayloadJson=$Contract|ConvertTo-Json -Depth 30 -Compress
        $Transfer=Invoke-V4Json -Root $Root -Arguments $Prepare
        $Transfer.next_action | Should Be 'present_activity'
        $Transfer.prepared_step.activity_id | Should Be 'A-new-transfer'
    }

    It 'enters a no-review lesson with a complete scored contract in one request' {
        $Root=New-ClassroomFixture -ReviewCount 0
        $Response=Enter-ClassroomFixture $Root
        $Response.next_action | Should Be 'present_activity'
        (Test-V4ActivityContract $Response.prepared_step.contract).valid | Should Be $true
        $Response.prepared_step.contract.prompt_text | Should Match 'time of day'
        $Response.metrics.script_elapsed_ms | Should BeGreaterThan 0
        ($null -eq $Response.metrics.user_visible_wait_ms) | Should Be $true
        $Again=Enter-ClassroomFixture $Root
        $Again.prepared_step.activity_id | Should Be $Response.prepared_step.activity_id
        $Again.receipt.revision | Should Be $Response.receipt.revision
    }

    It 'saves each answer once and returns the next question then main activity without a second call' {
        $Root=New-ClassroomFixture
        $Response=Enter-ClassroomFixture $Root
        $Response.next_action | Should Be 'prepare_review_questions'
        $First=Freeze-ClassroomQuestions $Root $Response
        $First.prepared_step.position | Should Be 1
        ($null -eq $First.prepared_step.PSObject.Properties['package_blueprint']) | Should Be $true
        $Second=Save-ClassroomAnswer $Root $First
        $Second.next_action | Should Be 'present_review_question'
        $Second.prepared_step.position | Should Be 2
        $Replay=Save-ClassroomAnswer $Root $First
        $Replay.prepared_step.position | Should Be 2
        $Replay.receipt.revision | Should Be $Second.receipt.revision
        Assert-ThrowsV4 { Save-ClassroomAnswer $Root $First -Overrides @{rating='hard'} }
        $Main=Save-ClassroomAnswer $Root $Second -Key 'answer-2'
        $Main.next_action | Should Be 'present_activity'
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        @($Checkpoint.pending_review_batches).Count | Should Be 1
        @($Checkpoint.pending_review_batches[0].items).Count | Should Be 2
        $Checkpoint.pending_review_batches[0].items[0].target_demonstrated | Should Be 'yes'
        $Context=New-V4Context -ProjectRoot $Root
        @(Get-TsvRows -Path $Context.paths.review_history -Headers $script:V4ReviewHistoryHeaders).Count | Should Be 0
        @(Get-TsvRows -Path $Context.paths.review_items -Headers $script:V4ReviewItemHeaders)[0].strength_level | Should Be '0'
    }

    It 'resumes after saved review and interrupted main preparation without asking the review again' {
        $Root=New-ClassroomFixture -ReviewCount 1
        $First=Freeze-ClassroomQuestions $Root (Enter-ClassroomFixture $Root)
        Assert-ThrowsV4 { Save-ClassroomAnswer $Root $First -Fault 'classroom_review_saved' }
        $Resumed=Enter-ClassroomFixture $Root
        $Resumed.next_action | Should Be 'present_activity'
        $Replay=Save-ClassroomAnswer $Root $First
        $Replay.prepared_step.activity_id | Should Be $Resumed.prepared_step.activity_id
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        @($Checkpoint.pending_review_batches[0].items).Count | Should Be 1
    }

    It 'freezes first rating through prompted repair and reconstruction, including recovery' {
        $Root=New-ClassroomFixture -ReviewCount 1
        $First=Freeze-ClassroomQuestions $Root (Enter-ClassroomFixture $Root)
        $Repair=Save-ClassroomAnswer $Root $First -Overrides @{rating='again';feedback_text='Use the -ing form.';followup='repair';followup_prompt='Repair the word after by.'}
        $Repair.next_action | Should Be 'repair_review'
        $Resume=Enter-ClassroomFixture $Root
        $Resume.prepared_step.followup_prompt | Should Be 'Repair the word after by.'
        Assert-ThrowsV4 { Save-ClassroomAnswer $Root $Repair -Key 'bad-regrade' }
        $Reconstruct=Save-ClassroomAnswer $Root $Repair -Key 'repair' -Overrides @{rating=$null;followup='reconstruct';followup_prompt='Rebuild the phrase once.'}
        $Reconstruct.next_action | Should Be 'reconstruct_review'
        Assert-ThrowsV4 { Save-ClassroomAnswer $Root $Reconstruct -Key 'extra-repair' -Overrides @{rating=$null;followup='repair'} }
        $Main=Save-ClassroomAnswer $Root $Reconstruct -Key 'reconstruct' -Overrides @{rating=$null}
        $Main.next_action | Should Be 'present_activity'
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        $Checkpoint.pending_review_batches[0].items[0].rating | Should Be 'again'
        $Checkpoint.pending_review_batches[0].items[0].repair_result.support | Should Be 'guided'
    }

    It 'rejects stale revisions, wrong question IDs and hidden feedback' {
        $Root=New-ClassroomFixture
        $First=Freeze-ClassroomQuestions $Root (Enter-ClassroomFixture $Root)
        Assert-ThrowsV4 { Save-ClassroomAnswer $Root $First -Overrides @{question_instance_id='wrong'} }
        Assert-ThrowsV4 { Save-ClassroomAnswer $Root $First -Overrides @{feedback_shown=$false} }
        $Second=Save-ClassroomAnswer $Root $First
        Assert-ThrowsV4 { Save-ClassroomAnswer $Root $First -Key 'stale' -Overrides @{question_instance_id=$Second.prepared_step.question.question_instance_id} }
    }

    It 'defers exposed future questions without scoring or inventing replacement items' {
        $Root=New-ClassroomFixture
        $First=Freeze-ClassroomQuestions $Root (Enter-ClassroomFixture $Root)
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        $Id=$Checkpoint.classroom_review.questions[1].question_instance_id
        $Main=Save-ClassroomAnswer $Root $First -Overrides @{exposed_question_ids=@($Id)}
        $Main.next_action | Should Be 'present_activity'
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        @($Checkpoint.pending_review_batches[0].items).Count | Should Be 1
        $Checkpoint.classroom_review.questions[1].disposition | Should Be 'exposed'
        $Context=New-V4Context -ProjectRoot $Root -Date ([datetime]'2026-09-05T12:00:00')
        $Facts=New-V4ReviewTransactionPayload -Context $Context -Checkpoint $Checkpoint -Disposition abandoned -Timestamp (Get-V4Timestamp $Context)
        @($Facts.audit_rows | Where-Object record_kind -eq 'control').Count | Should Be 1
        @($Facts.history_rows).Count | Should Be 1
        $Exposure=@($Facts.audit_rows | Where-Object record_kind -eq 'control')[0]
        $Exposure.rating | Should Be ''
        $Exposure.question_instance_id | Should Be ''
    }

    It 'keeps legacy V4 sessions on their old continuation path' {
        $Root=New-ClassroomFixture
        $Old=Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='old-start';Date=[datetime]'2026-09-05T12:00:00'}
        $Old.next_action | Should Be 'present_review'
        $Path=Join-Path $Root '.state/current-session.json'
        $Before=Get-FileSha256 $Path
        $Resume=Enter-ClassroomFixture $Root
        $Resume.next_action | Should Be 'present_review'
        (Get-FileSha256 $Path) | Should Be $Before
    }

    It 'does not open a lesson for a plain Bootstrap progress query' {
        $Root=New-ClassroomFixture
        $Response=Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap';Date=[datetime]'2026-09-05T12:00:00'}
        $Response.next_action | Should Be 'start_session'
        (Test-Path -LiteralPath (Join-Path $Root '.state/current-session.json')) | Should Be $false
    }

    It 'commits per-question pending results only at finalization' {
        $Root=New-ClassroomFixture -ReviewCount 1
        $First=Freeze-ClassroomQuestions $Root (Enter-ClassroomFixture $Root)
        $Main=Save-ClassroomAnswer $Root $First
        $Payload=@{activity_id=$Main.prepared_step.activity_id;feedback_shown=$true;first_answer_excerpt='I prefer mornings because I can focus.';criterion_results=@(@{criterion_id='CR-1';result='met'});task_result='success';selected_issues=@();stage_complete=$true;next_action='finalize_session'}
        $Saved=Invoke-V4Json -Root $Root -Arguments @{Action='SaveActivityCheckpoint';SessionId=$Main.receipt.session_id;OwnerToken=$Main.receipt.owner_token;ExpectedRevision=$Main.receipt.revision;IdempotencyKey='main-answer';PayloadJson=($Payload|ConvertTo-Json -Depth 12 -Compress)}
        $Final=Invoke-V4Json -Root $Root -Arguments @{Action='FinalizeSession';SessionId=$Main.receipt.session_id;OwnerToken=$Main.receipt.owner_token;ExpectedRevision=$Saved.receipt.revision;IdempotencyKey='classroom-final';PayloadJson='{"feedback_shown":true,"session_summary":"Completed review and main practice.","duration_minutes":20}'}
        $Final.status | Should Be 'completed'
        $Context=New-V4Context -ProjectRoot $Root
        @(Get-TsvRows -Path $Context.paths.review_history -Headers $script:V4ReviewHistoryHeaders).Count | Should Be 1
        @(Get-TsvRows -Path $Context.paths.review_audit -Headers $script:V4ReviewAuditHeaders).Count | Should Be 1
    }

    It 'allows skipped review without manufacturing a completed review stage' {
        $Root=New-ClassroomFixture -ReviewCount 1
        $First=Freeze-ClassroomQuestions $Root (Enter-ClassroomFixture $Root)
        $Main=Save-ClassroomAnswer $Root $First -Overrides @{control='skip';rating=$null}
        $Main.next_action | Should Be 'present_activity'
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        ('review' -in @($Checkpoint.completed_stages)) | Should Be $false
        @($Checkpoint.pending_review_batches[0].items).Count | Should Be 0
    }

    It 'keeps an invalid question out of schedule changes' {
        $Root=New-ClassroomFixture -ReviewCount 1
        $First=Freeze-ClassroomQuestions $Root (Enter-ClassroomFixture $Root)
        $Main=Save-ClassroomAnswer $Root $First -Overrides @{rating='invalid';invalid_reason='Reasonable alternative was omitted.';language_validity='pass';target_demonstrated='not_assessable'}
        $Main.next_action | Should Be 'present_activity'
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        $Context=New-V4Context -ProjectRoot $Root
        $Transaction=New-V4ReviewTransactionPayload -Context $Context -Checkpoint $Checkpoint -Disposition completed -Timestamp (Get-V4Timestamp $Context)
        @($Transaction.history_rows).Count | Should Be 0
    }

    It 'precompiles safe derived templates and invalidates them when the ladder changes' {
        $Root=New-ClassroomFixture -ReviewCount 0
        $Context=New-V4Context -ProjectRoot $Root
        $PackagePath=Join-Path $Root '.state/packages/P4-01.json'
        Publish-V4ClassroomTemplate -Context $Context -PackagePath $PackagePath
        (Test-Path -LiteralPath (Join-Path $Root '.state/classroom-templates/P4-01.json')) | Should Be $true
        $LadderPath=Join-Path $Root '.agents/skills/english-coach/references/difficulty-ladders.json'
        $Ladders=Read-StableJsonFile $LadderPath
        $Ladders.ladder_version='invalid-version'
        [IO.File]::WriteAllText($LadderPath,($Ladders|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
        $Response=Enter-ClassroomFixture $Root
        $Response.next_action | Should Be 'retry_classroom_transition'
    }

    It 'blocks corrupt main material after saving review and can recover with the original material' {
        $Root=New-ClassroomFixture -ReviewCount 1
        $First=Freeze-ClassroomQuestions $Root (Enter-ClassroomFixture $Root)
        $Path=Join-Path $Root '.agents/skills/english-coach/assets/classroom-core.json'
        $Original=[IO.File]::ReadAllText($Path)
        [IO.File]::WriteAllText($Path,'{}',[Text.UTF8Encoding]::new($false))
        $Blocked=Save-ClassroomAnswer $Root $First
        $Blocked.next_action | Should Be 'retry_classroom_transition'
        [IO.File]::WriteAllText($Path,$Original,[Text.UTF8Encoding]::new($false))
        $Restored=Enter-ClassroomFixture $Root
        $Restored.next_action | Should Be 'present_activity'
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        @($Checkpoint.pending_review_batches[0].items).Count | Should Be 1
    }

    It 'recovers a partially started classroom without creating another session' {
        $Root=New-ClassroomFixture -ReviewCount 0
        Assert-ThrowsV4 { Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap';EnterSession=$true;IdempotencyKey='classroom-start';Date=[datetime]'2026-09-05T12:00:00';FaultAfterPhase='start_intent'} }
        $Response=Enter-ClassroomFixture $Root
        $Response.next_action | Should Be 'present_activity'
        @(Get-ChildItem -LiteralPath (Join-Path $Root 'sessions') -Filter '*.md' -Recurse).Count | Should Be 1
    }

    It 'keeps expired queue guards from saving a new answer' {
        $Root=New-ClassroomFixture
        $First=Freeze-ClassroomQuestions $Root (Enter-ClassroomFixture $Root)
        $Path=Join-Path $Root '.state/bootstrap-index.json'
        $Index=(Read-DurableJson -Path $Path).value
        $Index.queue_revision++;$Index.queue_guard=Get-V4QueueGuard $Index
        [void](Write-DurableJson -Path $Path -Value $Index)
        Assert-ThrowsV4 { Save-ClassroomAnswer $Root $First }
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        @($Checkpoint.pending_review_batches).Count | Should Be 0
    }

    It 'preserves daily exposure deferrals across a committed abandonment without changing due' {
        $Root=New-ClassroomFixture
        $First=Freeze-ClassroomQuestions $Root (Enter-ClassroomFixture $Root)
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state/current-session.json')).value
        $OtherId=$Checkpoint.classroom_review.questions[1].question_instance_id
        $Main=Save-ClassroomAnswer $Root $First -Overrides @{exposed_question_ids=@($OtherId)}
        $Final=Invoke-V4Json -Root $Root -Arguments @{Action='AbandonSession';SessionId=$Main.receipt.session_id;OwnerToken=$Main.receipt.owner_token;ExpectedRevision=$Main.receipt.revision;IdempotencyKey='abandon';Date=[datetime]'2026-09-05T12:00:00';PayloadJson='{"feedback_shown":true,"session_summary":"User explicitly abandoned.","duration_minutes":5}'}
        $Context=New-V4Context -ProjectRoot $Root -Date ([datetime]'2026-09-05T12:00:00')
        $Index=(Read-DurableJson -Path $Context.paths.bootstrap_index).value
        ('RI-2' -in @($Index.review_exposures.item_ids)) | Should Be $true
        @(Get-TsvRows -Path $Context.paths.review_items -Headers $script:V4ReviewItemHeaders | Where-Object review_item_id -eq 'RI-2')[0].next_review | Should Be '2026-09-05'
        $New=Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap';EnterSession=$true;IdempotencyKey='restart';Date=[datetime]'2026-09-05T12:00:00'}
        $New.next_action | Should Be 'present_activity'
    }
}
