$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ScriptRoot = Join-Path $ProjectRoot '.agents\skills\english-coach\scripts'
$Tracker = Join-Path $ScriptRoot 'tracker-v4.ps1'
$MainTracker = Join-Path $ScriptRoot 'tracker.ps1'
foreach ($Library in @(
    'lib\state-io.ps1','lib\reducers.ps1','lib\v4-schema.ps1',
    'lib\session-runtime.ps1','lib\transaction-runtime.ps1','lib\maintenance-runtime.ps1',
    'lib\migration-runtime.ps1','lib\cycle-runtime.ps1','lib\classroom-runtime.ps1'
)) { . (Join-Path $ScriptRoot $Library) }

function Assert-ThrowsV4 {
    param([Parameter(Mandatory = $true)][scriptblock]$Operation)
    $Thrown = $false
    try { & $Operation | Out-Null } catch { $Thrown = $true }
    $Thrown | Should Be $true
}

function Invoke-V4Json {
    param([string]$Root, [hashtable]$Arguments)
    return ((& $Tracker -ProjectRoot $Root @Arguments | Out-String) | ConvertFrom-Json)
}

function New-V4Fixture {
    param([switch]$WithReview, [switch]$WithProbe, [switch]$WithFallback)
    $Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    foreach ($Relative in @('learner','sessions','.state','.state\packages')) {
        [void](New-Item -ItemType Directory -Force -Path (Join-Path $Root $Relative))
    }
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'learner\settings.json') -Destination (Join-Path $Root 'learner\settings.json')
    $Context = New-V4Context -ProjectRoot $Root -Date ([datetime]'2026-09-05T12:00:00')
    $Specs = @(
        @($Context.paths.evidence,$script:V4EvidenceHeaders),
        @($Context.paths.review_items,$script:V4ReviewItemHeaders),
        @($Context.paths.review_sources,$script:V4ReviewSourceHeaders),
        @($Context.paths.review_candidates,$script:V4ReviewCandidateHeaders),
        @($Context.paths.review_history,$script:V4ReviewHistoryHeaders),
        @($Context.paths.review_audit,$script:V4ReviewAuditHeaders),
        @($Context.paths.focus_goals,$script:V4FocusGoalHeaders),
        @($Context.paths.goal_events,$script:V4GoalEventHeaders),
        @($Context.paths.competency_status,$script:V4CompetencyStatusHeaders),
        @($Context.paths.competency_events,$script:V4CompetencyEventHeaders),
        @($Context.paths.stage_events,$script:V4StageEventHeaders),
        @($Context.paths.insights,$script:V4InsightHeaders)
    )
    foreach ($Spec in $Specs) { Write-TsvRowsAtomic -Path $Spec[0] -Rows @() -Headers $Spec[1] }
    $Plan = [pscustomobject]@{
        plan_item_id='P4-01'; plan_id='C0004'; sequence='1'; title='Fixture lesson';
        session_type='extra'; primary_skill='speaking'; required='true'; status='planned';
        completed_session_id=''; focus_goal_id=''; plan_role='maintenance'
    }
    Write-TsvRowsAtomic -Path $Context.paths.plans -Rows @($Plan) -Headers $script:V4PlanHeaders
    if ($WithReview) {
        $Review = [pscustomobject]@{
            review_item_id='RI-1'; concept_id='C-1'; target_version='1'; target_form='by doing';
            target_meaning='通过做某事'; review_family='collocation'; target_scope='gerund after by';
            allowed_variants_json='[]'; known_confusions_json='[]'; context_seeds_json='[]';
            recipe_stage='recall'; strength_level='0'; status='active'; next_review='2026-09-05';
            recheck_due=''; maintenance_interval_days=''; legacy_level=''; legacy_due='';
            created_at='2026-09-01T12:00:00+08:00'; updated_at='2026-09-01T12:00:00+08:00'
        }
        Write-TsvRowsAtomic -Path $Context.paths.review_items -Rows @($Review) -Headers $script:V4ReviewItemHeaders
    }
    [void](Write-DurableJson -Path $Context.paths.adaptation -Value ([pscustomobject]@{ schema_version=4; projection_revision=1; states=@() }))
    [void](Write-DurableJson -Path $Context.paths.long_term -Value ([pscustomobject]@{ schema_version=4; projection_revision=1; states=@() }))
    [void](Write-DurableJson -Path $Context.paths.current_cycle_evidence -Value ([pscustomobject]@{ schema_version=4; projection_revision=1; evidence_refs=@(); review_batch_refs=@() }))
    [void](Write-DurableJson -Path $Context.paths.runtime -Value ([pscustomobject]@{ schema_version=4; runtime_version=4; status='active'; activated_cycle_id='C0004' }))
    $PackagePath = Join-Path $Root '.state\packages\P4-01.json'
    [void](Write-DurableJson -Path $PackagePath -Value ([pscustomobject]@{
        schema_version=1;status='ready';plan_id='C0004';plan_item_id='P4-01';plan_role='maintenance';primary_skill='speaking';focus_goal_id='';
        policy_version='4.0.0';catalog_version='1.0.0';ladder_version='1.0.0';contract_version='4.0.0';rights_status='project_original';
        activity_skeletons=@([pscustomobject]@{activity_family='opinion_explanation';template_id='T-1'})
    }))
    $PackageHash = Get-FileSha256 -Path $PackagePath
    $Probe = if ($WithProbe) {
        [pscustomobject]@{ candidate_id='PC-1'; adaptation_key='AK-1'; activity_family='opinion_explanation'; competency_id='COMP-1'; changed_dimension='prompt_abstraction'; target_step='PA_2' }
    } else { $null }
    $ReviewSlice = if ($WithReview) {
        @([pscustomobject]@{ review_item_id='RI-1'; lane='active'; recipe_stage='recall'; weight=3; effective_due='2026-09-05'; review_family='collocation'; target_scope='gerund after by' })
    } else { @() }
    $Index = [pscustomobject]@{
        schema_version=4; index_revision=1; queue_revision=1; generated_at='2026-09-05T12:00:00+08:00';
        plan_id='C0004'; next_plan_item_id='P4-01'; next_title='Fixture lesson'; session_type='extra';
        primary_skill='speaking'; plan_role='maintenance'; focus_goal_id='';
        package_path=$(if($WithFallback){''}else{'.state/packages/P4-01.json'}); package_hash=$(if($WithFallback){''}else{$PackageHash});
        fallback_package_path=$(if($WithFallback){'.state/packages/P4-01.json'}else{''}); fallback_package_hash=$(if($WithFallback){$PackageHash}else{''}); compatible_previous_package_path=''; compatible_previous_package_hash='';
        next_package_descriptors=@(); preload_pending=$false; rebuild_required=$false; recovery_mode=$false;
        review_revision=1; review_due_counts=[pscustomobject]@{active=@($ReviewSlice).Count;maintenance=0;legacy=0;total=@($ReviewSlice).Count};
        review_candidates=$ReviewSlice; preauthorized_probe_candidate=$Probe;
        adaptation_projection_revision=1; long_term_projection_revision=1; policy_version='4.0.0';
        catalog_version='1.0.0'; ladder_version='1.0.0'; contract_version='4.0.0';
        protocol_refs=@('references/runtime-protocol-v4.md'); last_transaction_id=''; request_started_at=''; bootstrap_latency_ms=0; queue_guard=''
    }
    $Index.queue_guard = Get-V4QueueGuard -Index $Index
    [void](Write-DurableJson -Path $Context.paths.bootstrap_index -Value $Index)
    return $Root
}

function New-CyclePublicationFixture {
    $Root=New-V4Fixture
    $Context=New-V4Context -ProjectRoot $Root -Date ([datetime]'2026-09-25T12:00:00')
    $Start=Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='prior-review'}
    $Checkpoint=(Read-DurableJson -Path $Context.paths.current_session).value
    $Checkpoint.status='completed';$Checkpoint.plan_role='cycle_review'
    [void](Write-DurableJson -Path $Context.paths.current_session -Value $Checkpoint)
    [void](Write-DurableJson -Path $Context.paths.session_transaction -Value ([pscustomobject]@{phase='committed';disposition='completed';session_id=$Checkpoint.session_id}))
    $Plans=@(Get-TsvRows -Path $Context.paths.plans -Headers $script:V4PlanHeaders)
    $Plans[0].status='completed';$Plans[0].completed_session_id=$Checkpoint.session_id
    Write-TsvRowsAtomic -Path $Context.paths.plans -Rows $Plans -Headers $script:V4PlanHeaders
    $Index=(Read-DurableJson -Path $Context.paths.bootstrap_index).value
    $Index.next_plan_item_id='';$Index.queue_guard=Get-V4QueueGuard -Index $Index
    [void](Write-DurableJson -Path $Context.paths.bootstrap_index -Value $Index)
    $AssetRoot=Join-Path $Root '.agents/skills/english-coach/assets'
    [void](New-Item -ItemType Directory -Force -Path $AssetRoot)
    Copy-Item -LiteralPath (Join-Path $ProjectRoot '.agents/skills/english-coach/assets/c0005-ready-blueprints.json') -Destination $AssetRoot
    Copy-Item -LiteralPath (Join-Path $ProjectRoot '.agents/skills/english-coach/assets/fallback') -Destination $AssetRoot -Recurse
    $Goal=[ordered]@{};foreach($Header in $script:V4FocusGoalHeaders){$Goal[$Header]=''}
    $Goal.goal_id='FG-C0004-01';$Goal.status='active'
    Write-TsvRowsAtomic -Path $Context.paths.focus_goals -Rows @([pscustomobject]$Goal) -Headers $script:V4FocusGoalHeaders
    return $Root
}

