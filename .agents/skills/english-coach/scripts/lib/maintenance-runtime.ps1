Set-StrictMode -Version Latest

function Get-V4RawTsvRows {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    return @(Import-Csv -LiteralPath $Path -Delimiter "`t" -Encoding UTF8)
}

function Test-V4FallbackManifest {
    param([Parameter(Mandatory = $true)][object]$Context)
    $ManifestPath = Join-Path $Context.root '.agents\skills\english-coach\assets\fallback\manifest.json'
    $Errors = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        $Errors.Add('fallback_manifest_missing')
        return [pscustomobject]@{ valid = $false; errors = @($Errors); item_count = 0 }
    }
    try { $Manifest = Read-StableJsonFile -Path $ManifestPath }
    catch {
        $Errors.Add('fallback_manifest_invalid_json')
        return [pscustomobject]@{ valid = $false; errors = @($Errors); item_count = 0 }
    }
    $Items = @((Get-ReducerValue $Manifest 'items' @()))
    if ($Items.Count -lt 1) { $Errors.Add('fallback_manifest_empty') }
    $Root = Split-Path -Parent $ManifestPath
    foreach ($Item in $Items) {
        $ContentId = [string](Get-ReducerValue $Item 'content_id' 'unknown')
        if (-not (Test-ReducerTrue (Get-ReducerValue $Item 'presentable' $false))) {
            $Errors.Add("fallback_not_presentable:$ContentId")
        }
        if ([string](Get-ReducerValue $Item 'rights_status' '') -notin @('project_original','licensed','public_domain')) {
            $Errors.Add("fallback_rights_unverified:$ContentId")
        }
        foreach ($Pair in @(
            [pscustomobject]@{ path = [string](Get-ReducerValue $Item 'transcript_path' ''); hash = [string](Get-ReducerValue $Item 'transcript_sha256' ''); kind = 'transcript' },
            [pscustomobject]@{ path = [string](Get-ReducerValue $Item 'audio_path' ''); hash = [string](Get-ReducerValue $Item 'audio_sha256' ''); kind = 'audio' }
        )) {
            if ([string]::IsNullOrWhiteSpace($Pair.path) -or [string]::IsNullOrWhiteSpace($Pair.hash)) {
                $Errors.Add("fallback_$($Pair.kind)_unverified:$ContentId")
                continue
            }
            $AssetPath = Join-Path $Root $Pair.path.Replace('/', '\')
            if (-not (Test-Path -LiteralPath $AssetPath -PathType Leaf)) {
                $Errors.Add("fallback_$($Pair.kind)_missing:$ContentId")
            }
            elseif ((Get-FileSha256 -Path $AssetPath) -ne $Pair.hash.ToUpperInvariant()) {
                $Errors.Add("fallback_$($Pair.kind)_hash_mismatch:$ContentId")
            }
        }
    }
    return [pscustomobject]@{ valid = $Errors.Count -eq 0; errors = @($Errors); item_count = $Items.Count }
}

