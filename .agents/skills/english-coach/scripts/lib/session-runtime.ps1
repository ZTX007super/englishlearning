Set-StrictMode -Version Latest

function Get-V4BootstrapIndex {
    param([Parameter(Mandatory = $true)][object]$Context)
    $Read = Read-DurableJson -Path $Context.paths.bootstrap_index -AllowMissing
    if ($null -eq $Read) {
        return [pscustomobject]@{ status = 'missing'; source = 'none'; value = $null; reason_code = 'bootstrap_index_missing' }
    }
    if ($Read.status -ne 'valid') {
        return [pscustomobject]@{ status = 'invalid'; source = 'none'; value = $null; reason_code = 'bootstrap_index_invalid' }
    }
    $Index = $Read.value
    $ReviewCandidates = @((Get-ReducerValue $Index 'review_candidates' @()) | Where-Object { $null -ne $_ })
    if ($ReviewCandidates.Count -gt 10) {
        return [pscustomobject]@{ status = 'invalid'; source = $Read.source; value = $null; reason_code = 'review_slice_unbounded' }
    }
    $ExpectedGuard = Get-V4QueueGuard -Index $Index
    if ([string](Get-ReducerValue $Index 'queue_guard' '') -ne $ExpectedGuard) {
        return [pscustomobject]@{ status = 'invalid'; source = $Read.source; value = $null; reason_code = 'queue_guard_mismatch' }
    }
    return [pscustomobject]@{
        status = 'valid'
        source = $Read.source
        value = $Index
        reason_code = $(if ($Read.source -eq 'previous') { 'using_previous_index' } else { 'ok' })
    }
}

function Get-V4CurrentSession {
    param([Parameter(Mandatory = $true)][object]$Context)
    return Read-DurableJson -Path $Context.paths.current_session -AllowMissing
}

function Test-V4CommittedStartIntent {
    param([AllowNull()][object]$Intent)
    if ($null -eq $Intent -or [string](Get-ReducerValue $Intent 'phase' '') -ne 'committed') {
        return $false
    }
    $Receipt = Get-ReducerValue $Intent 'receipt' $null
    if ($null -eq $Receipt -or [string](Get-ReducerValue $Receipt 'operation' '') -ne 'StartSession') {
        return $false
    }
    return (
        [string](Get-ReducerValue $Receipt 'idempotency_key' '') -eq [string](Get-ReducerValue $Intent 'idempotency_key' '') -and
        [string](Get-ReducerValue $Receipt 'session_id' '') -eq [string](Get-ReducerValue $Intent 'session_id' '') -and
        [string](Get-ReducerValue $Receipt 'plan_item_id' '') -eq [string](Get-ReducerValue $Intent 'plan_item_id' '')
    )
}

function Get-V4ReviewPreparationItems {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [AllowEmptyCollection()][object[]]$Selected = @()
    )
    if (@($Selected).Count -eq 0) { return @() }
    $ReviewItems = @(Get-TsvRows -Path $Context.paths.review_items -Headers $script:V4ReviewItemHeaders)
    return @(foreach ($Candidate in @($Selected)) {
        $ReviewItemId = [string](Get-ReducerValue $Candidate 'review_item_id' '')
        $Match = @($ReviewItems | Where-Object { [string]$_.review_item_id -eq $ReviewItemId })
        if ($Match.Count -ne 1) {
            [pscustomobject]@{
                review_item_id = $ReviewItemId
                preparation_status = 'missing_review_item'
            }
            continue
        }
        [pscustomobject]@{
            review_item_id = $ReviewItemId
            lane = [string](Get-ReducerValue $Candidate 'lane' '')
            recipe_stage = [string](Get-ReducerValue $Candidate 'recipe_stage' '')
            weight = [int](Get-ReducerValue $Candidate 'weight' 0)
            effective_due = [string](Get-ReducerValue $Candidate 'effective_due' '')
            review_family = [string]$Match[0].review_family
            target_scope = [string]$Match[0].target_scope
            target_form = [string]$Match[0].target_form
            target_meaning = [string]$Match[0].target_meaning
            allowed_variants_json = [string]$Match[0].allowed_variants_json
            known_confusions_json = [string]$Match[0].known_confusions_json
            context_seeds_json = [string]$Match[0].context_seeds_json
            preparation_status = 'ready'
        }
    })
}

function Get-V4RequiredStages {
    param(
        [Parameter(Mandatory = $true)][string]$SessionType,
        [string]$PrimarySkill = '',
        [string]$PlanRole = ''
    )
    if ($PlanRole -eq 'cycle_review') { return @('feedback') }
    switch ($SessionType) {
        'daily' { return @('review','input','output','feedback') }
        'review' { return @('review','feedback') }
        'diagnostic' { return @('input','output','feedback') }
        'assessment' { return @('input','output','feedback') }
        'extra' { return @('input','output','feedback') }
        'integrated' {
            switch ($PrimarySkill) {
                { $_ -in @('listening','reading') } { return @('input','feedback') }
                { $_ -in @('speaking','writing') } { return @('output','feedback') }
                { $_ -in @('integrated','mixed') } { return @('input','output','feedback') }
                default { throw "Unsupported primary_skill for integrated session: $PrimarySkill" }
            }
        }
        default { throw "Unsupported session_type: $SessionType" }
    }
}

function Get-V4SessionFile {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$SessionId
    )
    $Folder = Join-Path (Join-Path $Context.paths.sessions $Context.study_date.ToString('yyyy')) $Context.study_date.ToString('MM')
    $Name = $Context.study_date.ToString('yyyy-MM-dd') + '-' + $SessionId.Substring([Math]::Max(0, $SessionId.Length - 8)) + '.md'
    return Join-Path $Folder $Name
}

function New-V4SessionStubText {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Intent
    )
    return @"
---
session_id: $($Intent.session_id)
date: $($Context.study_date.ToString('yyyy-MM-dd'))
plan_item_id: $($Intent.plan_item_id)
session_type: $($Intent.session_type)
status: in_progress
duration_minutes: 0
primary_skill: $($Intent.primary_skill)
study_timezone: $($Context.settings.study_timezone)
source_type: $($Intent.source_type)
runtime_schema_version: 4
protocol_version: 4
queue_guard: $($Intent.queue_guard)
package_hash: $($Intent.package_hash)
transaction_id: none
finalization_id: none
---

# $($Intent.title)

## 学习记录

- 本文件由 tracker 在课末事务中完成；教学过程中不手工写正式事实。
"@
}

