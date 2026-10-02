Set-StrictMode -Version Latest

function ConvertTo-V4Row {
    param(
        [Parameter(Mandatory = $true)][object]$Source,
        [Parameter(Mandatory = $true)][string[]]$Headers
    )
    $Values = [ordered]@{}
    foreach ($Header in $Headers) {
        $Property = $Source.PSObject.Properties[$Header]
        $Values[$Header] = if ($null -eq $Property) { '' } else { [string]$Property.Value }
    }
    return [pscustomobject]$Values
}

function Get-V4MigrationSnapshotEntries {
    param([Parameter(Mandatory = $true)][object]$Context)
    $Entries=[System.Collections.Generic.List[object]]::new()
    foreach($Area in @(
        [pscustomobject]@{relative='learner';classification='formal_fact'},
        [pscustomobject]@{relative='sessions';classification='formal_fact'},
        [pscustomobject]@{relative='.state';classification='pending_state'}
    )){
        $AreaPath=Join-Path $Context.root $Area.relative
        if(-not(Test-Path -LiteralPath $AreaPath -PathType Container)){continue}
        foreach($File in @(Get-ChildItem -LiteralPath $AreaPath -Recurse -File|Sort-Object FullName)){
            if([string]$File.FullName-eq[string]$Context.paths.lock){continue}
            $Relative=[IO.Path]::GetRelativePath($Context.root,$File.FullName).Replace('\','/')
            if($Relative -match '^\.state/migration-snapshots(?:/|$)' -or
                $Relative -in @('.state/migration-v4-transaction.json','.state/migration-v4-transaction.json.previous','.state/tracker.lock') -or
                $Relative -match '\.tmp$'){continue}
            $Classification=[string]$Area.classification
            if($Relative -eq 'learner/settings.json'){$Classification='configuration'}
            elseif($Relative -in @('learner/dashboard.md','learner/current-plan.md') -or $Relative -match '^learner/(?:adaptation-state|long-term-projection)\.json$'){$Classification='projection'}
            $Entries.Add([pscustomobject]@{relative_path=$Relative;sha256=Get-FileSha256 -Path $File.FullName;length=$File.Length;classification=$Classification})
        }
    }
    return @($Entries)
}

function New-V4ActivatedSettings {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Transaction
    )
    $Current=Read-StableJsonFile -Path $Context.paths.settings
    $Values=[ordered]@{}
    foreach($Property in $Current.PSObject.Properties){$Values[$Property.Name]=$Property.Value}
    $Values.schema_version=4
    $Values.runtime_protocol_version=4
    $Values.activation_id=[string]$Transaction.migration_id
    $Values.catalog_version='1.0.0'
    $Values.ladder_version='1.0.0'
    $Values.contract_version='4.0.0'
    $Values.review_schema_version='4.0.0'
    return [pscustomobject]$Values
}

function Assert-V4RecoverableMigration {
    param([Parameter(Mandatory = $true)][object]$Transaction)
    $Phase=[string](Get-ReducerValue $Transaction 'phase' '')
    if([int](Get-ReducerValue $Transaction 'schema_version' 0)-ne4-or
        [string](Get-ReducerValue $Transaction 'operation' '')-ne'ActivateV4'-or
        [string](Get-ReducerValue $Transaction 'from_cycle_id' '')-ne'C0003'-or
        [string](Get-ReducerValue $Transaction 'to_cycle_id' '')-ne'C0004'-or
        $Phase-notin@('intent','snapshot_verified','packages_written','schema_written','projections_written','index_written','settings_written','runtime_switched')){
        throw 'Pending migration transaction is not a recoverable C0003-to-C0004 activation.'
    }
    foreach($Name in @('migration_id','idempotency_key','payload_hash','snapshot_relative_path')){
        if([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Transaction $Name ''))){throw "Pending migration transaction is missing $Name."}
    }
    if([string](Get-ReducerValue $Transaction 'payload_hash' '')-notmatch'^[a-f0-9]{64}$'){throw 'Pending migration payload hash is invalid.'}
    return $true
}

