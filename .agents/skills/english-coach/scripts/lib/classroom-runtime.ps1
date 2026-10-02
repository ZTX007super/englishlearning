Set-StrictMode -Version Latest

# Classroom v1 is opt-in at session creation. Existing checkpoints retain their protocol.
function Test-V4Classroom {
    param([object]$Checkpoint)
    return [int](Get-ReducerValue $Checkpoint 'classroom_version' 0) -eq 1
}

function Assert-V4ClassroomQueue {
    param([object]$Context, [object]$Checkpoint)
    $Index=Get-V4BootstrapIndex -Context $Context
    if ($Index.status -ne 'valid' -or $Index.value.queue_guard -ne $Checkpoint.queue_guard -or
        $Index.value.next_plan_item_id -ne $Checkpoint.plan_item_id) { throw 'Classroom queue guard no longer matches the active lesson.' }
}

function New-V4ClassroomTemplate {
    param([object]$Context, [object]$Package)
    $Core = Get-V4CoreBlueprint -Context $Context -Package $Package
    if ($Core.status -ne 'ready' -or $Core.value.stage -eq 'cycle_review') { return $null }
    $LadderPath=Join-Path $Context.root '.agents/skills/english-coach/references/difficulty-ladders.json'
    $CachePath=Join-Path $Context.root ".state/classroom-templates/$($Package.plan_item_id).json"
    $Cached=Read-DurableJson -Path $CachePath -AllowMissing
    if ($null -ne $Cached -and $Cached.status -eq 'valid' -and $Cached.value.compiler_version -eq 1 -and
        $Cached.value.package_hash -eq (Get-PayloadHash $Package) -and (Test-Path -LiteralPath $LadderPath) -and
        $Cached.value.ladder_hash -eq (Get-FileSha256 $LadderPath)) { return $Cached.value.template }
    $Skeletons = @($Package.activity_skeletons | Where-Object { $_.activity_family -eq $Core.value.activity_family })
    if ($Skeletons.Count -ne 1) { return $null }
    $Skeleton = $Skeletons[0]
    $Path = Join-Path $Context.root '.agents/skills/english-coach/references/difficulty-ladders.json'
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $Ladders = Read-StableJsonFile -Path $Path
    if ($Ladders.ladder_version -ne $Package.ladder_version) { throw 'Classroom ladder version mismatch.' }
    $Bindings = @($Ladders.family_ladder_binding | Where-Object {
        $_.competency_family -eq $Skeleton.competency_family -and
        $_.activity_family -eq $Skeleton.activity_family -and $_.template_id -eq $Skeleton.template_id
    })
    if ($Bindings.Count -ne 1) { return $null }
    $Binding = $Bindings[0]
    $Contract = ConvertFrom-StableJson -Json (ConvertTo-CanonicalJson $Core.value)
    $Adapter = switch ($Contract.activity_family) {
        'source_comprehension' { 'meaning' }
        'interaction_roleplay' { 'pragmatics_interaction' }
        'controlled_form' { 'grammar_form' }
        'oral_imitation' { 'pronunciation_intelligibility' }
        default { 'organization' }
    }
    $Defaults = @{
        access_profile = [pscustomobject]@{lookback=($Contract.modality -eq 'reading'); preparation_seconds=0}
        planned_support = [pscustomobject]@{level='none'}
        allowed_support = [pscustomobject]@{maximum='guided'}
        correction_timing = $(if ($Contract.mode -eq 'accuracy' -and $Contract.purpose -eq 'practice') {'after_item'} else {'after_fluency_output'})
        adapter=$Adapter; hint_ladder=@('Point to the unmet criterion without giving its answer.', 'Give the smallest explanation needed to repair that criterion.')
        max_support=[pscustomobject]@{level='guided';count=2}; transfer_rule=[pscustomobject]@{required=$false}
        retry_budget=2; loop_budget=3; transfer_budget=1; complexity_budget=3
        evidence_mode='training'; lead_or_auxiliary='lead'
    }
    foreach ($Name in $Defaults.Keys) {
        if ($null -eq (Get-ReducerValue $Contract $Name $null)) { $Contract | Add-Member $Name $Defaults[$Name] }
    }
    foreach ($Name in @('competency_id','competency_family','indicator_id','anchor_id','template_id')) {
        $Contract | Add-Member $Name $Skeleton.$Name -Force
    }
    $Target = [string]$Binding.default_target_steps.($Binding.default_dimension)
    foreach ($Name in @('planned_step','target_step','presented_step')) { $Contract | Add-Member $Name $Target -Force }
    $Contract | Add-Member changed_dimension 'none' -Force
    $Contract | Add-Member adaptation_key "$($Skeleton.competency_family)|$($Skeleton.activity_family)|$($Skeleton.template_id)|$($Binding.default_dimension)" -Force
    foreach ($Name in @('catalog_version','ladder_version','contract_version')) { $Contract | Add-Member $Name $Package.$Name -Force }
    $Contract | Add-Member review_schema_version '4.0.0' -Force
    foreach ($Name in @('content_id','context_id')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Contract $Name ''))) {
            $Contract | Add-Member $Name (Get-ReducerValue (Get-ReducerValue $Contract 'material' $null) $Name "$Name-$($Package.plan_item_id)") -Force
        }
    }
    # Store only a template: real session, guards and probe authorization bind at runtime.
    return $Contract
}