function New-V4Checkpoint {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Intent,
        [Parameter(Mandatory = $true)][object]$Index
    )
    $Timestamp = Get-V4Timestamp -Context $Context
    $SelectedReview = @(Get-V4ReviewPreparationItems -Context $Context -Selected @((Get-ReducerValue $Index 'review_candidates' @()) | Where-Object { $null -ne $_ }))
    if ([int](Get-ReducerValue $Intent 'classroom_version' 0) -eq 1) {
        $Exposure=Get-ReducerValue $Index 'review_exposures' $null
        if ($null -ne $Exposure -and $Exposure.study_date -eq $Context.study_date.ToString('yyyy-MM-dd')) {
            $SelectedReview=@($SelectedReview | Where-Object { $_.review_item_id -notin @($Exposure.item_ids) })
        }
    }
    $RequiredStages = @(Get-V4RequiredStages -SessionType ([string]$Intent.session_type) `
        -PrimarySkill ([string]$Intent.primary_skill) -PlanRole ([string]$Intent.plan_role))
    return [pscustomobject]@{
        schema_version = 4
        protocol_version = 4
        classroom_version = [int](Get-ReducerValue $Intent 'classroom_version' 0)
        revision = 1
        status = 'in_progress'
        session_id = $Intent.session_id
        plan_item_id = $Intent.plan_item_id
        plan_id = $Intent.plan_id
        study_date = $Context.study_date.ToString('yyyy-MM-dd')
        study_timezone = [string]$Context.settings.study_timezone
        session_type = $Intent.session_type
        primary_skill = $Intent.primary_skill
        plan_role = $Intent.plan_role
        focus_goal_id = $Intent.focus_goal_id
        preauthorized_probe_candidate = Get-ReducerValue $Index 'preauthorized_probe_candidate' $null
        session_file = $Intent.session_file
        queue_guard = $Intent.queue_guard
        package_path = $Intent.package_path
        package_hash = $Intent.package_hash
        package_source = $Intent.package_source
        declared_source_type = $Intent.requested_source_type
        evidence_mode_cap = [string](Get-ReducerValue $Intent 'evidence_mode_cap' 'training')
        lease = [pscustomobject]@{
            owner_token = $Intent.owner_token
            acquired_at = $Timestamp
            renewed_at = $Timestamp
        }
        started_at = $Timestamp
        updated_at = $Timestamp
        waiting_action = $(if ($SelectedReview.Count -gt 0) {
            if ([int](Get-ReducerValue $Intent 'classroom_version' 0) -eq 1) { 'prepare_review_questions' } else { 'present_review' }
        } else { 'prepare_activity' })
        classroom_review = [pscustomobject]@{
            batch_id = (New-StableIdentifier -Prefix 'RB-' -Seed "$($Intent.session_id)|classroom-review" -HashLength 24)
            questions = @(); cursor = 0; repair_count = 0; feedback_text = ''; followup_prompt = ''
        }
        required_stages = $RequiredStages
        completed_stages = @()
        prepared_activity = $null
        activity_records = @()
        pending_activity_batch = @()
        pending_review_batches = @()
        pending_candidates = @()
        pending_corrections = @()
        idempotency_receipts = @()
        seen_content_ids = @()
        seen_context_ids = @()
        review_state = [pscustomobject]@{
            frozen_study_date = $Context.study_date.ToString('yyyy-MM-dd')
            recovery_mode = [bool](Get-ReducerValue $Index 'recovery_mode' $false)
            selected = $SelectedReview
            due_counts = Get-ReducerValue $Index 'review_due_counts' ([pscustomobject]@{})
        }
        performance = [pscustomobject]@{
            request_started_at = [string](Get-ReducerValue $Index 'request_started_at' '')
            bootstrap_latency_ms = [int](Get-ReducerValue $Index 'bootstrap_latency_ms' 0)
            material_ready_latency_ms = 0
            decision_latency_ms = 0
            checkpoint_latency_ms = 0
            persistence_latency_ms = 0
            uncontrolled_latency_ms = 0
            fallback_used = $false
            fallback_reason = ''
        }
        pending_persistence = [pscustomobject]@{ phase = 'none'; reason_code = '' }
    }
}

function Complete-V4StartIntent {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Intent,
        [string]$FaultAfterPhase
    )
    $IndexRead = Get-V4BootstrapIndex -Context $Context
    if ($IndexRead.status -ne 'valid') { throw "Cannot start without a valid bootstrap index: $($IndexRead.reason_code)" }
    $Index = $IndexRead.value
    if ([string]$Intent.queue_guard -ne (Get-V4QueueGuard -Index $Index)) {
        throw 'Start intent queue guard no longer matches the strict queue head.'
    }

    if ([string]$Intent.phase -eq 'intent') {
        $SessionFile = Join-Path $Context.root ([string]$Intent.session_file).Replace('/', '\')
        if (Test-Path -LiteralPath $SessionFile -PathType Leaf) {
            $Existing = Get-Content -LiteralPath $SessionFile -Raw -Encoding UTF8
            if ($Existing -notmatch "(?m)^session_id: $([regex]::Escape([string]$Intent.session_id))$") {
                throw 'Start intent session path is occupied by another session.'
            }
        }
        else {
            Write-DurableText -Path $SessionFile -Text (New-V4SessionStubText -Context $Context -Intent $Intent)
        }
        $Intent.phase = 'stub_written'
        $Intent.updated_at = Get-V4Timestamp -Context $Context
        $Intent = Write-DurableJson -Path $Context.paths.start_intent -Value $Intent
        Invoke-FaultPoint -Name 'start_stub' -RequestedFault $FaultAfterPhase
    }

    if ([string]$Intent.phase -eq 'stub_written') {
        $Plans = @(Get-TsvRows -Path $Context.paths.plans -Headers $script:V4PlanHeaders)
        $Target = @($Plans | Where-Object { $_.plan_item_id -eq [string]$Intent.plan_item_id })
        if ($Target.Count -ne 1) { throw 'Start intent plan item is missing.' }
        if ($Target[0].status -eq 'planned') {
            $Target[0].status = 'in_progress'
            $Target[0].completed_session_id = ''
            Write-TsvRowsAtomic -Path $Context.paths.plans -Rows $Plans -Headers $script:V4PlanHeaders
        }
        elseif ($Target[0].status -ne 'in_progress') {
            throw "Start intent cannot lock plan item in status $($Target[0].status)."
        }
        $Intent.phase = 'plan_locked'
        $Intent.updated_at = Get-V4Timestamp -Context $Context
        $Intent = Write-DurableJson -Path $Context.paths.start_intent -Value $Intent
        Invoke-FaultPoint -Name 'start_plan_lock' -RequestedFault $FaultAfterPhase
    }

    if ([string]$Intent.phase -eq 'plan_locked') {
        $Existing = Get-V4CurrentSession -Context $Context
        if ($null -ne $Existing -and $Existing.status -eq 'valid' -and
            [string]$Existing.value.status -eq 'in_progress' -and
            [string]$Existing.value.session_id -ne [string]$Intent.session_id) {
            throw "Another v4 session is active: $($Existing.value.session_id)"
        }
        if ($null -eq $Existing -or $Existing.status -ne 'valid' -or
            [string]$Existing.value.session_id -ne [string]$Intent.session_id) {
            $Checkpoint = New-V4Checkpoint -Context $Context -Intent $Intent -Index $Index
            [void](Write-DurableJson -Path $Context.paths.current_session -Value $Checkpoint)
        }
        $Intent.phase = 'checkpoint_written'
        $Intent.updated_at = Get-V4Timestamp -Context $Context
        $Intent = Write-DurableJson -Path $Context.paths.start_intent -Value $Intent
        Invoke-FaultPoint -Name 'start_checkpoint' -RequestedFault $FaultAfterPhase
    }

    if ([string]$Intent.phase -eq 'checkpoint_written') {
        $Intent.status = 'committed'
        $Intent.phase = 'committed'
        $Intent.committed_at = Get-V4Timestamp -Context $Context
        $Intent.receipt = [pscustomobject]@{
            operation = 'StartSession'
            idempotency_key = $Intent.idempotency_key
            payload_hash = $Intent.payload_hash
            session_id = $Intent.session_id
            plan_item_id = $Intent.plan_item_id
            queue_guard = $Intent.queue_guard
            owner_token = $Intent.owner_token
            revision = 1
            package_source = $Intent.package_source
            declared_source_type = $Intent.requested_source_type
        }
        $Intent = Write-DurableJson -Path $Context.paths.start_intent -Value $Intent
        Invoke-FaultPoint -Name 'start_commit' -RequestedFault $FaultAfterPhase
    }
    return $Intent
}

function Resolve-V4Package {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Index
    )
    $Candidates = @(
        [pscustomobject]@{
            path = [string](Get-ReducerValue $Index 'package_path' '')
            hash = [string](Get-ReducerValue $Index 'package_hash' '')
            source = 'published_exact'
            evidence_mode = 'planned'
        },
        [pscustomobject]@{
            path = [string](Get-ReducerValue $Index 'compatible_previous_package_path' '')
            hash = [string](Get-ReducerValue $Index 'compatible_previous_package_hash' '')
            source = 'compatible_previous'
            evidence_mode = 'training'
        },
        [pscustomobject]@{
            path = [string](Get-ReducerValue $Index 'fallback_package_path' '')
            hash = [string](Get-ReducerValue $Index 'fallback_package_hash' '')
            source = 'local_fallback'
            evidence_mode = 'training'
        }
    )
    foreach ($Candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($Candidate.path)) { continue }
        $FullPath = Join-Path $Context.root $Candidate.path.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) { continue }
        if ((Get-Item -LiteralPath $FullPath).Length -gt 262144) { continue }
        if ([string]::IsNullOrWhiteSpace($Candidate.hash) -or (Get-FileSha256 $FullPath) -ne $Candidate.hash) { continue }
        $PackageRead = Read-DurableJson -Path $FullPath -AllowMissing
        if ($null -eq $PackageRead -or $PackageRead.status -ne 'valid') { continue }
        $Manifest = $PackageRead.value
        if ([int](Get-ReducerValue $Manifest 'schema_version' 0) -ne 1 -or
            [string](Get-ReducerValue $Manifest 'status' '') -ne 'ready' -or
            [string](Get-ReducerValue $Manifest 'plan_item_id' '') -ne [string](Get-ReducerValue $Index 'next_plan_item_id' '') -or
            [string](Get-ReducerValue $Manifest 'plan_id' '') -ne [string](Get-ReducerValue $Index 'plan_id' '') -or
            [string](Get-ReducerValue $Manifest 'policy_version' '') -ne [string](Get-ReducerValue $Index 'policy_version' '') -or
            [string](Get-ReducerValue $Manifest 'catalog_version' '') -ne [string](Get-ReducerValue $Index 'catalog_version' '') -or
            [string](Get-ReducerValue $Manifest 'ladder_version' '') -ne [string](Get-ReducerValue $Index 'ladder_version' '') -or
            [string](Get-ReducerValue $Manifest 'contract_version' '') -ne [string](Get-ReducerValue $Index 'contract_version' '')) { continue }
        if ([string](Get-ReducerValue $Manifest 'rights_status' '') -notin @('project_original','licensed','public_domain','not_applicable')) { continue }
        $Skeletons = @((Get-ReducerValue $Manifest 'activity_skeletons' @()) | Where-Object { $null -ne $_ })
        if ($Skeletons.Count -lt 1 -or $Skeletons.Count -gt 3) { continue }
        $Core = Get-V4CoreBlueprint -Context $Context -Package $Manifest
        if (-not [string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Manifest 'blueprint_path' '')) -and
            [string]$Core.status -ne 'ready') { continue }
        return [pscustomobject]@{
            status = 'ready'
            path = $Candidate.path
            hash = $Candidate.hash
            source = $Candidate.source
            evidence_mode = $Candidate.evidence_mode
            fallback_used = $Candidate.source -ne 'published_exact'
            manifest = $Manifest
            core_blueprint = $Core
        }
    }
    return [pscustomobject]@{
        status = 'unavailable'
        path = ''
        hash = ''
        source = 'none'
        evidence_mode = 'training'
        fallback_used = $true
    }
}

function Get-V4CoreBlueprint {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Package
    )
    $RelativePath = [string](Get-ReducerValue $Package 'blueprint_path' '')
    $ExpectedHash = [string](Get-ReducerValue $Package 'blueprint_sha256' '')
    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return [pscustomobject]@{ status='skeleton_only'; value=$null; path=''; hash='' }
    }
    $Path = Join-Path $Context.root $RelativePath.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or
        [string]::IsNullOrWhiteSpace($ExpectedHash) -or
        (Get-FileSha256 -Path $Path) -ne $ExpectedHash) {
        return [pscustomobject]@{ status='invalid_blueprint_reference'; value=$null; path=$RelativePath; hash=$ExpectedHash }
    }
    try { $Registry = Read-StableJsonFile -Path $Path }
    catch { return [pscustomobject]@{ status='invalid_blueprint_json'; value=$null; path=$RelativePath; hash=$ExpectedHash } }
    $PlanItemId = [string](Get-ReducerValue $Package 'plan_item_id' '')
    $Matches = @((Get-ReducerValue $Registry 'blueprints' @()) | Where-Object {
        [string](Get-ReducerValue $_ 'plan_item_id' '') -eq $PlanItemId
    })
    if ($Matches.Count -ne 1) {
        return [pscustomobject]@{ status='blueprint_item_missing_or_duplicate'; value=$null; path=$RelativePath; hash=$ExpectedHash }
    }
    $Validation = Test-V4CoreBlueprint -Blueprint $Matches[0]
    if (-not $Validation.valid) {
        return [pscustomobject]@{ status='invalid_core_schema'; value=$null; path=$RelativePath; hash=$ExpectedHash; errors=@($Validation.errors) }
    }
    $Material = Get-ReducerValue $Matches[0] 'material' $null
    if ($null -ne $Material) {
        foreach ($Pair in @(
            [pscustomobject]@{ path=[string](Get-ReducerValue $Material 'audio_path' ''); hash=[string](Get-ReducerValue $Material 'audio_sha256' '') },
            [pscustomobject]@{ path=[string](Get-ReducerValue $Material 'transcript_path' ''); hash=[string](Get-ReducerValue $Material 'transcript_sha256' '') }
        )) {
            if ([string]::IsNullOrWhiteSpace($Pair.path)) { continue }
            $AssetPath = Join-Path $Context.root $Pair.path.Replace('/', '\')
            if (-not (Test-Path -LiteralPath $AssetPath -PathType Leaf) -or
                [string]::IsNullOrWhiteSpace($Pair.hash) -or
                (Get-FileSha256 -Path $AssetPath) -ne $Pair.hash) {
                return [pscustomobject]@{ status='invalid_core_asset'; value=$null; path=$RelativePath; hash=$ExpectedHash }
            }
        }
    }
    return [pscustomobject]@{ status='ready'; value=$Matches[0]; path=$RelativePath; hash=$ExpectedHash }
}

function Get-V4SessionNextAction {
    param([object]$Checkpoint)
    $Action = [string]$Checkpoint.waiting_action
    if ([string]$Checkpoint.plan_role -eq 'cycle_review' -and $Action -eq 'prepare_activity') {
        return 'evaluate_cycle_review'
    }
    return $Action
}

function Get-V4CycleReviewPacket {
    param([object]$Context, [object]$Checkpoint)
    $Projection = Read-DurableJson -Path $Context.paths.current_cycle_evidence -AllowMissing
    if ($null -eq $Projection -or $Projection.status -ne 'valid') { throw 'Cycle review evidence projection is unavailable.' }
    $Plans = @(Get-TsvRows -Path $Context.paths.plans -Headers $script:V4PlanHeaders)
    $CyclePlans = @($Plans | Where-Object { $_.plan_id -eq $Checkpoint.plan_id })
    $PlanIds = @($CyclePlans | ForEach-Object { $_.plan_item_id })
    $Rows = @(Get-TsvRows -Path $Context.paths.evidence -Headers $script:V4EvidenceHeaders)
    $Refs = @($Projection.value.evidence_refs)
    if ($Refs.Count -gt 18) { throw 'Cycle review projection exceeds its evidence bound.' }
    $Evidence = @(foreach ($Ref in $Refs) {
        $Matches = @($Rows | Where-Object { $_.evidence_id -eq $Ref.evidence_id -and $_.observation_id -eq $Ref.observation_id })
        if ($Matches.Count -ne 1) { throw 'Cycle review evidence reference is missing or ambiguous.' }
        $Row = $Matches[0]
        if ($Row.plan_item_id -notin $PlanIds) { continue }
        $Amendments = @($Rows | Where-Object { $_.ref_observation_id -eq $Row.observation_id -and $_.record_kind -in @('correction','void') })
        if ($Amendments.Count -gt 0) { throw 'Cycle review evidence requires correction/void projection maintenance.' }
        $Row | Add-Member -NotePropertyName evidence_class -NotePropertyValue (Get-EvidenceClass -Observation $Row) -Force
        $Row
    })
    if (@($Evidence | Select-Object -ExpandProperty observation_id -Unique).Count -gt 12) { throw 'Cycle review exceeds 12 primary observations.' }
    $Goals = @(Get-TsvRows -Path $Context.paths.focus_goals -Headers $script:V4FocusGoalHeaders | Where-Object { $_.goal_id -eq $Checkpoint.focus_goal_id })
    if (-not [string]::IsNullOrWhiteSpace([string]$Checkpoint.focus_goal_id) -and $Goals.Count -ne 1) {
        throw 'Cycle review focus goal is missing or ambiguous.'
    }
    $Competencies = @(Get-TsvRows -Path $Context.paths.competency_status -Headers $script:V4CompetencyStatusHeaders | Where-Object { $_.stage_id -in @($Goals | ForEach-Object { $_.stage_id }) })
    if ($Competencies.Count -gt 15) { throw 'Cycle review exceeds 15 competency summaries.' }
    $CycleSessions = @($CyclePlans | ForEach-Object { $_.completed_session_id } | Where-Object { $_ })
    $ReviewHistory = @(Get-TsvRows -Path $Context.paths.review_history -Headers $script:V4ReviewHistoryHeaders | Where-Object { $_.session_id -in $CycleSessions })
    $Insights = @(Get-TsvRows -Path $Context.paths.insights -Headers $script:V4InsightHeaders | Where-Object { $_.status -in @('active','watch') } | Select-Object -First 12)
    $Packet = [pscustomobject]@{
        schema_version=4; cycle_id=$Checkpoint.plan_id; session_id=$Checkpoint.session_id
        projection_revision=$Projection.value.projection_revision
        evidence=@($Evidence); goals=@($Goals); current_competencies=@($Competencies)
        review_batch_refs=@($Projection.value.review_batch_refs)
        review_trends=@($ReviewHistory | Group-Object result | ForEach-Object { [pscustomobject]@{rating=$_.Name;count=$_.Count} })
        insights=@($Insights)
        pending_review_summary=@($Checkpoint.pending_review_batches | ForEach-Object {
            [pscustomobject]@{batch_id=$_.batch_id; formally_committed=$false; items=@($_.items | Select-Object review_item_id,rating)}
        })
        completed_training_count=@($CyclePlans | Where-Object { $_.plan_role -ne 'cycle_review' -and $_.status -eq 'completed' }).Count
        scope='current_cycle_only'; supports_cross_cycle_attainment=$false
        next_plan_publication='PublishCycle_after_review_commit_and_plan_confirmation'
    }
    if ([System.Text.Encoding]::UTF8.GetByteCount((ConvertTo-CanonicalJson -Value $Packet)) -gt 65536) { throw 'Cycle review packet exceeds 64 KB.' }
    return $Packet
}

function Get-V4GoalContract {
    param([object]$Goal)
    try { $Contract=ConvertFrom-StableJson -Json ([string]$Goal.success_criteria_json) } catch { return $null }
    if ([int](Get-ReducerValue $Contract 'schema_version' 0) -ne 1) { return $null }
    foreach ($Name in @('catalog_version','indicator_id','anchor_id')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Contract $Name ''))) { return $null }
    }
    $Ids=@(Get-ReducerValue $Contract 'required_criterion_ids' @())
    $Guards=@(Get-ReducerValue $Contract 'guardrail_criterion_ids' @())
    if ($Ids.Count -lt 1 -or $Ids.Count -gt 4 -or $Guards.Count -gt 2 -or
        @($Ids+$Guards | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0 -or
        @($Ids+$Guards | Select-Object -Unique).Count -ne ($Ids.Count+$Guards.Count)) { return $null }
    if ([string](Get-ReducerValue $Contract 'confirmation_evidence_mode' '') -ne 'assessment') { return $null }
    return $Contract
}

function Get-V4PracticalGoalDecision {
    param([object]$Context, [object]$Checkpoint, [object]$Goal)
    $Plans=@(Get-TsvRows -Path $Context.paths.plans -Headers $script:V4PlanHeaders)
    $Cycles=@($Plans | Where-Object { $_.focus_goal_id -eq $Goal.goal_id -and $_.plan_id -ge $Goal.start_cycle_id -and $_.plan_id -le $Checkpoint.plan_id } |
        Group-Object plan_id | Where-Object {
            $Group=$_.Group
            @($Group | Where-Object { $_.plan_role -eq 'cycle_review' -and ($_.status -eq 'completed' -or $_.plan_item_id -eq $Checkpoint.plan_item_id) }).Count -eq 1 -and
            @($Group | Where-Object { $_.plan_role -ne 'cycle_review' -and $_.status -notin @('completed','cancelled') }).Count -eq 0
        } | Sort-Object Name)
    $Window=@($Cycles | Select-Object -Last 4 | ForEach-Object Name)
    $Committed=@($Plans | Where-Object { $_.plan_id -in $Window -and $_.status -eq 'completed' })
    $All=@(Get-TsvRows -Path $Context.paths.evidence -Headers $script:V4EvidenceHeaders)
    $CommittedIds=@($Committed | ForEach-Object plan_item_id)
    $Rows=@($All | Where-Object { $_.record_kind -eq 'observation' -and $_.focus_goal_id -eq $Goal.goal_id -and $_.plan_item_id -in $CommittedIds })
    $Contract=Get-V4GoalContract $Goal
    $A=@(); $Excluded=0; $Audit=$false; $Seen=@{}
    if ($null -ne $Contract) {
        foreach ($Row in $Rows) {
            if ($Seen.ContainsKey($Row.observation_id)) { $Audit=$true; continue }; $Seen[$Row.observation_id]=$true
            if (@($All | Where-Object { $_.ref_observation_id -eq $Row.observation_id -and $_.record_kind -in @('correction','void') }).Count) { $Audit=$true; continue }
            $Plan=@($Committed | Where-Object plan_item_id -eq $Row.plan_item_id)[0]
            if ($Plan.plan_role -ne 'focus' -or $Row.session_id -ne $Plan.completed_session_id -or (Get-EvidenceClass $Row) -ne 'A' -or
                $Row.source_session_outcome -ne 'completed' -or $Row.support_level -ne 'none' -or $Row.model_exposed -notin @('false','{}','[]') -or
                $Row.competency_id -ne $Goal.competency_id -or $Row.activity_family -ne $Goal.activity_family -or
                $Row.catalog_version -ne $Contract.catalog_version -or $Row.indicator_id -ne $Contract.indicator_id -or $Row.anchor_id -ne $Contract.anchor_id -or
                [string]::IsNullOrWhiteSpace($Row.context_id) -or $Row.day_id -notmatch '^\d{4}-\d{2}-\d{2}$') { $Excluded++; continue }
            try { $Criteria=@(ConvertFrom-StableJson -Json $Row.criterion_results_json) } catch { $Excluded++; continue }
            $Success=$true; $GuardFailure=$false; $Covered=$true
            foreach ($Id in @($Contract.required_criterion_ids)+@(Get-ReducerValue $Contract 'guardrail_criterion_ids' @())) {
                $Match=@($Criteria | Where-Object criterion_id -eq $Id)
                if ($Match.Count -ne 1 -or $Match[0].result -notin @('met','partial','not_met')) { $Covered=$false; break }
                if ($Match[0].result -ne 'met') {
                    $Success=$false
                    if ($Id -in @(Get-ReducerValue $Contract 'guardrail_criterion_ids' @())) { $GuardFailure=$true }
                }
            }
            if (-not $Covered) { $Excluded++; continue }
            $A+=@([pscustomobject]@{observation_id=$Row.observation_id;cycle_id=$Plan.plan_id;day_id=$Row.day_id;context_id=$Row.context_id;success=$Success;guardrail_failed=$GuardFailure;confirmation=($Row.evidence_mode -eq 'assessment' -and $Row.cost_signal -eq 'normal');criteria=$Criteria})
        }
    }
    $Current=@($A | Where-Object cycle_id -eq $Checkpoint.plan_id)
    $Previous=@($A | Where-Object cycle_id -ne $Checkpoint.plan_id)
    $Success=@($A | Where-Object success)
    $Markers=@(foreach ($Now in @($Current | Where-Object success)) {
        if (@($Previous | Where-Object { -not $_.success -and $_.day_id -lt $Now.day_id }).Count -and
            @($Previous | Where-Object success | ForEach-Object day_id | Select-Object -Unique).Count -lt 2 -and
            @($Success | Where-Object { $_.day_id -ne $Now.day_id }).Count) { $Now.observation_id }
    })
    $Events=@(Get-TsvRows -Path $Context.paths.goal_events -Headers $script:V4GoalEventHeaders | Where-Object { $_.goal_id -eq $Goal.goal_id -and $_.cycle_id -lt $Checkpoint.plan_id } | Sort-Object cycle_id -Descending)
    $Streak=0
    foreach ($Event in $Events) {
        if ($Event.decision -eq 'insufficient_evidence') { continue }
        if ($Event.reason -in @('first_cycle_without_marker','two_cycles_without_progress')) { $Streak++ } else { break }
    }
    $Decision='insufficient_evidence'; $Reason='fewer_than_two_valid_opportunities'
    $Maximum=[int]$Goal.max_completed_cycles; if ($Maximum -lt 2) { $Maximum=4 }
    $Minimum=[Math]::Max(2,[int]$Goal.min_completed_cycles)
    $Confirmation=@($Success | Where-Object confirmation | Sort-Object day_id -Descending | Select-Object -First 1)
    $Counter=@($A | Where-Object { -not $_.success -and ($Confirmation.Count -eq 0 -or $_.day_id -ge $Confirmation[0].day_id) })
    if ($Audit) { $Reason='evidence_audit_required' }
    elseif ($null -eq $Contract) { $Reason='goal_contract_upgrade_required'; if ($Cycles.Count -ge $Maximum) { $Decision='redesign' } }
    elseif ($Current.Count -lt 2) { if ($Cycles.Count -ge $Maximum) { $Decision='redesign';$Reason='maximum_cycles_without_sufficient_evidence' } }
    elseif ($Cycles.Count -ge $Minimum -and $Success.Count -ge 3 -and @($Success.day_id | Select-Object -Unique).Count -ge 2 -and
        @($Success | ForEach-Object context_id | Select-Object -Unique).Count -ge 2 -and $Confirmation.Count -gt 0 -and $Counter.Count -eq 0 -and @($Current | Where-Object guardrail_failed).Count -eq 0) {
        $Decision='met';$Reason='goal_contract_satisfied'
    }
    elseif ($Cycles.Count -ge $Maximum) { $Decision='redesign';$Reason='maximum_cycle_window_reached' }
    elseif ($Markers.Count -gt 0) { $Decision='continue';$Reason='new_progress_marker' }
    elseif ($Streak -ge 1) { $Decision='redesign';$Reason='two_cycles_without_progress' }
    else { $Decision='continue';$Reason='first_cycle_without_marker' }
    return [pscustomobject]@{
        goal_id=$Goal.goal_id;decision=$Decision;reason=$Reason;evidence_ids=@($A | ForEach-Object observation_id | Select-Object -Unique)
        catalog_version=$(if ($null -eq $Contract) {''} else {$Contract.catalog_version});goal_contract_version=[string]$Goal.version
        coverage=[pscustomobject]@{cycle_ids=$Window;completed_cycles=$Cycles.Count;current_opportunities=$Current.Count;independent_successes=$Success.Count;excluded_records=$Excluded;progress_marker_ids=$Markers;confirmation_present=($Confirmation.Count -gt 0);next_evidence_needed=$(if ($null -eq $Contract) {'versioned_goal_contract'} elseif ($Current.Count -lt 2) {'two_current_cycle_independent_checks'} elseif ($Confirmation.Count -eq 0) {'planned_normal_cost_assessment'} else {'review_goal_decision'})}
    }
}

function Invoke-V4CycleReviewEvaluation {
    param([object]$Context, [string]$SessionId)
    $Read = Get-V4CurrentSession -Context $Context
    if ($null -eq $Read -or $Read.status -ne 'valid' -or $Read.value.status -ne 'in_progress' -or
        $Read.value.plan_role -ne 'cycle_review' -or $Read.value.session_id -ne $SessionId -or
        (Get-V4SessionNextAction -Checkpoint $Read.value) -ne 'evaluate_cycle_review') {
        throw 'Cycle review evaluation requires the active cycle-review session at evaluate_cycle_review.'
    }
    $Packet = Get-V4CycleReviewPacket -Context $Context -Checkpoint $Read.value
    $Candidates = @(foreach ($Goal in $Packet.goals) {
        Get-V4PracticalGoalDecision -Context $Context -Checkpoint $Read.value -Goal $Goal
    })
    return New-V4Response -Status 'evaluated' -NextAction 'present_cycle_review_candidates' `
        -Receipt ([pscustomobject]@{operation='EvaluateLongTermState';generated_state_only=$true;session_id=$SessionId;revision=$Read.value.revision;owner_token=$Read.value.lease.owner_token}) `
        -ReasonCode 'practical_goal_review' -PreparedStep ([pscustomobject]@{
            evidence_packet=$Packet;goal_candidates=$Candidates;competency_candidates=@();stage_candidates=@()
            goal_scope='recent_four_completed_cycles'
            generated_state_only=$true;requires_plan_confirmation=$true;next_action_after_summary='finalize_session'
        }) -ProtocolRefs @('references/long-term-state.md','references/tracker-actions.md')
}

function Get-V4SessionPreparationEnvelope {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Checkpoint
    )
    $PackagePath = Join-Path $Context.root ([string]$Checkpoint.package_path).Replace('/', '\')
    $PackageRead = Read-DurableJson -Path $PackagePath -AllowMissing
    $Blueprint = $null
    if ($null -ne $PackageRead -and $PackageRead.status -eq 'valid' -and
        (Get-FileSha256 -Path $PackagePath) -eq [string]$Checkpoint.package_hash) {
        $Package = $PackageRead.value
        $Core = Get-V4CoreBlueprint -Context $Context -Package $Package
        $Blueprint = [pscustomobject]@{
            package_kind = 'activity_blueprint'
            lifecycle_state = [string](Get-ReducerValue $Package 'status' '')
            requires_prepare_activity = $true
            plan_item_id = [string](Get-ReducerValue $Package 'plan_item_id' '')
            plan_role = [string](Get-ReducerValue $Package 'plan_role' '')
            primary_skill = [string](Get-ReducerValue $Package 'primary_skill' '')
            focus_goal_id = [string](Get-ReducerValue $Package 'focus_goal_id' '')
            activity_skeletons = @((Get-ReducerValue $Package 'activity_skeletons' @()) | Where-Object { $null -ne $_ })
            core_status = [string]$Core.status
            core = $Core.value
            blueprint_path = [string]$Core.path
            blueprint_sha256 = [string]$Core.hash
            preauthorized_probe_candidates = @((Get-ReducerValue $Package 'preauthorized_probe_candidates' @()) | Where-Object { $null -ne $_ })
            policy_version = [string](Get-ReducerValue $Package 'policy_version' '')
            catalog_version = [string](Get-ReducerValue $Package 'catalog_version' '')
            ladder_version = [string](Get-ReducerValue $Package 'ladder_version' '')
            contract_version = [string](Get-ReducerValue $Package 'contract_version' '')
            rights_status = [string](Get-ReducerValue $Package 'rights_status' '')
        }
    }
    return [pscustomobject]@{
        session_id = [string]$Checkpoint.session_id
        owner_token = [string]$Checkpoint.lease.owner_token
        revision = [int]$Checkpoint.revision
        session_type = [string]$Checkpoint.session_type
        primary_skill = [string]$Checkpoint.primary_skill
        plan_role = [string]$Checkpoint.plan_role
        required_stages = @((Get-ReducerValue $Checkpoint 'required_stages' @(
            Get-V4RequiredStages -SessionType ([string]$Checkpoint.session_type) `
                -PrimarySkill ([string]$Checkpoint.primary_skill) -PlanRole ([string]$Checkpoint.plan_role)
        )))
        review_first = @($Checkpoint.review_state.selected).Count -gt 0 -and 'review' -notin @($Checkpoint.completed_stages)
        review_items = @($Checkpoint.review_state.selected)
        package_path = [string]$Checkpoint.package_path
        package_hash = [string]$Checkpoint.package_hash
        package_source = [string](Get-ReducerValue $Checkpoint 'package_source' '')
        declared_source_type = [string](Get-ReducerValue $Checkpoint 'declared_source_type' '')
        evidence_mode_cap = [string]$Checkpoint.evidence_mode_cap
        package_blueprint = $Blueprint
        evidence_packet = $(if ([string]$Checkpoint.plan_role -eq 'cycle_review') { Get-V4CycleReviewPacket -Context $Context -Checkpoint $Checkpoint } else { $null })
    }
}

