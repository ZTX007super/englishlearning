$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Tracker = Join-Path $ProjectRoot '.agents\skills\english-coach\scripts\tracker.ps1'
$FixtureRoot = Join-Path $PSScriptRoot 'fixtures\tracker-v3'

function New-TrackerFixture {
    $Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Force -Path $Root)
    Copy-Item -LiteralPath (Join-Path $FixtureRoot 'learner') -Destination $Root -Recurse
    Copy-Item -LiteralPath (Join-Path $FixtureRoot 'sessions') -Destination $Root -Recurse
    [void](New-Item -ItemType Directory -Force -Path (Join-Path $Root '.state'))
    return $Root
}

function Invoke-TrackerJson {
    param([string]$Root, [hashtable]$Arguments)
    return ((& $Tracker -ProjectRoot $Root @Arguments | Out-String) | ConvertFrom-Json)
}

function Assert-Throws {
    param([Parameter(Mandatory = $true)][scriptblock]$Operation)
    $Thrown = $false
    try { & $Operation | Out-Null }
    catch { $Thrown = $true }
    $Thrown | Should Be $true
}

function Get-QueuedPlanItems {
    param([string]$Root)
    return @(Import-Csv -LiteralPath (Join-Path $Root 'learner\plan-items.tsv') -Delimiter "`t" -Encoding UTF8 |
        Where-Object { $_.status -notin @('completed', 'cancelled') } |
        Sort-Object @{ Expression = 'plan_id'; Ascending = $true }, @{ Expression = { [int]$_.sequence }; Ascending = $true })
}

function Get-DurableDataFingerprint {
    param([string]$Root)
    $Files = @(Get-ChildItem -LiteralPath (Join-Path $Root 'learner'), (Join-Path $Root 'sessions') -Recurse -File | Sort-Object FullName)
    return (($Files | ForEach-Object {
        $RelativePath = $_.FullName.Substring($Root.Length + 1)
        "$RelativePath|$((Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash)|$($_.Length)"
    }) -join "`n")
}

function Set-SessionCompleted {
    param([string]$Root, [object]$StartResult)
    $Path = Join-Path $Root ([string]$StartResult.session_file).Replace('/', '\')
    $Text = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
    $Text = $Text.Replace('status: in_progress', 'status: completed').Replace('duration_minutes: 0', 'duration_minutes: 30')
    $Utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Text, $Utf8)
}

function Add-RawEvidence {
    param([string]$Root, [string]$SessionId, [string]$Skill)
    $Path = Join-Path $Root 'learner\skill-evidence.tsv'
    $Line = "EVT$([guid]::NewGuid().ToString('N'))`t$SessionId`t$Skill`traw`ttest_metric`t1`t1`tUnassisted test evidence`tContinue practice`r`n"
    $Utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::AppendAllText($Path, $Line, $Utf8)
}