function Publish-V4ClassroomTemplate {
    param([object]$Context, [string]$PackagePath)
    $Package=(Read-DurableJson -Path $PackagePath).value
    $Template=New-V4ClassroomTemplate -Context $Context -Package $Package
    if ($null -eq $Template) { return }
    $Cache=[pscustomobject]@{
        compiler_version=1;package_hash=(Get-PayloadHash $Package)
        ladder_hash=(Get-FileSha256 (Join-Path $Context.root '.agents/skills/english-coach/references/difficulty-ladders.json'))
        template=$Template
    }
    [void](Write-DurableJson -Path (Join-Path $Context.root ".state/classroom-templates/$($Package.plan_item_id).json") -Value $Cache)
}

function Get-V4ClassroomResponse {
    param([object]$Context, [object]$Checkpoint, [string]$Status='resume', [object]$Receipt=$null, [string]$Reason='ok')
    $Action = Get-V4SessionNextAction $Checkpoint
    $Step = [ordered]@{
        session_id=$Checkpoint.session_id; owner_token=$Checkpoint.lease.owner_token
        revision=$Checkpoint.revision; queue_guard=$Checkpoint.queue_guard; classroom_version=1
    }
    $Refs = @('references/classroom-flow.md','references/tracker-actions.md')
    switch ($Action) {
        'prepare_review_questions' {
            $Step.review_items = @($Checkpoint.review_state.selected)
            $Step.batch_id = $Checkpoint.classroom_review.batch_id
            $Refs += 'references/review-protocol.md'
        }
        { $_ -in @('present_review_question','repair_review','reconstruct_review') } {
            $Review = $Checkpoint.classroom_review
            $Step.question = $Review.questions[$Review.cursor]
            $Step.position = $Review.cursor + 1
            $Step.count = @($Review.questions).Count
            $Step.remaining_question_ids = @($Review.questions | Where-Object disposition -eq 'pending' | Select-Object -ExpandProperty question_instance_id)
            $Step.remaining_targets = @($Review.questions | Where-Object disposition -eq 'pending' | ForEach-Object {
                [pscustomobject]@{question_instance_id=$_.question_instance_id;scoring_target=$_.task_contract.scoring_target}
            })
            $Step.feedback_text = $Review.feedback_text
            $Step.followup_prompt = $Review.followup_prompt
            $Step.first_result = @($Checkpoint.pending_review_batches | Where-Object batch_id -eq $Review.batch_id |
                ForEach-Object { $_.items } | Where-Object question_instance_id -eq $Step.question.question_instance_id | Select-Object -First 1)
            $Refs += 'references/review-protocol.md'
        }
        { $_ -in @('await_answer','present_activity') } {
            $Action='present_activity'
            $Step.activity_id=$Checkpoint.prepared_activity.activity_id
            $Step.contract=$Checkpoint.prepared_activity.contract
            $Refs += @('references/task-contracts.md','references/teaching-loop.md')
        }
        { $_ -in @('repair','clarify') } {
            $Step.activity_id=$Checkpoint.prepared_activity.activity_id
            $Step.contract=$Checkpoint.prepared_activity.contract
            $Step.followup_state=$Checkpoint.prepared_activity.followup_state
            $Step.first_result=@($Checkpoint.activity_records | Where-Object activity_id -eq $Step.activity_id)[0]
            $Refs += 'references/teaching-loop.md'
        }
        { $_ -in @('prepare_activity','show_transfer') } {
            $Step.preparation = Get-V4SessionPreparationEnvelope -Context $Context -Checkpoint $Checkpoint
            $Refs += @('references/activity-preparation.md','references/task-contracts.md','references/teaching-loop.md')
        }
        default {
            if ($Action -eq 'evaluate_cycle_review') { $Step.evidence_packet=Get-V4CycleReviewPacket -Context $Context -Checkpoint $Checkpoint }
            if ($Action -in @('show_summary','finalize_session')) {
                $Step.summary_input=[pscustomobject]@{
                    activities=@($Checkpoint.activity_records | Select-Object activity_id,stage,task_result,criterion_results,selected_issues,followup_state)
                    review_ratings=@($Checkpoint.pending_review_batches | ForEach-Object {$_.items} | Group-Object rating | Select-Object Name,Count)
                }
            }
        }
    }
    $CurrentReceipt = [ordered]@{}
    if ($null -ne $Receipt) { foreach ($Property in $Receipt.PSObject.Properties) { $CurrentReceipt[$Property.Name]=$Property.Value } }
    $CurrentReceipt.session_id=$Checkpoint.session_id
    $CurrentReceipt.owner_token=$Checkpoint.lease.owner_token
    $CurrentReceipt.revision=$Checkpoint.revision
    return New-V4Response -Status $Status -NextAction $Action -Receipt ([pscustomobject]$CurrentReceipt) -ReasonCode $Reason -PreparedStep ([pscustomobject]$Step) -ProtocolRefs $Refs
}