function Get-V4MigrationPlan {
    param([Parameter(Mandatory = $true)][object]$Context)
    $Blockers = [System.Collections.Generic.List[string]]::new()
    $Warnings = [System.Collections.Generic.List[string]]::new()
    $Plans = @(Get-V4RawTsvRows -Path $Context.paths.plans)
    $BoundaryRows = @($Plans | Where-Object { [string]$_.plan_id -eq 'C0003' })
    if ($BoundaryRows.Count -eq 0) { $Blockers.Add('boundary_cycle_C0003_missing') }
    else {
        $Open = @($BoundaryRows | Where-Object { [string]$_.status -notin @('completed','cancelled') })
        if ($Open.Count -gt 0) { $Blockers.Add('boundary_cycle_C0003_not_terminal') }
        $Review = @($BoundaryRows | Where-Object { [string]$_.session_type -eq 'review' })
        if ($Review.Count -ne 1 -or [string]$Review[0].status -ne 'completed') {
            $Blockers.Add('boundary_cycle_C0003_review_not_completed')
        }
    }
    $Checkpoint = Read-DurableJson -Path $Context.paths.current_session -AllowMissing
    if ($null -ne $Checkpoint -and $Checkpoint.status -eq 'valid' -and
        [string](Get-ReducerValue $Checkpoint.value 'status' '') -eq 'in_progress') {
        $Blockers.Add('active_session_must_finish_under_v3')
    }
    $LegacyTransactionPath = Join-Path $Context.root '.state\review-transaction.json'
    if (Test-Path -LiteralPath $LegacyTransactionPath -PathType Leaf) {
        try {
            $LegacyTransaction = Read-StableJsonFile -Path $LegacyTransactionPath
            if ([string](Get-ReducerValue $LegacyTransaction 'phase' 'completed') -notin @('completed','committed')) {
                $Blockers.Add('legacy_review_transaction_pending')
            }
        }
        catch { $Blockers.Add('legacy_review_transaction_invalid') }
    }
    foreach ($Relative in @(
        '.agents\skills\english-coach\references\competency-catalog.json',
        '.agents\skills\english-coach\references\difficulty-ladders.json',
        '.agents\skills\english-coach\references\migration-v4.schema.json'
    )) {
        $Path = Join-Path $Context.root $Relative
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { $Blockers.Add("required_resource_missing:$Relative") }
        else {
            try { [void](Read-StableJsonFile -Path $Path) }
            catch { $Blockers.Add("required_resource_invalid:$Relative") }
        }
    }
    $Fallback = Test-V4FallbackManifest -Context $Context
    foreach ($ErrorCode in @($Fallback.errors)) { $Blockers.Add([string]$ErrorCode) }
    if (-not (Test-Path -LiteralPath (Join-Path $Context.root 'tests\tracker-v4.Tests.ps1') -PathType Leaf)) {
        $Blockers.Add('v4_fault_and_reducer_tests_missing')
    }
    $Runtime = Get-V4Runtime -Context $Context
    if ([int](Get-ReducerValue $Runtime 'runtime_version' 0) -eq 4 -and
        [string](Get-ReducerValue $Runtime 'status' '') -eq 'active') {
        $Warnings.Add('runtime_v4_already_active')
    }
    $Receipt = [pscustomobject]@{
        operation = 'migration_plan'
        from_runtime = 3
        to_runtime = 4
        boundary_from_cycle = 'C0003'
        boundary_to_cycle = 'C0004'
        checked_at = Get-V4Timestamp -Context $Context
        blocker_count = $Blockers.Count
    }
    $Prepared = [pscustomobject]@{
        ready_for_confirmation = $Blockers.Count -eq 0
        requires_explicit_user_confirmation = $true
        blockers = @($Blockers)
        warnings = @($Warnings)
        fallback_item_count = [int]$Fallback.item_count
        migration_rule = 'C0003 remains v3; runtime pointer is written last only after a verified C0004 activation.'
    }
    $CurrentRuntimeVersion = if ([int](Get-ReducerValue $Runtime 'runtime_version' 0) -eq 4) { 4 } else { 3 }
    return New-V4Response -Status $(if ($Blockers.Count -eq 0) { 'ready' } else { 'blocked' }) `
        -NextAction $(if ($Blockers.Count -eq 0) { 'request_c0004_confirmation' } else { 'finish_blockers_under_v3' }) `
        -Receipt $Receipt -ReasonCode $(if ($Blockers.Count -eq 0) { 'migration_gates_ready' } else { 'migration_gates_blocked' }) `
        -PreparedStep $Prepared -RuntimeVersion $CurrentRuntimeVersion `
        -ProtocolRefs @($(if ($CurrentRuntimeVersion -eq 4) { 'references/runtime-protocol-v4.md' } else { 'references/runtime-protocol-v3.md' }))
}

