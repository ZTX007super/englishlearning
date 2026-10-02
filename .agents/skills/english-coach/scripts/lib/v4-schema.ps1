Set-StrictMode -Version Latest

$script:V4PlanHeaders = @(
    'plan_item_id','plan_id','sequence','title','session_type','primary_skill','required',
    'status','completed_session_id','focus_goal_id','plan_role'
)
$script:V4EvidenceHeaders = @(
    'evidence_id','session_id','skill','phase','metric','score','scale','evidence','next_focus',
    'record_kind','event_seq','recorded_at','observation_id','ref_observation_id','idempotency_key',
    'plan_item_id','activity_id','criterion_id','loop_id','attempt_no','lead_or_auxiliary','purpose',
    'evidence_mode','evidence_kind','catalog_version','ladder_version','contract_version','competency_id',
    'competency_family','activity_family','indicator_id','anchor_id','role','review_item_id','focus_goal_id','template_id',
    'adaptation_key','load_axis_id','planned_step','target_step','presented_step','changed_dimension',
    'task_fingerprint','day_id','comparability_group','content_id','context_id','primary_result',
    'criterion_result','criterion_results_json','secondary_projection_json','task_result','core_result',
    'challenge_result','validity','invalid_reason','cost_signal','planned_support_json',
    'allowed_support_json','actual_support_json','support_level','support_kind','model_exposed',
    'access_profile_json','source_session_outcome'
)
$script:V4ReviewItemHeaders = @(
    'review_item_id','concept_id','target_version','target_form','target_meaning','review_family',
    'target_scope','allowed_variants_json','known_confusions_json','context_seeds_json','recipe_stage',
    'strength_level','status','next_review','recheck_due','maintenance_interval_days','legacy_level',
    'legacy_due','last_review','maintenance_ready','created_at','updated_at'
)
$script:V4ReviewSourceHeaders = @(
    'source_link_id','review_item_id','source_type','source_id','relation','source_session_id','linked_at'
)
$script:V4ReviewCandidateHeaders = @(
    'candidate_id','concept_key','item_kind','target_form','target_meaning','status','first_seen_at',
    'last_seen_at','source_session_id','source_ids_json','recurrence_count','priority_factors_json',
    'requested_by_user','activated_review_item_id','idempotency_key'
)
$script:V4ReviewHistoryHeaders = @(
    'event_id','reviewed_at','study_date','session_id','item_type','item_id','result','old_level',
    'new_level','previous_due','next_review'
)
$script:V4ReviewAuditHeaders = @(
    'audit_id','event_id','batch_id','question_instance_id','review_item_id','record_kind',
    'ref_event_id','event_seq','recorded_at','answered_at','study_date','session_id',
    'source_session_outcome','idempotency_key','recipe_stage','lane','weight','prompt_text',
    'task_contract_json','answer_excerpt','language_validity','target_demonstrated','rating',
    'rating_reason','invalid_reason','repair_result_json','exposed','model_exposed'
)
$script:V4FocusGoalHeaders = @(
    'goal_id','goal_key','version','supersedes_goal_id','stage_id','skill','competency_id',
    'competency_family','activity_family','quality_focus','goal_text','success_criteria_json',
    'min_completed_cycles','max_completed_cycles','start_cycle_id','status','end_cycle_id',
    'created_at','updated_at'
)
$script:V4GoalEventHeaders = @(
    'event_id','event_seq','occurred_at','study_date','cycle_id','goal_id','decision','reason',
    'evidence_ids_json','replacement_goal_id','catalog_version','goal_contract_version','idempotency_key'
)
$script:V4CompetencyStatusHeaders = @(
    'competency_id','family_id','stage_id','skill','level','role','status','decisive_event_ids_json',
    'evidence_ids_json','flags_json','catalog_version','projection_revision','updated_at'
)
$script:V4CompetencyEventHeaders = @(
    'event_id','event_seq','occurred_at','study_date','cycle_id','session_id','competency_id',
    'indicator_id','anchor_id','event_type','from_status','to_status','evidence_ids_json','reason',
    'catalog_version','idempotency_key'
)
$script:V4StageEventHeaders = @(
    'event_id','event_seq','occurred_at','study_date','cycle_id','skill','stage_id','event_type',
    'prerequisite_gate_ids_json','evidence_ids_json','catalog_version','idempotency_key'
)
$script:V4InsightHeaders = @(
    'insight_id','insight_key','version','insight_type','scope_type','scope_id','claim',
    'evidence_ids_json','counterevidence_ids_json','teaching_implication','status','freshness',
    'created_cycle_id','last_confirmed_cycle_id','supersedes_insight_id','created_at','updated_at',
    'idempotency_key'
)