function New-V4MigrationFixture {
    $Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    foreach ($Relative in @(
        'learner','sessions\2026\09','.state',
        '.agents\skills\english-coach\references',
        '.agents\skills\english-coach\assets','tests'
    )) { [void](New-Item -ItemType Directory -Force -Path (Join-Path $Root $Relative)) }
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'learner\settings.json') -Destination (Join-Path $Root 'learner\settings.json')
    foreach ($Name in @('competency-catalog.json','difficulty-ladders.json','migration-v4.schema.json')) {
        Copy-Item -LiteralPath (Join-Path $ProjectRoot ".agents\skills\english-coach\references\$Name") -Destination (Join-Path $Root ".agents\skills\english-coach\references\$Name")
    }
    Copy-Item -LiteralPath (Join-Path $ProjectRoot '.agents\skills\english-coach\assets\fallback') -Destination (Join-Path $Root '.agents\skills\english-coach\assets') -Recurse
    Copy-Item -LiteralPath (Join-Path $ProjectRoot 'tests\tracker-v4.Tests.ps1') -Destination (Join-Path $Root 'tests\tracker-v4.Tests.ps1')

    $V3PlanHeaders=@('plan_item_id','plan_id','sequence','title','session_type','primary_skill','required','status','completed_session_id')
    $C3=@(
        [pscustomobject]@{plan_item_id='P3-01';plan_id='C0003';sequence='1';title='Legacy training';session_type='integrated';primary_skill='speaking';required='true';status='completed';completed_session_id='S3-01'},
        [pscustomobject]@{plan_item_id='P3-02';plan_id='C0003';sequence='2';title='Legacy cycle review';session_type='review';primary_skill='integrated';required='true';status='completed';completed_session_id='S3-02'}
    )
    Write-TsvRowsAtomic -Path (Join-Path $Root 'learner\plan-items.tsv') -Rows $C3 -Headers $V3PlanHeaders
    Write-TsvRowsAtomic -Path (Join-Path $Root 'learner\skill-evidence.tsv') -Rows @([pscustomobject]@{
        evidence_id='EV3-1';session_id='S3-01';skill='speaking';phase='raw';metric='task';score='1';scale='binary';evidence='Legacy evidence';next_focus=''
    }) -Headers @('evidence_id','session_id','skill','phase','metric','score','scale','evidence','next_focus')
    Write-TsvRowsAtomic -Path (Join-Path $Root 'learner\review-history.tsv') -Rows @() -Headers $script:V4ReviewHistoryHeaders
    Write-TsvRowsAtomic -Path (Join-Path $Root 'learner\vocabulary.tsv') -Rows @([pscustomobject]@{
        id='V3-1';item='by doing';meaning='through an action';context='You improve by practicing.';status='active';level='2';next_review='2026-09-01';last_review='2026-08-20';source_session='S3-01'
    }) -Headers @('id','item','meaning','context','status','level','next_review','last_review','source_session')
    Write-TsvRowsAtomic -Path (Join-Path $Root 'learner\error-log.tsv') -Rows @([pscustomobject]@{
        id='ER3-1';category='grammar';original='He go';corrected='He goes';explanation='Third-person singular';status='paused';level='1';next_review='2026-09-02';last_review='2026-08-21';source_session='S3-01'
    }) -Headers @('id','category','original','corrected','explanation','status','level','next_review','last_review','source_session')
    Write-FlushedUtf8File -Path (Join-Path $Root 'sessions\2026\09\legacy.md') -Text "# Legacy session`n"
    Write-FlushedUtf8File -Path (Join-Path $Root '.state\legacy-marker.json') -Text '{"legacy":true}'
    return $Root
}

function New-V4ActivationPayload {
    param([string]$IdempotencyKey='activate-happy')
    $PlanItems=[System.Collections.Generic.List[object]]::new()
    $Packages=[System.Collections.Generic.List[object]]::new()
    $Skills=@('speaking','speaking','listening','reading','writing','speaking')
    for($i=0;$i -lt 6;$i++){
        $Sequence=$i+1;$PlanItemId="P4-$('{0:d2}' -f $Sequence)";$Skill=$Skills[$i]
        $Role=$(if($i-lt2){'focus'}else{'maintenance'})
        $FocusGoalId=$(if($Role-eq'focus'){'FG-C4-1'}else{''})
        $PlanItems.Add([pscustomobject]@{plan_item_id=$PlanItemId;plan_id='C0004';sequence=[string]$Sequence;title="C0004 training $Sequence";session_type='integrated';primary_skill=$Skill;required='true';status='planned';completed_session_id='';focus_goal_id=$FocusGoalId;plan_role=$Role;scored_skills=@($Skill)})
        $Skeleton=[pscustomobject]@{competency_id='G-SPO-A2-01';competency_family='spoken_production';activity_family='opinion_explanation';indicator_id='IND-1';anchor_id='A2';template_id='T-1';max_evidence_mode='training'}
        $Packages.Add([pscustomobject]@{schema_version=1;status='ready';plan_id='C0004';plan_item_id=$PlanItemId;plan_role=$Role;primary_skill=$Skill;focus_goal_id=$FocusGoalId;policy_version='4.0.0';catalog_version='1.0.0';ladder_version='1.0.0';contract_version='4.0.0';rights_status='project_original';activity_skeletons=@($Skeleton);fallback_activity_skeletons=@($Skeleton);preauthorized_probe_candidates=@()})
    }
    $ReviewId='P4-07'
    $PlanItems.Add([pscustomobject]@{plan_item_id=$ReviewId;plan_id='C0004';sequence='7';title='C0004 cycle review';session_type='review';primary_skill='integrated';required='true';status='planned';completed_session_id='';focus_goal_id='FG-C4-1';plan_role='cycle_review';scored_skills=@()})
    $ReviewSkeleton=[pscustomobject]@{competency_id='G-SPO-A2-01';competency_family='spoken_production';activity_family='cycle_review';indicator_id='IND-1';anchor_id='A2';template_id='T-REVIEW';max_evidence_mode='training'}
    $Packages.Add([pscustomobject]@{schema_version=1;status='ready';plan_id='C0004';plan_item_id=$ReviewId;plan_role='cycle_review';primary_skill='integrated';focus_goal_id='FG-C4-1';policy_version='4.0.0';catalog_version='1.0.0';ladder_version='1.0.0';contract_version='4.0.0';rights_status='project_original';activity_skeletons=@($ReviewSkeleton);fallback_activity_skeletons=@($ReviewSkeleton);preauthorized_probe_candidates=@()})
    $Goal=[pscustomobject]@{goal_id='FG-C4-1';goal_key='spoken_clarity';version='1';supersedes_goal_id='';stage_id='A2';skill='speaking';competency_id='G-SPO-A2-01';competency_family='spoken_production';activity_family='opinion_explanation';quality_focus='clear opinion and reason';goal_text='Give a clear opinion with one relevant reason.';success_criteria_json='["clear opinion","relevant reason"]';min_completed_cycles='1';max_completed_cycles='2';start_cycle_id='C0004';status='active';end_cycle_id='';created_at='2026-09-05T12:00:00+08:00';updated_at='2026-09-05T12:00:00+08:00'}
    $MigrationId=New-StableIdentifier -Prefix 'M4-' -Seed "$IdempotencyKey|C0003|C0004" -HashLength 24
    $ZeroHash='0'*64
    $Manifest=[pscustomobject]@{
        migration_schema_version=1;migration_id=$MigrationId;idempotency_key=$IdempotencyKey;created_at='2026-09-05T12:00:00+08:00';study_timezone='Asia/Shanghai'
        versions=[pscustomobject]@{from_data_schema=3;to_data_schema=4;from_protocol=3;to_protocol=4;catalog_version='1.0.0';ladder_version='1.0.0';contract_version='4.0.0';review_schema_version='4.0.0'}
        boundary=[pscustomobject]@{source_cycle_id='C0003';target_cycle_id='C0004';expected_queue_head_plan_item_id='P4-01';current_session_status='none';old_review_transaction_status='none';c0003_plan_item_mutations=@();user_confirmed_c0004_plan=$true;user_confirmation_ref='CONF-C0004-1'}
        dry_run=[pscustomobject]@{completed=$true;writes_performed=$false;manifest_id='DRY-C0004-1';manifest_sha256=$ZeroHash;generated_at='2026-09-05T12:00:00+08:00';proposed_actions_reviewed=$true}
        snapshot=[pscustomobject]@{snapshot_id='SNAP-C0004-1';relative_path=".state/migration-snapshots/$MigrationId";created_at='2026-09-05T12:00:00+08:00';verified=$true;manifest_sha256=$ZeroHash;files=@([pscustomobject]@{path='learner/settings.json';size_bytes=0;sha256=$ZeroHash;classification='configuration'})}
        baseline=[pscustomobject]@{queue_head_plan_item_id='P4-01';counts=[pscustomobject]@{sessions=2;plan_items=2;vocabulary=1;errors=1;review_events=0;skill_evidence=1};id_uniqueness_verified=$true;references_verified=$true;legacy_timestamp_bytes_preserved=$true}
        migration_plan=[pscustomobject]@{file_actions=@([pscustomobject]@{path='learner/settings.json';action='preserve';classification='configuration';old_rows_preserved=$true;semantic_backfill=$false});legacy_review=[pscustomobject]@{source_rows=2;exact_merge_groups=0;legacy_unverified_items=1;needs_recipe_fix_items=0;paused_or_retired_sources=1;manual_review_sources=@();old_schedule_used_only_for_sorting=$true;history_backfilled=$false};historical_semantic_backfill=$false;historical_session_rewrite=$false;historical_review_rewrite=$false;legacy_closed_sessions_replayed=$false;unknown_fields_policy='blank_or_unknown_never_inferred'}
        validation=[pscustomobject]@{isolated_rehearsal_passed=$true;immutable_hashes_match=$true;legacy_columns_equal=$true;counts_not_decreased=$true;ids_unique=$true;references_valid=$true;replay_deterministic=$true;migration_retry_idempotent=$true;phase_fault_recovery_passed=$true;catalog=[pscustomobject]@{family_count=15;gate_count=45;minimum_indicators_per_gate=2;maximum_indicators_per_gate=3;all_references_valid=$true;project_operationalization_marked=$true};ladders=[pscustomobject]@{all_references_valid=$true;steps_per_dimension_valid=$true;adjacent_only=$true;maximum_dimensions_per_binding=2;shared_load_axis_guarded=$true};fallbacks=[pscustomobject]@{c0004_skeleton_count=6;all_presentable=$true;rights_verified=$true;checksums_verified=$true;listening_audio_and_transcript_verified=$true};performance=[pscustomobject]@{bootstrap_latency_ms=100;first_answerable_latency_ms=500;controllable_path_latency_ms=1000;checkpoint_latency_ms=100;end_reducer_latency_ms=500;uncontrolled_latency_separated=$true};pending_transactions=@()}
        activation_gates=[pscustomobject]@{c0003_completed=$true;c0004_plan_confirmed=$true;snapshot_verified=$true;dry_run_verified=$true;isolated_rehearsal_verified=$true;legacy_integrity_verified=$true;catalog_verified=$true;ladders_verified=$true;facts_rebuild_verified=$true;wal_recovery_verified=$true;fallbacks_verified=$true;performance_verified=$true;no_pending_transactions=$true;queue_guard_verified=$true}
        activation=[pscustomobject]@{status='ready';receipt_id="AR-$MigrationId";activated_at='2026-09-05T12:00:00+08:00';expected_settings_sha256=$ZeroHash;expected_queue_guard_sha256=$ZeroHash;runtime_switch_is_final_write=$true}
    }
    return [pscustomobject]@{user_confirmed=$true;from_cycle_id='C0003';to_cycle_id='C0004';focus_skill='speaking';previous_cycle_lead_skills=@();plan_items=@($PlanItems);packages=@($Packages);focus_goals=@($Goal);migration_manifest=$Manifest}
}