function New-V4LegacyReviewData {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$Timestamp
    )
    $Items = [System.Collections.Generic.List[object]]::new()
    $Sources = [System.Collections.Generic.List[object]]::new()
    $Definitions = @(
        [pscustomobject]@{ path=Join-Path $Context.root 'learner\vocabulary.tsv'; kind='vocabulary'; id='id'; form='item'; meaning='meaning'; context='context'; confusion='' },
        [pscustomobject]@{ path=Join-Path $Context.root 'learner\error-log.tsv'; kind='error'; id='id'; form='corrected'; meaning='explanation'; context='corrected'; confusion='original' }
    )
    foreach ($Definition in $Definitions) {
        foreach ($Row in @(Get-V4RawTsvRows -Path $Definition.path)) {
            $LegacyId = [string]$Row.($Definition.id)
            if ([string]::IsNullOrWhiteSpace($LegacyId)) { continue }
            $ReviewId = New-StableIdentifier -Prefix 'RI-LEG-' -Seed "$($Definition.kind)|$LegacyId" -HashLength 20
            $Confusions = @()
            if (-not [string]::IsNullOrWhiteSpace($Definition.confusion)) {
                $Value = [string]$Row.($Definition.confusion)
                if (-not [string]::IsNullOrWhiteSpace($Value)) { $Confusions = @($Value) }
            }
            $ContextSeeds = @()
            $ContextValue = [string]$Row.($Definition.context)
            if (-not [string]::IsNullOrWhiteSpace($ContextValue)) { $ContextSeeds = @($ContextValue) }
            $LegacyStatus = [string]$Row.status
            $Items.Add([pscustomobject]@{
                review_item_id=$ReviewId; concept_id="$($Definition.kind):$LegacyId"; target_version='1';
                target_form=[string]$Row.($Definition.form); target_meaning=[string]$Row.($Definition.meaning);
                review_family=$(if($Definition.kind -eq 'vocabulary'){'lexical'}else{'corrective'});
                target_scope=$(if($Definition.kind -eq 'vocabulary'){'stored lexical meaning and use'}else{'stored corrected form and explanation'});
                allowed_variants_json='[]'; known_confusions_json=ConvertTo-CanonicalJson -Value $Confusions;
                context_seeds_json=ConvertTo-CanonicalJson -Value $ContextSeeds; recipe_stage='recall'; strength_level='0';
                status=$(if($LegacyStatus -eq 'active'){'legacy_unverified'}else{'inactive'});
                next_review=[string]$Row.next_review; recheck_due=''; maintenance_interval_days='';
                legacy_level=[string]$Row.level; legacy_due=[string]$Row.next_review; last_review=[string]$Row.last_review;
                maintenance_ready='false'; created_at=$Timestamp; updated_at=$Timestamp
            })
            $Sources.Add([pscustomobject]@{
                source_link_id=New-StableIdentifier -Prefix 'RSL-' -Seed "$ReviewId|$LegacyId" -HashLength 20;
                review_item_id=$ReviewId; source_type="legacy_$($Definition.kind)"; source_id=$LegacyId;
                relation='migrated_without_evidence_backfill'; source_session_id=[string]$Row.source_session; linked_at=$Timestamp
            })
        }
    }
    return [pscustomobject]@{ items=@($Items); sources=@($Sources) }
}

function New-V4InitialCompetencyRows {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$Timestamp
    )
    $CatalogPath = Join-Path $Context.root '.agents\skills\english-coach\references\competency-catalog.json'
    $Catalog = Read-StableJsonFile -Path $CatalogPath
    return @((Get-ReducerValue $Catalog 'gates' @()) | ForEach-Object {
        [pscustomobject]@{
            competency_id=[string](Get-ReducerValue $_ 'gate_id' ''); family_id=[string](Get-ReducerValue $_ 'family_id' '');
            stage_id=[string](Get-ReducerValue $_ 'stage_id' ''); skill=[string](Get-ReducerValue $_ 'skill' '');
            level=[string](Get-ReducerValue $_ 'level' ''); role=(@((Get-ReducerValue $_ 'evidence_roles' @())) -join ',');
            status='not_evidenced'; decisive_event_ids_json='[]'; evidence_ids_json='[]'; flags_json='[]';
            catalog_version=[string]$Catalog.catalog_version; projection_revision='1'; updated_at=$Timestamp
        }
    })
}