function New-V4Context {
    param(
        [Parameter(Mandatory = $true)][string]$ProjectRoot,
        [datetime]$Date
    )
    $Root = (Resolve-Path -LiteralPath $ProjectRoot).Path
    $SettingsPath = Join-Path $Root 'learner\settings.json'
    $Settings = Read-StableJsonFile -Path $SettingsPath
    if ([string]::IsNullOrWhiteSpace([string]$Settings.windows_timezone_id)) {
        throw 'settings.json is missing windows_timezone_id.'
    }
    $TimeZone = [TimeZoneInfo]::FindSystemTimeZoneById([string]$Settings.windows_timezone_id)
    $Now = if ($PSBoundParameters.ContainsKey('Date')) {
        [DateTime]::SpecifyKind($Date, [DateTimeKind]::Unspecified)
    }
    else {
        [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $TimeZone)
    }
    $Paths = [ordered]@{
        settings = $SettingsPath
        plans = Join-Path $Root 'learner\plan-items.tsv'
        evidence = Join-Path $Root 'learner\skill-evidence.tsv'
        review_items = Join-Path $Root 'learner\review-items.tsv'
        review_sources = Join-Path $Root 'learner\review-item-sources.tsv'
        review_candidates = Join-Path $Root 'learner\review-candidates.tsv'
        review_history = Join-Path $Root 'learner\review-history.tsv'
        review_audit = Join-Path $Root 'learner\review-audit.tsv'
        focus_goals = Join-Path $Root 'learner\focus-goals.tsv'
        goal_events = Join-Path $Root 'learner\goal-events.tsv'
        competency_status = Join-Path $Root 'learner\competency-status.tsv'
        competency_events = Join-Path $Root 'learner\competency-events.tsv'
        stage_events = Join-Path $Root 'learner\stage-events.tsv'
        insights = Join-Path $Root 'learner\learning-insights.tsv'
        adaptation = Join-Path $Root 'learner\adaptation-state.json'
        long_term = Join-Path $Root 'learner\long-term-projection.json'
        sessions = Join-Path $Root 'sessions'
        state = Join-Path $Root '.state'
        runtime = Join-Path $Root '.state\runtime.json'
        migration = Join-Path $Root '.state\migration-v4-transaction.json'
        start_intent = Join-Path $Root '.state\start-intent.json'
        session_transaction = Join-Path $Root '.state\session-transaction.json'
        current_session = Join-Path $Root '.state\current-session.json'
        bootstrap_index = Join-Path $Root '.state\bootstrap-index.json'
        current_cycle_evidence = Join-Path $Root '.state\current-cycle-evidence.json'
        packages = Join-Path $Root '.state\packages'
        skeletons = Join-Path $Root '.state\cycle-skeletons'
        lock = Join-Path $Root '.state\tracker-v4.lock'
    }
    return [pscustomobject]@{
        root = $Root
        settings = $Settings
        timezone = $TimeZone
        now = $Now
        study_date = $Now.Date
        paths = [pscustomobject]$Paths
    }
}

function Get-V4Timestamp {
    param([Parameter(Mandatory = $true)][object]$Context)
    $Offset = $Context.timezone.GetUtcOffset($Context.now)
    $Unspecified = [DateTime]::SpecifyKind($Context.now, [DateTimeKind]::Unspecified)
    return ([DateTimeOffset]::new($Unspecified, $Offset)).ToString('yyyy-MM-ddTHH:mm:sszzz')
}