function Test-V4Table {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Headers,
        [Parameter(Mandatory = $true)][string]$IdColumn,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[string]]$Errors
    )
    try { $Rows = @(Get-TsvRows -Path $Path -Headers $Headers) }
    catch { $Errors.Add($_.Exception.Message); return }
    $Ids = @($Rows | ForEach-Object { [string]$_.$IdColumn } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (@($Ids | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
        $Errors.Add("Duplicate $IdColumn in $Path")
    }
}

function Invoke-V4Validation {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [switch]$PreActivation
    )
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($Spec in @(
        @($Context.paths.plans,$script:V4PlanHeaders,'plan_item_id'),
        @($Context.paths.evidence,$script:V4EvidenceHeaders,'evidence_id'),
        @($Context.paths.review_items,$script:V4ReviewItemHeaders,'review_item_id'),
        @($Context.paths.review_sources,$script:V4ReviewSourceHeaders,'source_link_id'),
        @($Context.paths.review_candidates,$script:V4ReviewCandidateHeaders,'candidate_id'),
        @($Context.paths.review_history,$script:V4ReviewHistoryHeaders,'event_id'),
        @($Context.paths.review_audit,$script:V4ReviewAuditHeaders,'audit_id'),
        @($Context.paths.focus_goals,$script:V4FocusGoalHeaders,'goal_id'),
        @($Context.paths.goal_events,$script:V4GoalEventHeaders,'event_id'),
        @($Context.paths.competency_status,$script:V4CompetencyStatusHeaders,'competency_id'),
        @($Context.paths.competency_events,$script:V4CompetencyEventHeaders,'event_id'),
        @($Context.paths.stage_events,$script:V4StageEventHeaders,'event_id'),
        @($Context.paths.insights,$script:V4InsightHeaders,'insight_id')
    )) { Test-V4Table -Path $Spec[0] -Headers $Spec[1] -IdColumn $Spec[2] -Errors $Errors }
    $Plans = @(Get-V4RawTsvRows -Path $Context.paths.plans)
    foreach ($Plan in @($Plans | Where-Object { [string]$_.plan_id -ge 'C0004' })) {
        try {
            [void]@(Get-V4RequiredStages -SessionType ([string]$Plan.session_type) `
                -PrimarySkill ([string]$Plan.primary_skill) -PlanRole ([string]$Plan.plan_role))
        }
        catch { $Errors.Add("plan_stage_contract:$([string]$Plan.plan_item_id):$($_.Exception.Message)") }
    }
    $Index = Get-V4BootstrapIndex -Context $Context
    if ($Index.status -ne 'valid') { $Errors.Add("bootstrap_index:$($Index.reason_code)") }
    else {
        if((Resolve-V4Package -Context $Context -Index $Index.value).status-ne'ready'){$Errors.Add('bootstrap_package_unavailable')}
        foreach ($Descriptor in @((Get-ReducerValue $Index.value 'next_package_descriptors' @()) | Where-Object { $null -ne $_ })) {
            foreach ($Pair in @(
                [pscustomobject]@{ path=[string](Get-ReducerValue $Descriptor 'package_path' ''); hash=[string](Get-ReducerValue $Descriptor 'package_hash' ''); kind='main' },
                [pscustomobject]@{ path=[string](Get-ReducerValue $Descriptor 'fallback_package_path' ''); hash=[string](Get-ReducerValue $Descriptor 'fallback_package_hash' ''); kind='fallback' }
            )) {
                if ([string]::IsNullOrWhiteSpace($Pair.path)) { continue }
                $FullPath = Join-Path $Context.root $Pair.path.Replace('/', '\')
                if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf) -or (Get-FileSha256 -Path $FullPath) -ne $Pair.hash) {
                    $Errors.Add("package_descriptor_invalid:$([string]$Descriptor.plan_item_id):$($Pair.kind)")
                    continue
                }
                $PackageRead = Read-DurableJson -Path $FullPath -AllowMissing
                if ($null -eq $PackageRead -or $PackageRead.status -ne 'valid') {
                    $Errors.Add("package_integrity_invalid:$([string]$Descriptor.plan_item_id):$($Pair.kind)")
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace([string](Get-ReducerValue $PackageRead.value 'blueprint_path' ''))) {
                    $Core = Get-V4CoreBlueprint -Context $Context -Package $PackageRead.value
                    if ([string]$Core.status -ne 'ready') {
                        $Errors.Add("package_core_invalid:$([string]$Descriptor.plan_item_id):$($Pair.kind):$([string]$Core.status)")
                    }
                }
            }
        }
    }
    $Current = Get-V4CurrentSession -Context $Context
    if ($null -ne $Current -and $Current.status -ne 'valid') { $Errors.Add('current_session_integrity_invalid') }
    if(-not$PreActivation){
        try{$Settings=Read-StableJsonFile -Path $Context.paths.settings}catch{$Settings=$null;$Errors.Add('settings_invalid_json')}
        $RuntimeRead=Read-DurableJson -Path $Context.paths.runtime -AllowMissing
        $MigrationRead=Read-DurableJson -Path $Context.paths.migration -AllowMissing
        if($null-eq$Settings-or[int](Get-ReducerValue $Settings 'schema_version' 0)-ne4-or
            [int](Get-ReducerValue $Settings 'runtime_protocol_version' 0)-ne4-or
            [string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Settings 'activation_id' ''))){$Errors.Add('settings_v4_activation_invalid')}
        if($null-eq$RuntimeRead-or$RuntimeRead.status-ne'valid'-or[int](Get-ReducerValue $RuntimeRead.value 'runtime_version' 0)-ne4-or
            [string](Get-ReducerValue $RuntimeRead.value 'status' '')-ne'active'){$Errors.Add('runtime_v4_activation_invalid')}
        if($null-eq$MigrationRead-or$MigrationRead.status-ne'valid'-or[string](Get-ReducerValue $MigrationRead.value 'phase' '')-ne'committed'-or
            [string](Get-ReducerValue $MigrationRead.value 'status' '')-ne'committed'){$Errors.Add('migration_receipt_not_committed')}
        if($null-ne$Settings-and$null-ne$RuntimeRead-and$RuntimeRead.status-eq'valid'-and
            [string](Get-ReducerValue $Settings 'activation_id' '')-ne[string](Get-ReducerValue $RuntimeRead.value 'migration_id' '')){$Errors.Add('settings_runtime_activation_mismatch')}
        if($null-ne$MigrationRead-and$MigrationRead.status-eq'valid'-and$null-ne$RuntimeRead-and$RuntimeRead.status-eq'valid'-and
            [string](Get-ReducerValue $MigrationRead.value 'migration_id' '')-ne[string](Get-ReducerValue $RuntimeRead.value 'migration_id' '')){$Errors.Add('runtime_migration_receipt_mismatch')}
    }
    $Fallback = Test-V4FallbackManifest -Context $Context
    foreach ($Code in @($Fallback.errors)) { $Warnings.Add([string]$Code) }
    return [pscustomobject]@{
        status = $(if ($Errors.Count -eq 0) { 'valid' } else { 'invalid' })
        error_count = $Errors.Count
        warning_count = $Warnings.Count
        errors = @($Errors)
        warnings = @($Warnings)
    }
}