function Test-V4ActivationPayload {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey,
        [switch]$Confirmed
    )
    $Errors = [System.Collections.Generic.List[string]]::new()
    if (-not $Confirmed) { $Errors.Add('explicit_activation_switch_missing') }
    if (-not (Test-ReducerTrue (Get-ReducerValue $Payload 'user_confirmed' $false)) -or
        [string](Get-ReducerValue $Payload 'from_cycle_id' '') -ne 'C0003' -or
        [string](Get-ReducerValue $Payload 'to_cycle_id' '') -ne 'C0004') {
        $Errors.Add('c0003_to_c0004_confirmation_invalid')
    }
    $PlanItems = @((Get-ReducerValue $Payload 'plan_items' @()) | Where-Object { $null -ne $_ })
    if ($PlanItems.Count -ne 7) { $Errors.Add('c0004_requires_six_training_items_and_one_cycle_review') }
    if (@($PlanItems | Where-Object { [string](Get-ReducerValue $_ 'plan_id' '') -ne 'C0004' }).Count -gt 0) {
        $Errors.Add('activation_plan_must_be_C0004')
    }
    if (@($PlanItems | Group-Object { [string](Get-ReducerValue $_ 'plan_item_id' '') } | Where-Object Count -gt 1).Count -gt 0) {
        $Errors.Add('activation_plan_item_ids_not_unique')
    }
    $Manifest=Get-ReducerValue $Payload 'migration_manifest' $null
    if($null-eq$Manifest){$Errors.Add('migration_schema_manifest_missing')}
    else{
        $SchemaPath=Join-Path $Context.root '.agents\skills\english-coach\references\migration-v4.schema.json'
        if(-not(Test-Path -LiteralPath $SchemaPath -PathType Leaf)-or$null-eq(Get-Command Test-Json -ErrorAction SilentlyContinue)){$Errors.Add('migration_schema_validator_unavailable')}
        else{
            try{if(-not(Test-Json -Json (ConvertTo-CanonicalJson -Value $Manifest) -SchemaFile $SchemaPath -ErrorAction Stop)){$Errors.Add('migration_schema_manifest_invalid')}}
            catch{$Errors.Add('migration_schema_manifest_invalid')}
        }
        $ExpectedMigrationId=New-StableIdentifier -Prefix 'M4-' -Seed "$IdempotencyKey|C0003|C0004" -HashLength 24
        if([string](Get-ReducerValue $Manifest 'migration_id' '')-ne$ExpectedMigrationId-or
            [string](Get-ReducerValue $Manifest 'idempotency_key' '')-ne$IdempotencyKey){$Errors.Add('migration_manifest_identity_mismatch')}
        $Boundary=Get-ReducerValue $Manifest 'boundary' $null
        $ExpectedHead=@($PlanItems|Sort-Object{[int](Get-ReducerValue $_ 'sequence' 999)}|Select-Object -First 1)
        if($null-eq$Boundary-or$ExpectedHead.Count-ne1-or
            [string](Get-ReducerValue $Boundary 'source_cycle_id' '')-ne'C0003'-or
            [string](Get-ReducerValue $Boundary 'target_cycle_id' '')-ne'C0004'-or
            [string](Get-ReducerValue $Boundary 'expected_queue_head_plan_item_id' '')-ne[string](Get-ReducerValue $ExpectedHead[0] 'plan_item_id' '')){$Errors.Add('migration_manifest_boundary_mismatch')}
        if([string](Get-ReducerValue (Get-ReducerValue $Manifest 'activation' $null) 'status' '')-ne'ready'){$Errors.Add('migration_manifest_not_ready')}
    }
    $Reviews = @($PlanItems | Where-Object {
        [string](Get-ReducerValue $_ 'plan_role' '') -eq 'cycle_review' -or [string](Get-ReducerValue $_ 'session_type' '') -eq 'review'
    })
    if ($Reviews.Count -ne 1 -or [string](Get-ReducerValue $Reviews[0] 'plan_role' '') -ne 'cycle_review') {
        $Errors.Add('activation_plan_requires_one_terminal_cycle_review')
    }
    try {
        $Allocation = Test-CycleAllocation -PlanItems $PlanItems -FocusSkill ([string](Get-ReducerValue $Payload 'focus_skill' '')) `
            -PreviousCycleLeadSkills @((Get-ReducerValue $Payload 'previous_cycle_lead_skills' @()))
        foreach ($ErrorText in @($Allocation.errors)) { $Errors.Add("cycle_allocation:$ErrorText") }
    }
    catch { $Errors.Add("cycle_allocation_invalid:$($_.Exception.Message)") }
    $Packages = @((Get-ReducerValue $Payload 'packages' @()) | Where-Object { $null -ne $_ })
    if ($Packages.Count -ne $PlanItems.Count) { $Errors.Add('one_ready_package_per_plan_item_required') }
    foreach ($Package in $Packages) {
        $PlanItemId = [string](Get-ReducerValue $Package 'plan_item_id' '')
        $MatchingPlan=@($PlanItems | Where-Object { [string](Get-ReducerValue $_ 'plan_item_id' '') -eq $PlanItemId })
        if ($MatchingPlan.Count -ne 1) {
            $Errors.Add("package_plan_item_unknown:$PlanItemId")
        }
        elseif([string](Get-ReducerValue $Package 'plan_id' '')-ne'C0004' -or
            [string](Get-ReducerValue $Package 'plan_role' '')-ne[string](Get-ReducerValue $MatchingPlan[0] 'plan_role' '') -or
            [string](Get-ReducerValue $Package 'primary_skill' '')-ne[string](Get-ReducerValue $MatchingPlan[0] 'primary_skill' '') -or
            [string](Get-ReducerValue $Package 'focus_goal_id' '')-ne[string](Get-ReducerValue $MatchingPlan[0] 'focus_goal_id' '')){
            $Errors.Add("package_identity_mismatch:$PlanItemId")
        }
        if ([string](Get-ReducerValue $Package 'status' '') -ne 'ready') { $Errors.Add("package_not_ready:$PlanItemId") }
        foreach($VersionPair in @(
            [pscustomobject]@{name='policy_version';expected='4.0.0'},
            [pscustomobject]@{name='catalog_version';expected='1.0.0'},
            [pscustomobject]@{name='ladder_version';expected='1.0.0'},
            [pscustomobject]@{name='contract_version';expected='4.0.0'}
        )){if([string](Get-ReducerValue $Package $VersionPair.name '')-ne$VersionPair.expected){$Errors.Add("package_$($VersionPair.name)_invalid:$PlanItemId")}}
        if ([string](Get-ReducerValue $Package 'rights_status' '') -notin @('project_original','licensed','public_domain','not_applicable')) {
            $Errors.Add("package_rights_unverified:$PlanItemId")
        }
        $Activities = @((Get-ReducerValue $Package 'activity_skeletons' @()) | Where-Object { $null -ne $_ })
        if ($Activities.Count -lt 1 -or $Activities.Count -gt 3) { $Errors.Add("package_activity_count_invalid:$PlanItemId") }
        $Probe = @((Get-ReducerValue $Package 'preauthorized_probe_candidates' @()) | Where-Object { $null -ne $_ })
        if ($Probe.Count -gt 1) { $Errors.Add("package_has_multiple_probe_candidates:$PlanItemId") }
        foreach ($Activity in $Activities) {
            foreach ($Name in @('competency_id','competency_family','activity_family','indicator_id','anchor_id','template_id','max_evidence_mode')) {
                if ([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Activity $Name ''))) {
                    $Errors.Add("package_activity_missing_$Name`:$PlanItemId")
                }
            }
        }
        $FallbackActivities=@((Get-ReducerValue $Package 'fallback_activity_skeletons' @())|Where-Object{$null-ne$_})
        if($FallbackActivities.Count-lt1-or$FallbackActivities.Count-gt3){$Errors.Add("package_fallback_activity_count_invalid:$PlanItemId")}
        foreach($Activity in $FallbackActivities){
            foreach($Name in @('competency_id','competency_family','activity_family','indicator_id','anchor_id','template_id','max_evidence_mode')){
                if([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Activity $Name ''))){$Errors.Add("package_fallback_activity_missing_$Name`:$PlanItemId")}
            }
        }
    }
    if(@($Packages|Group-Object{[string](Get-ReducerValue $_ 'plan_item_id' '')}|Where-Object Count -gt 1).Count-gt0){$Errors.Add('package_plan_item_ids_not_unique')}
    $Goals = @((Get-ReducerValue $Payload 'focus_goals' @()) | Where-Object { $null -ne $_ })
    if (@($Goals | Where-Object { [string](Get-ReducerValue $_ 'status' '') -eq 'active' }).Count -ne 1) {
        $Errors.Add('exactly_one_active_focus_goal_required')
    }
    return [pscustomobject]@{ valid=$Errors.Count -eq 0; errors=@($Errors); plan_items=$PlanItems; packages=$Packages; focus_goals=$Goals }
}