function Get-V4Runtime {
    param([Parameter(Mandatory = $true)][object]$Context)
    $Read = Read-DurableJson -Path $Context.paths.runtime -AllowMissing
    if ($null -eq $Read) {
        return [pscustomobject]@{ status = 'legacy'; runtime_version = 3; reason_code = 'runtime_pointer_absent' }
    }
    if ($Read.status -ne 'valid') {
        return [pscustomobject]@{ status = 'blocked'; runtime_version = 0; reason_code = 'runtime_pointer_invalid' }
    }
    return $Read.value
}

function Assert-V4Active {
    param([Parameter(Mandatory = $true)][object]$Context)
    $Runtime = Get-V4Runtime -Context $Context
    if ([int](Get-ReducerValue $Runtime 'runtime_version' 0) -ne 4 -or
        [string](Get-ReducerValue $Runtime 'status' '') -ne 'active') {
        throw "Runtime v4 is not active: $([string](Get-ReducerValue $Runtime 'reason_code' 'not_active'))"
    }
    return $Runtime
}

function ConvertFrom-V4Payload {
    param(
        [string]$PayloadJson,
        [switch]$AllowEmpty
    )
    if ([string]::IsNullOrWhiteSpace($PayloadJson)) {
        if ($AllowEmpty) { return $null }
        throw 'This action requires -PayloadJson.'
    }
    return ConvertFrom-StableJson -Json $PayloadJson
}

function Get-V4QueueGuard {
    param([Parameter(Mandatory = $true)][object]$Index)
    $GuardInput = [pscustomobject]@{
        plan_id = [string](Get-ReducerValue $Index 'plan_id' '')
        plan_item_id = [string](Get-ReducerValue $Index 'next_plan_item_id' '')
        queue_revision = [int](Get-ReducerValue $Index 'queue_revision' 0)
        package_hash = [string](Get-ReducerValue $Index 'package_hash' '')
        focus_goal_id = [string](Get-ReducerValue $Index 'focus_goal_id' '')
    }
    return Get-PayloadHash -Payload $GuardInput
}

function Test-V4ActivityContract {
    param([Parameter(Mandatory = $true)][object]$Activity)
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Families = @(
        'source_comprehension','retell_summary','opinion_explanation','interaction_roleplay',
        'integrated_response','controlled_form','extended_writing','oral_imitation'
    )
    $Family = [string](Get-ReducerValue $Activity 'activity_family' '')
    if ($Family -notin $Families) { $Errors.Add("Invalid activity_family: $Family") }
    $Purpose = [string](Get-ReducerValue $Activity 'purpose' '')
    if ($Purpose -notin @('practice','probe','transfer','assessment')) { $Errors.Add("Invalid purpose: $Purpose") }
    $Mode = [string](Get-ReducerValue $Activity 'mode' '')
    if ($Mode -notin @('accuracy','fluency','mixed')) { $Errors.Add("Invalid mode: $Mode") }
    $EvidenceMode = [string](Get-ReducerValue $Activity 'evidence_mode' 'training')
    if ($EvidenceMode -notin @('training','target_check','difficulty_probe','capability_probe','assessment')) {
        $Errors.Add("Invalid evidence_mode: $EvidenceMode")
    }
    if ($Purpose -eq 'practice' -and $EvidenceMode -eq 'difficulty_probe') {
        $Errors.Add('practice cannot be a difficulty_probe.')
    }
    if ($EvidenceMode -eq 'capability_probe' -and $Purpose -notin @('probe','assessment')) {
        $Errors.Add('capability_probe requires probe or assessment purpose.')
    }
    $RequiredText = @(
        'session_id','contract_id','modality','primary_construct','correction_timing','competency_id',
        'indicator_id','anchor_id','template_id','planned_step','target_step','presented_step',
        'changed_dimension','content_id','context_id','package_hash','catalog_version','ladder_version',
        'contract_version','review_schema_version','queue_guard'
    )
    foreach ($Name in $RequiredText) {
        if ([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Activity $Name ''))) {
            $Errors.Add("$Name is required before presentation.")
        }
    }
    foreach ($Name in @('access_profile','planned_support','allowed_support','adapter','hint_ladder','max_support','transfer_rule','retry_budget','loop_budget','transfer_budget','complexity_budget')) {
        if ($null -eq (Get-ReducerValue $Activity $Name $null)) {
            $Errors.Add("$Name is required before presentation.")
        }
    }
    if ($null -eq (Get-ReducerValue $Activity 'semantic_scope' $null) -and
        $null -eq (Get-ReducerValue $Activity 'answer_key' $null)) {
        $Errors.Add('semantic_scope or answer_key is required before presentation.')
    }
    $Criteria = @((Get-ReducerValue $Activity 'criteria' @()))
    if ($Criteria.Count -lt 1 -or $Criteria.Count -gt 3) { $Errors.Add('A scored activity requires one to three criteria.') }
    foreach ($Criterion in $Criteria) {
        if ([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Criterion 'criterion_id' ''))) {
            $Errors.Add('Each criterion requires a stable criterion_id.')
        }
        if ([string](Get-ReducerValue $Criterion 'importance' '') -notin @('essential','required')) {
            $Errors.Add('Each criterion must be essential or required.')
        }
    }
    if ([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Activity 'activity_id' ''))) {
        $Errors.Add('activity_id is required.')
    }
    return [pscustomobject]@{ valid = $Errors.Count -eq 0; errors = @($Errors) }
}