function New-TestContract {
    param([object]$Checkpoint, [string]$ActivityId='A-1', [string]$Stage='input', [string]$EvidenceMode='training')
    return [pscustomobject]@{
        session_id=$Checkpoint.session_id; activity_id=$ActivityId; contract_id="CT-$ActivityId"; stage=$Stage; activity_family='opinion_explanation'; modality='writing';
        purpose=$(if($EvidenceMode -eq 'difficulty_probe'){'probe'}else{'practice'}); mode='accuracy'; primary_construct='clear opinion with one reason';
        criteria=@([pscustomobject]@{criterion_id='CR-1';importance='essential';description='states a clear opinion'});
        answer_key=[pscustomobject]@{semantic_requirements=@('opinion','reason')};
        access_profile=[pscustomobject]@{preparation_seconds=30;lookback=$false}; planned_support=[pscustomobject]@{level='none'}; allowed_support=[pscustomobject]@{maximum='guided'}; correction_timing='after_fluency_output';
        adapter='guided_recast'; hint_ladder=@('clarify task','point to missing reason'); max_support=[pscustomobject]@{level='guided';count=2};
        transfer_rule=[pscustomobject]@{required=$false}; retry_budget=2; loop_budget=3; transfer_budget=1; complexity_budget=3;
        competency_id='COMP-1'; competency_family='spoken_production'; indicator_id='IND-1'; anchor_id='A2'; template_id='T-1';
        evidence_mode=$EvidenceMode; planned_step='PA_1'; target_step=$(if($EvidenceMode -eq 'difficulty_probe'){'PA_2'}else{'PA_1'});
        presented_step=$(if($EvidenceMode -eq 'difficulty_probe'){'PA_2'}else{'PA_1'}); changed_dimension=$(if($EvidenceMode -eq 'difficulty_probe'){'prompt_abstraction'}else{'none'});
        adaptation_key='AK-1'; content_id="CONTENT-$ActivityId"; context_id="CONTEXT-$ActivityId";
        package_hash=$Checkpoint.package_hash; catalog_version='1.0.0'; ladder_version='1.0.0'; contract_version='4.0.0'; review_schema_version='4.0.0'; queue_guard=$Checkpoint.queue_guard;
        prompt_text='State your opinion and give one reason.'; lead_or_auxiliary='lead'
    }
}

function New-SavePayload {
    param([string]$ActivityId, [string]$Stage, [string]$NextAction='prepare_activity')
    return [pscustomobject]@{
        activity_id=$ActivityId; feedback_shown=$true; first_answer_excerpt='I prefer studying early because I can focus.';
        criterion_results=@([pscustomobject]@{criterion_id='CR-1';result='met'}); task_result='success';
        selected_issues=@(); stage_complete=$true; next_action=$NextAction;
        observation=[pscustomobject]@{ skill='speaking'; evidence='Clear opinion and reason'; criterion_id='CR-1';
            lead_or_auxiliary='lead'; purpose='practice'; evidence_mode='training'; evidence_kind='task';
            catalog_version='1.0.0'; ladder_version='1.0.0'; contract_version='4.0.0'; competency_id='COMP-1';
            competency_family='spoken_production'; activity_family='opinion_explanation'; indicator_id='IND-1'; anchor_id='A2';
            role='B'; template_id='T-1'; adaptation_key='AK-1'; load_axis_id='prompt_abstraction'; planned_step='PA_1';
            target_step='PA_1'; presented_step='PA_1'; changed_dimension='none'; task_fingerprint=$ActivityId;
            comparability_group='CG-1'; content_id="CONTENT-$ActivityId"; context_id="CONTEXT-$ActivityId";
            primary_result='success'; criterion_result='met'; task_result='success'; core_result='success'; challenge_result='not_applicable';
            validity='valid'; cost_signal='normal'; support_level='none'; support_kind='none'; model_exposed=$false }
    }
}

function New-DirectObservation {
    param(
        [string]$Id,
        [string]$Day,
        [string]$ContextId,
        [string]$Mode='target_check',
        [string]$Challenge='not_applicable',
        [string]$FocusGoalId=''
    )
    return [pscustomobject]@{
        observation_id=$Id; record_kind='observation'; validity='valid'; primary_result='met'; core_result='met';
        evidence_kind='primary'; evidence_mode=$Mode; purpose='probe'; attempt_no=1; lead_or_auxiliary='lead';
        independent=$true; within_allowed_support=$true; model_exposed=$false; support_level='none';
        source_session_outcome='completed'; adaptation_key='AK-1'; day_id=$Day; context_id=$ContextId;
        cost_signal='normal'; challenge_result=$Challenge; presented_step='PA_2'; focus_goal_id=$FocusGoalId;
        prearranged_focus_opportunity=$true; criterion_ids=@('CR-FOCUS'); guardrail_regressed=$false
    }
}

function New-TestReviewResult {
    return [pscustomobject]@{
        review_item_id='RI-1';question_instance_id='Q-RI-1';recipe_stage='recall';lane='active';rating='good';
        prompt_text='Complete: You can improve by ___. Use the pattern by + -ing.';answer_excerpt='by practicing';
        language_validity='valid';target_demonstrated='yes';rating_reason='Independent recall';exposed=$true;model_exposed=$false;
        task_contract=[pscustomobject]@{question_type='controlled_rewrite';target_scope='pattern';target_count=1;scoring_target='by + gerund';
            answer_key=[pscustomobject]@{required_pattern='by + gerund'};allowed_variants=@('practicing','practising');standard_hints=@('Use the given pattern');
            invalid_conditions=@('another grammatical answer fits without the target');content_id='REV-CONTENT-1';context_id='REV-CONTEXT-1';
            ambiguity_checked=$true;batch_leakage_checked=$true;uses_options=$false;uses_word_bank=$false}
    }
}

function Complete-TestActivities {
    param([string]$Root, [object]$Start)
    $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
    foreach ($Spec in @(
        [pscustomobject]@{id='A-IN';stage='input';next='prepare_activity'},
        [pscustomobject]@{id='A-OUT';stage='output';next='finalize_session'}
    )) {
        $Contract=New-TestContract -Checkpoint $Checkpoint -ActivityId $Spec.id -Stage $Spec.stage
        [void](Invoke-V4Json -Root $Root -Arguments @{Action='PrepareActivity';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey="prepare-$($Spec.id)";PayloadJson=($Contract|ConvertTo-Json -Depth 20 -Compress);Date=[datetime]'2026-09-05T12:01:00'})
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
        $Save=New-SavePayload -ActivityId $Spec.id -Stage $Spec.stage -NextAction $Spec.next
        [void](Invoke-V4Json -Root $Root -Arguments @{Action='SaveActivityCheckpoint';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey="save-$($Spec.id)";PayloadJson=($Save|ConvertTo-Json -Depth 20 -Compress);Date=[datetime]'2026-09-05T12:02:00'})
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
    }
    return $Checkpoint
}