function Save-RequiredCheckpoints {
    param([string]$Root, [string]$SessionId)
    foreach ($Stage in @('review', 'input', 'output', 'feedback')) {
        [void](Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Checkpoint'; SessionId = $SessionId; Stage = $Stage; Note = "test $Stage"; Date = [datetime]'2026-07-30T12:00:00' })
    }
}

Describe 'Queue tracker migration and scheduling' {
    It 'preserves completed rows and resumes at the current queue head' {
        $Root = New-TrackerFixture
        $Expected = @(Get-QueuedPlanItems -Root $Root)[0]
        $Result = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Bootstrap'; Date = [datetime]'2026-07-23T12:00:00' }
        $Result.status | Should Be 'ready'
        $Result.plan_state_reconciled | Should Be $false
        $Result.next_plan_item.plan_item_id | Should Be $Expected.plan_item_id
        $Result.review_limit | Should Be 6
        $Result.due_counts.total | Should Be ($Result.due_counts.vocabulary + $Result.due_counts.errors)
        (@($Result.due_vocabulary).Count + @($Result.due_errors).Count) | Should Be ([Math]::Min(6, [int]$Result.due_counts.total))
        $Result.due_items_selected | Should Be ([Math]::Min(6, [int]$Result.due_counts.total))
        $Result.include_all_due | Should Be $false
        $Plans = @(Import-Csv -LiteralPath (Join-Path $Root 'learner\plan-items.tsv') -Delimiter "`t" -Encoding UTF8)
        ($Plans | Where-Object plan_item_id -eq 'P2026W30-D1').completed_session_id | Should Be 'S20260721-01'
        ($Plans | Where-Object plan_item_id -eq 'P2026W30-D4').completed_session_id | Should Be 'S20260723-01'
    }

    It 'does not create missed work after a long gap and enables recovery mode' {
        $Root = New-TrackerFixture
        $Expected = @(Get-QueuedPlanItems -Root $Root)[0]
        [void](Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Rebuild'; Date = [datetime]'2026-08-25T12:00:00' })
        $Result = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Bootstrap'; Date = [datetime]'2026-08-25T12:00:00' }
        $Result.recovery_mode | Should Be $true
        $Result.review_limit | Should Be 10
        $Result.new_word_limit | Should Be 3
        $Result.due_items_selected | Should Be ([Math]::Min(10, [int]$Result.due_counts.total))
        $Result.next_plan_item.plan_item_id | Should Be $Expected.plan_item_id
        $Raw = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $Root 'learner\plan-items.tsv')
        $Raw.Contains('missed') | Should Be $false
    }

    It 'returns the complete due list only when explicitly requested' {
        $Root = New-TrackerFixture
        $Compact = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Bootstrap'; Date = [datetime]'2026-08-13T12:00:00' }
        $Complete = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Bootstrap'; IncludeAllDue = $true; Date = [datetime]'2026-08-13T12:00:00' }
        $Compact.due_items_selected | Should Be ([Math]::Min(6, [int]$Compact.due_counts.total))
        $Complete.include_all_due | Should Be $true
        $Complete.due_items_truncated | Should Be $false
        $Complete.due_items_selected | Should Be $Complete.due_counts.total
        (@($Complete.due_vocabulary).Count + @($Complete.due_errors).Count) | Should Be $Complete.due_counts.total
    }

    It 'keeps the full Due action compatible and does not mutate durable data during Bootstrap' {
        $Root = New-TrackerFixture
        $Before = Get-DurableDataFingerprint -Root $Root
        $Compact = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Bootstrap'; Date = [datetime]'2026-08-13T12:00:00' }
        $After = Get-DurableDataFingerprint -Root $Root
        $FullDue = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Due'; Date = [datetime]'2026-08-13T12:00:00' }
        $After | Should Be $Before
        ($FullDue.vocabulary_count + $FullDue.error_count) | Should Be $Compact.due_counts.total
        (@($FullDue.vocabulary).Count + @($FullDue.errors).Count) | Should Be $Compact.due_counts.total
    }

    It 'reconciles an interrupted completed session without changing history' {
        $Root = New-TrackerFixture
        $CompletedPlan = @(Import-Csv -LiteralPath (Join-Path $Root 'learner\plan-items.tsv') -Delimiter "`t" -Encoding UTF8 | Where-Object status -eq 'completed' | Select-Object -First 1)[0]
        $PlansPath = Join-Path $Root 'learner\plan-items.tsv'
        $Plans = @(Import-Csv -LiteralPath $PlansPath -Delimiter "`t" -Encoding UTF8)
        $Target = @($Plans | Where-Object plan_item_id -eq $CompletedPlan.plan_item_id)[0]
        $Target.status = 'in_progress'
        $Target.completed_session_id = ''
        $Plans | Select-Object plan_item_id, plan_id, sequence, title, session_type, primary_skill, required, status, completed_session_id | Export-Csv -LiteralPath $PlansPath -Delimiter "`t" -Encoding UTF8 -NoTypeInformation
        $HistoryHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'learner\review-history.tsv')).Hash
        $Result = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Bootstrap'; Date = [datetime]'2026-08-13T12:00:00' }
        $Repaired = @(Import-Csv -LiteralPath $PlansPath -Delimiter "`t" -Encoding UTF8 | Where-Object plan_item_id -eq $CompletedPlan.plan_item_id)[0]
        $Result.plan_state_reconciled | Should Be $true
        $Repaired.status | Should Be 'completed'
        $Repaired.completed_session_id | Should Be $CompletedPlan.completed_session_id
        (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'learner\review-history.tsv')).Hash | Should Be $HistoryHash
    }

    It 'uses the supplied Shanghai study date near midnight' {
        $Root = New-TrackerFixture
        $Result = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Summary'; Date = [datetime]'2026-07-24T00:01:00' }
        $Result.study_date | Should Be '2026-07-24'
        $Result.study_timezone | Should Be 'Asia/Shanghai'
    }

    It 'blocks a later item while another item is at the queue head' {
        $Root = New-TrackerFixture
        $Queue = @(Get-QueuedPlanItems -Root $Root)
        Assert-Throws { & $Tracker -ProjectRoot $Root -Action StartSession -PlanItemId $Queue[1].plan_item_id -Date ([datetime]'2026-07-30T12:00:00') }
        @(Get-ChildItem -LiteralPath (Join-Path $Root '.state') -File).Count | Should Be 0
    }

    It 'allows the review only after earlier training items are terminal' {
        $Root = New-TrackerFixture
        $QueueHead = @(Get-QueuedPlanItems -Root $Root)[0]
        $CycleRows = @(Import-Csv -LiteralPath (Join-Path $Root 'learner\plan-items.tsv') -Delimiter "`t" -Encoding UTF8 |
            Where-Object plan_id -eq $QueueHead.plan_id |
            Sort-Object { [int]$_.sequence })
        foreach ($Item in @($CycleRows | Where-Object { $_.session_type -ne 'review' -and $_.status -notin @('completed', 'cancelled') })) {
            [void](Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'CancelPlanItem'; PlanItemId = $Item.plan_item_id; CancelReason = 'test-only explicit cancellation'; Date = [datetime]'2026-07-30T12:00:00' })
        }
        $Result = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Bootstrap'; Date = [datetime]'2026-07-30T12:00:00' }
        $ExpectedReview = @($CycleRows | Where-Object session_type -eq 'review')[0]
        $Result.next_plan_item.plan_item_id | Should Be $ExpectedReview.plan_item_id
        @(Import-Csv -LiteralPath (Join-Path $Root 'learner\plan-events.tsv') -Delimiter "`t" -Encoding UTF8).Count | Should Be @($CycleRows | Where-Object { $_.session_type -ne 'review' -and $_.status -notin @('completed', 'cancelled') }).Count
    }
}

