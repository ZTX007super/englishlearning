Set-StrictMode -Version Latest

function Complete-V4CyclePublication {
    param([object]$Context, [object]$Intent, [string]$FaultAfterPhase)
    $Path = Join-Path $Context.root '.state/cycle-publication.json'
    if ($Intent.phase -eq 'committed') { return $Intent }
    if ($Intent.phase -eq 'intent') {
        $FinalGoals=Get-ReducerValue $Intent 'final_goals' $null
        if ($null -ne $FinalGoals) {
            $Goals=@(Get-TsvRows -Path $Context.paths.focus_goals -Headers $script:V4FocusGoalHeaders)
            if ((Get-PayloadHash $Goals) -ne (Get-PayloadHash @($FinalGoals))) {
                if ((Get-PayloadHash $Goals) -ne (Get-PayloadHash @($Intent.original_goals))) { throw 'Goals changed during cycle publication.' }
                Write-TsvRowsAtomic -Path $Context.paths.focus_goals -Rows @($FinalGoals) -Headers $script:V4FocusGoalHeaders
            }
        }
        $Intent.phase='goals_written'
        $Intent=Write-DurableJson -Path $Path -Value $Intent
        Invoke-FaultPoint -Name 'cycle_goals' -RequestedFault $FaultAfterPhase
    }
    if ($Intent.phase -eq 'goals_written') {
        foreach ($Package in $Intent.payload.packages) {
            $PackagePath = Join-Path $Context.root ".state/packages/$($Package.plan_item_id).json"
            $Existing = Read-DurableJson -Path $PackagePath -AllowMissing
            if ($null -ne $Existing -and ($Existing.status -ne 'valid' -or
                (Get-PayloadHash $Existing.value) -ne (Get-PayloadHash (Add-StateIntegrity -Value $Package)))) { throw 'Published package conflicts with cycle intent.' }
            if ($null -eq $Existing) { [void](Write-DurableJson -Path $PackagePath -Value $Package) }
            # Optional derived cache: failure must not invalidate the confirmed cycle.
            if ($null -ne (Get-Command Publish-V4ClassroomTemplate -ErrorAction SilentlyContinue)) {
                try { Publish-V4ClassroomTemplate -Context $Context -PackagePath $PackagePath } catch { Write-Verbose "Classroom template preload pending: $($_.Exception.Message)" }
            }
        }
        $Intent.phase = 'packages_written'
        $Intent = Write-DurableJson -Path $Path -Value $Intent
        Invoke-FaultPoint -Name 'cycle_packages' -RequestedFault $FaultAfterPhase
    }
    if ($Intent.phase -eq 'packages_written') {
        $Plans = @(Get-TsvRows -Path $Context.paths.plans -Headers $script:V4PlanHeaders)
        $FinalPlans = @($Intent.original_plans) + @($Intent.payload.plan_items)
        if ((Get-PayloadHash -Payload $Plans) -ne (Get-PayloadHash -Payload $FinalPlans)) {
            if ((Get-PayloadHash -Payload $Plans) -ne (Get-PayloadHash -Payload @($Intent.original_plans))) { throw 'Plans changed during cycle publication.' }
            Write-TsvRowsAtomic -Path $Context.paths.plans -Rows $FinalPlans -Headers $script:V4PlanHeaders
        }
        $Intent.phase = 'plans_written'
        $Intent = Write-DurableJson -Path $Path -Value $Intent
        Invoke-FaultPoint -Name 'cycle_plans' -RequestedFault $FaultAfterPhase
    }
    if ($Intent.phase -eq 'plans_written') {
        $ArchivePath = Join-Path $Context.root ".state/cycle-evidence/$($Intent.payload.from_cycle_id).json"
        $Archive = Read-DurableJson -Path $ArchivePath -AllowMissing
        if ($null -eq $Archive) { [void](Write-DurableJson -Path $ArchivePath -Value $Intent.original_evidence) }
        elseif ($Archive.status -ne 'valid' -or (Get-PayloadHash $Archive.value) -ne (Get-PayloadHash $Intent.original_evidence)) { throw 'Cycle evidence archive conflicts with publication.' }
        $NewProjection = [pscustomobject]@{schema_version=4;projection_revision=([int]$Intent.original_evidence.projection_revision+1);cycle_id=$Intent.payload.to_cycle_id;evidence_refs=@();review_batch_refs=@()}
        $Current = Read-DurableJson -Path $Context.paths.current_cycle_evidence
        if ((Get-PayloadHash $Current.value) -ne (Get-PayloadHash (Add-StateIntegrity -Value $NewProjection))) {
            if ((Get-PayloadHash $Current.value) -ne (Get-PayloadHash $Intent.original_evidence)) { throw 'Cycle evidence changed during publication.' }
            [void](Write-DurableJson -Path $Context.paths.current_cycle_evidence -Value $NewProjection)
        }
        $Intent.phase = 'evidence_archived'
        $Intent = Write-DurableJson -Path $Path -Value $Intent
        Invoke-FaultPoint -Name 'cycle_evidence' -RequestedFault $FaultAfterPhase
    }
    if ($Intent.phase -eq 'evidence_archived') {
        $Index = $Intent.original_index
        $Descriptors = @(foreach ($Package in $Intent.payload.packages) {
            $Relative = ".state/packages/$($Package.plan_item_id).json"
            [pscustomobject]@{plan_item_id=$Package.plan_item_id;package_path=$Relative;package_hash=(Get-FileSha256 (Join-Path $Context.root $Relative));fallback_package_path=$Relative;fallback_package_hash=(Get-FileSha256 (Join-Path $Context.root $Relative));preauthorized_probe_candidate=$null}
        })
        $Head = @($Intent.payload.plan_items | Sort-Object {[int]$_.sequence})[0]
        foreach ($Name in @('plan_id','session_type','primary_skill','plan_role','focus_goal_id')) { $Index.$Name = $Head.$Name }
        $Index.next_plan_item_id=$Head.plan_item_id; $Index.next_title=$Head.title
        $First = @($Descriptors | Where-Object { $_.plan_item_id -eq $Head.plan_item_id })[0]
        foreach ($Name in @('package_path','package_hash','fallback_package_path','fallback_package_hash')) { $Index.$Name=$First.$Name }
        $Index.next_package_descriptors=$Descriptors; $Index.preload_pending=$false
        $Index.compatible_previous_package_path=''; $Index.compatible_previous_package_hash=''
        $Index.queue_revision=[int]$Index.queue_revision+1; $Index.index_revision=[int]$Index.index_revision+1
        $Index.generated_at=$Intent.created_at; $Index.last_transaction_id=$Intent.transaction_id
        $Index.queue_guard=Get-V4QueueGuard -Index $Index
        $CurrentIndex=Get-V4BootstrapIndex -Context $Context
        if ($CurrentIndex.status -ne 'valid' -or $CurrentIndex.value.queue_guard -notin @($Intent.queue_guard,$Index.queue_guard)) { throw 'Queue changed during cycle publication.' }
        if ($CurrentIndex.value.queue_guard -ne $Index.queue_guard) { [void](Write-DurableJson -Path $Context.paths.bootstrap_index -Value $Index) }
        $Intent.phase='index_written'
        $Intent=Write-DurableJson -Path $Path -Value $Intent
        Invoke-FaultPoint -Name 'cycle_index' -RequestedFault $FaultAfterPhase
    }
    if ($Intent.phase -eq 'index_written') {
        $Intent.phase='committed'; $Intent.status='committed'
        $Intent.receipt=[pscustomobject]@{operation='PublishCycle';status='committed';transaction_id=$Intent.transaction_id;plan_id=$Intent.payload.to_cycle_id;idempotency_key=$Intent.idempotency_key;first_plan_item_id=$Intent.payload.plan_items[0].plan_item_id}
        $Intent=Write-DurableJson -Path $Path -Value $Intent
        Invoke-FaultPoint -Name 'cycle_commit' -RequestedFault $FaultAfterPhase
    }
    return $Intent
}