Describe 'V4 pure learning reducers' {
    It 'uses the accepted review capacity weights' {
        (Get-ReviewWeight 'relearn') | Should Be 2
        (Get-ReviewWeight 'recall') | Should Be 3
        (Get-ReviewWeight 'constrained_transfer') | Should Be 4
    }

    It 'computes task result from frozen criterion importance' {
        $Partial = Resolve-TaskResult -CriterionResults @(
            [pscustomobject]@{importance='essential';result='met'},
            [pscustomobject]@{importance='required';result='not_met'}
        )
        $Failed = Resolve-TaskResult -CriterionResults @(
            [pscustomobject]@{importance='essential';result='not_met'}
        )
        $Partial | Should Be 'partial'
        $Failed | Should Be 'failed'
    }

    It 'does not treat abandoned or supported work as direct A evidence' {
        $Base = [pscustomobject]@{
            validity='valid'; lead_or_auxiliary='lead'; evidence_mode='target_check'; purpose='probe';
            primary_result='success'; evidence_kind='primary'; record_kind='observation';
            model_exposed=$false; comparable=$true; first_attempt=$true; independent=$true;
            support_level='none'; source_session_outcome='completed'
        }
        (Get-EvidenceClass -Observation $Base) | Should Be 'A'
        $Base.source_session_outcome='abandoned'
        (Get-EvidenceClass -Observation $Base) | Should Be 'none'
        $Base.source_session_outcome='completed'; $Base.support_level='guided'
        (Get-EvidenceClass -Observation $Base) | Should Be 'C'
    }

    It 'keeps review lanes independent while respecting total capacity' {
        $Items = @(
            [pscustomobject]@{review_item_id='A';lane='active';recipe_stage='recall';effective_due='2026-09-01';strength_level=0},
            [pscustomobject]@{review_item_id='M';lane='maintenance';recipe_stage='constrained_transfer';effective_due='2026-09-01';strength_level=3},
            [pscustomobject]@{review_item_id='L';lane='legacy';recipe_stage='relearn';effective_due='2026-09-01';strength_level=0},
            [pscustomobject]@{review_item_id='A2';lane='active';recipe_stage='constrained_transfer';effective_due='2026-09-02';strength_level=1}
        )
        $Selected = Select-ReviewQueue -Items $Items -Mode normal
        $Selected.used_weight | Should Be 9
        @($Selected.selected).Count | Should Be 3
        @($Selected.selected | ForEach-Object lane) -contains 'maintenance' | Should Be $true
    }

    It 'promotes only after cross-day target, probe, intermediate target, and confirmation evidence' {
        $State=New-AdaptationProjection -AdaptationKey 'AK-1' -TargetStep 'PA_1' -LoadAxisId 'prompt_abstraction'
        $State=Update-AdaptationProjection -Current $State -Observation (New-DirectObservation -Id O1 -Day D1 -ContextId C1)
        $State=Update-AdaptationProjection -Current $State -Observation (New-DirectObservation -Id O2 -Day D2 -ContextId C2)
        $State.progress_state | Should Be 'probe_ready'
        $State=Update-AdaptationProjection -Current $State -Observation (New-DirectObservation -Id P1 -Day D3 -ContextId C3 -Mode difficulty_probe -Challenge stretch_met) -CycleProbeAuthorized
        $State.required_next | Should Be 'target_check'
        $State=Update-AdaptationProjection -Current $State -Observation (New-DirectObservation -Id O3 -Day D4 -ContextId C4)
        $State.required_next | Should Be 'difficulty_probe'
        $State=Update-AdaptationProjection -Current $State -Observation (New-DirectObservation -Id P2 -Day D5 -ContextId C5 -Mode difficulty_probe -Challenge stretch_met) -CycleProbeAuthorized
        $State.last_transition | Should Be 'promoted'
        $State.needs_consolidation | Should Be $true
    }

    It 'enters promotion hold after repeated failed upward probes' {
        $State=New-AdaptationProjection -AdaptationKey 'AK-1' -TargetStep 'PA_1' -LoadAxisId 'prompt_abstraction'
        $State.progress_state='probe_ready'
        $State=Update-AdaptationProjection -Current $State -Observation (New-DirectObservation -Id P1 -Day D1 -ContextId C1 -Mode difficulty_probe -Challenge stretch_not_ready) -CycleProbeAuthorized
        $State=Update-AdaptationProjection -Current $State -Observation (New-DirectObservation -Id P2 -Day D2 -ContextId C2 -Mode difficulty_probe -Challenge stretch_not_ready) -CycleProbeAuthorized
        $State.progress_state | Should Be 'promotion_hold'
        $State.hold_phase | Should Be 'recovering'
    }

    It 'marks a focus goal met only with diverse success and a normal-cost confirmation' {
        $Goal=[pscustomobject]@{goal_id='FG-1';required_criterion_ids=@('CR-FOCUS');min_completed_cycles=2;max_completed_cycles=4}
        $TooLittle=Get-FocusGoalDecision -Goal $Goal -Evidence @(
            (New-DirectObservation -Id F1 -Day D1 -ContextId C1 -FocusGoalId FG-1)
        ) -CompletedCycles 2
        $TooLittle.decision | Should Be 'insufficient_evidence'
        $Evidence=@(
            (New-DirectObservation -Id F1 -Day D1 -ContextId C1 -FocusGoalId FG-1),
            (New-DirectObservation -Id F2 -Day D2 -ContextId C2 -FocusGoalId FG-1),
            (New-DirectObservation -Id F3 -Day D3 -ContextId C3 -FocusGoalId FG-1)
        )
        $Evidence[2] | Add-Member -NotePropertyName focus_confirmation -NotePropertyValue $true
        $Met=Get-FocusGoalDecision -Goal $Goal -Evidence $Evidence -CompletedCycles 2
        $Met.decision | Should Be 'met'
    }

    It 'requires transfer successes at least fourteen days apart before maintenance' {
        $Current=[pscustomobject]@{review_item_id='RI-X';review_family='receptive_meaning';recipe_stage='constrained_transfer';strength_level=4;status='active';next_review='2026-09-01';maintenance_interval_days=''}
        $Event=[pscustomobject]@{rating='good';study_date='2026-09-20'}
        $TooClose=@(
            [pscustomobject]@{result='met';recipe_stage='constrained_transfer';evidence_kind='formal_review';study_date='2026-09-10';context_id='C1'},
            [pscustomobject]@{result='met';recipe_stage='constrained_transfer';evidence_kind='spontaneous_transfer';study_date='2026-09-20';context_id='C2'}
        )
        (Apply-ReviewEvent -Current $Current -Event $Event -TransferEvidence $TooClose).status | Should Be 'active'
        $FarEnough=@(
            [pscustomobject]@{result='met';recipe_stage='constrained_transfer';evidence_kind='formal_review';study_date='2026-09-01';context_id='C1'},
            [pscustomobject]@{result='met';recipe_stage='constrained_transfer';evidence_kind='spontaneous_transfer';study_date='2026-09-20';context_id='C2'}
        )
        (Apply-ReviewEvent -Current $Current -Event $Event -TransferEvidence $FarEnough).status | Should Be 'maintenance'
    }
}