function Invoke-V4StartSession {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey,
        [string]$PlanItemId,
        [ValidateSet('network','user-provided','fallback','none')][string]$SourceType = 'none',
        [switch]$Classroom,
        [string]$FaultAfterPhase
    )
    [void](Assert-V4Active -Context $Context)
    if ([string]::IsNullOrWhiteSpace($IdempotencyKey)) { throw 'StartSession requires -IdempotencyKey.' }
    return Invoke-WithFileLock -LockPath $Context.paths.lock -Script {
        $Publication=Read-DurableJson -Path (Join-Path $Context.root '.state/cycle-publication.json') -AllowMissing
        if ($null -ne $Publication -and ($Publication.status -ne 'valid' -or $Publication.value.phase -ne 'committed')) {
            throw 'Cycle publication must be recovered by Bootstrap before StartSession.'
        }
        $ActiveRead = Get-V4CurrentSession -Context $Context
        if ($null -ne $ActiveRead -and $ActiveRead.status -eq 'valid' -and
            [string]$ActiveRead.value.status -eq 'in_progress') {
            $StartReplay = Read-DurableJson -Path $Context.paths.start_intent -AllowMissing
            if ($null -ne $StartReplay -and $StartReplay.status -eq 'valid' -and
                (Test-V4CommittedStartIntent -Intent $StartReplay.value) -and
                [string]$StartReplay.value.idempotency_key -eq $IdempotencyKey) {
                if ((-not [string]::IsNullOrWhiteSpace($PlanItemId) -and
                    $PlanItemId -ne [string]$StartReplay.value.plan_item_id) -or
                    [string](Get-ReducerValue $StartReplay.value 'requested_source_type' $SourceType) -ne $SourceType) {
                    throw 'Idempotency key was reused with a different StartSession payload.'
                }
                $Prepared = if ($null -ne $ActiveRead.value.prepared_activity) { $ActiveRead.value.prepared_activity } else { Get-V4SessionPreparationEnvelope -Context $Context -Checkpoint $ActiveRead.value }
                return New-V4Response -Status 'started' -NextAction (Get-V4SessionNextAction $ActiveRead.value) `
                    -Receipt $StartReplay.value.receipt -ReasonCode 'idempotent_replay' `
                    -PreparedStep $Prepared
            }
            $Prepared = if ($null -ne $ActiveRead.value.prepared_activity) { $ActiveRead.value.prepared_activity } else { Get-V4SessionPreparationEnvelope -Context $Context -Checkpoint $ActiveRead.value }
            return New-V4Response -Status 'resume' -NextAction (Get-V4SessionNextAction $ActiveRead.value) -ReasonCode 'active_session_exists' -Receipt ([pscustomobject]@{
                session_id = $ActiveRead.value.session_id
                revision = $ActiveRead.value.revision
                owner_token = $ActiveRead.value.lease.owner_token
            }) -PreparedStep $Prepared
        }
        $IndexRead = Get-V4BootstrapIndex -Context $Context
        if ($IndexRead.status -ne 'valid') {
            return New-V4Response -Status 'blocked' -NextAction 'run_maintenance' -ReasonCode $IndexRead.reason_code
        }
        $Index = $IndexRead.value
        $QueueHead = [string](Get-ReducerValue $Index 'next_plan_item_id' '')
        if ([string]::IsNullOrWhiteSpace($QueueHead)) {
            return New-V4Response -Status 'awaiting_plan' -NextAction 'confirm_next_cycle_plan' -ReasonCode 'cycle_queue_complete'
        }
        if (-not [string]::IsNullOrWhiteSpace($PlanItemId) -and $PlanItemId -ne $QueueHead) {
            throw "The strict queue head is $QueueHead; $PlanItemId is blocked."
        }
        $Package = Resolve-V4Package -Context $Context -Index $Index
        if ($Package.status -ne 'ready') {
            return New-V4Response -Status 'blocked' -NextAction 'use_bounded_external_replacement_or_fallback' -ReasonCode 'no_presentable_package'
        }
        $Payload = [pscustomobject]@{
            plan_item_id = $QueueHead
            queue_guard = Get-V4QueueGuard -Index $Index
            package_hash = $Package.hash
            source_type = $SourceType
        }
        $PayloadHash = Get-PayloadHash -Payload $Payload
        $IntentRead = Read-DurableJson -Path $Context.paths.start_intent -AllowMissing
        if ($null -ne $IntentRead -and $IntentRead.status -eq 'valid') {
            $Existing = $IntentRead.value
            $ExistingCommitted = Test-V4CommittedStartIntent -Intent $Existing
            if ([string]$Existing.phase -eq 'committed' -and -not $ExistingCommitted) {
                throw 'Committed start intent has no matching StartSession receipt; run maintenance before starting.'
            }
            if (-not $ExistingCommitted) {
                if ([string]$Existing.idempotency_key -ne $IdempotencyKey -or [string]$Existing.payload_hash -ne $PayloadHash) {
                    throw 'A different start intent is pending and must be recovered first.'
                }
                $Completed = Complete-V4StartIntent -Context $Context -Intent $Existing -FaultAfterPhase $FaultAfterPhase
                $Checkpoint = (Get-V4CurrentSession -Context $Context).value
                return New-V4Response -Status 'started' -NextAction (Get-V4SessionNextAction $Checkpoint) -Receipt $Completed.receipt `
                    -ReasonCode 'recovered_start_intent' -PreparedStep (Get-V4SessionPreparationEnvelope -Context $Context -Checkpoint $Checkpoint)
            }
            if ([string]$Existing.idempotency_key -eq $IdempotencyKey) {
                if ([string]$Existing.payload_hash -ne $PayloadHash) { throw 'Idempotency key was reused with a different StartSession payload.' }
                $Checkpoint = (Get-V4CurrentSession -Context $Context).value
                return New-V4Response -Status 'started' -NextAction (Get-V4SessionNextAction $Checkpoint) -Receipt $Existing.receipt `
                    -ReasonCode 'idempotent_replay' -PreparedStep (Get-V4SessionPreparationEnvelope -Context $Context -Checkpoint $Checkpoint)
            }
        }
        $SessionSeed = "$IdempotencyKey|$QueueHead|$($Context.study_date.ToString('yyyy-MM-dd'))"
        $SessionId = 'S' + $Context.study_date.ToString('yyyyMMdd') + '-' +
            (Get-Sha256Text $SessionSeed).Substring(0, 10)
        $SessionFilePath = Get-V4SessionFile -Context $Context -SessionId $SessionId
        $RelativeSessionPath = $SessionFilePath.Substring($Context.root.Length + 1).Replace('\','/')
        $OwnerToken = New-StableIdentifier -Prefix 'owner-' -Seed "$SessionSeed|owner" -HashLength 20
        $Intent = [pscustomobject]@{
            schema_version = 4
            status = 'pending'
            phase = 'intent'
            operation = 'StartSession'
            classroom_version = $(if ($Classroom) { 1 } else { 0 })
            idempotency_key = $IdempotencyKey
            payload_hash = $PayloadHash
            session_id = $SessionId
            session_file = $RelativeSessionPath
            plan_id = [string](Get-ReducerValue $Index 'plan_id' '')
            plan_item_id = $QueueHead
            title = [string](Get-ReducerValue $Index 'next_title' $QueueHead)
            session_type = [string](Get-ReducerValue $Index 'session_type' 'daily')
            primary_skill = [string](Get-ReducerValue $Index 'primary_skill' 'mixed')
            plan_role = [string](Get-ReducerValue $Index 'plan_role' 'maintenance')
            focus_goal_id = [string](Get-ReducerValue $Index 'focus_goal_id' '')
            queue_guard = Get-V4QueueGuard -Index $Index
            package_path = $Package.path
            package_hash = $Package.hash
            package_source = $Package.source
            evidence_mode_cap = $Package.evidence_mode
            requested_source_type = $SourceType
            source_type = $(if ($Package.fallback_used) { 'fallback' } else { $SourceType })
            owner_token = $OwnerToken
            created_at = Get-V4Timestamp -Context $Context
            updated_at = Get-V4Timestamp -Context $Context
            committed_at = ''
            receipt = $null
        }
        $Intent = Write-DurableJson -Path $Context.paths.start_intent -Value $Intent
        Invoke-FaultPoint -Name 'start_intent' -RequestedFault $FaultAfterPhase
        $Completed = Complete-V4StartIntent -Context $Context -Intent $Intent -FaultAfterPhase $FaultAfterPhase
        $Checkpoint = (Get-V4CurrentSession -Context $Context).value
        return New-V4Response -Status 'started' -NextAction (Get-V4SessionNextAction $Checkpoint) -Receipt $Completed.receipt -ReasonCode $(
            if ($Package.fallback_used) { $Package.source } else { 'ok' }
        ) -PreparedStep (Get-V4SessionPreparationEnvelope -Context $Context -Checkpoint $Checkpoint)
    }
}