function Complete-V4ClassroomTransition {
    param([object]$Context, [object]$Receipt=$null, [string]$FaultAfterPhase)
    $Checkpoint = (Get-V4CurrentSession -Context $Context).value
    if (-not (Test-V4Classroom $Checkpoint)) { throw 'Classroom transition requires a classroom session.' }
    Assert-V4ClassroomQueue -Context $Context -Checkpoint $Checkpoint
    if ((Get-V4SessionNextAction $Checkpoint) -eq 'prepare_activity' -and @($Checkpoint.activity_records).Count -eq 0) {
        # A saved review remains durable even if binding the main activity fails.
        Invoke-FaultPoint -Name 'classroom_review_saved' -RequestedFault $FaultAfterPhase
        try {
            $PackagePath = Join-Path $Context.root $Checkpoint.package_path
            if ((Get-FileSha256 $PackagePath) -ne $Checkpoint.package_hash) { throw 'Frozen package changed.' }
            $Package = (Read-DurableJson -Path $PackagePath).value
            $Core = Get-V4CoreBlueprint -Context $Context -Package $Package
            if ($Core.status -ne 'ready') { throw "Core not available: $($Core.status)" }
            $Contract = New-V4ClassroomTemplate -Context $Context -Package $Package
            if ($null -eq $Contract) { return Get-V4ClassroomResponse -Context $Context -Checkpoint $Checkpoint -Receipt $Receipt -Reason 'manual_preparation_required' }
            $ActivityId=New-StableIdentifier -Prefix 'A-' -Seed "$($Checkpoint.session_id)|classroom-lead" -HashLength 20
            foreach ($Pair in @{
                session_id=$Checkpoint.session_id;activity_id=$ActivityId;contract_id="CT-$ActivityId"
                queue_guard=$Checkpoint.queue_guard;package_hash=$Checkpoint.package_hash
            }.GetEnumerator()) { $Contract | Add-Member $Pair.Key $Pair.Value -Force }
            if ($Checkpoint.evidence_mode_cap -eq 'training') { $Contract.evidence_mode='training';$Contract.purpose='practice' }
            $Skeleton=@($Package.activity_skeletons | Where-Object { $_.activity_family -eq $Contract.activity_family })[0]
            if ([string](Get-ReducerValue $Skeleton 'max_evidence_mode' 'training') -eq 'training') {
                $Contract.evidence_mode='training';$Contract.purpose='practice'
            }
            if ($Contract.evidence_mode -eq 'difficulty_probe' -or $null -ne $Checkpoint.preauthorized_probe_candidate) {
                return Get-V4ClassroomResponse -Context $Context -Checkpoint $Checkpoint -Receipt $Receipt -Reason 'probe_requires_explicit_binding'
            }
            [void](Invoke-V4PrepareActivity -Context $Context -SessionId $Checkpoint.session_id -OwnerToken $Checkpoint.lease.owner_token `
                -ExpectedRevision $Checkpoint.revision -IdempotencyKey "prepare-$ActivityId" -Payload $Contract)
            $Checkpoint=(Get-V4CurrentSession -Context $Context).value
        }
        catch {
            return New-V4Response -Status 'blocked' -NextAction 'retry_classroom_transition' -ReasonCode 'main_preparation_pending' `
                -Receipt ([pscustomobject]@{session_id=$Checkpoint.session_id;owner_token=$Checkpoint.lease.owner_token;revision=$Checkpoint.revision}) `
                -PreparedStep ([pscustomobject]@{detail=$_.Exception.Message;review_saved=(@($Checkpoint.pending_review_batches).Count -gt 0)}) `
                -ProtocolRefs @('references/classroom-flow.md','references/tracker-actions.md')
        }
    }
    return Get-V4ClassroomResponse -Context $Context -Checkpoint $Checkpoint -Receipt $Receipt
}

function Invoke-V4ClassroomBootstrap {
    param([object]$Context, [string]$IdempotencyKey, [string]$FaultAfterPhase)
    $Response=Invoke-V4Bootstrap -Context $Context -FaultAfterPhase $FaultAfterPhase
    # Never cross a completed recovery transaction into another lesson in the same request.
    if ($Response.next_action -eq 'start_session') {
        if ([string]::IsNullOrWhiteSpace($IdempotencyKey)) { throw 'Bootstrap -EnterSession requires a stable IdempotencyKey.' }
        $Response=Invoke-V4StartSession -Context $Context -IdempotencyKey $IdempotencyKey -Classroom -FaultAfterPhase $FaultAfterPhase
    }
    $Read=Get-V4CurrentSession -Context $Context
    if ($Response.status -in @('started','resume') -and $null -ne $Read -and $Read.status -eq 'valid' -and
        $Read.value.status -eq 'in_progress' -and (Test-V4Classroom $Read.value)) {
        return Complete-V4ClassroomTransition -Context $Context -Receipt $Response.receipt -FaultAfterPhase $FaultAfterPhase
    }
    return $Response
}

function Invoke-V4PrepareReviewQuestions {
    param([object]$Context, [string]$SessionId, [string]$OwnerToken, [int]$ExpectedRevision, [string]$IdempotencyKey, [object]$Payload)
    [void](Assert-V4Active -Context $Context)
    if ([string]::IsNullOrWhiteSpace($IdempotencyKey)) { throw 'A stable review preparation key is required.' }
    if ([Text.Encoding]::UTF8.GetByteCount((ConvertTo-CanonicalJson $Payload)) -gt 65536) { throw 'Review preparation exceeds its bounded envelope.' }
    return Invoke-WithFileLock -LockPath $Context.paths.lock -Script {
        $Hash=Get-PayloadHash $Payload
        $Checkpoint=Get-V4CheckpointForReplay -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken
        $Known=Find-V4IdempotencyReceipt -Checkpoint $Checkpoint -IdempotencyKey $IdempotencyKey -PayloadHash $Hash
        if ($null -ne $Known) { return Get-V4ClassroomResponse -Context $Context -Checkpoint $Checkpoint -Receipt $Known.receipt -Reason 'idempotent_replay' }
        $Checkpoint=Get-V4CheckpointForWrite -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken -ExpectedRevision $ExpectedRevision
        Assert-V4ClassroomQueue -Context $Context -Checkpoint $Checkpoint
        if (-not (Test-V4Classroom $Checkpoint) -or $Checkpoint.waiting_action -ne 'prepare_review_questions') { throw 'Review preparation is not the current action.' }
        $Questions=@(Get-ReducerValue $Payload 'questions' @())
        $Selected=@($Checkpoint.review_state.selected)
        if ($Questions.Count -ne $Selected.Count -or $Questions.Count -lt 1) { throw 'Freeze the selected slice exactly once, in its original order.' }
        $Weight=0
        for ($i=0;$i -lt $Questions.Count;$i++) {
            $InputQuestion=$Questions[$i];$Item=$Selected[$i]
            $Q=[pscustomobject]@{review_item_id=$InputQuestion.review_item_id;prompt_text=[string]$InputQuestion.prompt_text;task_contract=$InputQuestion.task_contract}
            $Questions[$i]=$Q
            if ($Q.review_item_id -ne $Item.review_item_id) { throw 'Review order or membership changed.' }
            if ($Item.target_scope -in @('exact_expression','pattern','meaning_or_function') -and $Q.task_contract.target_scope -ne $Item.target_scope) { throw 'Review target scope changed.' }
            $AllowedTypes=switch ($Item.review_family) {
                'receptive_meaning' { @('meaning_explanation','contextual_meaning') }
                'productive_expression' { @('constrained_fill','contrast_drill','constrained_production') }
                'productive_pattern' { @('constrained_fill','controlled_rewrite','constrained_production') }
                default { @() }
            }
            if (@($AllowedTypes).Count -gt 0 -and $Q.task_contract.question_type -notin $AllowedTypes) { throw 'Review question type changes the frozen family.' }
            if ([string]::IsNullOrWhiteSpace([string]$Q.prompt_text) -or $Q.prompt_text.Length -gt 1200) { throw 'A bounded review prompt is required.' }
            $Check=Test-V4ReviewQuestionContract -Item $Item -Contract $Q.task_contract
            if (-not $Check.valid) { throw "Invalid review contract: $($Check.errors -join '; ')" }
            foreach ($Name in @('lane','recipe_stage')) { $Q | Add-Member $Name $Item.$Name -Force }
            $Q | Add-Member weight (Get-ReviewWeight -RecipeStage $Item.recipe_stage) -Force
            $Q | Add-Member question_instance_id (New-StableIdentifier -Prefix 'RQ-' -Seed "$SessionId|$($Q.review_item_id)" -HashLength 20) -Force
            $Q | Add-Member disposition 'pending' -Force
            $Weight += Get-ReviewWeight -RecipeStage $Item.recipe_stage
        }
        $Limit=if ($Checkpoint.review_state.recovery_mode) {10} else {6}
        $Capacity=if ($Checkpoint.review_state.recovery_mode) {20} else {12}
        if ($Questions.Count -gt $Limit -or $Weight -gt $Capacity) { throw 'Frozen review exceeds selected capacity.' }
        $Checkpoint.classroom_review.questions=$Questions
        $Checkpoint.waiting_action='present_review_question'
        $Receipt=[pscustomobject]@{operation='PrepareReviewQuestions';idempotency_key=$IdempotencyKey;revision=($ExpectedRevision+1)}
        Add-V4CheckpointReceipt -Checkpoint $Checkpoint -IdempotencyKey $IdempotencyKey -PayloadHash $Hash -Receipt $Receipt
        [void](Save-V4Checkpoint -Context $Context -Checkpoint $Checkpoint)
        return Get-V4ClassroomResponse -Context $Context -Checkpoint $Checkpoint -Receipt $Receipt -Status 'prepared'
    }
}

function Invoke-V4SaveReviewAnswer {
    param([object]$Context, [string]$SessionId, [string]$OwnerToken, [int]$ExpectedRevision, [string]$IdempotencyKey, [object]$Payload, [string]$FaultAfterPhase)
    [void](Assert-V4Active -Context $Context)
    if ([string]::IsNullOrWhiteSpace($IdempotencyKey)) { throw 'A stable review answer key is required.' }
    $Receipt=Invoke-WithFileLock -LockPath $Context.paths.lock -Script {
        $Hash=Get-PayloadHash $Payload
        $Checkpoint=Get-V4CheckpointForReplay -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken
        $Known=Find-V4IdempotencyReceipt -Checkpoint $Checkpoint -IdempotencyKey $IdempotencyKey -PayloadHash $Hash
        if ($null -ne $Known) { return $Known.receipt }
        $Checkpoint=Get-V4CheckpointForWrite -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken -ExpectedRevision $ExpectedRevision
        Assert-V4ClassroomQueue -Context $Context -Checkpoint $Checkpoint
        if (-not (Test-V4Classroom $Checkpoint) -or $Checkpoint.waiting_action -notin @('present_review_question','repair_review','reconstruct_review')) { throw 'No review response is expected.' }
        $Review=$Checkpoint.classroom_review
        $Question=$Review.questions[$Review.cursor]
        if ($Payload.question_instance_id -ne $Question.question_instance_id) { throw 'Answer does not match the current frozen question.' }
        if (-not (Test-ReducerTrue (Get-ReducerValue $Payload 'feedback_shown' $false))) { throw 'Show feedback before saving.' }
        $Next=[string](Get-ReducerValue $Payload 'followup' 'advance')
        if ($Next -notin @('advance','repair','reconstruct')) { throw 'Invalid review followup.' }
        $Feedback=[string](Get-ReducerValue $Payload 'feedback_text' '')
        $Prompt=[string](Get-ReducerValue $Payload 'followup_prompt' '')
        if ($Feedback.Length -gt 1200 -or $Prompt.Length -gt 600 -or [string]::IsNullOrWhiteSpace($Feedback)) { throw 'A bounded visible feedback summary is required.' }
        if ($Next -ne 'advance' -and [string]::IsNullOrWhiteSpace($Prompt)) { throw 'A repair requires a frozen followup prompt.' }
        $Batches=@($Checkpoint.pending_review_batches | Where-Object batch_id -eq $Review.batch_id)
        if ($Batches.Count -eq 0) {
            $Batch=[pscustomobject]@{batch_id=$Review.batch_id;idempotency_key=$Review.batch_id;payload_hash='';study_date=$Checkpoint.study_date;session_id=$SessionId;source_session_outcome='pending';feedback_shown=$true;total_weight=0;items=@()}
            $Checkpoint.pending_review_batches=@($Checkpoint.pending_review_batches)+@($Batch)
        } else { $Batch=$Batches[0] }
        $Control=[string](Get-ReducerValue $Payload 'control' '')
        if ($Control -notin @('','skip','exposed')) { throw 'Unsupported review control.' }
        if ($Checkpoint.waiting_action -eq 'present_review_question') {
            if ($Control) {
                if ($Next -ne 'advance') { throw 'Deferred questions cannot enter repair.' }
                if ($null -ne (Get-ReducerValue $Payload 'rating' $null)) { throw 'An unassessed control cannot carry a rating.' }
                $Question.disposition=$Control
            } else {
                $Rating=[string](Get-ReducerValue $Payload 'rating' '')
                if ($Rating -notin @('again','hard','good','easy','invalid')) { throw 'Invalid first rating.' }
                if ($Rating -eq 'easy' -and ($Question.recipe_stage -ne 'constrained_transfer' -or $Question.lane -eq 'legacy')) { throw 'easy is not allowed for this question.' }
                foreach ($Name in @('answer_excerpt','language_validity','target_demonstrated','rating_reason')) {
                    if ([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Payload $Name ''))) { throw "Review result requires $Name." }
                }
                if ($Payload.language_validity -notin @('pass','fail','not_assessable') -or
                    $Payload.target_demonstrated -notin @('demonstrated','not_demonstrated','not_assessable')) { throw 'Invalid review judgment labels.' }
                if ([string]$Payload.answer_excerpt -and $Payload.answer_excerpt.Length -gt 600) { throw 'Answer excerpt exceeds privacy bound.' }
                if ($Rating -eq 'invalid' -and [string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Payload 'invalid_reason' ''))) { throw 'invalid requires its reason.' }
                if ($Next -ne 'advance' -and ($Next -ne 'repair' -or $Rating -ne 'again' -or $Review.repair_count -ge 3)) { throw 'Only the first three again items may enter one short repair.' }
                $Result=ConvertFrom-StableJson -Json (ConvertTo-CanonicalJson $Question)
                foreach ($Name in @('answer_excerpt','language_validity','target_demonstrated','rating','rating_reason','invalid_reason')) { $Result | Add-Member $Name (Get-ReducerValue $Payload $Name '') -Force }
                # Existing reducers use yes/no; keep the public classroom labels readable.
                if ($Result.target_demonstrated -eq 'demonstrated') { $Result.target_demonstrated='yes' }
                elseif ($Result.target_demonstrated -eq 'not_demonstrated') { $Result.target_demonstrated='no' }
                $Result | Add-Member answered_at (Get-V4Timestamp -Context $Context) -Force
                $Result | Add-Member event_id (New-StableIdentifier -Prefix 'R-' -Seed "$($Review.batch_id)|$($Question.review_item_id)|event" -HashLength 24) -Force
                $Result | Add-Member audit_id (New-StableIdentifier -Prefix 'RA-' -Seed "$($Review.batch_id)|$($Question.review_item_id)|audit" -HashLength 24) -Force
                $Result | Add-Member repair_result ([pscustomobject]@{status=$Next;support='none';attempts=0}) -Force
                $Result | Add-Member exposed $false -Force
                $Result | Add-Member model_exposed $false -Force
                $Result | Add-Member pre_state $null -Force
                $Batch.items=@($Batch.items)+@($Result)
                $Batch.total_weight += [int]$Question.weight
                $Question.disposition='answered'
                if ($Next -eq 'repair') { $Review.repair_count++;$Result.repair_result.support='guided' }
            }
        } else {
            if ($Control -or $null -ne (Get-ReducerValue $Payload 'rating' $null)) { throw 'Repair cannot replace the first rating or defer an answered question.' }
            $Result=@($Batch.items | Where-Object question_instance_id -eq $Question.question_instance_id)[0]
            if ($Checkpoint.waiting_action -eq 'reconstruct_review' -and $Next -ne 'advance') { throw 'Reconstruction ends this short repair.' }
            if ($Next -eq 'repair') { throw 'Only one prompted repair is allowed.' }
            $Result.repair_result=[pscustomobject]@{status=$Next;support='guided';attempts=([int]$Result.repair_result.attempts+1);answer_excerpt=[string](Get-ReducerValue $Payload 'answer_excerpt' '')}
            if ($Result.repair_result.answer_excerpt.Length -gt 600) { throw 'Repair excerpt exceeds privacy bound.' }
            if ($Next -eq 'reconstruct') { $Result.model_exposed=$true }
        }
        foreach ($Id in @((Get-ReducerValue $Payload 'exposed_question_ids' @()))) {
            $Matches=@($Review.questions | Where-Object { $_.question_instance_id -eq $Id -and $_.disposition -eq 'pending' })
            if ($Matches.Count -ne 1 -or $Id -eq $Question.question_instance_id) { throw 'Only unasked frozen questions may be deferred as exposed.' }
            $Matches[0].disposition='exposed'
        }
        $Review.feedback_text=$Feedback;$Review.followup_prompt=$Prompt
        if ($Next -eq 'advance') {
            $Review.cursor++
            while ($Review.cursor -lt @($Review.questions).Count -and $Review.questions[$Review.cursor].disposition -eq 'exposed') { $Review.cursor++ }
            if ($Review.cursor -lt @($Review.questions).Count) { $Checkpoint.waiting_action='present_review_question' }
            else {
                if (@($Batch.items).Count -gt 0) { $Checkpoint.completed_stages=@($Checkpoint.completed_stages)+@('review') | Select-Object -Unique }
                $Checkpoint.waiting_action=if ($Checkpoint.session_type -eq 'review' -and $Checkpoint.plan_role -ne 'cycle_review') {'show_summary'} else {'prepare_activity'}
            }
        } else { $Checkpoint.waiting_action=if ($Next -eq 'repair') {'repair_review'} else {'reconstruct_review'} }
        $Batch.payload_hash=Get-PayloadHash $Batch.items
        $Receipt=[pscustomobject]@{operation='SaveReviewAnswer';idempotency_key=$IdempotencyKey;question_instance_id=$Question.question_instance_id;revision=($ExpectedRevision+1)}
        Add-V4CheckpointReceipt -Checkpoint $Checkpoint -IdempotencyKey $IdempotencyKey -PayloadHash $Hash -Receipt $Receipt
        [void](Save-V4Checkpoint -Context $Context -Checkpoint $Checkpoint)
        return $Receipt
    }
    return Complete-V4ClassroomTransition -Context $Context -Receipt $Receipt -FaultAfterPhase $FaultAfterPhase
}