Describe 'V4 session checkpoint and idempotency' {
    It 'resumes cycle review after staged SRS, evaluates persisted evidence and finalizes without a scored activity' {
        $Root = New-V4Fixture -WithReview
        $Context = New-V4Context -ProjectRoot $Root -Date ([datetime]'2026-09-05T12:00:00')
        $Plans = @(Get-TsvRows -Path $Context.paths.plans -Headers $script:V4PlanHeaders)
        $Plans[0].plan_role = 'cycle_review'
        $Plans[0].session_type = 'review'
        $Plans[0].focus_goal_id = 'FG-TEST'
        Write-TsvRowsAtomic -Path $Context.paths.plans -Rows $Plans -Headers $script:V4PlanHeaders
        $Index = (Read-DurableJson -Path $Context.paths.bootstrap_index).value
        $Index.plan_role = 'cycle_review'
        $Index.session_type = 'review'
        $Index.focus_goal_id = 'FG-TEST'
        $Index.queue_guard = Get-V4QueueGuard -Index $Index
        [void](Write-DurableJson -Path $Context.paths.bootstrap_index -Value $Index)
        $Goal = [ordered]@{}
        foreach ($Header in $script:V4FocusGoalHeaders) { $Goal[$Header] = '' }
        $Goal.goal_id = 'FG-TEST'; $Goal.status = 'active'; $Goal.stage_id = 'A2'
        Write-TsvRowsAtomic -Path $Context.paths.focus_goals -Rows @([pscustomobject]$Goal) -Headers $script:V4FocusGoalHeaders
        $Start = Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='cycle-start';Date=[datetime]'2026-09-05T12:00:00'}
        $Start.next_action | Should Be 'present_review'
        $Checkpoint = (Read-DurableJson -Path $Context.paths.current_session).value
        $Payload = @{feedback_shown=$true;stage_complete=$true;next_action='prepare_activity';items=@(New-TestReviewResult)}
        $Staged = Invoke-V4Json -Root $Root -Arguments @{Action='StageReviewBatch';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=1;IdempotencyKey='cycle-srs';PayloadJson=($Payload|ConvertTo-Json -Depth 20 -Compress)}
        $Staged.next_action | Should Be 'evaluate_cycle_review'
        $Before = Get-FileSha256 -Path $Context.paths.current_session
        $Boot = Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap'}
        $Boot.next_action | Should Be 'evaluate_cycle_review'
        $Boot.next_action_contract.action | Should Be 'EvaluateLongTermState'
        @($Boot.prepared_step.evidence_packet.pending_review_summary).Count | Should Be 1
        $Evaluation = Invoke-V4Json -Root $Root -Arguments @{Action='EvaluateLongTermState';SessionId=$Start.receipt.session_id}
        $Evaluation.next_action | Should Be 'present_cycle_review_candidates'
        $Evaluation.prepared_step.goal_candidates[0].decision | Should Be 'insufficient_evidence'
        (Get-FileSha256 -Path $Context.paths.current_session) | Should Be $Before
        $FinalPayload = @{feedback_shown=$true;session_summary='Reviewed the bounded cycle evidence; independent evidence remains insufficient.';duration_minutes=10;goal_decision=$Evaluation.prepared_step.goal_candidates[0]}
        $Final = Invoke-V4Json -Root $Root -Arguments @{Action='FinalizeSession';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=2;IdempotencyKey='cycle-final';PayloadJson=($FinalPayload|ConvertTo-Json -Depth 20 -Compress)}
        $Final.status | Should Be 'completed'
        @((Get-TsvRows -Path $Context.paths.review_history -Headers $script:V4ReviewHistoryHeaders)).Count | Should Be 1
        @((Get-TsvRows -Path $Context.paths.evidence -Headers $script:V4EvidenceHeaders)).Count | Should Be 0
    }

    It 'rejects cycle review evaluation on a normal training session' {
        $Root = New-V4Fixture
        $Start = Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='not-cycle'}
        Assert-ThrowsV4 { Invoke-V4Json -Root $Root -Arguments @{Action='EvaluateLongTermState';SessionId=$Start.receipt.session_id} }
    }

    It 'routes a v4 runtime through the small Bootstrap response' {
        $Root = New-V4Fixture
        $Result = Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap';Date=[datetime]'2026-09-05T12:00:00'}
        $Result.status | Should Be 'ready'
        $Result.next_action | Should Be 'start_session'
        $Result.runtime_version | Should Be 4
        $Result.prepared_step.runtime_version | Should Be 4
        @($Result.prepared_step.review_candidates).Count | Should Be 0
        $Result.next_action_contract.action | Should Be 'StartSession'
        @($Result.protocol_refs) -contains 'references/tracker-actions.md' | Should Be $true
    }

    It 'returns the session write parameters and bounded package blueprint after StartSession' {
        $Root = New-V4Fixture
        $Start = Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='start-contract';Date=[datetime]'2026-09-05T12:00:00'}
        $Intent = (Read-DurableJson -Path (Join-Path $Root '.state\start-intent.json')).value
        $Intent.status | Should Be 'committed'
        $Start.receipt.owner_token | Should Not BeNullOrEmpty
        $Start.receipt.revision | Should Be 1
        $Start.next_action_contract.action | Should Be 'PrepareActivity'
        $Start.prepared_step.package_source | Should Be 'published_exact'
        $Start.prepared_step.declared_source_type | Should Be 'none'
        $Start.prepared_step.package_blueprint.package_kind | Should Be 'activity_blueprint'
        @($Start.prepared_step.package_blueprint.activity_skeletons).Count | Should Be 1
    }

    It 'allows the next queue head when a legacy committed start intent still says pending' {
        $Root = New-V4Fixture
        $First = Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='start-first';Date=[datetime]'2026-09-05T12:00:00'}
        $Context = New-V4Context -ProjectRoot $Root -Date ([datetime]'2026-09-06T12:00:00')

        $LegacyIntent = (Read-DurableJson -Path $Context.paths.start_intent).value
        $LegacyIntent.status = 'pending'
        [void](Write-DurableJson -Path $Context.paths.start_intent -Value $LegacyIntent)

        $Checkpoint = (Read-DurableJson -Path $Context.paths.current_session).value
        $Checkpoint.status = 'completed'
        [void](Write-DurableJson -Path $Context.paths.current_session -Value $Checkpoint)

        $Plans = @(Get-TsvRows -Path $Context.paths.plans -Headers $script:V4PlanHeaders)
        $Plans[0].status = 'completed'
        $Plans[0].completed_session_id = $First.receipt.session_id
        $SecondPlan = [pscustomobject]@{
            plan_item_id='P4-02'; plan_id='C0004'; sequence='2'; title='Second fixture lesson';
            session_type='extra'; primary_skill='speaking'; required='true'; status='planned';
            completed_session_id=''; focus_goal_id=''; plan_role='maintenance'
        }
        Write-TsvRowsAtomic -Path $Context.paths.plans -Rows @($Plans + $SecondPlan) -Headers $script:V4PlanHeaders

        $SecondPackagePath = Join-Path $Root '.state\packages\P4-02.json'
        $SecondPackage = (Read-DurableJson -Path (Join-Path $Root '.state\packages\P4-01.json')).value
        $SecondPackage.plan_item_id = 'P4-02'
        [void](Write-DurableJson -Path $SecondPackagePath -Value $SecondPackage)
        $SecondPackageHash = Get-FileSha256 -Path $SecondPackagePath

        $Index = (Read-DurableJson -Path $Context.paths.bootstrap_index).value
        $Index.index_revision = 2
        $Index.queue_revision = 2
        $Index.generated_at = '2026-09-06T12:00:00+08:00'
        $Index.next_plan_item_id = 'P4-02'
        $Index.next_title = 'Second fixture lesson'
        $Index.package_path = '.state/packages/P4-02.json'
        $Index.package_hash = $SecondPackageHash
        $Index.queue_guard = Get-V4QueueGuard -Index $Index
        [void](Write-DurableJson -Path $Context.paths.bootstrap_index -Value $Index)

        $Boot = Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap';Date=[datetime]'2026-09-06T12:00:00'}
        $Boot.next_action | Should Be 'start_session'
        $Second = Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';PlanItemId='P4-02';IdempotencyKey='start-second';Date=[datetime]'2026-09-06T12:00:01'}
        $Second.status | Should Be 'started'
        $Second.receipt.plan_item_id | Should Be 'P4-02'
        $Second.receipt.session_id | Should Not Be $First.receipt.session_id
        (Read-DurableJson -Path $Context.paths.start_intent).value.status | Should Be 'committed'
    }

    It 'returns hydrated due review items before the main activity' {
        $Root = New-V4Fixture -WithReview
        $Start = Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='start-review-first';Date=[datetime]'2026-09-05T12:00:00'}
        $Start.next_action | Should Be 'present_review'
        $Start.prepared_step.review_first | Should Be $true
        $Start.prepared_step.review_items[0].target_form | Should Be 'by doing'
        $Start.prepared_step.review_items[0].preparation_status | Should Be 'ready'
    }

    It 'returns the original receipts for same-key retries and rejects changed payloads' {
        $Root = New-V4Fixture
        $Start = Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='start-1';Date=[datetime]'2026-09-05T12:00:00'}
        $StartReplay = Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='start-1';Date=[datetime]'2026-09-05T12:00:00'}
        $StartReplay.reason_code | Should Be 'idempotent_replay'
        $StartReplay.receipt.session_id | Should Be $Start.receipt.session_id
        $Guard = (Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value.queue_guard
        $CheckpointObject=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
        $Contract = New-TestContract -Checkpoint $CheckpointObject
        $Prepare = Invoke-V4Json -Root $Root -Arguments @{Action='PrepareActivity';SessionId=$Start.receipt.session_id;OwnerToken=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value.lease.owner_token;ExpectedRevision=1;IdempotencyKey='prepare-1';PayloadJson=($Contract|ConvertTo-Json -Depth 20 -Compress);Date=[datetime]'2026-09-05T12:01:00'}
        $PrepareReplay = Invoke-V4Json -Root $Root -Arguments @{Action='PrepareActivity';SessionId=$Start.receipt.session_id;OwnerToken=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value.lease.owner_token;ExpectedRevision=1;IdempotencyKey='prepare-1';PayloadJson=($Contract|ConvertTo-Json -Depth 20 -Compress);Date=[datetime]'2026-09-05T12:01:00'}
        $PrepareReplay.reason_code | Should Be 'idempotent_replay'
        $PrepareReplay.receipt.contract_hash | Should Be $Prepare.receipt.contract_hash
        $Changed = New-TestContract -Checkpoint $CheckpointObject
        $Changed.prompt_text='A different prompt'
        Assert-ThrowsV4 { Invoke-V4Json -Root $Root -Arguments @{Action='PrepareActivity';SessionId=$Start.receipt.session_id;OwnerToken=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value.lease.owner_token;ExpectedRevision=1;IdempotencyKey='prepare-1';PayloadJson=($Changed|ConvertTo-Json -Depth 20 -Compress);Date=[datetime]'2026-09-05T12:01:00'} }
        $SavePayload = New-SavePayload -ActivityId 'A-1' -Stage input
        $Save = Invoke-V4Json -Root $Root -Arguments @{Action='SaveActivityCheckpoint';SessionId=$Start.receipt.session_id;OwnerToken=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value.lease.owner_token;ExpectedRevision=2;IdempotencyKey='save-1';PayloadJson=($SavePayload|ConvertTo-Json -Depth 20 -Compress);Date=[datetime]'2026-09-05T12:02:00'}
        $SaveReplay = Invoke-V4Json -Root $Root -Arguments @{Action='SaveActivityCheckpoint';SessionId=$Start.receipt.session_id;OwnerToken=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value.lease.owner_token;ExpectedRevision=2;IdempotencyKey='save-1';PayloadJson=($SavePayload|ConvertTo-Json -Depth 20 -Compress);Date=[datetime]'2026-09-05T12:02:00'}
        $SaveReplay.reason_code | Should Be 'idempotent_replay'
        $SaveReplay.receipt.observation_id | Should Be $Save.receipt.observation_id
    }

    It 'rejects an unplanned difficulty probe and accepts the one matching preauthorization' {
        $Root = New-V4Fixture
        $Start = Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='start-no-probe';Date=[datetime]'2026-09-05T12:00:00'}
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
        $Probe=New-TestContract -Checkpoint $Checkpoint -EvidenceMode difficulty_probe
        Assert-ThrowsV4 { Invoke-V4Json -Root $Root -Arguments @{Action='PrepareActivity';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=1;IdempotencyKey='probe';PayloadJson=($Probe|ConvertTo-Json -Depth 20 -Compress)} }

        $Root2 = New-V4Fixture -WithProbe
        $Start2 = Invoke-V4Json -Root $Root2 -Arguments @{Action='StartSession';IdempotencyKey='start-probe';Date=[datetime]'2026-09-05T12:00:00'}
        $Checkpoint2=(Read-DurableJson -Path (Join-Path $Root2 '.state\current-session.json')).value
        $Probe2=New-TestContract -Checkpoint $Checkpoint2 -EvidenceMode difficulty_probe
        $Accepted=Invoke-V4Json -Root $Root2 -Arguments @{Action='PrepareActivity';SessionId=$Start2.receipt.session_id;OwnerToken=$Checkpoint2.lease.owner_token;ExpectedRevision=1;IdempotencyKey='probe';PayloadJson=($Probe2|ConvertTo-Json -Depth 20 -Compress)}
        $Accepted.status | Should Be 'prepared'
    }

    It 'uses a safe fallback but caps every fallback activity at training' {
        $Root=New-V4Fixture -WithFallback -WithProbe
        $Bootstrap=Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap';Date=[datetime]'2026-09-05T12:00:00'}
        $Bootstrap.reason_code | Should Be 'local_fallback'
        $Bootstrap.prepared_step.evidence_mode_cap | Should Be 'training'
        $Start=Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='fallback-start';Date=[datetime]'2026-09-05T12:00:01'}
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
        $Formal=New-TestContract -Checkpoint $Checkpoint -EvidenceMode difficulty_probe
        Assert-ThrowsV4 { Invoke-V4Json -Root $Root -Arguments @{Action='PrepareActivity';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=1;IdempotencyKey='fallback-formal';PayloadJson=($Formal|ConvertTo-Json -Depth 20 -Compress)} }
        $Training=New-TestContract -Checkpoint $Checkpoint
        $Prepared=Invoke-V4Json -Root $Root -Arguments @{Action='PrepareActivity';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=1;IdempotencyKey='fallback-training';PayloadJson=($Training|ConvertTo-Json -Depth 20 -Compress)}
        $Prepared.status | Should Be 'prepared'
    }

    It 'keeps review results pending until the final transaction' {
        $Root = New-V4Fixture -WithReview
        $Start = Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='start-review';Date=[datetime]'2026-09-05T12:00:00'}
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
        $Payload=[pscustomobject]@{feedback_shown=$true;items=@((New-TestReviewResult))}
        $Before=@(Get-TsvRows -Path (Join-Path $Root 'learner\review-history.tsv') -Headers $script:V4ReviewHistoryHeaders).Count
        $Staged=Invoke-V4Json -Root $Root -Arguments @{Action='StageReviewBatch';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=1;IdempotencyKey='review-1';PayloadJson=($Payload|ConvertTo-Json -Depth 20 -Compress)}
        $After=@(Get-TsvRows -Path (Join-Path $Root 'learner\review-history.tsv') -Headers $script:V4ReviewHistoryHeaders).Count
        $Staged.status | Should Be 'staged'
        $After | Should Be $Before
        @((Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value.pending_review_batches).Count | Should Be 1
    }
}