function Invoke-V4Bootstrap {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [string]$FaultAfterPhase
    )
    $Timer = [Diagnostics.Stopwatch]::StartNew()
    $Migration = Read-DurableJson -Path $Context.paths.migration -AllowMissing
    if ($null -ne $Migration -and $Migration.status -eq 'valid' -and
        [string](Get-ReducerValue $Migration.value 'phase' 'committed') -ne 'committed') {
        if($null-eq(Get-Command Complete-V4Migration -ErrorAction SilentlyContinue)-or
            $null-eq(Get-Command Assert-V4RecoverableMigration -ErrorAction SilentlyContinue)){
            return New-V4Response -Status 'blocked' -NextAction 'recover_migration' -ReasonCode 'migration_runtime_unavailable'
        }
        [void](Assert-V4RecoverableMigration -Transaction $Migration.value)
        $Recovered=Invoke-WithFileLock -LockPath $Context.paths.lock -Script {
            Complete-V4Migration -Context $Context -Transaction $Migration.value -FaultAfterPhase $FaultAfterPhase
        }
        return New-V4Response -Status 'recovered' -NextAction 'bootstrap' -Receipt $Recovered.receipt -ReasonCode 'migration_recovered'
    }
    if ($null -ne $Migration -and $Migration.status -ne 'valid') {
        return New-V4Response -Status 'blocked' -NextAction 'repair_migration_state' -ReasonCode 'migration_state_invalid'
    }
    $Runtime = Get-V4Runtime -Context $Context
    if ([int](Get-ReducerValue $Runtime 'runtime_version' 0) -ne 4) {
        return New-V4Response -Status 'legacy' -NextAction 'use_v3_protocol' `
            -ReasonCode ([string](Get-ReducerValue $Runtime 'reason_code' 'v4_not_active')) `
            -RuntimeVersion 3 -ProtocolRefs @('references/runtime-protocol-v3.md')
    }
    $Start = Read-DurableJson -Path $Context.paths.start_intent -AllowMissing
    $CyclePublication = Read-DurableJson -Path (Join-Path $Context.root '.state/cycle-publication.json') -AllowMissing
    if ($null -ne $CyclePublication -and $CyclePublication.status -ne 'valid') {
        return New-V4Response -Status 'blocked' -NextAction 'run_maintenance' -ReasonCode 'cycle_publication_invalid'
    }
    if ($null -ne $CyclePublication -and $CyclePublication.status -eq 'valid' -and $CyclePublication.value.phase -ne 'committed') {
        $CycleDone = Invoke-WithFileLock -LockPath $Context.paths.lock -Script {
            Complete-V4CyclePublication -Context $Context -Intent $CyclePublication.value -FaultAfterPhase $FaultAfterPhase
        }
        return New-V4Response -Status 'recovered' -NextAction 'bootstrap' -Receipt $CycleDone.receipt -ReasonCode 'cycle_publication_recovered'
    }
    if ($null -ne $Start -and $Start.status -eq 'valid' -and
        [string]$Start.value.phase -eq 'committed' -and
        -not (Test-V4CommittedStartIntent -Intent $Start.value)) {
        return New-V4Response -Status 'blocked' -NextAction 'run_maintenance' -ReasonCode 'start_intent_invalid_commit'
    }
    if ($null -ne $Start -and $Start.status -eq 'valid' -and
        -not (Test-V4CommittedStartIntent -Intent $Start.value)) {
        $Completed = Invoke-WithFileLock -LockPath $Context.paths.lock -Script {
            Complete-V4StartIntent -Context $Context -Intent $Start.value -FaultAfterPhase $FaultAfterPhase
        }
        $Checkpoint = Get-V4CurrentSession -Context $Context
        $Prepared = if ($null -ne $Checkpoint.value.prepared_activity) { $Checkpoint.value.prepared_activity } else { Get-V4SessionPreparationEnvelope -Context $Context -Checkpoint $Checkpoint.value }
        return New-V4Response -Status 'resume' -NextAction (Get-V4SessionNextAction $Checkpoint.value) -Receipt $Completed.receipt -ReasonCode 'start_intent_recovered' -PreparedStep $Prepared
    }
    $Transaction = Read-DurableJson -Path $Context.paths.session_transaction -AllowMissing
    if ($null -ne $Transaction -and $Transaction.status -eq 'valid' -and
        [string]$Transaction.value.phase -ne 'committed') {
        $Committed = Invoke-WithFileLock -LockPath $Context.paths.lock -Script {
            Complete-V4SessionTransaction -Context $Context -Transaction $Transaction.value -FaultAfterPhase $FaultAfterPhase
        }
        return New-V4Response -Status 'recovered' -NextAction 'bootstrap' -Receipt $Committed.receipt -ReasonCode 'session_transaction_recovered'
    }
    $Checkpoint = Get-V4CurrentSession -Context $Context
    if ($null -ne $Checkpoint -and $Checkpoint.status -eq 'valid' -and
        [string]$Checkpoint.value.status -eq 'in_progress') {
        $Prepared = if ($null -ne $Checkpoint.value.prepared_activity) { $Checkpoint.value.prepared_activity } else { Get-V4SessionPreparationEnvelope -Context $Context -Checkpoint $Checkpoint.value }
        return New-V4Response -Status 'resume' -NextAction (Get-V4SessionNextAction $Checkpoint.value) -Receipt ([pscustomobject]@{
            session_id = $Checkpoint.value.session_id
            revision = $Checkpoint.value.revision
            owner_token = $Checkpoint.value.lease.owner_token
        }) -ReasonCode $(if ($Checkpoint.source -eq 'previous') { 'checkpoint_previous_recovered' } else { 'active_session' }) -PreparedStep $Prepared
    }
    $IndexRead = Get-V4BootstrapIndex -Context $Context
    if ($IndexRead.status -ne 'valid') {
        return New-V4Response -Status 'blocked' -NextAction 'run_maintenance' -ReasonCode $IndexRead.reason_code
    }
    $Index = $IndexRead.value
    if ([string]::IsNullOrWhiteSpace([string]$Index.next_plan_item_id)) {
        return New-V4Response -Status 'awaiting_plan' -NextAction 'confirm_next_cycle_plan' -ReasonCode 'cycle_queue_complete' `
            -PreparedStep ([pscustomobject]@{publication_action='PublishCycle';requires_plan_confirmation=$true}) `
            -ProtocolRefs @('references/cycle-publication.md','references/tracker-actions.md')
    }
    $Package = Resolve-V4Package -Context $Context -Index $Index
    if ($Package.status -ne 'ready') {
        return New-V4Response -Status 'degraded' -NextAction 'use_bounded_external_replacement_or_fallback' -ReasonCode 'no_presentable_package'
    }
    $Timer.Stop()
    $Prepared = [pscustomobject]@{
        runtime_version = 4
        protocol_refs = @((Get-ReducerValue $Index 'protocol_refs' @('references/runtime-protocol-v4.md')))
        queue_guard = Get-V4QueueGuard -Index $Index
        next_plan_item_id = [string](Get-ReducerValue $Index 'next_plan_item_id' '')
        package_path = $Package.path
        package_hash = $Package.hash
        package_source = $Package.source
        evidence_mode_cap = $Package.evidence_mode
        review_candidates = @((Get-ReducerValue $Index 'review_candidates' @()) | Where-Object { $null -ne $_ })
        recovery_mode = [bool](Get-ReducerValue $Index 'recovery_mode' $false)
        bootstrap_latency_ms = $Timer.ElapsedMilliseconds
    }
    return New-V4Response -Status 'ready' -NextAction 'start_session' -ReasonCode $(
        if ($Package.fallback_used) { $Package.source } else { $IndexRead.reason_code }
    ) -PreparedStep $Prepared
}