function New-V4MigrationTransaction {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey,
        [Parameter(Mandatory = $true)][string]$PayloadHash
    )
    $Timestamp = Get-V4Timestamp -Context $Context
    $MigrationId = New-StableIdentifier -Prefix 'M4-' -Seed "$IdempotencyKey|C0003|C0004" -HashLength 24
    $PlanRows = @((Get-V4RawTsvRows -Path $Context.paths.plans) | ForEach-Object { ConvertTo-V4Row -Source $_ -Headers $script:V4PlanHeaders })
    if (@($PlanRows | Where-Object { $_.plan_id -eq 'C0004' }).Count -gt 0) { throw 'C0004 already exists in plan-items.tsv.' }
    $PlanRows += @((Get-ReducerValue $Payload 'plan_items' @()) | ForEach-Object { ConvertTo-V4Row -Source $_ -Headers $script:V4PlanHeaders })
    $EvidenceRows = @((Get-V4RawTsvRows -Path $Context.paths.evidence) | ForEach-Object { ConvertTo-V4Row -Source $_ -Headers $script:V4EvidenceHeaders })
    $HistoryRows = @((Get-V4RawTsvRows -Path $Context.paths.review_history) | ForEach-Object { ConvertTo-V4Row -Source $_ -Headers $script:V4ReviewHistoryHeaders })
    $LegacyReview = New-V4LegacyReviewData -Context $Context -Timestamp $Timestamp
    $FocusGoals = @((Get-ReducerValue $Payload 'focus_goals' @()) | ForEach-Object { ConvertTo-V4Row -Source $_ -Headers $script:V4FocusGoalHeaders })
    $Competencies = @(New-V4InitialCompetencyRows -Context $Context -Timestamp $Timestamp)
    $SnapshotEntries = @(Get-V4MigrationSnapshotEntries -Context $Context)
    return [pscustomobject]@{
        schema_version=4; migration_id=$MigrationId; operation='ActivateV4'; status='pending'; phase='intent';
        idempotency_key=$IdempotencyKey; payload_hash=$PayloadHash; from_runtime=3; to_runtime=4;
        from_cycle_id='C0003'; to_cycle_id='C0004'; created_at=$Timestamp; updated_at=$Timestamp;
        committed_at=''; error=$null; receipt=$null; snapshot_entries=$SnapshotEntries;
        snapshot_relative_path=".state/migration-snapshots/$MigrationId";
        plan_rows=$PlanRows; evidence_rows=$EvidenceRows; review_history_rows=$HistoryRows;
        review_item_rows=@($LegacyReview.items); review_source_rows=@($LegacyReview.sources);
        focus_goal_rows=$FocusGoals; competency_rows=$Competencies;
        packages=@((Get-ReducerValue $Payload 'packages' @())); package_descriptors=@(); bootstrap_index=$null
    }
}