function Test-V4ReviewQuestionContract {
    param(
        [Parameter(Mandatory = $true)][object]$Item,
        [Parameter(Mandatory = $true)][object]$Contract
    )
    $Errors=[System.Collections.Generic.List[string]]::new()
    $QuestionType=[string](Get-ReducerValue $Contract 'question_type' '')
    if($QuestionType -notin @('meaning_explanation','constrained_fill','controlled_rewrite','contrast_drill','constrained_production','contextual_meaning')){
        $Errors.Add("Invalid review question_type: $QuestionType")
    }
    $TargetScope=[string](Get-ReducerValue $Contract 'target_scope' '')
    if($TargetScope -notin @('exact_expression','pattern','meaning_or_function')){$Errors.Add("Invalid review target_scope: $TargetScope")}
    if([int](Get-ReducerValue $Contract 'target_count' 0)-ne1){$Errors.Add('A review question must have exactly one scoring target.')}
    foreach($Name in @('scoring_target','content_id','context_id')){
        if([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Contract $Name ''))){$Errors.Add("Review contract requires $Name.")}
    }
    foreach($Name in @('allowed_variants','standard_hints','invalid_conditions')){
        if($null-eq(Get-ReducerValue $Contract $Name $null)){$Errors.Add("Review contract requires $Name.")}
    }
    if($null-eq(Get-ReducerValue $Contract 'answer_key' $null)-and$null-eq(Get-ReducerValue $Contract 'semantic_scope' $null)){
        $Errors.Add('Review contract requires answer_key or semantic_scope.')
    }
    if(-not(Test-ReducerTrue(Get-ReducerValue $Contract 'ambiguity_checked' $false))){$Errors.Add('Review ambiguity gate was not confirmed.')}
    if(-not(Test-ReducerTrue(Get-ReducerValue $Contract 'batch_leakage_checked' $false))){$Errors.Add('Review batch leakage gate was not confirmed.')}
    $Stage=[string](Get-ReducerValue $Item 'recipe_stage' '')
    if($Stage -in @('recall','constrained_transfer')-and
        ((Test-ReducerTrue(Get-ReducerValue $Contract 'uses_options' $false))-or(Test-ReducerTrue(Get-ReducerValue $Contract 'uses_word_bank' $false)))){
        $Errors.Add('Recall and constrained transfer cannot use options or a word bank.')
    }
    return [pscustomobject]@{valid=$Errors.Count-eq0;errors=@($Errors)}
}