function Get-V4CheckpointForWrite {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][string]$OwnerToken,
        [Parameter(Mandatory = $true)][int]$ExpectedRevision
    )
    $Read = Get-V4CurrentSession -Context $Context
    if ($null -eq $Read -or $Read.status -ne 'valid') { throw 'No valid v4 current-session checkpoint exists.' }
    $Checkpoint = $Read.value
    if ([string]$Checkpoint.status -ne 'in_progress' -or [string]$Checkpoint.session_id -ne $SessionId) {
        throw 'Checkpoint does not match an active session.'
    }
    if ([string]$Checkpoint.lease.owner_token -ne $OwnerToken) { throw 'Session owner token does not match.' }
    if ([int]$Checkpoint.revision -ne $ExpectedRevision) {
        throw "Checkpoint revision conflict. Expected $ExpectedRevision; current is $($Checkpoint.revision)."
    }
    return $Checkpoint
}

function Get-V4CheckpointForReplay {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][string]$OwnerToken
    )
    $Read = Get-V4CurrentSession -Context $Context
    if ($null -eq $Read -or $Read.status -ne 'valid') { throw 'No valid v4 current-session checkpoint exists.' }
    $Checkpoint = $Read.value
    if ([string]$Checkpoint.status -ne 'in_progress' -or [string]$Checkpoint.session_id -ne $SessionId) {
        throw 'Checkpoint does not match an active session.'
    }
    if ([string]$Checkpoint.lease.owner_token -ne $OwnerToken) { throw 'Session owner token does not match.' }
    return $Checkpoint
}