function Invoke-V4PublishCycle {
    param([object]$Context, [object]$Payload, [string]$IdempotencyKey, [string]$FaultAfterPhase)
    [void](Assert-V4Active -Context $Context)
    if ([string]::IsNullOrWhiteSpace($IdempotencyKey)) { throw 'PublishCycle requires IdempotencyKey.' }
    return Invoke-WithFileLock -LockPath $Context.paths.lock -Script {
        $Path=Join-Path $Context.root '.state/cycle-publication.json'
        $Hash=Get-PayloadHash $Payload
        $Existing=Read-DurableJson -Path $Path -AllowMissing
        if ($null -ne $Existing) {
            if ($Existing.status -ne 'valid') { throw 'Cycle publication transaction is corrupt.' }
            if ($Existing.value.idempotency_key -eq $IdempotencyKey) {
                if ($Existing.value.payload_hash -ne $Hash) { throw 'PublishCycle idempotency key payload conflict.' }
                $Done=Complete-V4CyclePublication -Context $Context -Intent $Existing.value -FaultAfterPhase $FaultAfterPhase
                return New-V4Response -Status 'published' -NextAction 'bootstrap' -Receipt $Done.receipt -ReasonCode 'idempotent_replay'
            }
            if ($Existing.value.phase -ne 'committed') { throw 'Recover the pending cycle publication first.' }
        }
        if (-not (Test-ReducerTrue (Get-ReducerValue $Payload 'user_confirmed' $false)) -or [string]::IsNullOrWhiteSpace([string](Get-ReducerValue $Payload 'confirmation_ref' ''))) { throw 'PublishCycle requires a confirmed plan and confirmation_ref.' }
        if ($Payload.from_cycle_id -notmatch '^C\d{4}$' -or $Payload.to_cycle_id -notmatch '^C\d{4}$' -or
            [int]$Payload.to_cycle_id.Substring(1) -ne ([int]$Payload.from_cycle_id.Substring(1)+1)) { throw 'PublishCycle must publish the immediately following cycle.' }
        $Checkpoint=Get-V4CurrentSession -Context $Context
        $Terminal=Read-DurableJson -Path $Context.paths.session_transaction -AllowMissing
        if ($null -eq $Checkpoint -or $Checkpoint.status -ne 'valid' -or $Checkpoint.value.status -ne 'completed' -or
            $Checkpoint.value.plan_role -ne 'cycle_review' -or $Checkpoint.value.plan_id -ne $Payload.from_cycle_id -or
            $null -eq $Terminal -or $Terminal.status -ne 'valid' -or $Terminal.value.phase -ne 'committed' -or
            $Terminal.value.session_id -ne $Checkpoint.value.session_id -or $Terminal.value.disposition -ne 'completed') { throw 'PublishCycle requires the prior cycle review committed receipt.' }
        $Index=Get-V4BootstrapIndex -Context $Context
        if ($Index.status -ne 'valid' -or -not [string]::IsNullOrWhiteSpace([string]$Index.value.next_plan_item_id)) { throw 'PublishCycle requires an empty queue.' }
        $Plans=@(Get-TsvRows -Path $Context.paths.plans -Headers $script:V4PlanHeaders)
        if (@($Plans | Where-Object { $_.status -notin @('completed','cancelled') -or $_.plan_id -eq $Payload.to_cycle_id }).Count) { throw 'Existing plans block cycle publication.' }
        $Items=@($Payload.plan_items); $Packages=@($Payload.packages)
        if ($Items.Count -ne 7 -or $Packages.Count -ne 7 -or @($Items | Select-Object -ExpandProperty plan_item_id -Unique).Count -ne 7) { throw 'A cycle requires six training items and one review with unique IDs.' }
        if (@($Items | Where-Object { $_.plan_item_id -in @($Plans.plan_item_id) }).Count) { throw 'Plan item IDs cannot reuse historical IDs.' }
        $Goals=@(Get-TsvRows -Path $Context.paths.focus_goals -Headers $script:V4FocusGoalHeaders)
        $OriginalGoals=ConvertFrom-StableJson -Json (ConvertTo-CanonicalJson -Value $Goals)
        $NewGoal=Get-ReducerValue $Payload 'next_goal' $null
        $PriorDecision=Get-ReducerValue $Terminal.value 'goal_decision' $null
        if ($null -eq $NewGoal -and [string](Get-ReducerValue $PriorDecision 'decision' '') -in @('met','redesign')) { throw 'A met or redesign decision requires a confirmed next_goal.' }
        if ($null -ne $NewGoal) {
            if ([string]$NewGoal.goal_id -notmatch '^[A-Za-z0-9_-]+$' -or $NewGoal.goal_id -in @($Goals.goal_id)) { throw 'next_goal requires a new safe goal_id.' }
            foreach ($Name in @('goal_key','stage_id','skill','competency_id','competency_family','activity_family','quality_focus','goal_text')) {
                if ([string]::IsNullOrWhiteSpace([string](Get-ReducerValue $NewGoal $Name ''))) { throw "next_goal requires $Name." }
            }
            if ($NewGoal.skill -notin @('listening','speaking','reading','writing') -or [int]$NewGoal.min_completed_cycles -ne 2 -or [int]$NewGoal.max_completed_cycles -notin @(2,3,4)) { throw 'New goals require a skill and a 2-4 completed-cycle window.' }
            $Contract=Get-V4GoalContract $NewGoal
            if ($null -eq $Contract -or $Contract.catalog_version -ne $Index.value.catalog_version) { throw 'next_goal requires a structured, current success contract.' }
            $Old=@($Goals | Where-Object { $_.goal_id -eq $Checkpoint.value.focus_goal_id -and $_.status -eq 'active' })
            if ($Old.Count -ne 1) { throw 'The reviewed active goal must be identifiable before replacement.' }
            $Timestamp=Get-V4Timestamp $Context
            $Old[0].status=if ([string](Get-ReducerValue $PriorDecision 'decision' '') -eq 'met') {'met'} else {'superseded'}
            $Old[0].end_cycle_id=$Payload.from_cycle_id;$Old[0].updated_at=$Timestamp
            $Values=[ordered]@{}; foreach ($Header in $script:V4FocusGoalHeaders) { $Values[$Header]=[string](Get-ReducerValue $NewGoal $Header '') }
            $Versions=@($Goals | Where-Object goal_key -eq $NewGoal.goal_key | ForEach-Object { [int]$_.version })
            $Values.version=[string](1+$(if ($Versions.Count) { ($Versions | Measure-Object -Maximum).Maximum } else {0}))
            $Values.supersedes_goal_id=$Old[0].goal_id;$Values.start_cycle_id=$Payload.to_cycle_id;$Values.status='active';$Values.end_cycle_id='';$Values.created_at=$Timestamp;$Values.updated_at=$Timestamp
            $Goals+=@([pscustomobject]$Values)
        }
        for ($i=0;$i -lt 7;$i++) {
            $Item=$Items[$i]
            if ([string]$Item.sequence -ne [string]($i+1) -or $Item.plan_id -ne $Payload.to_cycle_id -or $Item.plan_item_id -notmatch '^[A-Za-z0-9_-]+$' -or $Item.status -ne 'planned' -or $Item.completed_session_id -ne '' -or $Item.required -ne 'true') { throw 'Invalid new cycle plan row.' }
            if (($i -eq 6 -and ($Item.plan_role -ne 'cycle_review' -or $Item.session_type -ne 'review')) -or ($i -lt 6 -and $Item.plan_role -notin @('focus','maintenance'))) { throw 'The seventh item must be the only cycle review.' }
            [void](Get-V4RequiredStages -SessionType $Item.session_type -PrimarySkill $Item.primary_skill -PlanRole $Item.plan_role)
            if ($Item.plan_role -in @('focus','cycle_review') -and @($Goals | Where-Object { $_.goal_id -eq $Item.focus_goal_id -and $_.status -eq 'active' }).Count -ne 1) { throw 'The cycle must reference an existing active goal.' }
            if ($null -ne $NewGoal -and $Item.plan_role -in @('focus','cycle_review') -and $Item.focus_goal_id -ne $NewGoal.goal_id) { throw 'Focus and review items must bind the confirmed next goal.' }
            $Matches=@($Packages | Where-Object { $_.plan_item_id -eq $Item.plan_item_id })
            if ($Matches.Count -ne 1) { throw 'Each plan item requires one package.' }
            $Package=$Matches[0]
            foreach ($Name in @('plan_id','plan_role','primary_skill','focus_goal_id')) { if ($Package.$Name -ne $Item.$Name) { throw "Package mismatch: $Name" } }
            foreach ($Name in @('policy_version','catalog_version','ladder_version','contract_version')) { if ($Package.$Name -ne $Index.value.$Name) { throw "Package version mismatch: $Name" } }
            if ($Package.status -ne 'ready' -or $Package.schema_version -ne 1 -or $Package.rights_status -notin @('project_original','licensed','public_domain','not_applicable') -or @($Package.activity_skeletons).Count -lt 1) { throw 'Invalid ready package.' }
            $Core=Get-V4CoreBlueprint -Context $Context -Package $Package
            if ($Core.status -ne 'ready') { throw 'PublishCycle requires a verified complete core for each package.' }
            if ($Core.value.activity_family -notin @($Package.activity_skeletons.activity_family)) { throw 'Core and skeleton activity families differ.' }
            if (Test-Path -LiteralPath (Join-Path $Context.root ".state/packages/$($Item.plan_item_id).json")) { throw 'New package path already exists.' }
        }
        foreach ($Skill in @('speaking','listening','reading','writing')) { if ($Skill -notin @($Items.primary_skill)) { throw 'Cycle must retain coverage of all four skills.' } }
        $Projection=Read-DurableJson -Path $Context.paths.current_cycle_evidence
        if ($Projection.status -ne 'valid') { throw 'Current cycle evidence is invalid.' }
        $Intent=[pscustomobject]@{schema_version=4;status='pending';phase='intent';transaction_id=(New-StableIdentifier -Prefix 'CP-' -Seed $IdempotencyKey -HashLength 24);idempotency_key=$IdempotencyKey;payload_hash=$Hash;payload=$Payload;original_plans=$Plans;original_index=$Index.value;original_evidence=$Projection.value;queue_guard=$Index.value.queue_guard;created_at=(Get-V4Timestamp -Context $Context);receipt=$null}
        if ($null -ne $NewGoal) { $Intent | Add-Member original_goals @($OriginalGoals); $Intent | Add-Member final_goals @($Goals) }
        $Intent=Write-DurableJson -Path $Path -Value $Intent
        Invoke-FaultPoint -Name 'cycle_intent' -RequestedFault $FaultAfterPhase
        $Done=Complete-V4CyclePublication -Context $Context -Intent $Intent -FaultAfterPhase $FaultAfterPhase
        return New-V4Response -Status 'published' -NextAction 'bootstrap' -Receipt $Done.receipt
    }
}