function Test-V4IssueBatch {
    param(
        [AllowEmptyCollection()][object[]]$Issues=@(),
        [AllowEmptyCollection()][string[]]$CriterionIds=@()
    )
    $Errors=[System.Collections.Generic.List[string]]::new();$Seen=@{}
    foreach($Issue in @($Issues)){
        $IssueId=[string](Get-ReducerValue $Issue 'issue_id' '')
        if([string]::IsNullOrWhiteSpace($IssueId)){$Errors.Add('Each selected issue requires issue_id.')}
        elseif($Seen.ContainsKey($IssueId)){$Errors.Add("Duplicate selected issue: $IssueId")}else{$Seen[$IssueId]=$true}
        foreach($Name in @('issue_type','focus_relation','impact','root_cause','nature')){
            if([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Issue $Name ''))){$Errors.Add("Issue $IssueId requires $Name.")}
        }
        if([string](Get-ReducerValue $Issue 'nature' '') -notin @('error','upgrade_opportunity')){$Errors.Add("Issue $IssueId has invalid nature.")}
        $Affected=[string](Get-ReducerValue $Issue 'affected_criterion' '')
        if(-not[string]::IsNullOrWhiteSpace($Affected)-and$Affected-notin$CriterionIds){$Errors.Add("Issue $IssueId references an unknown criterion.")}
        if($null-eq(Get-ReducerValue $Issue 'recurrence_evidence_ids' $null)){$Errors.Add("Issue $IssueId must declare recurrence_evidence_ids, even when empty.")}
        if(Test-ReducerTrue(Get-ReducerValue $Issue 'full_loop' $false)){
            if([string](Get-ReducerValue $Issue 'adapter' '') -notin @('meaning','fact_location','organization','grammar_form','lexis_register','pragmatics_interaction','pronunciation_intelligibility')){$Errors.Add("Issue $IssueId has invalid adapter.")}
            $Cost=[int](Get-ReducerValue $Issue 'complexity_cost' 0);if($Cost-notin@(1,2)){$Errors.Add("Issue $IssueId has invalid complexity cost.")}
            $Retries=[int](Get-ReducerValue $Issue 'retry_count' 0);if($Retries-lt0-or$Retries-gt2){$Errors.Add("Issue $IssueId exceeds two retries.")}
            if([string](Get-ReducerValue $Issue 'scope' '') -notin @('local','global')){$Errors.Add("Issue $IssueId requires local or global scope.")}
            if([string](Get-ReducerValue $Issue 'waiting_action' '') -notin @('clarify','repair','transfer','advance')){$Errors.Add("Issue $IssueId requires a valid waiting_action.")}
        }
        if([string](Get-ReducerValue $Issue 'impact' '') -eq 'incidental_slip' -and(Test-ReducerTrue(Get-ReducerValue $Issue 'full_loop' $false))){$Errors.Add("Incidental slip $IssueId cannot consume a full loop.")}
    }
    return [pscustomobject]@{valid=$Errors.Count-eq0;errors=@($Errors)}
}