function Find-V4IdempotencyReceipt {
    param(
        [Parameter(Mandatory = $true)][object]$Checkpoint,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey,
        [Parameter(Mandatory = $true)][string]$PayloadHash
    )
    $Known = @($Checkpoint.idempotency_receipts | Where-Object { $_.key -eq $IdempotencyKey })
    if ($Known.Count -eq 0) { return $null }
    if ([string]$Known[0].payload_hash -ne $PayloadHash) {
        throw 'Idempotency key was reused with a different checkpoint payload.'
    }
    return $Known[0]
}

function Add-V4CheckpointReceipt {
    param(
        [Parameter(Mandatory = $true)][object]$Checkpoint,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey,
        [Parameter(Mandatory = $true)][string]$PayloadHash,
        [Parameter(Mandatory = $true)][object]$Receipt
    )
    $Entries = @($Checkpoint.idempotency_receipts) + @([pscustomobject]@{
        key = $IdempotencyKey
        payload_hash = $PayloadHash
        receipt = $Receipt
    })
    if ($Entries.Count -gt 64) { $Entries = @($Entries | Select-Object -Last 64) }
    $Checkpoint.idempotency_receipts = $Entries
}

function Save-V4Checkpoint {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Checkpoint
    )
    $Checkpoint.revision = [int]$Checkpoint.revision + 1
    $Checkpoint.updated_at = Get-V4Timestamp -Context $Context
    $Checkpoint.lease.renewed_at = $Checkpoint.updated_at
    return Write-DurableJson -Path $Context.paths.current_session -Value $Checkpoint
}

function Invoke-V4PrepareActivity {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][string]$OwnerToken,
        [Parameter(Mandatory = $true)][int]$ExpectedRevision,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey,
        [Parameter(Mandatory = $true)][object]$Payload
    )
    [void](Assert-V4Active -Context $Context)
    if ([string]::IsNullOrWhiteSpace($IdempotencyKey)) { throw 'PrepareActivity requires -IdempotencyKey.' }
    return Invoke-WithFileLock -LockPath $Context.paths.lock -Script {
        $PayloadHash = Get-PayloadHash -Payload $Payload
        $ReplayCheckpoint = Get-V4CheckpointForReplay -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken
        $Known = Find-V4IdempotencyReceipt -Checkpoint $ReplayCheckpoint -IdempotencyKey $IdempotencyKey -PayloadHash $PayloadHash
        if ($null -ne $Known) {
            return New-V4Response -Status 'prepared' -NextAction 'present_activity' -Receipt $Known.receipt -ReasonCode 'idempotent_replay' -PreparedStep $ReplayCheckpoint.prepared_activity
        }
        $Checkpoint = Get-V4CheckpointForWrite -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken -ExpectedRevision $ExpectedRevision
        if ($null -ne $Checkpoint.prepared_activity -and
            [string]$Checkpoint.prepared_activity.status -in @('prepared','awaiting_followup')) {
            throw 'The current prepared activity must be presented and answered before another is prepared.'
        }
        $Contract = ConvertFrom-StableJson -Json (ConvertTo-CanonicalJson -Value $Payload)
        if ([int](Get-ReducerValue $Checkpoint 'classroom_version' 0) -eq 1 -and $Checkpoint.waiting_action -notin @('prepare_activity','show_transfer')) {
            throw 'Finish the current classroom action before preparing a main activity.'
        }
        if ([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Contract 'activity_id' ''))) {
            $Contract | Add-Member -NotePropertyName activity_id -NotePropertyValue (
                New-StableIdentifier -Prefix 'A-' -Seed "$SessionId|$IdempotencyKey" -HashLength 20
            ) -Force
        }
        if (@($Checkpoint.activity_records | Where-Object activity_id -eq $Contract.activity_id).Count -gt 0) {
            throw 'A new activity or transfer requires a new activity_id.'
        }
        $Validation = Test-V4ActivityContract -Activity $Contract
        if ([string]$Checkpoint.plan_role -eq 'cycle_review') { throw 'Cycle review uses EvaluateLongTermState with SessionId, not a scored PrepareActivity contract.' }
        if (-not $Validation.valid) { throw "Activity contract is invalid: $($Validation.errors -join '; ')" }
        if ([string]$Contract.session_id -ne $SessionId -or
            [string]$Contract.queue_guard -ne [string]$Checkpoint.queue_guard -or
            [string]$Contract.package_hash -ne [string]$Checkpoint.package_hash) {
            throw 'Activity contract runtime binding does not match the active session, package, or queue guard.'
        }
        if ([string]$Checkpoint.evidence_mode_cap -eq 'training' -and
            [string](Get-ReducerValue $Contract 'evidence_mode' 'training') -ne 'training') {
            throw 'A compatible old or fallback package is restricted to training evidence.'
        }
        $Existing = @($Checkpoint.activity_records)
        $LeadOrAux = [string](Get-ReducerValue $Contract 'lead_or_auxiliary' 'lead')
        if ($LeadOrAux -notin @('lead','auxiliary')) { throw 'lead_or_auxiliary must be lead or auxiliary.' }
        $PrimaryCount = @($Existing | Where-Object {
            [string](Get-ReducerValue $_ 'lead_or_auxiliary' '') -in @('lead','auxiliary')
        }).Count
        if ($PrimaryCount -ge 2) { throw 'A normal lesson may contain at most two primary observations.' }
        if ([string](Get-ReducerValue $Contract 'evidence_mode' '') -eq 'difficulty_probe' -and
            @($Existing | Where-Object { [string](Get-ReducerValue $_ 'evidence_mode' '') -eq 'difficulty_probe' }).Count -ge 1) {
            throw 'A lesson may contain at most one difficulty probe.'
        }
        if ($LeadOrAux -eq 'auxiliary' -and [string](Get-ReducerValue $Contract 'evidence_mode' '') -eq 'difficulty_probe') {
            throw 'Only the lead primary may be a difficulty probe.'
        }
        if ([string](Get-ReducerValue $Contract 'evidence_mode' '') -eq 'difficulty_probe') {
            if ([bool]$Checkpoint.review_state.recovery_mode) {
                throw 'Recovery mode cannot present a difficulty probe.'
            }
            $Candidate = Get-ReducerValue $Checkpoint 'preauthorized_probe_candidate' $null
            if ($null -eq $Candidate -or
                [string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Candidate 'candidate_id' ''))) {
                throw 'A difficulty probe requires the one preauthorized candidate frozen at cycle review.'
            }
            foreach ($Name in @('adaptation_key','activity_family','competency_id','changed_dimension','target_step')) {
                $Expected = [string](Get-ReducerValue $Candidate $Name '')
                $Actual = [string](Get-ReducerValue $Contract $Name '')
                if ([string]::IsNullOrWhiteSpace($Expected) -or $Actual -ne $Expected) {
                    throw "Difficulty probe does not match its preauthorized candidate: $Name"
                }
            }
        }
        $PreparedAt = Get-V4Timestamp -Context $Context
        $Checkpoint.prepared_activity = [pscustomobject]@{
            activity_id = $Contract.activity_id
            stage = [string](Get-ReducerValue $Contract 'stage' '')
            status = 'prepared'
            prepared_at = $PreparedAt
            contract_hash = Get-PayloadHash -Payload $Contract
            prompt_hash = Get-Sha256Text ([string](Get-ReducerValue $Contract 'prompt_text' ''))
            contract = $Contract
            first_answer_received = $false
            judgment_frozen = $false
            feedback_shown = $false
        }
        $Checkpoint.waiting_action = 'await_answer'
        $Receipt = [pscustomobject]@{
            operation = 'PrepareActivity'
            idempotency_key = $IdempotencyKey
            payload_hash = $PayloadHash
            activity_id = $Contract.activity_id
            contract_hash = $Checkpoint.prepared_activity.contract_hash
            revision = $ExpectedRevision + 1
        }
        Add-V4CheckpointReceipt -Checkpoint $Checkpoint -IdempotencyKey $IdempotencyKey -PayloadHash $PayloadHash -Receipt $Receipt
        $Saved = Save-V4Checkpoint -Context $Context -Checkpoint $Checkpoint
        return New-V4Response -Status 'prepared' -NextAction 'present_activity' -Receipt $Receipt -PreparedStep $Saved.prepared_activity
    }
}

function Update-V4ActivityFollowup {
    param([object]$Checkpoint, [object]$Prepared, [object]$Record, [object]$Payload, [bool]$IsFollowup)
    $Next = [string](Get-ReducerValue $Payload 'next_action' 'prepare_activity')
    if ($Next -notin @('clarify','repair','prepare_activity','show_transfer','show_summary','finalize_session')) { throw "Invalid next_action: $Next" }
    $Pending = $Next -in @('clarify','repair')
    if ($Pending -and (Test-ReducerTrue (Get-ReducerValue $Payload 'stage_complete' $false))) { throw 'Finish or stop the repair before completing its stage.' }
    $State = Get-ReducerValue $Record 'followup_state' $null
    if (-not $IsFollowup -and -not $Pending) { return }
    if ($null -eq $State) {
        $State = [pscustomobject]@{ history=@(); issue_ids=@(); feedback_text=''; followup_prompt=''; support_level='none'; support_kind=@(); model_exposed=$false; result='pending' }
    }
    $Feedback = [string](Get-ReducerValue $Payload 'feedback_text' '')
    $Prompt = [string](Get-ReducerValue $Payload 'followup_prompt' '')
    if ([string]::IsNullOrWhiteSpace($Feedback) -or $Feedback.Length -gt 1200) { throw 'Followup feedback_text requires 1-1200 characters.' }
    if ($Prompt.Length -gt 600 -or ($Pending -and [string]::IsNullOrWhiteSpace($Prompt))) { throw 'A pending followup requires a prompt of 1-600 characters.' }
    $Levels = @('none','light_hint','heavy_hint','model')
    $Level = [string](Get-ReducerValue $Payload 'support_level' '')
    if ($Level -notin $Levels) { throw 'Followup support_level must be none, light_hint, heavy_hint or model.' }
    $Kinds = @((Get-ReducerValue $Payload 'support_kind' @()))
    if ($Kinds.Count -gt 8 -or @($Kinds | Where-Object { ([string]$_).Length -gt 80 }).Count -gt 0) { throw 'Support kinds exceed the bounded checkpoint limit.' }
    if ($IsFollowup) {
        foreach ($Frozen in @('first_answer_excerpt','criterion_results','task_result','selected_issues','observation','review_candidates','corrections')) {
            if (($Payload -is [System.Collections.IDictionary] -and $Payload.Contains($Frozen)) -or $null -ne $Payload.PSObject.Properties[$Frozen]) { throw "A followup cannot replace first-answer field: $Frozen" }
        }
        $Answer = [string](Get-ReducerValue $Payload 'answer_excerpt' '')
        $Result = [string](Get-ReducerValue $Payload 'followup_result' '')
        if ($Answer.Length -gt 600) { throw 'Followup answer_excerpt exceeds 600 characters.' }
        if ($Result -notin @('clarified','repaired','needs_help','stopped')) { throw 'Followup requires a result: clarified, repaired, needs_help or stopped.' }
        if (@($State.history).Count -ge 12) { throw 'Activity followup limit reached.' }
        $State.history = @($State.history) + @([pscustomobject]@{
            action=$Checkpoint.waiting_action; issue_ids=@($State.issue_ids); answer_excerpt=$Answer; result=$Result
        })
        $State.result = $Result
    }
    $Ids = @((Get-ReducerValue $Payload 'followup_issue_ids' @($Record.selected_issues | ForEach-Object { $_.issue_id })))
    if ($Ids.Count -eq 0) { $Ids = @($Prepared.activity_id) }
    $AllowedIds = @($Record.selected_issues | ForEach-Object { $_.issue_id })
    if ($AllowedIds.Count -eq 0) { $AllowedIds=@($Prepared.activity_id) }
    if (@($Ids | Where-Object { $_ -notin $AllowedIds }).Count -gt 0) { throw 'Followup refers to an unknown issue.' }
    if ($Next -eq 'repair') {
        foreach ($Id in $Ids) {
            if (@($State.history | Where-Object { $_.action -eq 'repair' -and $Id -in @($_.issue_ids) }).Count -ge 2) {
                throw 'Each issue permits at most two repair attempts; stop or prepare a new transfer.'
            }
        }
    }
    if ($Pending -and @($State.history).Count -ge 12) { throw 'Close the activity after twelve followup turns.' }
    if ([array]::IndexOf($Levels,$Level) -gt [array]::IndexOf($Levels,[string]$State.support_level)) { $State.support_level=$Level }
    $State.support_kind = @(@($State.support_kind) + $Kinds | Select-Object -Unique)
    if ($State.support_kind.Count -gt 8) { throw 'Accumulated support kinds exceed eight.' }
    $State.model_exposed = $State.model_exposed -or $Level -eq 'model' -or (Test-ReducerTrue (Get-ReducerValue $Payload 'model_exposed' $false))
    $State.feedback_text=$Feedback; $State.followup_prompt=$(if ($Pending) {$Prompt} else {''}); $State.issue_ids=$Ids
    $Record | Add-Member -NotePropertyName followup_state -NotePropertyValue $State -Force
    $Prepared | Add-Member -NotePropertyName followup_state -NotePropertyValue $State -Force
    $Prepared | Add-Member -NotePropertyName first_result -NotePropertyValue ($Record | Select-Object answer_excerpt,task_result,criterion_results,selected_issues) -Force
}