function New-V4MigrationBootstrapIndex {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Transaction
    )
    $Next = @($Transaction.plan_rows | Where-Object { $_.status -in @('planned','in_progress') } |
        Sort-Object plan_id, { [int]$_.sequence } | Select-Object -First 1)
    if ($Next.Count -ne 1 -or [string]$Next[0].plan_id -ne 'C0004') { throw 'Activation index requires C0004 as the next strict queue head.' }
    $Descriptor = @($Transaction.package_descriptors | Where-Object { $_.plan_item_id -eq [string]$Next[0].plan_item_id })
    if ($Descriptor.Count -ne 1) { throw 'Activation index cannot resolve one package for the queue head.' }
    $Due = foreach ($Item in @($Transaction.review_item_rows)) {
        if ([string]$Item.status -notin @('active','maintenance','legacy_unverified')) { continue }
        $DueDate = [string]$Item.next_review
        if ($DueDate -notmatch '^\d{4}-\d{2}-\d{2}$') { continue }
        if ([datetime]::ParseExact($DueDate,'yyyy-MM-dd',[Globalization.CultureInfo]::InvariantCulture) -gt $Context.study_date) { continue }
        [pscustomobject]@{
            review_item_id=[string]$Item.review_item_id; lane=$(if($Item.status -eq 'legacy_unverified'){'legacy'}else{[string]$Item.status});
            recipe_stage=[string]$Item.recipe_stage; strength_level=[int]$Item.strength_level; effective_due=$DueDate;
            review_family=[string]$Item.review_family; target_scope=[string]$Item.target_scope
        }
    }
    $Selection = Select-ReviewQueue -Items @($Due) -Mode normal
    $Selected = @($Selection.selected | ForEach-Object {
        [pscustomobject]@{ review_item_id=$_.item.review_item_id; lane=$_.lane; recipe_stage=$_.item.recipe_stage; weight=$_.weight; effective_due=$_.item.effective_due; review_family=$_.item.review_family; target_scope=$_.item.target_scope }
    })
    $Index = [pscustomobject]@{
        schema_version=4; index_revision=1; queue_revision=1; generated_at=Get-V4Timestamp -Context $Context;
        plan_id=[string]$Next[0].plan_id; next_plan_item_id=[string]$Next[0].plan_item_id; next_title=[string]$Next[0].title;
        session_type=[string]$Next[0].session_type; primary_skill=[string]$Next[0].primary_skill; plan_role=[string]$Next[0].plan_role;
        focus_goal_id=[string]$Next[0].focus_goal_id; package_path=[string]$Descriptor[0].package_path; package_hash=[string]$Descriptor[0].package_hash;
        fallback_package_path=[string]$Descriptor[0].fallback_package_path; fallback_package_hash=[string]$Descriptor[0].fallback_package_hash;
        compatible_previous_package_path=''; compatible_previous_package_hash=''; next_package_descriptors=@($Transaction.package_descriptors);
        preload_pending=$false; rebuild_required=$false; recovery_mode=$false; review_revision=1;
        review_due_counts=[pscustomobject]@{active=@($Due|Where-Object lane -eq active).Count;maintenance=@($Due|Where-Object lane -eq maintenance).Count;legacy=@($Due|Where-Object lane -eq legacy).Count;total=@($Due).Count};
        review_candidates=$Selected; preauthorized_probe_candidate=Get-ReducerValue $Descriptor[0] 'preauthorized_probe_candidate' $null;
        adaptation_projection_revision=1; long_term_projection_revision=1; policy_version='4.0.0'; catalog_version='1.0.0';
        ladder_version='1.0.0'; contract_version='4.0.0'; protocol_refs=@('references/runtime-protocol-v4.md');
        last_transaction_id=[string]$Transaction.migration_id; request_started_at=''; bootstrap_latency_ms=0; queue_guard=''
    }
    $Index.queue_guard = Get-V4QueueGuard -Index $Index
    return $Index
}