function Test-V4CoreBlueprint {
    param([Parameter(Mandatory = $true)][object]$Blueprint)
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Stage = [string](Get-ReducerValue $Blueprint 'stage' '')
    if ($Stage -eq 'cycle_review') {
        if ([string](Get-ReducerValue $Blueprint 'activity_family' '') -ne 'cycle_review') { $Errors.Add('cycle_review family is required.') }
        if ([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Blueprint 'prompt_text' ''))) { $Errors.Add('cycle_review prompt_text is required.') }
        if (@((Get-ReducerValue $Blueprint 'required_outputs' @())).Count -lt 1) { $Errors.Add('cycle_review required_outputs are missing.') }
        return [pscustomobject]@{ valid=$Errors.Count -eq 0; errors=@($Errors) }
    }
    if ($Stage -notin @('input','output')) { $Errors.Add("Invalid core stage: $Stage") }
    foreach ($Name in @('plan_item_id','activity_family','modality','purpose','mode','primary_construct','prompt_text')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Blueprint $Name ''))) { $Errors.Add("Core blueprint requires $Name.") }
    }
    if ([string](Get-ReducerValue $Blueprint 'activity_family' '') -notin @(
        'source_comprehension','retell_summary','opinion_explanation','interaction_roleplay',
        'integrated_response','controlled_form','extended_writing','oral_imitation'
    )) { $Errors.Add('Core blueprint activity_family is invalid.') }
    $Criteria = @((Get-ReducerValue $Blueprint 'criteria' @()))
    if ($Criteria.Count -lt 1 -or $Criteria.Count -gt 3) { $Errors.Add('Core blueprint requires one to three criteria.') }
    foreach ($Criterion in $Criteria) {
        if ([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Criterion 'criterion_id' '')) -or
            [string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Criterion 'description' '')) -or
            [string](Get-ReducerValue $Criterion 'importance' '') -notin @('essential','required')) {
            $Errors.Add('Each core criterion requires id, description, and essential/required importance.')
        }
    }
    if ($null -eq (Get-ReducerValue $Blueprint 'semantic_scope' $null) -and
        $null -eq (Get-ReducerValue $Blueprint 'answer_key' $null)) { $Errors.Add('Core blueprint requires semantic_scope or answer_key.') }
    $Modality = [string](Get-ReducerValue $Blueprint 'modality' '')
    $Material = Get-ReducerValue $Blueprint 'material' $null
    if ($Modality -eq 'listening') {
        foreach ($Name in @('audio_path','audio_sha256','transcript_path','transcript_sha256','transcript_text')) {
            if ($null -eq $Material -or [string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Material $Name ''))) { $Errors.Add("Listening core requires material.$Name.") }
        }
    }
    if ($Modality -eq 'reading' -and ($null -eq $Material -or [string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Material 'text' '')))) {
        $Errors.Add('Reading core requires bounded material.text.')
    }
    return [pscustomobject]@{ valid=$Errors.Count -eq 0; errors=@($Errors) }
}