function Invoke-V4SaveActivityCheckpoint {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][string]$OwnerToken,
        [Parameter(Mandatory = $true)][int]$ExpectedRevision,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey,
        [Parameter(Mandatory = $true)][object]$Payload
    )
    [void](Assert-V4Active -Context $Context)
    if ([string]::IsNullOrWhiteSpace($IdempotencyKey)) { throw 'SaveActivityCheckpoint requires -IdempotencyKey.' }
    return Invoke-WithFileLock -LockPath $Context.paths.lock -Script {
        $Timer = [Diagnostics.Stopwatch]::StartNew()
        $PayloadHash = Get-PayloadHash -Payload $Payload
        $ReplayCheckpoint = Get-V4CheckpointForReplay -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken
        $Known = Find-V4IdempotencyReceipt -Checkpoint $ReplayCheckpoint -IdempotencyKey $IdempotencyKey -PayloadHash $PayloadHash
        if ($null -ne $Known) {
            if (Test-V4Classroom $ReplayCheckpoint) { return Get-V4ClassroomResponse -Context $Context -Checkpoint $ReplayCheckpoint -Status 'saved' -Receipt $Known.receipt -Reason 'idempotent_replay' }
            return New-V4Response -Status 'saved' -NextAction ([string]$ReplayCheckpoint.waiting_action) -Receipt $Known.receipt -ReasonCode 'idempotent_replay' -PreparedStep $ReplayCheckpoint.prepared_activity
        }
        $Checkpoint = Get-V4CheckpointForWrite -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken -ExpectedRevision $ExpectedRevision
        $Prepared = $Checkpoint.prepared_activity
        if ($null -eq $Prepared -or [string]$Prepared.status -notin @('prepared','awaiting_followup')) { throw 'No prepared activity is awaiting an answer.' }
        $IsFollowup = [string]$Prepared.status -eq 'awaiting_followup'
        if ([string](Get-ReducerValue $Payload 'activity_id' '') -ne [string]$Prepared.activity_id) {
            throw 'SaveActivityCheckpoint activity_id does not match the frozen activity.'
        }
        if (-not (Test-ReducerTrue (Get-ReducerValue $Payload 'feedback_shown' $false))) {
            throw 'The learner-visible feedback must be shown before saving the activity checkpoint.'
        }
        $Observation = $null
        if ($IsFollowup) {
            if ($Checkpoint.waiting_action -notin @('repair','clarify')) { throw 'No main activity followup is expected.' }
            $Records = @($Checkpoint.activity_records | Where-Object activity_id -eq $Prepared.activity_id)
            if ($Records.Count -ne 1) { throw 'Followup requires one frozen first-answer record.' }
            $Record = $Records[0]
        } else {
        $Excerpt = [string](Get-ReducerValue $Payload 'first_answer_excerpt' '')
        if ($Excerpt.Length -gt 600) { throw 'first_answer_excerpt exceeds the 600-character privacy limit.' }
        $ContractCriteria = @($Prepared.contract.criteria)
        $SubmittedCriteria = @((Get-ReducerValue $Payload 'criterion_results' @()))
        $Merged = [System.Collections.Generic.List[object]]::new()
        foreach ($Criterion in $ContractCriteria) {
            $CriterionId = [string](Get-ReducerValue $Criterion 'criterion_id' '')
            $Result = @($SubmittedCriteria | Where-Object {
                [string](Get-ReducerValue $_ 'criterion_id' '') -eq $CriterionId
            })
            if ($Result.Count -ne 1) { throw "Missing or duplicate result for criterion $CriterionId." }
            $Merged.Add([pscustomobject]@{
                criterion_id = $CriterionId
                importance = [string](Get-ReducerValue $Criterion 'importance' '')
                result = [string](Get-ReducerValue $Result[0] 'result' '')
            })
        }
        $NotAssessable = [string](Get-ReducerValue $Payload 'task_result' '') -eq 'not_assessable'
        $Computed = Resolve-TaskResult -CriterionResults @($Merged) -NotAssessable:$NotAssessable
        if ($Computed -ne [string](Get-ReducerValue $Payload 'task_result' '')) {
            throw "task_result conflicts with the frozen criteria: expected $Computed."
        }
        $Issues = @((Get-ReducerValue $Payload 'selected_issues' @()))
        if ($Issues.Count -gt 3) { throw 'At most three feedback themes may be selected.' }
        $IssueValidation=Test-V4IssueBatch -Issues $Issues -CriterionIds @($ContractCriteria|ForEach-Object{[string]$_.criterion_id})
        if(-not$IssueValidation.valid){throw "Selected issue batch is invalid: $($IssueValidation.errors -join '; ')"}
        $FullLoops = @($Issues | Where-Object { Test-ReducerTrue (Get-ReducerValue $_ 'full_loop' $false) })
        if ($FullLoops.Count -gt 3) { throw 'At most three full teaching loops are allowed.' }
        $Complexity = 0
        foreach ($Issue in $FullLoops) { $Complexity += [int](Get-ReducerValue $Issue 'complexity_cost' 1) }
        if ($Complexity -gt 3) { throw 'Teaching-loop complexity budget exceeds three.' }
        if (@($FullLoops | Where-Object { [string](Get-ReducerValue $_ 'scope' '') -eq 'global' }).Count -gt 1) {
            throw 'At most one global teaching loop is allowed.'
        }

        $Observation = Get-ReducerValue $Payload 'observation' $null
        if ($null -ne $Observation) {
            $Observation = ConvertFrom-StableJson -Json (ConvertTo-CanonicalJson -Value $Observation)
            # Use the contract shown before the answer for evidence identity and purpose.
            foreach ($Name in @('catalog_version','competency_id','competency_family','activity_family','indicator_id','anchor_id','evidence_mode','purpose','content_id','context_id','lead_or_auxiliary')) {
                $FrozenValue=Get-ReducerValue $Prepared.contract $Name $null
                if ($null -ne $FrozenValue) { $Observation | Add-Member $Name $FrozenValue -Force }
            }
            if ($Checkpoint.plan_role -eq 'focus') { $Observation | Add-Member focus_goal_id $Checkpoint.focus_goal_id -Force }
            $ObservationId = New-StableIdentifier -Prefix 'O-' -Seed "$SessionId|$($Prepared.activity_id)" -HashLength 24
            foreach ($Pair in ([ordered]@{
                observation_id = $ObservationId
                session_id = $SessionId
                plan_item_id = [string]$Checkpoint.plan_item_id
                activity_id = [string]$Prepared.activity_id
                idempotency_key = $IdempotencyKey
                day_id = [string]$Checkpoint.study_date
                record_kind = 'observation'
                attempt_no = 1
                criterion_results_json = ConvertTo-CanonicalJson -Value @($Merged)
                task_result = $Computed
            }).GetEnumerator()) {
                $Observation | Add-Member -NotePropertyName $Pair.Key -NotePropertyValue $Pair.Value -Force
            }
            $Checkpoint.pending_activity_batch = @($Checkpoint.pending_activity_batch) + @($Observation)
        }
        $NewCandidates=@((Get-ReducerValue $Payload 'review_candidates' @())|Where-Object{$null-ne$_})
        if((@($Checkpoint.pending_candidates).Count+$NewCandidates.Count)-gt6){throw 'A session may stage at most six review candidates.'}
        foreach($CandidateInput in $NewCandidates){
            $Candidate=ConvertFrom-StableJson -Json (ConvertTo-CanonicalJson -Value $CandidateInput)
            foreach($Name in @('concept_key','item_kind','target_form','target_meaning')){
                if([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Candidate $Name ''))){throw "Review candidate requires $Name."}
            }
            $ConceptKey=[string]$Candidate.concept_key
            if(@($Checkpoint.pending_candidates|Where-Object{[string](Get-ReducerValue $_ 'concept_key' '')-eq$ConceptKey}).Count-gt0){continue}
            $Candidate|Add-Member -NotePropertyName candidate_id -NotePropertyValue (New-StableIdentifier -Prefix 'RC-' -Seed "$SessionId|$ConceptKey" -HashLength 24) -Force
            $Candidate|Add-Member -NotePropertyName idempotency_key -NotePropertyValue $IdempotencyKey -Force
            $Candidate|Add-Member -NotePropertyName source_ids_json -NotePropertyValue (Get-ReducerValue $Candidate 'source_ids' @()) -Force
            $Checkpoint.pending_candidates=@($Checkpoint.pending_candidates)+@($Candidate)
        }
        $NewCorrections=@((Get-ReducerValue $Payload 'corrections' @())|Where-Object{$null-ne$_})
        if($NewCorrections.Count-gt3-or(@($Checkpoint.pending_corrections).Count+$NewCorrections.Count)-gt6){throw 'Correction or void events exceed the bounded session limit.'}
        foreach($CorrectionInput in $NewCorrections){
            $Correction=ConvertFrom-StableJson -Json (ConvertTo-CanonicalJson -Value $CorrectionInput)
            $Kind=[string](Get-ReducerValue $Correction 'record_kind' '')
            if($Kind-notin@('correction','void')){throw 'Correction events require record_kind correction or void.'}
            if([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Correction 'ref_observation_id' ''))-or
                [string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Correction 'evidence' ''))){throw 'Correction events require ref_observation_id and a concise reason.'}
            if(@($Checkpoint.pending_activity_batch|Where-Object{[string](Get-ReducerValue $_ 'observation_id' '')-eq[string]$Correction.ref_observation_id}).Count-ne1){throw 'An in-session correction must reference one frozen observation from this session.'}
            $Correction|Add-Member -NotePropertyName observation_id -NotePropertyValue (New-StableIdentifier -Prefix 'O-COR-' -Seed "$SessionId|$IdempotencyKey|$Kind|$($Correction.ref_observation_id)" -HashLength 24) -Force
            $Correction|Add-Member -NotePropertyName idempotency_key -NotePropertyValue $IdempotencyKey -Force
            $Correction|Add-Member -NotePropertyName validity -NotePropertyValue 'valid' -Force
            $Checkpoint.pending_corrections=@($Checkpoint.pending_corrections)+@($Correction)
        }
        $Record = [pscustomobject]@{
            activity_id = $Prepared.activity_id
            stage = $Prepared.stage
            contract_hash = $Prepared.contract_hash
            answered_at = [string](Get-ReducerValue $Payload 'answered_at' (Get-V4Timestamp -Context $Context))
            answer_excerpt = $Excerpt
            task_result = $Computed
            criterion_results = @($Merged)
            selected_issues = $Issues
            full_loop_count = $FullLoops.Count
            complexity_cost = $Complexity
            lead_or_auxiliary = [string](Get-ReducerValue $Prepared.contract 'lead_or_auxiliary' 'lead')
            evidence_mode = [string](Get-ReducerValue $Prepared.contract 'evidence_mode' 'training')
            content_id = [string](Get-ReducerValue $Prepared.contract 'content_id' '')
            context_id = [string](Get-ReducerValue $Prepared.contract 'context_id' '')
            feedback_shown = $true
        }
        $Checkpoint.activity_records = @($Checkpoint.activity_records) + @($Record)
        $Checkpoint.seen_content_ids = @($Checkpoint.seen_content_ids) + @($Record.content_id) | Select-Object -Unique
        $Checkpoint.seen_context_ids = @($Checkpoint.seen_context_ids) + @($Record.context_id) | Select-Object -Unique
        }
        Update-V4ActivityFollowup -Checkpoint $Checkpoint -Prepared $Prepared -Record $Record -Payload $Payload -IsFollowup $IsFollowup
        if (Test-ReducerTrue (Get-ReducerValue $Payload 'stage_complete' $false)) {
            $Checkpoint.completed_stages = @($Checkpoint.completed_stages) + @($Prepared.stage) | Select-Object -Unique
        }
        $Prepared.status = if ([string](Get-ReducerValue $Payload 'next_action' '') -in @('repair','clarify')) { 'awaiting_followup' } else { 'answered' }
        $Prepared.first_answer_received = $true
        $Prepared.judgment_frozen = $true
        $Prepared.feedback_shown = $true
        $Checkpoint.prepared_activity = $Prepared
        $NextAction = [string](Get-ReducerValue $Payload 'next_action' 'prepare_activity')
        if ($NextAction -notin @('clarify','repair','prepare_activity','show_transfer','show_summary','finalize_session')) {
            throw "Invalid next_action: $NextAction"
        }
        $Checkpoint.waiting_action = $NextAction
        $Timer.Stop()
        $Checkpoint.performance.checkpoint_latency_ms = $Timer.ElapsedMilliseconds
        $Receipt = [pscustomobject]@{
            operation = 'SaveActivityCheckpoint'
            idempotency_key = $IdempotencyKey
            payload_hash = $PayloadHash
            activity_id = $Prepared.activity_id
            observation_id = $(if ($null -eq $Observation) { '' } else { $Observation.observation_id })
            revision = $ExpectedRevision + 1
        }
        Add-V4CheckpointReceipt -Checkpoint $Checkpoint -IdempotencyKey $IdempotencyKey -PayloadHash $PayloadHash -Receipt $Receipt
        $Saved = Save-V4Checkpoint -Context $Context -Checkpoint $Checkpoint
        if (Test-V4Classroom $Saved) { return Get-V4ClassroomResponse -Context $Context -Checkpoint $Saved -Status 'saved' -Receipt $Receipt }
        return New-V4Response -Status 'saved' -NextAction $NextAction -Receipt $Receipt -PreparedStep $Saved.prepared_activity
    }
}