Describe 'V4 recoverable start and terminal transaction' {
    It 'archives an integrated speaking session after its output stage' {
        $Root = New-V4Fixture
        $Context = New-V4Context -ProjectRoot $Root -Date ([datetime]'2026-09-05T12:00:00')
        $Plans = @(Get-TsvRows -Path $Context.paths.plans -Headers $script:V4PlanHeaders)
        $Plans[0].session_type = 'integrated'
        Write-TsvRowsAtomic -Path $Context.paths.plans -Rows $Plans -Headers $script:V4PlanHeaders
        $Index = (Read-DurableJson -Path $Context.paths.bootstrap_index).value
        $Index.session_type = 'integrated'
        [void](Write-DurableJson -Path $Context.paths.bootstrap_index -Value $Index)

        $Start = Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='integrated-start';Date=[datetime]'2026-09-05T12:00:00'}
        (($Start.prepared_step.required_stages) -join ',') | Should Be 'output,feedback'
        $Checkpoint=(Read-DurableJson -Path $Context.paths.current_session).value
        $Contract=New-TestContract -Checkpoint $Checkpoint -ActivityId 'A-INTEGRATED' -Stage 'output'
        [void](Invoke-V4Json -Root $Root -Arguments @{Action='PrepareActivity';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='integrated-prepare';PayloadJson=($Contract|ConvertTo-Json -Depth 20 -Compress)})
        $Checkpoint=(Read-DurableJson -Path $Context.paths.current_session).value
        $Save=New-SavePayload -ActivityId 'A-INTEGRATED' -Stage 'output' -NextAction 'finalize_session'
        [void](Invoke-V4Json -Root $Root -Arguments @{Action='SaveActivityCheckpoint';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='integrated-save';PayloadJson=($Save|ConvertTo-Json -Depth 20 -Compress)})
        $Checkpoint=(Read-DurableJson -Path $Context.paths.current_session).value
        $Payload=[pscustomobject]@{feedback_shown=$true;duration_minutes=1;session_summary='Integrated speaking fixture completed.'}
        $Final=Invoke-V4Json -Root $Root -Arguments @{Action='FinalizeSession';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='integrated-final';PayloadJson=($Payload|ConvertTo-Json -Depth 10 -Compress)}
        $Final.status | Should Be 'completed'
    }

    It 'uses feedback plus goal decision rather than SRS review as the cycle-review stage contract' {
        ((Get-V4RequiredStages -SessionType review -PrimarySkill integrated -PlanRole cycle_review) -join ',') | Should Be 'feedback'
        ((Get-V4RequiredStages -SessionType review -PrimarySkill integrated -PlanRole maintenance) -join ',') | Should Be 'review,feedback'
    }

    foreach ($Fault in @('start_intent','start_stub','start_plan_lock','start_checkpoint','start_commit')) {
        It "recovers one session after $Fault interruption" {
            $Root=New-V4Fixture
            Assert-ThrowsV4 { Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey="start-$Fault";FaultAfterPhase=$Fault;Date=[datetime]'2026-09-05T12:00:00'} }
            $Recovered=Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap';Date=[datetime]'2026-09-05T12:00:01'}
            $Recovered.status | Should Be 'resume'
            @(Get-ChildItem -LiteralPath (Join-Path $Root 'sessions') -Recurse -Filter '*.md').Count | Should Be 1
            @(Get-TsvRows -Path (Join-Path $Root 'learner\plan-items.tsv') -Headers $script:V4PlanHeaders | Where-Object status -eq 'in_progress').Count | Should Be 1
        }
    }

    It 'recovers a finalization after facts append without duplicating facts or queue progress' {
        $Root=New-V4Fixture
        $Start=Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='start-final';Date=[datetime]'2026-09-05T12:00:00'}
        $Checkpoint=Complete-TestActivities -Root $Root -Start $Start
        $FinalPayload=[pscustomobject]@{feedback_shown=$true;duration_minutes=30;session_summary='Completed two short speaking activities.'}
        Assert-ThrowsV4 { Invoke-V4Json -Root $Root -Arguments @{Action='FinalizeSession';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='final-1';PayloadJson=($FinalPayload|ConvertTo-Json -Compress);FaultAfterPhase='transaction_facts';Date=[datetime]'2026-09-05T12:05:00'} }
        $Recovered=Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap';Date=[datetime]'2026-09-05T12:05:01'}
        $Recovered.reason_code | Should Be 'session_transaction_recovered'
        $Evidence=@(Get-TsvRows -Path (Join-Path $Root 'learner\skill-evidence.tsv') -Headers $script:V4EvidenceHeaders)
        $Evidence.Count | Should Be 2
        @($Evidence.evidence_id | Select-Object -Unique).Count | Should Be 2
        $Plan=@(Get-TsvRows -Path (Join-Path $Root 'learner\plan-items.tsv') -Headers $script:V4PlanHeaders)[0]
        $Plan.status | Should Be 'completed'
        $Replay=Invoke-V4Json -Root $Root -Arguments @{Action='FinalizeSession';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='final-1';PayloadJson=($FinalPayload|ConvertTo-Json -Compress);Date=[datetime]'2026-09-05T12:05:02'}
        $Replay.reason_code | Should Be 'idempotent_replay'
        @(Get-TsvRows -Path (Join-Path $Root 'learner\skill-evidence.tsv') -Headers $script:V4EvidenceHeaders).Count | Should Be 2
    }

    It 'converges to one completed state from every finalization fault boundary' {
        foreach($Fault in @('transaction_intent','transaction_validated','transaction_facts','transaction_projections','transaction_terminal','transaction_plan','transaction_index','transaction_commit')) {
            $Root=New-V4Fixture
            $Start=Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey="start-$Fault";Date=[datetime]'2026-09-05T12:00:00'}
            $Checkpoint=Complete-TestActivities -Root $Root -Start $Start
            $Payload=[pscustomobject]@{feedback_shown=$true;duration_minutes=30;session_summary="Fault recovery fixture $Fault"}
            Assert-ThrowsV4 { Invoke-V4Json -Root $Root -Arguments @{Action='FinalizeSession';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey="final-$Fault";PayloadJson=($Payload|ConvertTo-Json -Compress);FaultAfterPhase=$Fault;Date=[datetime]'2026-09-05T12:05:00'} }
            [void](Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap';Date=[datetime]'2026-09-05T12:05:01'})
            $Transaction=(Read-DurableJson -Path (Join-Path $Root '.state\session-transaction.json')).value
            $Transaction.phase | Should Be 'committed'
            $Plan=@(Get-TsvRows -Path (Join-Path $Root 'learner\plan-items.tsv') -Headers $script:V4PlanHeaders)[0]
            $Plan.status | Should Be 'completed'
            $Evidence=@(Get-TsvRows -Path (Join-Path $Root 'learner\skill-evidence.tsv') -Headers $script:V4EvidenceHeaders)
            $Evidence.Count | Should Be 2
            @($Evidence.evidence_id|Select-Object -Unique).Count | Should Be 2
        }
    }

    It 'abandons only feedback-shown observations and keeps the same plan item at queue head' {
        $Root=New-V4Fixture
        $Start=Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='start-abandon';Date=[datetime]'2026-09-05T12:00:00'}
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
        $Contract=New-TestContract -Checkpoint $Checkpoint -ActivityId 'A-PART' -Stage input
        [void](Invoke-V4Json -Root $Root -Arguments @{Action='PrepareActivity';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=1;IdempotencyKey='prepare-part';PayloadJson=($Contract|ConvertTo-Json -Depth 20 -Compress)})
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
        $Save=New-SavePayload -ActivityId 'A-PART' -Stage input
        [void](Invoke-V4Json -Root $Root -Arguments @{Action='SaveActivityCheckpoint';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='save-part';PayloadJson=($Save|ConvertTo-Json -Depth 20 -Compress)})
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
        $Payload=[pscustomobject]@{duration_minutes=8;session_summary='Learner explicitly stopped the session.'}
        $Result=Invoke-V4Json -Root $Root -Arguments @{Action='AbandonSession';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='abandon-1';PayloadJson=($Payload|ConvertTo-Json -Compress)}
        $Result.status | Should Be 'abandoned'
        $Evidence=@(Get-TsvRows -Path (Join-Path $Root 'learner\skill-evidence.tsv') -Headers $script:V4EvidenceHeaders)
        $Evidence.Count | Should Be 1
        $Evidence[0].source_session_outcome | Should Be 'abandoned'
        $Plan=@(Get-TsvRows -Path (Join-Path $Root 'learner\plan-items.tsv') -Headers $script:V4PlanHeaders)[0]
        $Plan.status | Should Be 'planned'
        $Index=(Read-DurableJson -Path (Join-Path $Root '.state\bootstrap-index.json')).value
        $Index.next_plan_item_id | Should Be 'P4-01'
    }

    It 'commits a staged review audit and schedule exactly once at finalization' {
        $Root=New-V4Fixture -WithReview
        $Start=Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='start-review-final';Date=[datetime]'2026-09-05T12:00:00'}
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
        $ReviewPayload=[pscustomobject]@{feedback_shown=$true;stage_complete=$true;next_action='prepare_activity';items=@((New-TestReviewResult))}
        [void](Invoke-V4Json -Root $Root -Arguments @{Action='StageReviewBatch';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=1;IdempotencyKey='review-final-batch';PayloadJson=($ReviewPayload|ConvertTo-Json -Depth 20 -Compress);Date=[datetime]'2026-09-05T12:00:30'})
        $Checkpoint=Complete-TestActivities -Root $Root -Start $Start
        $FinalPayload=[pscustomobject]@{feedback_shown=$true;duration_minutes=30;session_summary='Completed review and two activities.'}
        [void](Invoke-V4Json -Root $Root -Arguments @{Action='FinalizeSession';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='final-review';PayloadJson=($FinalPayload|ConvertTo-Json -Compress);Date=[datetime]'2026-09-05T12:05:00'})
        @(Get-TsvRows -Path (Join-Path $Root 'learner\review-history.tsv') -Headers $script:V4ReviewHistoryHeaders).Count | Should Be 1
        @(Get-TsvRows -Path (Join-Path $Root 'learner\review-audit.tsv') -Headers $script:V4ReviewAuditHeaders).Count | Should Be 1
        $Item=@(Get-TsvRows -Path (Join-Path $Root 'learner\review-items.tsv') -Headers $script:V4ReviewItemHeaders)[0]
        $Item.recipe_stage | Should Be 'constrained_transfer'
        $Item.next_review | Should Be '2026-09-08'
        $Replay=Invoke-V4Json -Root $Root -Arguments @{Action='FinalizeSession';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='final-review';PayloadJson=($FinalPayload|ConvertTo-Json -Compress);Date=[datetime]'2026-09-05T12:05:01'}
        $Replay.reason_code | Should Be 'idempotent_replay'
        @(Get-TsvRows -Path (Join-Path $Root 'learner\review-history.tsv') -Headers $script:V4ReviewHistoryHeaders).Count | Should Be 1
    }

    It 'keeps lesson candidates and corrections in the checkpoint until finalization' {
        $Root=New-V4Fixture
        $Start=Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='start-pending-facts';Date=[datetime]'2026-09-05T12:00:00'}
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value

        $Contract=New-TestContract -Checkpoint $Checkpoint -ActivityId 'A-IN' -Stage input
        [void](Invoke-V4Json -Root $Root -Arguments @{Action='PrepareActivity';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='prepare-candidate';PayloadJson=($Contract|ConvertTo-Json -Depth 20 -Compress)})
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
        $FirstSave=New-SavePayload -ActivityId 'A-IN' -Stage input
        $FirstSave | Add-Member -NotePropertyName review_candidates -NotePropertyValue @([pscustomobject]@{
            concept_key='collocation|by_doing';item_kind='collocation';target_form='by doing';target_meaning='through an action';source_ids=@('A-IN')
        })
        $FirstResult=Invoke-V4Json -Root $Root -Arguments @{Action='SaveActivityCheckpoint';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='save-candidate';PayloadJson=($FirstSave|ConvertTo-Json -Depth 20 -Compress)}

        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
        @($Checkpoint.pending_candidates).Count | Should Be 1
        @(Get-TsvRows -Path (Join-Path $Root 'learner\review-candidates.tsv') -Headers $script:V4ReviewCandidateHeaders).Count | Should Be 0
        @(Get-TsvRows -Path (Join-Path $Root 'learner\skill-evidence.tsv') -Headers $script:V4EvidenceHeaders).Count | Should Be 0

        $Contract=New-TestContract -Checkpoint $Checkpoint -ActivityId 'A-OUT' -Stage output
        [void](Invoke-V4Json -Root $Root -Arguments @{Action='PrepareActivity';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='prepare-correction';PayloadJson=($Contract|ConvertTo-Json -Depth 20 -Compress)})
        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
        $SecondSave=New-SavePayload -ActivityId 'A-OUT' -Stage output -NextAction 'finalize_session'
        $SecondSave | Add-Member -NotePropertyName corrections -NotePropertyValue @([pscustomobject]@{
            record_kind='correction';ref_observation_id=[string]$FirstResult.receipt.observation_id;evidence='Corrected the earlier frozen observation after feedback.'
        })
        [void](Invoke-V4Json -Root $Root -Arguments @{Action='SaveActivityCheckpoint';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='save-correction';PayloadJson=($SecondSave|ConvertTo-Json -Depth 20 -Compress)})

        $Checkpoint=(Read-DurableJson -Path (Join-Path $Root '.state\current-session.json')).value
        @($Checkpoint.pending_corrections).Count | Should Be 1
        @(Get-TsvRows -Path (Join-Path $Root 'learner\review-candidates.tsv') -Headers $script:V4ReviewCandidateHeaders).Count | Should Be 0
        @(Get-TsvRows -Path (Join-Path $Root 'learner\skill-evidence.tsv') -Headers $script:V4EvidenceHeaders).Count | Should Be 0

        $FinalPayload=[pscustomobject]@{feedback_shown=$true;duration_minutes=30;session_summary='Completed two activities and consolidated pending facts.'}
        [void](Invoke-V4Json -Root $Root -Arguments @{Action='FinalizeSession';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='final-pending-facts';PayloadJson=($FinalPayload|ConvertTo-Json -Compress);Date=[datetime]'2026-09-05T12:05:00'})

        $Evidence=@(Get-TsvRows -Path (Join-Path $Root 'learner\skill-evidence.tsv') -Headers $script:V4EvidenceHeaders)
        $Evidence.Count | Should Be 3
        @($Evidence | Where-Object record_kind -eq 'correction').Count | Should Be 1
        @($Evidence | Where-Object record_kind -eq 'correction')[0].ref_observation_id | Should Be ([string]$FirstResult.receipt.observation_id)
        @(Get-TsvRows -Path (Join-Path $Root 'learner\review-candidates.tsv') -Headers $script:V4ReviewCandidateHeaders).Count | Should Be 1

        $Replay=Invoke-V4Json -Root $Root -Arguments @{Action='FinalizeSession';SessionId=$Start.receipt.session_id;OwnerToken=$Checkpoint.lease.owner_token;ExpectedRevision=[int]$Checkpoint.revision;IdempotencyKey='final-pending-facts';PayloadJson=($FinalPayload|ConvertTo-Json -Compress);Date=[datetime]'2026-09-05T12:05:01'}
        $Replay.reason_code | Should Be 'idempotent_replay'
        @(Get-TsvRows -Path (Join-Path $Root 'learner\skill-evidence.tsv') -Headers $script:V4EvidenceHeaders).Count | Should Be 3
        @(Get-TsvRows -Path (Join-Path $Root 'learner\review-candidates.tsv') -Headers $script:V4ReviewCandidateHeaders).Count | Should Be 1
    }
}