function Complete-V4Migration {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Transaction,
        [string]$FaultAfterPhase
    )
    try {
        if ([string]$Transaction.phase -eq 'intent') {
            $SnapshotRoot = Join-Path $Context.root ([string]$Transaction.snapshot_relative_path).Replace('/', '\')
            if (-not (Test-Path -LiteralPath $SnapshotRoot -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $SnapshotRoot) }
            foreach ($Entry in @($Transaction.snapshot_entries)) {
                $Source = Join-Path $Context.root ([string]$Entry.relative_path).Replace('/', '\')
                if ((Get-FileSha256 -Path $Source) -ne [string]$Entry.sha256) { throw "Migration source changed before snapshot: $($Entry.relative_path)" }
                $Destination = Join-Path $SnapshotRoot ([string]$Entry.relative_path).Replace('/', '\')
                $DestinationDirectory = Split-Path -Parent $Destination
                if (-not (Test-Path -LiteralPath $DestinationDirectory -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $DestinationDirectory) }
                if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) { Copy-Item -LiteralPath $Source -Destination $Destination }
                if ((Get-FileSha256 -Path $Destination) -ne [string]$Entry.sha256) { throw "Migration snapshot verification failed: $($Entry.relative_path)" }
            }
            $Transaction.phase='snapshot_verified';$Transaction.updated_at=Get-V4Timestamp -Context $Context
            $Transaction=Write-DurableJson -Path $Context.paths.migration -Value $Transaction
            Invoke-FaultPoint -Name 'migration_snapshot' -RequestedFault $FaultAfterPhase
        }
        if ([string]$Transaction.phase -eq 'snapshot_verified') {
            $Descriptors=[System.Collections.Generic.List[object]]::new()
            foreach($Package in @($Transaction.packages)) {
                $PlanItemId=[string]$Package.plan_item_id
                $PackageRelative=".state/packages/$PlanItemId.json";$PackagePath=Join-Path $Context.root $PackageRelative.Replace('/', '\')
                [void](Write-DurableJson -Path $PackagePath -Value $Package -MaximumBytes 262144)
                $Fallback=[pscustomobject]@{
                    schema_version=1;status='ready';plan_id='C0004';plan_item_id=$PlanItemId;
                    plan_role=[string](Get-ReducerValue $Package 'plan_role' '');primary_skill=[string](Get-ReducerValue $Package 'primary_skill' '');
                    focus_goal_id=[string](Get-ReducerValue $Package 'focus_goal_id' '');evidence_mode_cap='training';
                    policy_version=[string](Get-ReducerValue $Package 'policy_version' '');catalog_version=[string](Get-ReducerValue $Package 'catalog_version' '');
                    ladder_version=[string](Get-ReducerValue $Package 'ladder_version' '');contract_version=[string](Get-ReducerValue $Package 'contract_version' '');
                    rights_status=[string]$Package.rights_status;activity_skeletons=@((Get-ReducerValue $Package 'fallback_activity_skeletons' @()))
                }
                $FallbackRelative=".state/packages/$PlanItemId-fallback.json";$FallbackPath=Join-Path $Context.root $FallbackRelative.Replace('/', '\')
                [void](Write-DurableJson -Path $FallbackPath -Value $Fallback -MaximumBytes 131072)
                $Probe=@((Get-ReducerValue $Package 'preauthorized_probe_candidates' @())|Where-Object{$null-ne$_}|Select-Object -First 1)
                $Descriptors.Add([pscustomobject]@{plan_item_id=$PlanItemId;package_path=$PackageRelative;package_hash=Get-FileSha256 -Path $PackagePath;fallback_package_path=$FallbackRelative;fallback_package_hash=Get-FileSha256 -Path $FallbackPath;preauthorized_probe_candidate=$(if($Probe.Count-eq1){$Probe[0]}else{$null})})
            }
            $Transaction.package_descriptors=@($Descriptors);$Transaction.phase='packages_written';$Transaction.updated_at=Get-V4Timestamp -Context $Context
            $Transaction=Write-DurableJson -Path $Context.paths.migration -Value $Transaction
            Invoke-FaultPoint -Name 'migration_packages' -RequestedFault $FaultAfterPhase
        }
        if ([string]$Transaction.phase -eq 'packages_written') {
            Write-TsvRowsAtomic -Path $Context.paths.plans -Rows @($Transaction.plan_rows) -Headers $script:V4PlanHeaders
            Write-TsvRowsAtomic -Path $Context.paths.evidence -Rows @($Transaction.evidence_rows) -Headers $script:V4EvidenceHeaders
            Write-TsvRowsAtomic -Path $Context.paths.review_history -Rows @($Transaction.review_history_rows) -Headers $script:V4ReviewHistoryHeaders
            Write-TsvRowsAtomic -Path $Context.paths.review_items -Rows @($Transaction.review_item_rows) -Headers $script:V4ReviewItemHeaders
            Write-TsvRowsAtomic -Path $Context.paths.review_sources -Rows @($Transaction.review_source_rows) -Headers $script:V4ReviewSourceHeaders
            Write-TsvRowsAtomic -Path $Context.paths.review_candidates -Rows @() -Headers $script:V4ReviewCandidateHeaders
            Write-TsvRowsAtomic -Path $Context.paths.review_audit -Rows @() -Headers $script:V4ReviewAuditHeaders
            Write-TsvRowsAtomic -Path $Context.paths.focus_goals -Rows @($Transaction.focus_goal_rows) -Headers $script:V4FocusGoalHeaders
            Write-TsvRowsAtomic -Path $Context.paths.goal_events -Rows @() -Headers $script:V4GoalEventHeaders
            Write-TsvRowsAtomic -Path $Context.paths.competency_status -Rows @($Transaction.competency_rows) -Headers $script:V4CompetencyStatusHeaders
            Write-TsvRowsAtomic -Path $Context.paths.competency_events -Rows @() -Headers $script:V4CompetencyEventHeaders
            Write-TsvRowsAtomic -Path $Context.paths.stage_events -Rows @() -Headers $script:V4StageEventHeaders
            Write-TsvRowsAtomic -Path $Context.paths.insights -Rows @() -Headers $script:V4InsightHeaders
            $Transaction.phase='schema_written';$Transaction.updated_at=Get-V4Timestamp -Context $Context
            $Transaction=Write-DurableJson -Path $Context.paths.migration -Value $Transaction
            Invoke-FaultPoint -Name 'migration_schema' -RequestedFault $FaultAfterPhase
        }
        if ([string]$Transaction.phase -eq 'schema_written') {
            [void](Write-DurableJson -Path $Context.paths.adaptation -Value ([pscustomobject]@{schema_version=4;projection_revision=1;states=@()}))
            [void](Write-DurableJson -Path $Context.paths.long_term -Value ([pscustomobject]@{schema_version=4;projection_revision=1;last_evaluated_cycle_id='';states=@();insight_ids=@()}))
            [void](Write-DurableJson -Path $Context.paths.current_cycle_evidence -Value ([pscustomobject]@{schema_version=4;projection_revision=1;evidence_refs=@();review_batch_refs=@()}))
            [void](Write-DurableJson -Path $Context.paths.current_session -Value ([pscustomobject]@{schema_version=4;protocol_version=4;revision=0;status='idle';session_id='';updated_at=(Get-V4Timestamp -Context $Context)}))
            $Transaction.phase='projections_written';$Transaction.updated_at=Get-V4Timestamp -Context $Context
            $Transaction=Write-DurableJson -Path $Context.paths.migration -Value $Transaction
            Invoke-FaultPoint -Name 'migration_projections' -RequestedFault $FaultAfterPhase
        }
        if ([string]$Transaction.phase -eq 'projections_written') {
            $Index=New-V4MigrationBootstrapIndex -Context $Context -Transaction $Transaction
            [void](Write-DurableJson -Path $Context.paths.bootstrap_index -Value $Index -MaximumBytes 65536)
            $Transaction.bootstrap_index=$Index;$Transaction.phase='index_written';$Transaction.updated_at=Get-V4Timestamp -Context $Context
            $Transaction=Write-DurableJson -Path $Context.paths.migration -Value $Transaction
            Invoke-FaultPoint -Name 'migration_index' -RequestedFault $FaultAfterPhase
        }
        if ([string]$Transaction.phase -eq 'index_written') {
            $Report=Invoke-V4Validation -Context $Context -PreActivation
            if ($Report.status -ne 'valid') { throw "Pre-switch v4 validation failed: $($Report.errors -join '; ')" }
            $ActivatedSettings=New-V4ActivatedSettings -Context $Context -Transaction $Transaction
            Write-DurableText -Path $Context.paths.settings -Text ($ActivatedSettings|ConvertTo-Json -Depth 20)
            $Transaction.phase='settings_written';$Transaction.updated_at=Get-V4Timestamp -Context $Context
            $Transaction=Write-DurableJson -Path $Context.paths.migration -Value $Transaction
            Invoke-FaultPoint -Name 'migration_settings' -RequestedFault $FaultAfterPhase
        }
        if ([string]$Transaction.phase -eq 'settings_written') {
            [void](Write-DurableJson -Path $Context.paths.runtime -Value ([pscustomobject]@{
                schema_version=4;runtime_version=4;status='active';activated_at=Get-V4Timestamp -Context $Context;
                activated_cycle_id='C0004';migration_id=[string]$Transaction.migration_id;catalog_version='1.0.0';
                ladder_version='1.0.0';contract_version='4.0.0'
            }))
            $Transaction.phase='runtime_switched';$Transaction.updated_at=Get-V4Timestamp -Context $Context
            $Transaction=Write-DurableJson -Path $Context.paths.migration -Value $Transaction
            Invoke-FaultPoint -Name 'migration_runtime' -RequestedFault $FaultAfterPhase
        }
        if ([string]$Transaction.phase -eq 'runtime_switched') {
            $Transaction.phase='committed';$Transaction.status='committed';$Transaction.committed_at=Get-V4Timestamp -Context $Context
            $Transaction.receipt=[pscustomobject]@{operation='ActivateV4';migration_id=[string]$Transaction.migration_id;idempotency_key=[string]$Transaction.idempotency_key;payload_hash=[string]$Transaction.payload_hash;from_cycle_id='C0003';to_cycle_id='C0004';runtime_version=4;post_activation_maintenance='remove_v3_branches_from_skill_keep_legacy_docs'}
            $Transaction=Write-DurableJson -Path $Context.paths.migration -Value $Transaction
            Invoke-FaultPoint -Name 'migration_commit' -RequestedFault $FaultAfterPhase
        }
        return $Transaction
    }
    catch {
        try {
            $Transaction.error=[pscustomobject]@{phase=[string]$Transaction.phase;message=$_.Exception.Message;recorded_at=Get-V4Timestamp -Context $Context}
            $Transaction.updated_at=Get-V4Timestamp -Context $Context
            [void](Write-DurableJson -Path $Context.paths.migration -Value $Transaction)
        } catch { }
        throw
    }
}

function Invoke-V4ActivateMigration {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey,
        [switch]$ConfirmActivation,
        [string]$FaultAfterPhase
    )
    if ([string]::IsNullOrWhiteSpace($IdempotencyKey)) { throw 'ActivateV4 requires -IdempotencyKey.' }
    $Plan=Get-V4MigrationPlan -Context $Context
    if ($Plan.status -ne 'ready') { return $Plan }
    $PayloadValidation=Test-V4ActivationPayload -Context $Context -Payload $Payload -IdempotencyKey $IdempotencyKey -Confirmed:$ConfirmActivation
    if (-not $PayloadValidation.valid) {
        return New-V4Response -Status 'blocked' -NextAction 'repair_activation_payload' `
            -ReasonCode 'activation_payload_invalid' -PreparedStep ([pscustomobject]@{errors=@($PayloadValidation.errors)}) `
            -RuntimeVersion 3 -ProtocolRefs @('references/runtime-protocol-v3.md')
    }
    return Invoke-WithFileLock -LockPath $Context.paths.lock -Script {
        $PayloadHash=Get-PayloadHash -Payload $Payload
        $ExistingRead=Read-DurableJson -Path $Context.paths.migration -AllowMissing
        if($null-ne$ExistingRead-and$ExistingRead.status-eq'valid'){
            $Existing=$ExistingRead.value
            if([string]$Existing.idempotency_key-eq$IdempotencyKey){
                if([string]$Existing.payload_hash-ne$PayloadHash){throw 'Idempotency key was reused with a different migration payload.'}
                if([string]$Existing.phase-eq'committed'){
                    return New-V4Response -Status 'active' -NextAction 'bootstrap' -Receipt $Existing.receipt -ReasonCode 'idempotent_replay'
                }
                $Recovered=Complete-V4Migration -Context $Context -Transaction $Existing -FaultAfterPhase $FaultAfterPhase
                return New-V4Response -Status 'active' -NextAction 'bootstrap' -Receipt $Recovered.receipt -ReasonCode 'migration_recovered'
            }
            if([string]$Existing.phase-ne'committed'){throw 'A different v4 migration is pending and must be recovered first.'}
        }
        $Runtime=Get-V4Runtime -Context $Context
        if([int](Get-ReducerValue $Runtime 'runtime_version' 0)-eq4){throw 'Runtime v4 is already active under a different activation transaction.'}
        $Transaction=New-V4MigrationTransaction -Context $Context -Payload $Payload -IdempotencyKey $IdempotencyKey -PayloadHash $PayloadHash
        $Transaction=Write-DurableJson -Path $Context.paths.migration -Value $Transaction
        Invoke-FaultPoint -Name 'migration_intent' -RequestedFault $FaultAfterPhase
        $Completed=Complete-V4Migration -Context $Context -Transaction $Transaction -FaultAfterPhase $FaultAfterPhase
        return New-V4Response -Status 'active' -NextAction 'bootstrap' -Receipt $Completed.receipt -ReasonCode 'migration_committed'
    }
}