Describe 'Session lifecycle' {
    It 'creates a session stub before any review and resumes it through Bootstrap' {
        $Root = New-TrackerFixture
        $Expected = @(Get-QueuedPlanItems -Root $Root)[0]
        $BeforeCount = @(Get-ChildItem -LiteralPath (Join-Path $Root 'sessions\2026\07') -Filter '*.md').Count
        $Start = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'StartSession'; Date = [datetime]'2026-07-30T12:00:00' }
        $Start.plan_item_id | Should Be $Expected.plan_item_id
        Test-Path -LiteralPath (Join-Path $Root ([string]$Start.session_file).Replace('/', '\')) | Should Be $true
        $Resume = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Bootstrap'; Date = [datetime]'2026-07-30T12:01:00' }
        $Resume.status | Should Be 'resume'
        $Resume.checkpoint.session_id | Should Be $Start.session_id
        @(Get-ChildItem -LiteralPath (Join-Path $Root 'sessions\2026\07') -Filter '*.md').Count | Should Be ($BeforeCount + 1)
    }

    It 'rejects finalization before all stage checkpoints exist' {
        $Root = New-TrackerFixture
        $Start = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'StartSession'; Date = [datetime]'2026-07-30T12:00:00' }
        Assert-Throws { & $Tracker -ProjectRoot $Root -Action FinalizeSession -SessionId $Start.session_id -Date ([datetime]'2026-07-30T12:05:00') }
        $Plan = @(Import-Csv -LiteralPath (Join-Path $Root 'learner\plan-items.tsv') -Delimiter "`t" -Encoding UTF8 | Where-Object plan_item_id -eq $Start.plan_item_id)[0]
        $Plan.status | Should Be 'in_progress'
    }

    It 'finalizes a complete diagnostic and allocates a second same-day filename' {
        $Root = New-TrackerFixture
        $Queue = @(Get-QueuedPlanItems -Root $Root)
        $Start = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'StartSession'; Date = [datetime]'2026-07-30T12:00:00' }
        Save-RequiredCheckpoints -Root $Root -SessionId $Start.session_id
        Set-SessionCompleted -Root $Root -StartResult $Start
        Add-RawEvidence -Root $Root -SessionId $Start.session_id -Skill 'listening'
        $Final = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'FinalizeSession'; SessionId = $Start.session_id; Date = [datetime]'2026-07-30T12:10:00' }
        $Final.status | Should Be 'completed'
        $Final.archive.views_rebuilt | Should Be $true
        $Final.archive.validation_status | Should Be 'valid'
        $Final.archive.validation_errors | Should Be 0
        $Second = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'StartSession'; Date = [datetime]'2026-07-30T12:11:00' }
        $Second.plan_item_id | Should Be $Queue[1].plan_item_id
        ([string]$Second.session_file).EndsWith('2026-07-30-02.md') | Should Be $true
    }
}