Describe 'V4 non-retroactive activation migration' {
    It 'preserves legacy bytes, snapshots every protected area, and publishes a usable v4 runtime' {
        $Root=New-V4MigrationFixture
        $Context=New-V4Context -ProjectRoot $Root -Date ([datetime]'2026-09-05T12:00:00')
        $Payload=New-V4ActivationPayload
        $VocabularyHash=Get-FileSha256 -Path (Join-Path $Root 'learner\vocabulary.tsv')
        $ErrorHash=Get-FileSha256 -Path (Join-Path $Root 'learner\error-log.tsv')

        $Result=Invoke-V4ActivateMigration -Context $Context -Payload $Payload -IdempotencyKey 'activate-happy' -ConfirmActivation
        $Result.status | Should Be 'active'
        $Result.receipt.runtime_version | Should Be 4
        $Result.receipt.post_activation_maintenance | Should Be 'remove_v3_branches_from_skill_keep_legacy_docs'
        (Get-FileSha256 -Path (Join-Path $Root 'learner\vocabulary.tsv')) | Should Be $VocabularyHash
        (Get-FileSha256 -Path (Join-Path $Root 'learner\error-log.tsv')) | Should Be $ErrorHash

        $Settings=Read-StableJsonFile -Path (Join-Path $Root 'learner\settings.json')
        [int]$Settings.schema_version | Should Be 4
        [int]$Settings.runtime_protocol_version | Should Be 4
        [string]$Settings.activation_id | Should Be ([string]$Result.receipt.migration_id)

        $Transaction=(Read-DurableJson -Path (Join-Path $Root '.state\migration-v4-transaction.json')).value
        $SnapshotRoot=Join-Path $Root ([string]$Transaction.snapshot_relative_path).Replace('/', '\')
        foreach($Relative in @('learner/settings.json','sessions/2026/09/legacy.md','.state/legacy-marker.json')){
            Test-Path -LiteralPath (Join-Path $SnapshotRoot $Relative.Replace('/', '\')) -PathType Leaf | Should Be $true
        }

        $Plans=@(Get-TsvRows -Path (Join-Path $Root 'learner\plan-items.tsv') -Headers $script:V4PlanHeaders)
        @($Plans|Where-Object plan_id -eq 'C0003').Count | Should Be 2
        @($Plans|Where-Object plan_id -eq 'C0004').Count | Should Be 7
        @($Plans|Where-Object plan_id -eq 'C0003'|Where-Object{$_.focus_goal_id-ne''-or$_.plan_role-ne''}).Count | Should Be 0

        $Index=(Read-DurableJson -Path (Join-Path $Root '.state\bootstrap-index.json')).value
        $Index.package_path='';$Index.package_hash=''
        $Fallback=Resolve-V4Package -Context $Context -Index $Index
        $Fallback.status | Should Be 'ready'
        $Fallback.source | Should Be 'local_fallback'
        $Fallback.evidence_mode | Should Be 'training'

        $Bootstrap=Invoke-V4Bootstrap -Context $Context
        $Bootstrap.runtime_version | Should Be 4
        $Bootstrap.prepared_step.next_plan_item_id | Should Be 'P4-01'
        (Invoke-V4Validation -Context $Context).status | Should Be 'valid'
        $Replay=Invoke-V4ActivateMigration -Context $Context -Payload $Payload -IdempotencyKey 'activate-happy' -ConfirmActivation
        $Replay.reason_code | Should Be 'idempotent_replay'
    }

    It 'converges to one activation from every migration fault boundary' {
        foreach($Fault in @('migration_intent','migration_snapshot','migration_packages','migration_schema','migration_projections','migration_index','migration_settings','migration_runtime','migration_commit')){
            $Root=New-V4MigrationFixture
            $Context=New-V4Context -ProjectRoot $Root -Date ([datetime]'2026-09-05T12:00:00')
            $Payload=New-V4ActivationPayload -IdempotencyKey "activate-$Fault"
            Assert-ThrowsV4 { Invoke-V4ActivateMigration -Context $Context -Payload $Payload -IdempotencyKey "activate-$Fault" -ConfirmActivation -FaultAfterPhase $Fault }
            $Recovered=Invoke-V4ActivateMigration -Context $Context -Payload $Payload -IdempotencyKey "activate-$Fault" -ConfirmActivation
            $Recovered.status | Should Be 'active'
            $Runtime=(Read-DurableJson -Path (Join-Path $Root '.state\runtime.json')).value
            [int]$Runtime.runtime_version | Should Be 4
            $Transaction=(Read-DurableJson -Path (Join-Path $Root '.state\migration-v4-transaction.json')).value
            $Transaction.phase | Should Be 'committed'
            @((Get-TsvRows -Path (Join-Path $Root 'learner\plan-items.tsv') -Headers $script:V4PlanHeaders)|Where-Object plan_id -eq 'C0004').Count | Should Be 7
        }
    }

    It 'rejects a schema-invalid migration manifest before creating an intent' {
        $Root=New-V4MigrationFixture
        $Context=New-V4Context -ProjectRoot $Root -Date ([datetime]'2026-09-05T12:00:00')
        $Payload=New-V4ActivationPayload -IdempotencyKey 'activate-invalid-schema'
        $Payload.migration_manifest.activation_gates.c0003_completed=$false
        $Result=Invoke-V4ActivateMigration -Context $Context -Payload $Payload -IdempotencyKey 'activate-invalid-schema' -ConfirmActivation
        $Result.status | Should Be 'blocked'
        $Result.reason_code | Should Be 'activation_payload_invalid'
        @($Result.prepared_step.errors) -contains 'migration_schema_manifest_invalid' | Should Be $true
        Test-Path -LiteralPath (Join-Path $Root '.state\migration-v4-transaction.json') -PathType Leaf | Should Be $false
    }

    It 'routes explicit activation and migration recovery through the main tracker' {
        $Root=New-V4MigrationFixture
        $Key='activate-main-recovery'
        $Payload=New-V4ActivationPayload -IdempotencyKey $Key
        $PayloadJson=$Payload|ConvertTo-Json -Depth 100 -Compress
        Assert-ThrowsV4 {
            & $MainTracker -ProjectRoot $Root -Action ActivateV4 -IdempotencyKey $Key -PayloadJson $PayloadJson `
                -ConfirmActivation -FaultAfterPhase 'migration_schema' | Out-Null
        }
        Test-Path -LiteralPath (Join-Path $Root '.state\migration-v4-transaction.json') -PathType Leaf | Should Be $true
        $Recovered=((& $MainTracker -ProjectRoot $Root -Action Bootstrap|Out-String)|ConvertFrom-Json)
        $Recovered.status | Should Be 'recovered'
        $Recovered.reason_code | Should Be 'migration_recovered'
        $Recovered.receipt.post_activation_maintenance | Should Be 'remove_v3_branches_from_skill_keep_legacy_docs'
        $Ready=((& $MainTracker -ProjectRoot $Root -Action Bootstrap|Out-String)|ConvertFrom-Json)
        $Ready.status | Should Be 'ready'
        $Ready.runtime_version | Should Be 4
        $Ready.prepared_step.next_plan_item_id | Should Be 'P4-01'
    }
}

. (Join-Path $PSScriptRoot 'cycle-publication.cases.ps1')
. (Join-Path $PSScriptRoot 'classroom-latency.cases.ps1')
. (Join-Path $PSScriptRoot 'goal-review.cases.ps1')
