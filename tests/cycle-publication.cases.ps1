# Loaded by tracker-v4.Tests.ps1 after shared fixtures.
Describe 'V4 next-cycle publication' {
    It 'requires confirmed plans and preserves the empty queue on rejection' {
        $Root=New-CyclePublicationFixture
        $Payload=Get-Content (Join-Path $ProjectRoot 'maintenance/examples/c0005-publication.json') -Raw | ConvertFrom-Json
        $Payload.user_confirmed=$false
        Assert-ThrowsV4 {Invoke-V4Json -Root $Root -Arguments @{Action='PublishCycle';IdempotencyKey='cycle-denied';PayloadJson=($Payload|ConvertTo-Json -Depth 40 -Compress)}}
        (Test-Path (Join-Path $Root '.state/cycle-publication.json')) | Should Be $false
        (Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap'}).next_action | Should Be 'confirm_next_cycle_plan'
    }
    foreach($Phase in @('cycle_intent','cycle_packages','cycle_plans','cycle_evidence','cycle_index','cycle_commit')) {
        It "recovers $Phase and starts the next cycle without duplicate rows" {
            $Root=New-CyclePublicationFixture
            $Payload=Get-Content (Join-Path $ProjectRoot 'maintenance/examples/c0005-publication.json') -Raw
            $OriginalEvidence=Get-FileSha256 (Join-Path $Root '.state/current-cycle-evidence.json')
            Assert-ThrowsV4 {Invoke-V4Json -Root $Root -Arguments @{Action='PublishCycle';IdempotencyKey='cycle-publish';PayloadJson=$Payload;FaultAfterPhase=$Phase}}
            $Boot=Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap'}
            if($Boot.next_action-eq'bootstrap'){$Boot=Invoke-V4Json -Root $Root -Arguments @{Action='Bootstrap'}}
            $Boot.next_action | Should Be 'start_session'
            $Boot.prepared_step.next_plan_item_id | Should Be 'PC0005-D1'
            $Replay=Invoke-V4Json -Root $Root -Arguments @{Action='PublishCycle';IdempotencyKey='cycle-publish';PayloadJson=$Payload}
            $Replay.receipt.status | Should Be 'committed'
            @((Import-Csv (Join-Path $Root 'learner/plan-items.tsv') -Delimiter "`t")).Count | Should Be 8
            (Get-FileSha256 (Join-Path $Root '.state/cycle-evidence/C0004.json')) | Should Be $OriginalEvidence
            $Start=Invoke-V4Json -Root $Root -Arguments @{Action='StartSession';IdempotencyKey='new-cycle-start'}
            $Start.receipt.plan_item_id | Should Be 'PC0005-D1'
            $Start.prepared_step.package_blueprint.core_status | Should Be 'ready'
            $Altered=$Payload|ConvertFrom-Json;$Altered.plan_items[0].title='changed'
            Assert-ThrowsV4 {Invoke-V4Json -Root $Root -Arguments @{Action='PublishCycle';IdempotencyKey='cycle-publish';PayloadJson=($Altered|ConvertTo-Json -Depth 40 -Compress)}}
        }
    }
}