Describe 'Review transactions' {
    It 'writes a valid batch once and Bootstrap recovery is idempotent' {
        $Root = New-TrackerFixture
        $Start = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'StartSession'; Date = [datetime]'2026-07-30T12:00:00' }
        $Before = @(Import-Csv -LiteralPath (Join-Path $Root 'learner\review-history.tsv') -Delimiter "`t" -Encoding UTF8).Count
        $ReviewsJson = @([pscustomobject]@{ collection = 'vocabulary'; id = 'V0001'; result = 'good' }) | ConvertTo-Json -Compress
        $Batch = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'ReviewBatch'; SessionId = $Start.session_id; ReviewsJson = $ReviewsJson; Date = [datetime]'2026-07-30T12:01:00' }
        $Batch.reviewed | Should Be 1
        $After = @(Import-Csv -LiteralPath (Join-Path $Root 'learner\review-history.tsv') -Delimiter "`t" -Encoding UTF8).Count
        $After | Should Be ($Before + 1)
        $TransactionPath = Join-Path $Root '.state\review-transaction.json'
        $Transaction = Get-Content -Raw -Encoding UTF8 -LiteralPath $TransactionPath | ConvertFrom-Json
        $Transaction.status = 'pending'
        $Utf8 = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($TransactionPath, ($Transaction | ConvertTo-Json -Depth 10), $Utf8)
        $Bootstrap = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Bootstrap'; Date = [datetime]'2026-07-30T12:02:00' }
        $Bootstrap.recovered_review_transaction | Should Be $true
        @(Import-Csv -LiteralPath (Join-Path $Root 'learner\review-history.tsv') -Delimiter "`t" -Encoding UTF8).Count | Should Be $After
    }

    It 'does not change history or item state when batch validation fails' {
        $Root = New-TrackerFixture
        $Start = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'StartSession'; Date = [datetime]'2026-07-30T12:00:00' }
        $HistoryHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'learner\review-history.tsv')).Hash
        $VocabHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'learner\vocabulary.tsv')).Hash
        $ReviewsJson = @([pscustomobject]@{ collection = 'vocabulary'; id = 'V0001'; result = 'good' }, [pscustomobject]@{ collection = 'error'; id = 'E9999'; result = 'again' }) | ConvertTo-Json -Compress
        Assert-Throws { & $Tracker -ProjectRoot $Root -Action ReviewBatch -SessionId $Start.session_id -ReviewsJson $ReviewsJson -Date ([datetime]'2026-07-30T12:01:00') }
        (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'learner\review-history.tsv')).Hash | Should Be $HistoryHash
        (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Root 'learner\vocabulary.tsv')).Hash | Should Be $VocabHash
        Test-Path -LiteralPath (Join-Path $Root '.state\review-transaction.json') | Should Be $false
    }
}

Describe 'Generated views and validation' {
    It 'rebuilds idempotently and does not report a completion rate' {
        $Root = New-TrackerFixture
        [void](Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Rebuild'; Date = [datetime]'2026-07-30T12:00:00' })
        $DashboardPath = Join-Path $Root 'learner\dashboard.md'; $PlanPath = Join-Path $Root 'learner\current-plan.md'; $ItemsPath = Join-Path $Root 'learner\plan-items.tsv'
        $First = @((Get-FileHash -Algorithm SHA256 -LiteralPath $DashboardPath).Hash, (Get-FileHash -Algorithm SHA256 -LiteralPath $PlanPath).Hash, (Get-FileHash -Algorithm SHA256 -LiteralPath $ItemsPath).Hash)
        [void](Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Rebuild'; Date = [datetime]'2026-07-30T12:00:00' })
        $Second = @((Get-FileHash -Algorithm SHA256 -LiteralPath $DashboardPath).Hash, (Get-FileHash -Algorithm SHA256 -LiteralPath $PlanPath).Hash, (Get-FileHash -Algorithm SHA256 -LiteralPath $ItemsPath).Hash)
        ($Second -join '|') | Should Be ($First -join '|')
        (Get-Content -Raw -Encoding UTF8 -LiteralPath $DashboardPath).Contains('完成率') | Should Be $false
        $Report = Invoke-TrackerJson -Root $Root -Arguments @{ Action = 'Validate'; Date = [datetime]'2026-07-30T12:00:00' }
        $Report.status | Should Be 'valid'
    }
}