function Get-V4NextActionContract {
    param([Parameter(Mandatory = $true)][string]$NextAction)
    $Reference = 'references/tracker-actions.md'
    switch ($NextAction) {
        'prepare_review_questions' { return [pscustomobject]@{kind='tracker';action='PrepareReviewQuestions';required_parameters=@('SessionId','OwnerToken','ExpectedRevision','IdempotencyKey','PayloadJson');values_from='current frozen review slice; compile all questions before presentation';reference='references/classroom-flow.md'} }
        { $_ -in @('present_review_question','repair_review','reconstruct_review') } { return [pscustomobject]@{kind='interaction';action=$NextAction;required_parameters=@();values_from='prepared_step.question or frozen followup_prompt; after visible feedback use SaveReviewAnswer';reference='references/classroom-flow.md'} }
        'retry_classroom_transition' { return [pscustomobject]@{kind='tracker';action='Bootstrap';required_parameters=@('EnterSession','IdempotencyKey');values_from='resume same session once; if still blocked report technical issue';reference='references/classroom-flow.md'} }
        'bootstrap' { return [pscustomobject]@{ kind='tracker'; action='Bootstrap'; required_parameters=@(); values_from='none'; reference=$Reference } }
        'start_session' { return [pscustomobject]@{ kind='tracker'; action='StartSession'; required_parameters=@('IdempotencyKey'); optional_parameters=@('PlanItemId','SourceType'); values_from='prepared_step plus caller-generated stable key'; reference=$Reference } }
        'confirm_next_cycle_plan' { return [pscustomobject]@{kind='interaction';action='confirm_next_cycle_plan';required_parameters=@();values_from='completed cycle review and existing learner confirmation; compile six training items plus one cycle review, then PublishCycle';reference='references/cycle-publication.md'} }
        'prepare_activity' { return [pscustomobject]@{ kind='tracker'; action='PrepareActivity'; required_parameters=@('SessionId','OwnerToken','ExpectedRevision','IdempotencyKey','PayloadJson'); values_from='latest receipt/prepared_step plus compiled activity contract'; reference=$Reference } }
        'evaluate_cycle_review' { return [pscustomobject]@{ kind='tracker'; action='EvaluateLongTermState'; required_parameters=@('SessionId'); values_from='receipt.session_id; tracker loads persisted evidence, no caller-authored evidence payload'; reference='references/long-term-state.md' } }
        'present_cycle_review_candidates' { return [pscustomobject]@{ kind='interaction'; action='present_cycle_review_candidates'; required_parameters=@(); values_from='prepared_step.evidence_packet and goal_candidates; show evidence limits and discuss plan before finalizing'; reference='references/long-term-state.md' } }
        'finalize_session' { return [pscustomobject]@{ kind='tracker'; action='FinalizeSession'; required_parameters=@('SessionId','OwnerToken','ExpectedRevision','IdempotencyKey','PayloadJson'); values_from='latest receipt/checkpoint and already-shown summary'; reference=$Reference } }
        'present_review' { return [pscustomobject]@{ kind='interaction'; action='present_review'; required_parameters=@(); values_from='prepared_step.review_items; stage results later with StageReviewBatch'; reference='references/review-protocol.md' } }
        'select_next_review_batch' { return [pscustomobject]@{ kind='interaction'; action='select_next_review_batch'; required_parameters=@(); values_from='remaining frozen review slice'; reference='references/review-protocol.md' } }
        'present_activity' { return [pscustomobject]@{ kind='interaction'; action='present_activity'; required_parameters=@(); values_from='prepared_step.contract public fields'; reference='references/task-contracts.md' } }
        'await_answer' { return [pscustomobject]@{ kind='interaction'; action='await_answer'; required_parameters=@(); values_from='prepared_step'; reference='references/task-contracts.md' } }
        { $_ -in @('clarify','repair') } { return [pscustomobject]@{ kind='interaction'; action=$NextAction; required_parameters=@(); values_from='prepared_step.followup_state.followup_prompt; after feedback call SaveActivityCheckpoint with followup fields'; reference='references/teaching-loop.md' } }
        'show_transfer' { return [pscustomobject]@{ kind='tracker'; action='PrepareActivity'; required_parameters=@('SessionId','OwnerToken','ExpectedRevision','IdempotencyKey','PayloadJson'); values_from='new activity_id and complete contract using the frozen transfer rule and remaining budget'; reference='references/activity-preparation.md' } }
        'show_summary' { return [pscustomobject]@{ kind='interaction'; action='show_summary'; required_parameters=@(); values_from='frozen checkpoint results'; reference=$Reference } }
        default { return [pscustomobject]@{ kind='maintenance_or_router'; action=$NextAction; required_parameters=@(); values_from='reason_code and referenced protocol'; reference=$Reference } }
    }
}

function New-V4Response {
    param(
        [string]$Status,
        [string]$NextAction,
        [AllowNull()][object]$Receipt = $null,
        [string]$ReasonCode = 'ok',
        [AllowNull()][object]$PreparedStep = $null,
        [int]$RuntimeVersion = 4,
        [string[]]$ProtocolRefs = @('references/runtime-protocol-v4.md','references/tracker-actions.md')
    )
    $Response = New-TrackerResponse -Status $Status -NextAction $NextAction -Receipt $Receipt -ReasonCode $ReasonCode -PreparedStep $PreparedStep
    $Response | Add-Member -NotePropertyName runtime_version -NotePropertyValue $RuntimeVersion
    $Response | Add-Member -NotePropertyName protocol_refs -NotePropertyValue @($ProtocolRefs)
    $Response | Add-Member -NotePropertyName next_action_contract -NotePropertyValue (Get-V4NextActionContract -NextAction $NextAction)
    return $Response
}