function Invoke-V4StageReviewBatch {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][string]$OwnerToken,
        [Parameter(Mandatory = $true)][int]$ExpectedRevision,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey,
        [Parameter(Mandatory = $true)][object]$Payload
    )
    [void](Assert-V4Active -Context $Context)
    if ([string]::IsNullOrWhiteSpace($IdempotencyKey)) { throw 'StageReviewBatch requires -IdempotencyKey.' }
    return Invoke-WithFileLock -LockPath $Context.paths.lock -Script {
        $PayloadHash = Get-PayloadHash -Payload $Payload
        $ReplayCheckpoint = Get-V4CheckpointForReplay -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken
        $Known = Find-V4IdempotencyReceipt -Checkpoint $ReplayCheckpoint -IdempotencyKey $IdempotencyKey -PayloadHash $PayloadHash
        if ($null -ne $Known) {
            return New-V4Response -Status 'staged' -NextAction (Get-V4SessionNextAction $ReplayCheckpoint) -Receipt $Known.receipt -ReasonCode 'idempotent_replay' -PreparedStep (Get-V4SessionPreparationEnvelope -Context $Context -Checkpoint $ReplayCheckpoint)
        }
        $Checkpoint = Get-V4CheckpointForWrite -Context $Context -SessionId $SessionId -OwnerToken $OwnerToken -ExpectedRevision $ExpectedRevision
        if ([int](Get-ReducerValue $Checkpoint 'classroom_version' 0) -eq 1) { throw 'Classroom review uses SaveReviewAnswer; do not stage a duplicate batch.' }
        if (-not (Test-ReducerTrue (Get-ReducerValue $Payload 'feedback_shown' $false))) {
            throw 'Review feedback must be shown before a review batch is staged.'
        }
        $Items = @((Get-ReducerValue $Payload 'items' @()))
        $RecoveryMode = [bool]$Checkpoint.review_state.recovery_mode
        $Limit = if ($RecoveryMode) { 10 } else { 6 }
        $Capacity = if ($RecoveryMode) { 20 } else { 12 }
        if ($Items.Count -lt 1 -or $Items.Count -gt $Limit) {
            throw "A review batch must contain between 1 and $Limit displayed items."
        }
        $SelectedIds = @($Checkpoint.review_state.selected | ForEach-Object {
            [string](Get-ReducerValue $_ 'review_item_id' '')
        })
        $Weight = 0
        $FrozenItems = [System.Collections.Generic.List[object]]::new()
        $BatchId = New-StableIdentifier -Prefix 'RB-' -Seed "$SessionId|$IdempotencyKey" -HashLength 24
        foreach ($Item in $Items) {
            $ReviewItemId = [string](Get-ReducerValue $Item 'review_item_id' '')
            if ([string]::IsNullOrWhiteSpace($ReviewItemId)) { throw 'Each review result requires review_item_id.' }
            if ($SelectedIds.Count -gt 0 -and $ReviewItemId -notin $SelectedIds) {
                throw "Review item $ReviewItemId was not in the frozen due slice."
            }
            $Rating = [string](Get-ReducerValue $Item 'rating' '')
            if ($Rating -notin @('again','hard','good','easy','invalid')) { throw "Invalid review rating: $Rating" }
            $Stage = [string](Get-ReducerValue $Item 'recipe_stage' '')
            $ItemWeight = Get-ReviewWeight -RecipeStage $Stage
            $Weight += $ItemWeight
            $QuestionId = [string](Get-ReducerValue $Item 'question_instance_id' '')
            if ([string]::IsNullOrWhiteSpace($QuestionId)) {
                throw 'A displayed review question requires its frozen question_instance_id.'
            }
            $ReviewContract = Get-ReducerValue $Item 'task_contract' $null
            if ($null -eq $ReviewContract) { throw 'A displayed review question requires its frozen task_contract.' }
            $ReviewValidation = Test-V4ReviewQuestionContract -Item $Item -Contract $ReviewContract
            if (-not $ReviewValidation.valid) { throw "Review question contract is invalid: $($ReviewValidation.errors -join '; ')" }
            if ($Rating -eq 'easy' -and $Stage -ne 'constrained_transfer') {
                throw 'easy is only allowed for constrained_transfer.'
            }
            if ([string](Get-ReducerValue $Item 'lane' '') -eq 'legacy' -and $Rating -eq 'easy') {
                throw 'Legacy positioning does not allow easy.'
            }
            $Prompt = [string](Get-ReducerValue $Item 'prompt_text' '')
            $Answer = [string](Get-ReducerValue $Item 'answer_excerpt' '')
            if ($Prompt.Length -gt 1200 -or $Answer.Length -gt 600) {
                throw 'Review audit excerpt exceeds the privacy size limit.'
            }
            $EventId = New-StableIdentifier -Prefix 'R-' -Seed "$BatchId|$ReviewItemId|event" -HashLength 24
            $AuditId = New-StableIdentifier -Prefix 'RA-' -Seed "$BatchId|$ReviewItemId|audit" -HashLength 24
            $FrozenItems.Add([pscustomobject]@{
                review_item_id = $ReviewItemId
                question_instance_id = $QuestionId
                event_id = $EventId
                audit_id = $AuditId
                recipe_stage = $Stage
                lane = [string](Get-ReducerValue $Item 'lane' '')
                weight = $ItemWeight
                prompt_text = $Prompt
                task_contract = $ReviewContract
                answer_excerpt = $Answer
                answered_at = [string](Get-ReducerValue $Item 'answered_at' (Get-V4Timestamp -Context $Context))
                language_validity = [string](Get-ReducerValue $Item 'language_validity' '')
                target_demonstrated = [string](Get-ReducerValue $Item 'target_demonstrated' '')
                rating = $Rating
                rating_reason = [string](Get-ReducerValue $Item 'rating_reason' '')
                invalid_reason = [string](Get-ReducerValue $Item 'invalid_reason' '')
                repair_result = Get-ReducerValue $Item 'repair_result' ([pscustomobject]@{})
                exposed = [bool](Get-ReducerValue $Item 'exposed' $false)
                model_exposed = [bool](Get-ReducerValue $Item 'model_exposed' $false)
                pre_state = Get-ReducerValue $Item 'pre_state' $null
            })
        }
        if ($Weight -gt $Capacity) { throw "Review batch exceeds capacity weight $Capacity." }
        $Batch = [pscustomobject]@{
            batch_id = $BatchId
            idempotency_key = $IdempotencyKey
            payload_hash = $PayloadHash
            study_date = [string]$Checkpoint.study_date
            session_id = $SessionId
            source_session_outcome = 'pending'
            feedback_shown = $true
            total_weight = $Weight
            items = @($FrozenItems)
        }
        $Checkpoint.pending_review_batches = @($Checkpoint.pending_review_batches) + @($Batch)
        if (Test-ReducerTrue (Get-ReducerValue $Payload 'stage_complete' $false)) {
            $Checkpoint.completed_stages = @($Checkpoint.completed_stages) + @('review') | Select-Object -Unique
        }
        $NextAction = [string](Get-ReducerValue $Payload 'next_action' 'prepare_activity')
        if ($NextAction -notin @('prepare_activity','show_summary','finalize_session','select_next_review_batch')) {
            throw "Invalid next_action: $NextAction"
        }
        $Checkpoint.waiting_action = $NextAction
        $Receipt = [pscustomobject]@{
            operation = 'StageReviewBatch'
            idempotency_key = $IdempotencyKey
            payload_hash = $PayloadHash
            batch_id = $BatchId
            item_count = $Items.Count
            revision = $ExpectedRevision + 1
        }
        Add-V4CheckpointReceipt -Checkpoint $Checkpoint -IdempotencyKey $IdempotencyKey -PayloadHash $PayloadHash -Receipt $Receipt
        [void](Save-V4Checkpoint -Context $Context -Checkpoint $Checkpoint)
        return New-V4Response -Status 'staged' -NextAction (Get-V4SessionNextAction $Checkpoint) -Receipt $Receipt -PreparedStep (Get-V4SessionPreparationEnvelope -Context $Context -Checkpoint $Checkpoint)
    }
}
