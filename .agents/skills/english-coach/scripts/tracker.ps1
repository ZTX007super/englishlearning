[CmdletBinding()]
param(
    [ValidateSet('Due', 'Review', 'ReviewBatch', 'Summary', 'Bootstrap', 'StartSession', 'Checkpoint', 'PrepareActivity', 'PrepareReviewQuestions', 'SaveReviewAnswer', 'SaveActivityCheckpoint', 'StageReviewBatch', 'FinalizeSession', 'CloseCheckpoint', 'AbandonSession', 'AbandonCheckpoint', 'CancelPlanItem', 'Rebuild', 'MonthlySummary', 'QuarterlySummary', 'EvaluateLongTermState', 'PublishCycle', 'MigrationPlan', 'ActivateV4', 'Validate')]
    [string]$Action = 'Due',
    [string]$ProjectRoot,
    [datetime]$Date,
    [ValidateSet('vocabulary', 'error')][string]$Collection,
    [string]$Id,
    [ValidateSet('again', 'hard', 'good', 'easy')][string]$Result,
    [string]$ReviewsJson,
    [string]$SessionId,
    [string]$PlanItemId,
    [ValidateSet('review', 'input', 'output', 'feedback', 'recording')][string]$Stage,
    [string]$PrimarySkill,
    [string]$SessionType,
    [ValidateSet('network', 'user-provided', 'fallback', 'none')][string]$SourceType = 'none',
    [int]$DurationMinutes,
    [string]$Note,
    [string]$CancelReason,
    [string]$PeriodKey,
    [string]$OwnerToken,
    [int]$ExpectedRevision = -1,
    [string]$IdempotencyKey,
    [string]$PayloadJson,
    [string]$FaultAfterPhase,
    [switch]$ConfirmActivation,
    [switch]$EnterSession,
    [switch]$IncludeAllDue
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..')).Path
}
else { $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path }

$V4OnlyActions = @('PrepareActivity','PrepareReviewQuestions','SaveReviewAnswer','SaveActivityCheckpoint','StageReviewBatch','EvaluateLongTermState','PublishCycle','MigrationPlan','ActivateV4')
$V4SharedActions = @('Bootstrap','StartSession','FinalizeSession','AbandonSession','Validate')
$RuntimePointerPath = Join-Path $ProjectRoot '.state\runtime.json'
$MigrationPointerPath = Join-Path $ProjectRoot '.state\migration-v4-transaction.json'
$V4StateExists = (Test-Path -LiteralPath $RuntimePointerPath -PathType Leaf) -or
    (Test-Path -LiteralPath $MigrationPointerPath -PathType Leaf)
if ($Action -in $V4OnlyActions -or ($V4StateExists -and $Action -in $V4SharedActions)) {
    $V4Tracker = Join-Path $PSScriptRoot 'tracker-v4.ps1'
    $V4Arguments = @{
        Action = $Action
        ProjectRoot = $ProjectRoot
        SessionId = $SessionId
        PlanItemId = $PlanItemId
        OwnerToken = $OwnerToken
        ExpectedRevision = $ExpectedRevision
        IdempotencyKey = $IdempotencyKey
        PayloadJson = $PayloadJson
        SourceType = $SourceType
        FaultAfterPhase = $FaultAfterPhase
        ConfirmActivation = $ConfirmActivation
        EnterSession = $EnterSession
    }
    if ($PSBoundParameters.ContainsKey('Date')) { $V4Arguments.Date = $Date }
    & $V4Tracker @V4Arguments
    return
}
if ($V4StateExists) {
    throw "Action $Action uses the legacy v3 interface and is unavailable while a v4 migration/runtime pointer exists. Run Bootstrap for the allowed next action."
}

$SettingsPath = Join-Path $ProjectRoot 'learner\settings.json'
$VocabularyPath = Join-Path $ProjectRoot 'learner\vocabulary.tsv'
$ErrorLogPath = Join-Path $ProjectRoot 'learner\error-log.tsv'
$ReviewHistoryPath = Join-Path $ProjectRoot 'learner\review-history.tsv'
$PlanItemsPath = Join-Path $ProjectRoot 'learner\plan-items.tsv'
$PlanEventsPath = Join-Path $ProjectRoot 'learner\plan-events.tsv'
$EvidencePath = Join-Path $ProjectRoot 'learner\skill-evidence.tsv'
$DashboardPath = Join-Path $ProjectRoot 'learner\dashboard.md'
$CurrentPlanPath = Join-Path $ProjectRoot 'learner\current-plan.md'
$SessionPath = Join-Path $ProjectRoot 'sessions'
$SummaryPath = Join-Path $ProjectRoot 'learner\summaries'
$CheckpointPath = Join-Path $ProjectRoot '.state\current-session.json'
$ReviewTransactionPath = Join-Path $ProjectRoot '.state\review-transaction.json'
$Intervals = @(1, 3, 7, 14, 30, 60)
$RequiredStages = @('review', 'input', 'output', 'feedback')
$NormalReviewLimit = 6

$VocabularyHeaders = @('id', 'item', 'meaning', 'context', 'status', 'level', 'next_review', 'last_review', 'source_session')
$ErrorHeaders = @('id', 'category', 'original', 'corrected', 'explanation', 'status', 'level', 'next_review', 'last_review', 'source_session')
$ReviewHeaders = @('event_id', 'reviewed_at', 'study_date', 'session_id', 'item_type', 'item_id', 'result', 'old_level', 'new_level', 'previous_due', 'next_review')
$PlanHeaders = @('plan_item_id', 'plan_id', 'sequence', 'title', 'session_type', 'primary_skill', 'required', 'status', 'completed_session_id')
$PlanEventHeaders = @('event_id', 'occurred_at', 'study_date', 'plan_item_id', 'event', 'reason')
$EvidenceHeaders = @('evidence_id', 'session_id', 'skill', 'phase', 'metric', 'score', 'scale', 'evidence', 'next_focus')
$SupportsJsonDateKind = (Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')

function ConvertFrom-StableJson {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    if ($script:SupportsJsonDateKind) { return ($Text | ConvertFrom-Json -DateKind String) }
    return ($Text | ConvertFrom-Json)
}

function Write-AtomicText {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $Directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $Directory) }
    $TemporaryPath = Join-Path $Directory ((Split-Path -Leaf $Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $Utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($TemporaryPath, $Text, $Utf8)
    Move-Item -LiteralPath $TemporaryPath -Destination $Path -Force
}

function Get-TableRows {
    param([string]$Path, [string[]]$RequiredHeaders)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing data file: $Path" }
    $HeaderLine = Get-Content -LiteralPath $Path -Encoding UTF8 -TotalCount 1
    if ([string]::IsNullOrWhiteSpace($HeaderLine)) { throw "Empty data file: $Path" }
    $ActualHeaders = @(($HeaderLine -split "`t") | ForEach-Object { $_.Trim().Trim('"') })
    if (($ActualHeaders -join '|') -ne ($RequiredHeaders -join '|')) { throw "Unexpected headers in $Path. Expected: $($RequiredHeaders -join ', ')" }
    return @(Import-Csv -LiteralPath $Path -Delimiter "`t" -Encoding UTF8)
}

function Write-TableRows {
    param([string]$Path, [object[]]$Rows, [string[]]$Headers)
    $Rows = @($Rows)
    if ($Rows.Count -eq 0) { Write-AtomicText -Path $Path -Text (($Headers -join "`t") + "`r`n"); return }
    $Directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $Directory) }
    $TemporaryPath = Join-Path $Directory ((Split-Path -Leaf $Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $Rows | Select-Object -Property $Headers | Export-Csv -LiteralPath $TemporaryPath -Delimiter "`t" -Encoding UTF8 -NoTypeInformation
    Move-Item -LiteralPath $TemporaryPath -Destination $Path -Force
}

function Add-TableRow {
    param([string]$Path, [object]$Row, [string[]]$Headers)
    $Values = @()
    foreach ($Header in $Headers) {
        $Value = [string]$Row.$Header
        if ($Value.Contains("`t") -or $Value.Contains("`r") -or $Value.Contains("`n")) { throw "Value for $Header contains a forbidden control character." }
        $Values += $Value
    }
    $Utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::AppendAllText($Path, (($Values -join "`t") + "`r`n"), $Utf8)
}

function Test-DateValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    try { [void][datetime]::ParseExact($Value, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture); return $true }
    catch { return $false }
}

function Test-StudyTimestamp {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $Parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$Parsed)) { return $false }
    return $Parsed.Offset -eq [TimeSpan]::FromHours(8)
}

function Get-StudyTimestamp {
    $Offset = $script:StudyTimeZone.GetUtcOffset($script:StudyNow)
    $Unspecified = [DateTime]::SpecifyKind($script:StudyNow, [DateTimeKind]::Unspecified)
    return ([DateTimeOffset]::new($Unspecified, $Offset)).ToString('yyyy-MM-ddTHH:mm:sszzz')
}

function Get-Frontmatter {
    param([string]$Path)
    $Lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $Metadata = @{}
    if ($Lines.Count -lt 3 -or $Lines[0].Trim() -ne '---') { return $Metadata }
    for ($Index = 1; $Index -lt $Lines.Count; $Index++) {
        if ($Lines[$Index].Trim() -eq '---') { break }
        $Separator = $Lines[$Index].IndexOf(':')
        if ($Separator -gt 0) { $Metadata[$Lines[$Index].Substring(0, $Separator).Trim()] = $Lines[$Index].Substring($Separator + 1).Trim() }
    }
    return $Metadata
}

function Get-SessionRecords {
    $Records = @()
    if (-not (Test-Path -LiteralPath $SessionPath -PathType Container)) { return $Records }
    foreach ($File in @(Get-ChildItem -LiteralPath $SessionPath -Recurse -File -Filter '*.md')) {
        $Records += [pscustomobject]@{
            File = $File
            RelativeFile = $File.FullName.Substring($ProjectRoot.Length + 1).Replace('\', '/')
            Meta = Get-Frontmatter -Path $File.FullName
            Content = Get-Content -Raw -Encoding UTF8 -LiteralPath $File.FullName
        }
    }
    return @($Records)
}

function Read-AllData {
    $script:Vocabulary = @(Get-TableRows -Path $VocabularyPath -RequiredHeaders $VocabularyHeaders)
    $script:Errors = @(Get-TableRows -Path $ErrorLogPath -RequiredHeaders $ErrorHeaders)
    $script:ReviewHistory = @(Get-TableRows -Path $ReviewHistoryPath -RequiredHeaders $ReviewHeaders)
    $script:Plans = @(Get-TableRows -Path $PlanItemsPath -RequiredHeaders $PlanHeaders)
    $script:PlanEvents = @(Get-TableRows -Path $PlanEventsPath -RequiredHeaders $PlanEventHeaders)
    $script:Evidence = @(Get-TableRows -Path $EvidencePath -RequiredHeaders $EvidenceHeaders)
    $script:Sessions = @(Get-SessionRecords)
}

function Get-DueRows {
    param([object[]]$Rows)
    return @($Rows | Where-Object {
        $_.status -eq 'active' -and (Test-DateValue $_.next_review) -and
        ([datetime]::ParseExact($_.next_review, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)).Date -le $script:StudyDate
    } | Sort-Object next_review, id)
}

function Get-DueSelection {
    param(
        [object[]]$VocabularyRows,
        [object[]]$ErrorRows,
        [int]$Limit,
        [switch]$IncludeAll
    )
    $DueVocabulary = @(Get-DueRows -Rows $VocabularyRows)
    $DueErrors = @(Get-DueRows -Rows $ErrorRows)
    $Tagged = @(
        @($DueVocabulary | ForEach-Object { [pscustomobject]@{ collection = 'vocabulary'; row = $_ } }) +
        @($DueErrors | ForEach-Object { [pscustomobject]@{ collection = 'error'; row = $_ } })
    )
    $Ordered = @($Tagged | Sort-Object @{ Expression = { $_.row.next_review }; Ascending = $true }, @{ Expression = { [int]$_.row.level }; Ascending = $true }, @{ Expression = { $_.row.id }; Ascending = $true })
    $Selected = if ($IncludeAll) { $Ordered } else { @($Ordered | Select-Object -First $Limit) }
    return [pscustomobject]@{
        vocabulary_count = $DueVocabulary.Count
        error_count = $DueErrors.Count
        total_count = $DueVocabulary.Count + $DueErrors.Count
        vocabulary = @($Selected | Where-Object collection -eq 'vocabulary' | ForEach-Object { $_.row })
        errors = @($Selected | Where-Object collection -eq 'error' | ForEach-Object { $_.row })
        selected_count = @($Selected).Count
        truncated = (-not $IncludeAll -and @($Selected).Count -lt ($DueVocabulary.Count + $DueErrors.Count))
    }
}

function Get-CurrentCycleRows {
    param([object[]]$PlanRows)
    $Ordered = @($PlanRows | Sort-Object plan_id, { [int]$_.sequence })
    $Open = @($Ordered | Where-Object { $_.status -in @('planned', 'in_progress') } | Select-Object -First 1)
    if ($Open.Count -eq 1) { $PlanId = $Open[0].plan_id }
    elseif ($Ordered.Count -gt 0) { $PlanId = $Ordered[-1].plan_id }
    else { return @() }
    return @($Ordered | Where-Object { $_.plan_id -eq $PlanId } | Sort-Object { [int]$_.sequence })
}

function Get-NextPlanItem {
    param([object[]]$PlanRows)
    return @(Get-CurrentCycleRows -PlanRows $PlanRows | Where-Object { $_.status -in @('planned', 'in_progress') } | Select-Object -First 1)
}

function Sync-PlanState {
    param([object[]]$PlanRows, [object[]]$SessionRows)
    $CompletedByPlan = @{}
    $AbandonedByPlan = @{}
    foreach ($Session in $SessionRows) {
        if (-not $Session.Meta.ContainsKey('plan_item_id') -or $Session.Meta.plan_item_id -eq 'none') { continue }
        if ($Session.Meta.ContainsKey('status') -and $Session.Meta.status -eq 'completed') { $CompletedByPlan[$Session.Meta.plan_item_id] = $Session }
        if ($Session.Meta.ContainsKey('status') -and $Session.Meta.status -eq 'abandoned') { $AbandonedByPlan[$Session.Meta.plan_item_id] = $Session }
    }
    foreach ($Plan in $PlanRows) {
        if ($CompletedByPlan.ContainsKey($Plan.plan_item_id)) {
            $Plan.status = 'completed'; $Plan.completed_session_id = $CompletedByPlan[$Plan.plan_item_id].Meta.session_id
        }
        elseif ($AbandonedByPlan.ContainsKey($Plan.plan_item_id) -and $Plan.status -eq 'in_progress') {
            $Plan.status = 'planned'; $Plan.completed_session_id = ''
        }
    }
    return @($PlanRows)
}

function Replace-MarkedBlock {
    param([string]$Path, [string]$StartMarker, [string]$EndMarker, [string]$Body)
    $Content = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
    $StartIndex = $Content.IndexOf($StartMarker); $EndIndex = $Content.IndexOf($EndMarker)
    if ($StartIndex -lt 0 -or $EndIndex -lt $StartIndex) { throw "Missing generated block markers in $Path" }
    $Replacement = $StartMarker + "`r`n" + $Body.TrimEnd() + "`r`n" + $EndMarker
    Write-AtomicText -Path $Path -Text ($Content.Substring(0, $StartIndex) + $Replacement + $Content.Substring($EndIndex + $EndMarker.Length))
}

function Get-Metrics {
    param([object[]]$VocabularyRows, [object[]]$ErrorRows, [object[]]$PlanRows, [object[]]$SessionRows)
    $Completed = @()
    foreach ($Session in $SessionRows) {
        if ($Session.Meta.ContainsKey('status') -and $Session.Meta.status -eq 'completed' -and $Session.Meta.ContainsKey('date') -and (Test-DateValue $Session.Meta.date)) { $Completed += $Session }
    }
    $Dates = @{}
    $Minutes14 = 0; $Minutes28 = 0; $Sessions14 = 0; $Sessions28 = 0
    $Start14 = $script:StudyDate.AddDays(-13); $Start28 = $script:StudyDate.AddDays(-27)
    foreach ($Session in $Completed) {
        $SessionDate = [datetime]::ParseExact($Session.Meta.date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date
        if ($SessionDate -le $script:StudyDate) { $Dates[$Session.Meta.date] = $true }
        $Minutes = 0
        if ($Session.Meta.ContainsKey('duration_minutes') -and $Session.Meta.duration_minutes -match '^\d+$') { $Minutes = [int]$Session.Meta.duration_minutes }
        if ($SessionDate -ge $Start14 -and $SessionDate -le $script:StudyDate) { $Sessions14++; $Minutes14 += $Minutes }
        if ($SessionDate -ge $Start28 -and $SessionDate -le $script:StudyDate) { $Sessions28++; $Minutes28 += $Minutes }
    }
    $Streak = 0; $Cursor = $script:StudyDate
    if (-not $Dates.ContainsKey($Cursor.ToString('yyyy-MM-dd'))) { $Cursor = $Cursor.AddDays(-1) }
    while ($Dates.ContainsKey($Cursor.ToString('yyyy-MM-dd'))) { $Streak++; $Cursor = $Cursor.AddDays(-1) }
    $Last = @($Completed | Where-Object {
        [datetime]::ParseExact($_.Meta.date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -le $script:StudyDate
    } | Sort-Object { [datetime]::ParseExact($_.Meta.date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) } | Select-Object -Last 1)
    $Gap = $null
    if ($Last.Count -eq 1) { $Gap = [int]($script:StudyDate - [datetime]::ParseExact($Last[0].Meta.date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date).TotalDays }
    $CycleRows = @(Get-CurrentCycleRows -PlanRows $PlanRows)
    $Next = @(Get-NextPlanItem -PlanRows $PlanRows)
    $CycleCompleted = @($CycleRows | Where-Object { $_.status -eq 'completed' }).Count
    $CycleCancelled = @($CycleRows | Where-Object { $_.status -eq 'cancelled' }).Count
    return [pscustomobject]@{
        study_date = $script:StudyDate.ToString('yyyy-MM-dd'); study_timezone = [string]$script:Settings.study_timezone
        study_days_14d = @($Dates.Keys | Where-Object { [datetime]::ParseExact($_, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) -ge $Start14 }).Count
        completed_sessions_14d = $Sessions14; total_minutes_14d = $Minutes14
        completed_sessions_28d = $Sessions28; total_minutes_28d = $Minutes28; streak_days = $Streak
        days_since_last_session = $Gap; recovery_mode = ($null -ne $Gap -and $Gap -ge [int]$script:Settings.recovery_gap_days)
        current_cycle = $(if ($CycleRows.Count -gt 0) { $CycleRows[0].plan_id } else { '' })
        cycle_completed = $CycleCompleted; cycle_cancelled = $CycleCancelled; cycle_total = $CycleRows.Count
        next_plan_item_id = $(if ($Next.Count -eq 1) { $Next[0].plan_item_id } else { '' })
        next_title = $(if ($Next.Count -eq 1) { $Next[0].title } else { '' })
        due_vocabulary = @(Get-DueRows -Rows $VocabularyRows).Count; due_errors = @(Get-DueRows -Rows $ErrorRows).Count
    }
}

function Get-DashboardBlock {
    param([object]$Metrics)
    $GapText = if ($null -eq $Metrics.days_since_last_session) { '尚无记录' } else { "$($Metrics.days_since_last_session) 天" }
    $RecoveryText = if ($Metrics.recovery_mode) { '是（先复习最多 10 项，新词最多 3 个）' } else { '否' }
    $NextText = if ([string]::IsNullOrWhiteSpace($Metrics.next_plan_item_id)) { '本轮已结束' } else { "$($Metrics.next_plan_item_id) — $($Metrics.next_title)" }
    return @(
        "- 自动统计日期：$($Metrics.study_date)（$($Metrics.study_timezone)）",
        "- 连续学习：$($Metrics.streak_days) 天",
        "- 距上次学习：$GapText",
        "- 最近 14 天：$($Metrics.study_days_14d) 个学习日 / $($Metrics.completed_sessions_14d) 课次 / $($Metrics.total_minutes_14d) 分钟",
        "- 最近 28 天：$($Metrics.completed_sessions_28d) 课次 / $($Metrics.total_minutes_28d) 分钟",
        "- 当前轮次：$($Metrics.current_cycle)；已完成 $($Metrics.cycle_completed)，已取消 $($Metrics.cycle_cancelled)，共 $($Metrics.cycle_total) 项",
        "- 下一项：$NextText",
        "- 恢复模式：$RecoveryText",
        "- 到期词汇：$($Metrics.due_vocabulary)",
        "- 到期错误：$($Metrics.due_errors)"
    ) -join "`r`n"
}

function Get-PlanBlock {
    param([object[]]$PlanRows)
    $Rows = @(Get-CurrentCycleRows -PlanRows $PlanRows)
    if ($Rows.Count -eq 0) { return "| 轮次 | 顺序 | 内容 | 类型 | 状态 |`r`n| --- | ---: | --- | --- | --- |" }
    $Next = @(Get-NextPlanItem -PlanRows $PlanRows)
    $Labels = @{ planned = '待开始'; in_progress = '进行中'; completed = '已完成'; cancelled = '已取消' }
    $Lines = @('| 轮次 | 顺序 | 内容 | 类型 | 状态 |', '| --- | ---: | --- | --- | --- |')
    foreach ($Row in $Rows) {
        $Label = if ($Labels.ContainsKey($Row.status)) { $Labels[$Row.status] } else { $Row.status }
        if ($Row.status -eq 'completed' -and -not [string]::IsNullOrWhiteSpace($Row.completed_session_id)) { $Label += "（$($Row.completed_session_id)）" }
        if ($Next.Count -eq 1 -and $Row.plan_item_id -eq $Next[0].plan_item_id) { $Label += ' ← 下一项' }
        $Lines += "| $($Row.plan_id) | $($Row.sequence) | $($Row.title) | $($Row.session_type) | $Label |"
    }
    return $Lines -join "`r`n"
}

function Complete-ReviewTransaction {
    if (-not (Test-Path -LiteralPath $ReviewTransactionPath -PathType Leaf)) { return $false }
    $Transaction = ConvertFrom-StableJson -Text (Get-Content -Raw -Encoding UTF8 -LiteralPath $ReviewTransactionPath)
    if ($Transaction.status -eq 'completed') { return $false }
    if ($Transaction.status -ne 'pending') { throw 'Review transaction has an unknown status.' }
    $KnownEvents = @{}
    foreach ($Event in @(Get-TableRows -Path $ReviewHistoryPath -RequiredHeaders $ReviewHeaders)) { $KnownEvents[$Event.event_id] = $true }
    foreach ($Event in @($Transaction.events)) {
        if (-not $KnownEvents.ContainsKey([string]$Event.event_id)) { Add-TableRow -Path $ReviewHistoryPath -Row $Event -Headers $ReviewHeaders; $KnownEvents[[string]$Event.event_id] = $true }
    }
    $VocabRows = @(Get-TableRows -Path $VocabularyPath -RequiredHeaders $VocabularyHeaders)
    $ErrorRows = @(Get-TableRows -Path $ErrorLogPath -RequiredHeaders $ErrorHeaders)
    foreach ($Update in @($Transaction.updates)) {
        $TargetRows = if ($Update.collection -eq 'vocabulary') { $VocabRows } else { $ErrorRows }
        $Target = @($TargetRows | Where-Object { $_.id -eq $Update.id })
        if ($Target.Count -ne 1) { throw "Cannot recover review transaction: missing item $($Update.id)." }
        $Target[0].level = [string]$Update.new_level; $Target[0].last_review = [string]$Update.study_date; $Target[0].next_review = [string]$Update.next_review
    }
    Write-TableRows -Path $VocabularyPath -Rows $VocabRows -Headers $VocabularyHeaders
    Write-TableRows -Path $ErrorLogPath -Rows $ErrorRows -Headers $ErrorHeaders
    $Transaction.status = 'completed'
    $Transaction | Add-Member -NotePropertyName completed_at -NotePropertyValue (Get-StudyTimestamp) -Force
    Write-AtomicText -Path $ReviewTransactionPath -Text ($Transaction | ConvertTo-Json -Depth 10)
    return $true
}

function Invoke-ReviewBatch {
    param([object[]]$Reviews, [string]$ForSessionId)
    if ([string]::IsNullOrWhiteSpace($ForSessionId)) { throw 'ReviewBatch requires -SessionId.' }
    $KnownSession = @($script:Sessions | Where-Object { $_.Meta.ContainsKey('session_id') -and $_.Meta.session_id -eq $ForSessionId })
    if ($KnownSession.Count -ne 1) { throw "ReviewBatch requires one existing session: $ForSessionId" }
    if (@($Reviews).Count -eq 0) { return [pscustomobject]@{ status = 'completed'; reviewed = 0; session_id = $ForSessionId } }
    $Seen = @{}; $Updates = @(); $Events = @(); $Timestamp = Get-StudyTimestamp
    foreach ($Review in @($Reviews)) {
        $ReviewCollection = [string]$Review.collection; $ReviewId = [string]$Review.id; $ReviewResult = [string]$Review.result
        if ($ReviewCollection -notin @('vocabulary', 'error')) { throw "Invalid review collection: $ReviewCollection" }
        if ($ReviewResult -notin @('again', 'hard', 'good', 'easy')) { throw "Invalid review result: $ReviewResult" }
        $Key = "$ReviewCollection|$ReviewId"
        if ($Seen.ContainsKey($Key)) { throw "ReviewBatch contains a duplicate item: $Key" }; $Seen[$Key] = $true
        $Rows = if ($ReviewCollection -eq 'vocabulary') { $script:Vocabulary } else { $script:Errors }
        $Match = @($Rows | Where-Object { $_.id -eq $ReviewId })
        if ($Match.Count -ne 1) { throw "Expected exactly one item with ID $ReviewId in $ReviewCollection." }
        $Item = $Match[0]; $OldLevel = [Math]::Max(0, [Math]::Min(5, [int]$Item.level))
        switch ($ReviewResult) { 'again' { $NewLevel = 0 }; 'hard' { $NewLevel = $OldLevel }; 'good' { $NewLevel = [Math]::Min(5, $OldLevel + 1) }; 'easy' { $NewLevel = [Math]::Min(5, $OldLevel + 2) } }
        $NextReview = $script:StudyDate.AddDays($Intervals[$NewLevel]).ToString('yyyy-MM-dd')
        $Event = [pscustomobject]@{ event_id = ('R' + [guid]::NewGuid().ToString('N')); reviewed_at = $Timestamp; study_date = $script:StudyDate.ToString('yyyy-MM-dd'); session_id = $ForSessionId; item_type = $ReviewCollection; item_id = $ReviewId; result = $ReviewResult; old_level = [string]$OldLevel; new_level = [string]$NewLevel; previous_due = [string]$Item.next_review; next_review = $NextReview }
        $Events += $Event
        $Updates += [pscustomobject]@{ collection = $ReviewCollection; id = $ReviewId; new_level = [string]$NewLevel; study_date = $script:StudyDate.ToString('yyyy-MM-dd'); next_review = $NextReview }
    }
    $Transaction = [pscustomobject]@{ schema_version = 1; status = 'pending'; batch_id = ('B' + [guid]::NewGuid().ToString('N')); session_id = $ForSessionId; created_at = $Timestamp; updates = $Updates; events = $Events }
    Write-AtomicText -Path $ReviewTransactionPath -Text ($Transaction | ConvertTo-Json -Depth 10)
    [void](Complete-ReviewTransaction)
    Read-AllData
    return [pscustomobject]@{ status = 'completed'; reviewed = $Events.Count; session_id = $ForSessionId; batch_id = $Transaction.batch_id }
}

function Invoke-Rebuild {
    [void](Complete-ReviewTransaction)
    Read-AllData
    $script:Plans = @(Sync-PlanState -PlanRows $script:Plans -SessionRows $script:Sessions)
    Write-TableRows -Path $PlanItemsPath -Rows $script:Plans -Headers $PlanHeaders
    $Metrics = Get-Metrics -VocabularyRows $script:Vocabulary -ErrorRows $script:Errors -PlanRows $script:Plans -SessionRows $script:Sessions
    Replace-MarkedBlock -Path $DashboardPath -StartMarker '<!-- AUTO:METRICS:START -->' -EndMarker '<!-- AUTO:METRICS:END -->' -Body (Get-DashboardBlock -Metrics $Metrics)
    Replace-MarkedBlock -Path $CurrentPlanPath -StartMarker '<!-- AUTO:PLAN:START -->' -EndMarker '<!-- AUTO:PLAN:END -->' -Body (Get-PlanBlock -PlanRows $script:Plans)
    $Dashboard = Get-Content -Raw -Encoding UTF8 -LiteralPath $DashboardPath
    $Dashboard = [regex]::Replace($Dashboard, '(?m)^- 最后更新：.*$', ('- 最后更新：' + $script:StudyDate.ToString('yyyy-MM-dd')), 1)
    Write-AtomicText -Path $DashboardPath -Text $Dashboard
    $Status = if (@($script:Plans | Where-Object { $_.status -in @('planned', 'in_progress') }).Count -gt 0) { '进行中' } else { '已完成' }
    $PlanDocument = Get-Content -Raw -Encoding UTF8 -LiteralPath $CurrentPlanPath
    $PlanDocument = [regex]::Replace($PlanDocument, '(?m)^- 状态：.*$', ('- 状态：' + $Status), 1)
    Write-AtomicText -Path $CurrentPlanPath -Text $PlanDocument
    return $Metrics
}

function Get-ValidationReport {
    $ValidationErrors = New-Object System.Collections.Generic.List[string]
    $ValidationWarnings = New-Object System.Collections.Generic.List[string]
    if ([string]$script:Settings.study_timezone -ne 'Asia/Shanghai') { $ValidationErrors.Add('settings.json study_timezone must be Asia/Shanghai.') }
    if ([string]$script:Settings.windows_timezone_id -ne 'China Standard Time') { $ValidationErrors.Add('settings.json windows_timezone_id must be China Standard Time.') }
    if ([int]$script:Settings.schema_version -lt 3) { $ValidationErrors.Add('settings.json schema_version must be at least 3.') }
    if ([string]$script:Settings.schedule_mode -ne 'queue') { $ValidationErrors.Add('settings.json schedule_mode must be queue.') }
    foreach ($Name in @('daily_target_minutes', 'progress_window_days', 'training_sessions_per_cycle', 'recovery_gap_days')) {
        if ([string]$script:Settings.$Name -notmatch '^\d+$' -or [int]$script:Settings.$Name -lt 1) { $ValidationErrors.Add("settings.json $Name must be a positive integer.") }
    }
    foreach ($Definition in @(
        [pscustomobject]@{ Label = 'Vocabulary'; Rows = $script:Vocabulary; Id = 'id' },
        [pscustomobject]@{ Label = 'Error log'; Rows = $script:Errors; Id = 'id' },
        [pscustomobject]@{ Label = 'Review history'; Rows = $script:ReviewHistory; Id = 'event_id' },
        [pscustomobject]@{ Label = 'Plan items'; Rows = $script:Plans; Id = 'plan_item_id' },
        [pscustomobject]@{ Label = 'Plan events'; Rows = $script:PlanEvents; Id = 'event_id' },
        [pscustomobject]@{ Label = 'Skill evidence'; Rows = $script:Evidence; Id = 'evidence_id' }
    )) {
        $Duplicates = @($Definition.Rows | Group-Object -Property $Definition.Id | Where-Object { $_.Count -gt 1 -or [string]::IsNullOrWhiteSpace($_.Name) })
        if ($Duplicates.Count -gt 0) { $ValidationErrors.Add("$($Definition.Label) contains duplicate or empty IDs: $($Duplicates.Name -join ', ')") }
    }
    foreach ($Row in @($script:Vocabulary) + @($script:Errors)) {
        if ($Row.status -notin @('active', 'mastered', 'paused')) { $ValidationErrors.Add("Invalid item status for $($Row.id): $($Row.status)") }
        if ($Row.level -notmatch '^\d+$' -or [int]$Row.level -lt 0 -or [int]$Row.level -gt 5) { $ValidationErrors.Add("Invalid level for $($Row.id): $($Row.level)") }
        foreach ($Value in @($Row.next_review, $Row.last_review)) { if (-not [string]::IsNullOrWhiteSpace($Value) -and -not (Test-DateValue $Value)) { $ValidationErrors.Add("Invalid date for $($Row.id): $Value") } }
    }
    $SessionById = @{}; $PlanById = @{}
    foreach ($Plan in $script:Plans) { $PlanById[$Plan.plan_item_id] = $Plan }
    $RequiredSessionFields = @('session_id', 'date', 'plan_item_id', 'session_type', 'status', 'duration_minutes', 'primary_skill', 'study_timezone', 'source_type')
    foreach ($Session in $script:Sessions) {
        foreach ($Field in $RequiredSessionFields) { if (-not $Session.Meta.ContainsKey($Field) -or [string]::IsNullOrWhiteSpace([string]$Session.Meta[$Field])) { $ValidationErrors.Add("$($Session.RelativeFile) is missing frontmatter field: $Field") } }
        if (-not $Session.Meta.ContainsKey('session_id')) { continue }
        $CurrentId = [string]$Session.Meta.session_id
        if ($SessionById.ContainsKey($CurrentId)) { $ValidationErrors.Add("Duplicate session_id: $CurrentId") } else { $SessionById[$CurrentId] = $Session }
        if ($Session.Meta.ContainsKey('date') -and -not (Test-DateValue $Session.Meta.date)) { $ValidationErrors.Add("Invalid session date in $($Session.RelativeFile): $($Session.Meta.date)") }
        if ($Session.Meta.ContainsKey('status') -and $Session.Meta.status -notin @('in_progress', 'completed', 'abandoned')) { $ValidationErrors.Add("Invalid session status in $($Session.RelativeFile): $($Session.Meta.status)") }
        if ($Session.Meta.ContainsKey('session_type') -and $Session.Meta.session_type -notin @('daily', 'diagnostic', 'review', 'assessment', 'extra')) { $ValidationErrors.Add("Invalid session_type in $($Session.RelativeFile): $($Session.Meta.session_type)") }
        if ($Session.Meta.ContainsKey('primary_skill') -and $Session.Meta.primary_skill -notin @('listening', 'speaking', 'reading', 'writing', 'mixed', 'review')) { $ValidationErrors.Add("Invalid primary_skill in $($Session.RelativeFile): $($Session.Meta.primary_skill)") }
        if ($Session.Meta.ContainsKey('source_type') -and $Session.Meta.source_type -notin @('network', 'user-provided', 'fallback', 'none')) { $ValidationErrors.Add("Invalid source_type in $($Session.RelativeFile): $($Session.Meta.source_type)") }
        if ($Session.Meta.ContainsKey('study_timezone') -and $Session.Meta.study_timezone -ne [string]$script:Settings.study_timezone) { $ValidationErrors.Add("Timezone mismatch in $($Session.RelativeFile)") }
        if ($Session.Meta.ContainsKey('duration_minutes') -and $Session.Meta.duration_minutes -notmatch '^\d+$') { $ValidationErrors.Add("Invalid duration_minutes in $($Session.RelativeFile)") }
        if ($Session.Meta.ContainsKey('plan_item_id') -and $Session.Meta.plan_item_id -ne 'none' -and -not $PlanById.ContainsKey($Session.Meta.plan_item_id)) { $ValidationErrors.Add("Unknown plan_item_id in $($Session.RelativeFile): $($Session.Meta.plan_item_id)") }
        if ($Session.Meta.ContainsKey('source_type') -and $Session.Meta.source_type -eq 'network' -and $Session.Content -notmatch '(?m)^- URL：https?://') { $ValidationWarnings.Add("Network session lacks a recognizable URL line: $($Session.RelativeFile)") }
        if ($Session.Meta.ContainsKey('date') -and (Test-DateValue $Session.Meta.date)) { $Expected = 'sessions/' + $Session.Meta.date.Substring(0, 4) + '/' + $Session.Meta.date.Substring(5, 2) + '/'; if (-not $Session.RelativeFile.StartsWith($Expected)) { $ValidationErrors.Add("Session path does not match its date: $($Session.RelativeFile)") } }
    }
    foreach ($Plan in $script:Plans) {
        if ($Plan.required -notin @('true', 'false')) { $ValidationErrors.Add("Invalid required value for $($Plan.plan_item_id)") }
        if ($Plan.status -notin @('planned', 'in_progress', 'completed', 'cancelled')) { $ValidationErrors.Add("Invalid plan status for $($Plan.plan_item_id): $($Plan.status)") }
        if ($Plan.sequence -notmatch '^\d+$' -or [int]$Plan.sequence -lt 1) { $ValidationErrors.Add("Invalid sequence for $($Plan.plan_item_id)") }
        if ($Plan.status -eq 'completed') {
            if ([string]::IsNullOrWhiteSpace($Plan.completed_session_id) -or -not $SessionById.ContainsKey($Plan.completed_session_id)) { $ValidationErrors.Add("Completed plan item lacks a valid session: $($Plan.plan_item_id)") }
            elseif ($SessionById[$Plan.completed_session_id].Meta.plan_item_id -ne $Plan.plan_item_id) { $ValidationErrors.Add("Plan/session mismatch for $($Plan.plan_item_id)") }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($Plan.completed_session_id)) { $ValidationErrors.Add("Non-completed plan item has a completed_session_id: $($Plan.plan_item_id)") }
    }
    foreach ($Group in @($script:Plans | Group-Object plan_id)) {
        $DuplicateSequence = @($Group.Group | Group-Object sequence | Where-Object { $_.Count -gt 1 })
        if ($DuplicateSequence.Count -gt 0) { $ValidationErrors.Add("Cycle $($Group.Name) contains duplicate sequence numbers.") }
        $ReviewRows = @($Group.Group | Where-Object { $_.session_type -eq 'review' })
        if ($ReviewRows.Count -ne 1) { $ValidationErrors.Add("Cycle $($Group.Name) must contain exactly one review item.") }
        elseif ([int]$ReviewRows[0].sequence -ne ([int]$script:Settings.training_sessions_per_cycle + 1)) { $ValidationErrors.Add("Cycle $($Group.Name) review must follow the configured training sessions.") }
    }
    $InProgressPlans = @($script:Plans | Where-Object { $_.status -eq 'in_progress' })
    if ($InProgressPlans.Count -gt 1) { $ValidationErrors.Add('Only one queued plan item may be in progress.') }
    foreach ($ActivePlan in $InProgressPlans) {
        $ActiveSessions = @($script:Sessions | Where-Object { $_.Meta.ContainsKey('status') -and $_.Meta.status -eq 'in_progress' -and $_.Meta.plan_item_id -eq $ActivePlan.plan_item_id })
        if ($ActiveSessions.Count -ne 1) { $ValidationErrors.Add("In-progress plan item lacks exactly one session stub: $($ActivePlan.plan_item_id)") }
    }
    foreach ($Session in $script:Sessions) {
        if ($Session.Meta.ContainsKey('status') -and $Session.Meta.status -eq 'completed' -and $Session.Meta.plan_item_id -ne 'none' -and $PlanById.ContainsKey($Session.Meta.plan_item_id)) {
            $Linked = $PlanById[$Session.Meta.plan_item_id]
            if ($Linked.status -ne 'completed' -or $Linked.completed_session_id -ne $Session.Meta.session_id) { $ValidationErrors.Add("Completed session is not linked back: $($Session.Meta.session_id)") }
        }
    }
    foreach ($Event in $script:ReviewHistory) {
        if ($Event.result -notin @('again', 'hard', 'good', 'easy')) { $ValidationErrors.Add("Invalid review result for $($Event.event_id)") }
        if (-not (Test-DateValue $Event.study_date) -or -not (Test-DateValue $Event.next_review) -or -not (Test-StudyTimestamp $Event.reviewed_at)) { $ValidationErrors.Add("Review event has invalid date data: $($Event.event_id)") }
        if (-not $SessionById.ContainsKey($Event.session_id)) { $ValidationErrors.Add("Review event references unknown session: $($Event.event_id)") }
        if ($Event.old_level -notmatch '^\d+$' -or $Event.new_level -notmatch '^\d+$' -or [int]$Event.old_level -gt 5 -or [int]$Event.new_level -gt 5) { $ValidationErrors.Add("Review event has invalid levels: $($Event.event_id)") }
        if (-not [string]::IsNullOrWhiteSpace($Event.previous_due) -and -not (Test-DateValue $Event.previous_due)) { $ValidationErrors.Add("Review event has invalid previous_due: $($Event.event_id)") }
        if ($Event.item_type -eq 'vocabulary') { $KnownItem = @($script:Vocabulary | Where-Object { $_.id -eq $Event.item_id }) }
        elseif ($Event.item_type -eq 'error') { $KnownItem = @($script:Errors | Where-Object { $_.id -eq $Event.item_id }) }
        else { $KnownItem = @(); $ValidationErrors.Add("Review event has invalid item_type: $($Event.event_id)") }
        if ($KnownItem.Count -ne 1) { $ValidationErrors.Add("Review event references unknown item: $($Event.event_id)") }
        if ((Test-StudyTimestamp $Event.reviewed_at) -and (Test-DateValue $Event.study_date)) {
            $ReviewedAt = [DateTimeOffset]::Parse($Event.reviewed_at, [Globalization.CultureInfo]::InvariantCulture)
            if ($ReviewedAt.ToOffset([TimeSpan]::FromHours(8)).ToString('yyyy-MM-dd') -ne $Event.study_date) { $ValidationErrors.Add("Review timestamp/date mismatch: $($Event.event_id)") }
        }
    }
    foreach ($HistoryGroup in @($script:ReviewHistory | Group-Object item_id)) {
        $Ordered = @($HistoryGroup.Group | Sort-Object reviewed_at)
        for ($Index = 1; $Index -lt $Ordered.Count; $Index++) { if ($Ordered[$Index].old_level -ne $Ordered[$Index - 1].new_level -or $Ordered[$Index].previous_due -ne $Ordered[$Index - 1].next_review) { $ValidationErrors.Add("Review history is discontinuous for $($HistoryGroup.Name)") } }
    }
    foreach ($Item in @($script:Vocabulary) + @($script:Errors)) {
        if (-not [string]::IsNullOrWhiteSpace($Item.source_session) -and -not $SessionById.ContainsKey($Item.source_session)) { $ValidationErrors.Add("$($Item.id) references unknown source_session") }
        $Latest = @($script:ReviewHistory | Where-Object { $_.item_id -eq $Item.id } | Sort-Object reviewed_at | Select-Object -Last 1)
        if ($Latest.Count -eq 1 -and ($Item.level -ne $Latest[0].new_level -or $Item.next_review -ne $Latest[0].next_review -or $Item.last_review -ne $Latest[0].study_date)) { $ValidationErrors.Add("Current state disagrees with latest review for $($Item.id)") }
    }
    foreach ($Event in $script:PlanEvents) {
        if ($Event.event -ne 'cancelled') { $ValidationErrors.Add("Invalid plan event type: $($Event.event_id)") }
        if (-not $PlanById.ContainsKey($Event.plan_item_id)) { $ValidationErrors.Add("Plan event references unknown item: $($Event.event_id)") }
        if ([string]::IsNullOrWhiteSpace($Event.reason)) { $ValidationErrors.Add("Plan cancellation lacks a reason: $($Event.event_id)") }
        if (-not (Test-DateValue $Event.study_date) -or -not (Test-StudyTimestamp $Event.occurred_at)) { $ValidationErrors.Add("Plan event has invalid date data: $($Event.event_id)") }
    }
    foreach ($Cancelled in @($script:Plans | Where-Object { $_.status -eq 'cancelled' })) {
        if (@($script:PlanEvents | Where-Object { $_.plan_item_id -eq $Cancelled.plan_item_id -and $_.event -eq 'cancelled' }).Count -ne 1) { $ValidationErrors.Add("Cancelled plan item lacks exactly one cancellation event: $($Cancelled.plan_item_id)") }
    }
    foreach ($Row in $script:Evidence) {
        if (-not $SessionById.ContainsKey($Row.session_id)) { $ValidationErrors.Add("Evidence references unknown session: $($Row.evidence_id)") }
        if ($Row.skill -notin @('listening', 'speaking', 'reading', 'writing', 'mixed', 'review')) { $ValidationErrors.Add("Invalid evidence skill: $($Row.evidence_id)") }
        if ($Row.phase -notin @('raw', 'revised', 'assessment')) { $ValidationErrors.Add("Invalid evidence phase: $($Row.evidence_id)") }
        if (-not [string]::IsNullOrWhiteSpace($Row.score)) { if ($Row.score -notmatch '^\d+(\.\d+)?$' -or $Row.scale -notmatch '^\d+(\.\d+)?$' -or [double]$Row.scale -le 0 -or [double]$Row.score -gt [double]$Row.scale) { $ValidationErrors.Add("Invalid evidence score: $($Row.evidence_id)") } }
    }
    foreach ($Session in @($script:Sessions | Where-Object { $_.Meta.ContainsKey('status') -and $_.Meta.status -eq 'completed' -and $_.Meta.session_type -eq 'diagnostic' })) {
        if (@($script:Evidence | Where-Object { $_.session_id -eq $Session.Meta.session_id -and $_.phase -eq 'raw' }).Count -eq 0) { $ValidationErrors.Add("Diagnostic session lacks raw evidence: $($Session.Meta.session_id)") }
    }
    if (Test-Path -LiteralPath $CheckpointPath -PathType Leaf) {
        try {
            $Checkpoint = ConvertFrom-StableJson -Text (Get-Content -Raw -Encoding UTF8 -LiteralPath $CheckpointPath)
            foreach ($Field in @('schema_version', 'status', 'session_id', 'plan_item_id', 'study_date', 'study_timezone', 'session_type', 'primary_skill', 'started_at', 'updated_at', 'last_completed_stage', 'checkpoints')) { if ($Field -notin $Checkpoint.PSObject.Properties.Name) { $ValidationErrors.Add("current-session is missing field: $Field") } }
            if ($Checkpoint.status -notin @('in_progress', 'completed', 'abandoned')) { $ValidationErrors.Add("Invalid current-session status: $($Checkpoint.status)") }
            if ($Checkpoint.study_timezone -ne [string]$script:Settings.study_timezone -or -not (Test-DateValue $Checkpoint.study_date)) { $ValidationErrors.Add('current-session has invalid date or timezone.') }
            if (-not (Test-StudyTimestamp $Checkpoint.started_at) -or -not (Test-StudyTimestamp $Checkpoint.updated_at)) { $ValidationErrors.Add('current-session has invalid Shanghai timestamps.') }
            if ($Checkpoint.plan_item_id -ne 'none' -and -not $PlanById.ContainsKey([string]$Checkpoint.plan_item_id)) { $ValidationErrors.Add('current-session references an unknown plan item.') }
            if (-not $SessionById.ContainsKey([string]$Checkpoint.session_id)) { $ValidationErrors.Add('current-session references an unknown session.') }
            elseif ($Checkpoint.status -ne $SessionById[[string]$Checkpoint.session_id].Meta.status) { $ValidationErrors.Add('current-session status disagrees with its session file.') }
        }
        catch { $ValidationErrors.Add("current-session checkpoint is not valid JSON: $($_.Exception.Message)") }
    }
    $Metrics = Get-Metrics -VocabularyRows $script:Vocabulary -ErrorRows $script:Errors -PlanRows $script:Plans -SessionRows $script:Sessions
    if (-not (Get-Content -Raw -Encoding UTF8 -LiteralPath $DashboardPath).Contains((Get-DashboardBlock -Metrics $Metrics))) { $ValidationWarnings.Add('Dashboard metrics are stale; run tracker Rebuild.') }
    if (-not (Get-Content -Raw -Encoding UTF8 -LiteralPath $CurrentPlanPath).Contains((Get-PlanBlock -PlanRows $script:Plans))) { $ValidationWarnings.Add('Current plan view is stale; run tracker Rebuild.') }
    return [pscustomobject]@{ status = $(if ($ValidationErrors.Count -eq 0) { 'valid' } else { 'invalid' }); study_date = $script:StudyDate.ToString('yyyy-MM-dd'); study_timezone = [string]$script:Settings.study_timezone; error_count = $ValidationErrors.Count; warning_count = $ValidationWarnings.Count; errors = @($ValidationErrors); warnings = @($ValidationWarnings); counts = [pscustomobject]@{ sessions = $script:Sessions.Count; plan_items = $script:Plans.Count; vocabulary = $script:Vocabulary.Count; errors = $script:Errors.Count; review_events = $script:ReviewHistory.Count; evidence = $script:Evidence.Count } }
}

function New-PeriodSummary {
    param([ValidateSet('month', 'quarter')][string]$Kind, [string]$Key)
    if ($Kind -eq 'month') { if ($Key -notmatch '^\d{4}-\d{2}$') { throw 'MonthlySummary requires -PeriodKey YYYY-MM.' }; $Start = [datetime]::ParseExact(($Key + '-01'), 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture); $End = $Start.AddMonths(1).AddDays(-1) }
    else { if ($Key -notmatch '^(\d{4})-Q([1-4])$') { throw 'QuarterlySummary requires -PeriodKey YYYY-Q1 through YYYY-Q4.' }; $Start = [datetime]::new([int]$Matches[1], (([int]$Matches[2] - 1) * 3) + 1, 1); $End = $Start.AddMonths(3).AddDays(-1) }
    $PeriodSessions = @($script:Sessions | Where-Object { $_.Meta.ContainsKey('date') -and (Test-DateValue $_.Meta.date) -and $_.Meta.status -eq 'completed' -and [datetime]::ParseExact($_.Meta.date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -ge $Start -and [datetime]::ParseExact($_.Meta.date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -le $End })
    $Minutes = 0; $Days = @{}
    foreach ($Session in $PeriodSessions) { $Days[$Session.Meta.date] = $true; if ($Session.Meta.duration_minutes -match '^\d+$') { $Minutes += [int]$Session.Meta.duration_minutes } }
    $PeriodReviews = @($script:ReviewHistory | Where-Object { (Test-DateValue $_.study_date) -and [datetime]::ParseExact($_.study_date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -ge $Start -and [datetime]::ParseExact($_.study_date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -le $End })
    $ReviewGroups = @($PeriodReviews | Group-Object result | Sort-Object Name); $ReviewText = if ($ReviewGroups.Count -eq 0) { '尚无复习事件' } else { ($ReviewGroups | ForEach-Object { "$($_.Name): $($_.Count)" }) -join '；' }
    $SkillGroups = @($PeriodSessions | ForEach-Object { $_.Meta.primary_skill } | Group-Object | Sort-Object Name); $SkillText = if ($SkillGroups.Count -eq 0) { '尚无数据' } else { ($SkillGroups | ForEach-Object { "$($_.Name): $($_.Count)" }) -join '；' }
    $Text = "# $Key 自动统计摘要`r`n`r`n- 统计时区：$($script:Settings.study_timezone)`r`n- 统计范围：$($Start.ToString('yyyy-MM-dd')) 至 $($End.ToString('yyyy-MM-dd'))`r`n- 学习日：$($Days.Count)`r`n- 完成课次：$($PeriodSessions.Count)`r`n- 学习分钟：$Minutes`r`n- 能力分布：$SkillText`r`n- 复习结果：$ReviewText`r`n- 证据条目：$(@($script:Evidence | Where-Object { $SessionIds = @($PeriodSessions | ForEach-Object { $_.Meta.session_id }); $_.session_id -in $SessionIds }).Count)`r`n`r`n## 教师分析`r`n`r`n- 本节由 AI 根据原始 session、结构化证据和以上统计补充。`r`n"
    $OutputPath = Join-Path $SummaryPath ($Key + '.md'); Write-AtomicText -Path $OutputPath -Text $Text
    return [pscustomobject]@{ status = 'written'; path = $OutputPath; sessions = $PeriodSessions.Count; minutes = $Minutes; study_days = $Days.Count }
}

if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { throw "Missing settings file: $SettingsPath" }
$Settings = Get-Content -Raw -Encoding UTF8 -LiteralPath $SettingsPath | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$Settings.windows_timezone_id)) { throw 'settings.json is missing windows_timezone_id.' }
$StudyTimeZone = [TimeZoneInfo]::FindSystemTimeZoneById([string]$Settings.windows_timezone_id)
if ($PSBoundParameters.ContainsKey('Date')) { $StudyNow = [DateTime]::SpecifyKind($Date, [DateTimeKind]::Unspecified) }
else { $StudyNow = [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $StudyTimeZone) }
$StudyDate = $StudyNow.Date
Read-AllData

switch ($Action) {
    'Due' {
        $DueVocabulary = @(Get-DueRows -Rows $Vocabulary); $DueErrors = @(Get-DueRows -Rows $Errors)
        [pscustomobject]@{ study_date = $StudyDate.ToString('yyyy-MM-dd'); study_timezone = [string]$Settings.study_timezone; vocabulary_count = $DueVocabulary.Count; vocabulary = $DueVocabulary; error_count = $DueErrors.Count; errors = $DueErrors } | ConvertTo-Json -Depth 6
    }
    'Summary' { Get-Metrics -VocabularyRows $Vocabulary -ErrorRows $Errors -PlanRows $Plans -SessionRows $Sessions | ConvertTo-Json -Depth 6 }
    'Bootstrap' {
        $Recovered = Complete-ReviewTransaction; if ($Recovered) { Read-AllData }
        $PlanStateBefore = @($Plans | ForEach-Object { "$($_.plan_item_id)|$($_.status)|$($_.completed_session_id)" }) -join "`n"
        $Plans = @(Sync-PlanState -PlanRows $Plans -SessionRows $Sessions)
        $PlanStateAfter = @($Plans | ForEach-Object { "$($_.plan_item_id)|$($_.status)|$($_.completed_session_id)" }) -join "`n"
        $PlanStateReconciled = $PlanStateBefore -ne $PlanStateAfter
        if ($PlanStateReconciled) { Write-TableRows -Path $PlanItemsPath -Rows $Plans -Headers $PlanHeaders }
        $Next = @(Get-NextPlanItem -PlanRows $Plans); $Checkpoint = $null
        if (Test-Path -LiteralPath $CheckpointPath -PathType Leaf) { $Candidate = ConvertFrom-StableJson -Text (Get-Content -Raw -Encoding UTF8 -LiteralPath $CheckpointPath); if ($Candidate.status -eq 'in_progress') { $Checkpoint = $Candidate } }
        $Metrics = Get-Metrics -VocabularyRows $Vocabulary -ErrorRows $Errors -PlanRows $Plans -SessionRows $Sessions
        $ReviewLimit = if ($Metrics.recovery_mode) { 10 } else { $NormalReviewLimit }
        $DueSelection = Get-DueSelection -VocabularyRows $Vocabulary -ErrorRows $Errors -Limit $ReviewLimit -IncludeAll:$IncludeAllDue
        [pscustomobject]@{
            status = $(if ($null -ne $Checkpoint) { 'resume' } else { 'ready' })
            recovered_review_transaction = $Recovered
            plan_state_reconciled = $PlanStateReconciled
            checkpoint = $Checkpoint
            next_plan_item = $(if ($Next.Count -eq 1) { $Next[0] } else { $null })
            recovery_mode = $Metrics.recovery_mode
            review_limit = $ReviewLimit
            new_word_limit = $(if ($Metrics.recovery_mode) { 3 } else { $null })
            due_counts = [pscustomobject]@{ vocabulary = $DueSelection.vocabulary_count; errors = $DueSelection.error_count; total = $DueSelection.total_count }
            due_vocabulary = @($DueSelection.vocabulary)
            due_errors = @($DueSelection.errors)
            due_items_selected = $DueSelection.selected_count
            due_items_truncated = $DueSelection.truncated
            include_all_due = [bool]$IncludeAllDue
            metrics = $Metrics
        } | ConvertTo-Json -Depth 8
    }
    'StartSession' {
        if (Test-Path -LiteralPath $CheckpointPath -PathType Leaf) { $Existing = ConvertFrom-StableJson -Text (Get-Content -Raw -Encoding UTF8 -LiteralPath $CheckpointPath); if ($Existing.status -eq 'in_progress') { throw "Resume active session $($Existing.session_id) before starting another." } }
        $Next = @(Get-NextPlanItem -PlanRows $Plans); if ($Next.Count -ne 1) { throw 'No queued plan item is available.' }
        if (-not [string]::IsNullOrWhiteSpace($PlanItemId) -and $PlanItemId -ne $Next[0].plan_item_id) { throw "The next queued item is $($Next[0].plan_item_id); $PlanItemId is blocked by sequence." }
        $PlanItemId = $Next[0].plan_item_id
        if ([string]::IsNullOrWhiteSpace($SessionId)) {
            $Prefix = 'S' + $StudyDate.ToString('yyyyMMdd') + '-'; $Numbers = @($Sessions | Where-Object { $_.Meta.ContainsKey('session_id') -and $_.Meta.session_id.StartsWith($Prefix) } | ForEach-Object { if ($_.Meta.session_id -match '-(\d+)$') { [int]$Matches[1] } }); $Number = 1; if ($Numbers.Count -gt 0) { $Number = ($Numbers | Measure-Object -Maximum).Maximum + 1 }; $SessionId = $Prefix + $Number.ToString('00')
        }
        if (@($Sessions | Where-Object { $_.Meta.ContainsKey('session_id') -and $_.Meta.session_id -eq $SessionId }).Count -gt 0) { throw "SessionId already exists: $SessionId" }
        $YearFolder = Join-Path $SessionPath $StudyDate.ToString('yyyy'); $MonthFolder = Join-Path $YearFolder $StudyDate.ToString('MM'); if (-not (Test-Path -LiteralPath $MonthFolder -PathType Container)) { [void](New-Item -ItemType Directory -Force -Path $MonthFolder) }
        $BaseName = $StudyDate.ToString('yyyy-MM-dd'); $SessionFile = Join-Path $MonthFolder ($BaseName + '.md'); $Suffix = 2
        while (Test-Path -LiteralPath $SessionFile) { $SessionFile = Join-Path $MonthFolder ($BaseName + '-' + $Suffix.ToString('00') + '.md'); $Suffix++ }
        $SessionType = [string]$Next[0].session_type; $PrimarySkill = [string]$Next[0].primary_skill
        $Text = "---`r`nsession_id: $SessionId`r`ndate: $($StudyDate.ToString('yyyy-MM-dd'))`r`nplan_item_id: $PlanItemId`r`nsession_type: $SessionType`r`nstatus: in_progress`r`nduration_minutes: 0`r`nprimary_skill: $PrimarySkill`r`nstudy_timezone: $($Settings.study_timezone)`r`nsource_type: $SourceType`r`n---`r`n`r`n# $($Next[0].title)`r`n`r`n## 学习记录`r`n`r`n- 本课已创建，完成后补充必要答案摘要、反馈和来源链接。`r`n"
        Write-AtomicText -Path $SessionFile -Text $Text
        $Next[0].status = 'in_progress'; $Next[0].completed_session_id = ''; Write-TableRows -Path $PlanItemsPath -Rows $Plans -Headers $PlanHeaders
        $Timestamp = Get-StudyTimestamp
        $Checkpoint = [pscustomobject]@{ schema_version = 2; status = 'in_progress'; session_id = $SessionId; plan_item_id = $PlanItemId; study_date = $StudyDate.ToString('yyyy-MM-dd'); study_timezone = [string]$Settings.study_timezone; session_type = $SessionType; primary_skill = $PrimarySkill; session_file = $SessionFile.Substring($ProjectRoot.Length + 1).Replace('\', '/'); started_at = $Timestamp; updated_at = $Timestamp; last_completed_stage = ''; checkpoints = @() }
        Write-AtomicText -Path $CheckpointPath -Text ($Checkpoint | ConvertTo-Json -Depth 8); [void](Invoke-Rebuild)
        [pscustomobject]@{ status = 'started'; session_id = $SessionId; plan_item_id = $PlanItemId; session_file = $Checkpoint.session_file } | ConvertTo-Json
    }
    'Review' {
        if ([string]::IsNullOrWhiteSpace($Collection) -or [string]::IsNullOrWhiteSpace($Id) -or [string]::IsNullOrWhiteSpace($Result)) { throw 'Review requires -Collection, -Id, and -Result.' }
        Invoke-ReviewBatch -Reviews @([pscustomobject]@{ collection = $Collection; id = $Id; result = $Result }) -ForSessionId $SessionId | ConvertTo-Json
    }
    'ReviewBatch' {
        if ([string]::IsNullOrWhiteSpace($ReviewsJson)) { throw 'ReviewBatch requires -ReviewsJson.' }
        try {
            $ParsedReviews = $ReviewsJson | ConvertFrom-Json
            $Reviews = @($ParsedReviews | ForEach-Object { $_ })
        }
        catch { throw "ReviewsJson is not valid JSON: $($_.Exception.Message)" }
        Invoke-ReviewBatch -Reviews $Reviews -ForSessionId $SessionId | ConvertTo-Json
    }
    'Checkpoint' {
        if ([string]::IsNullOrWhiteSpace($SessionId) -or [string]::IsNullOrWhiteSpace($Stage)) { throw 'Checkpoint requires -SessionId and -Stage.' }
        if (-not (Test-Path -LiteralPath $CheckpointPath -PathType Leaf)) { throw 'StartSession must create the session before checkpoints can be saved.' }
        $Checkpoint = ConvertFrom-StableJson -Text (Get-Content -Raw -Encoding UTF8 -LiteralPath $CheckpointPath)
        if ($Checkpoint.status -ne 'in_progress' -or $Checkpoint.session_id -ne $SessionId) { throw 'Checkpoint does not match an active session.' }
        $Order = @('review', 'input', 'output', 'feedback', 'recording'); $ExpectedIndex = @($Checkpoint.checkpoints).Count
        if ($ExpectedIndex -ge $Order.Count -or $Stage -ne $Order[$ExpectedIndex]) { throw "Expected checkpoint stage $($Order[$ExpectedIndex]); received $Stage." }
        $Entry = [pscustomobject]@{ stage = $Stage; saved_at = Get-StudyTimestamp; note = [string]$Note }
        $Checkpoint.checkpoints = @($Checkpoint.checkpoints) + @($Entry); $Checkpoint.last_completed_stage = $Stage; $Checkpoint.updated_at = $Entry.saved_at
        Write-AtomicText -Path $CheckpointPath -Text ($Checkpoint | ConvertTo-Json -Depth 8)
        [pscustomobject]@{ status = 'saved'; session_id = $SessionId; stage = $Stage } | ConvertTo-Json
    }
    { $_ -in @('FinalizeSession', 'CloseCheckpoint') } {
        if ([string]::IsNullOrWhiteSpace($SessionId)) { throw 'FinalizeSession requires -SessionId.' }
        if (-not (Test-Path -LiteralPath $CheckpointPath -PathType Leaf)) { throw 'No current-session checkpoint exists.' }
        $Checkpoint = ConvertFrom-StableJson -Text (Get-Content -Raw -Encoding UTF8 -LiteralPath $CheckpointPath)
        if ($Checkpoint.status -ne 'in_progress' -or $Checkpoint.session_id -ne $SessionId) { throw 'Checkpoint does not match the session being finalized.' }
        $SavedStages = @($Checkpoint.checkpoints | ForEach-Object { $_.stage })
        foreach ($Required in $RequiredStages) { if ($Required -notin $SavedStages) { throw "FinalizeSession requires checkpoint stage: $Required" } }
        Read-AllData; $Recorded = @($Sessions | Where-Object { $_.Meta.ContainsKey('session_id') -and $_.Meta.session_id -eq $SessionId })
        if ($Recorded.Count -ne 1 -or $Recorded[0].Meta.status -ne 'completed') { throw 'FinalizeSession requires one matching completed session file.' }
        if ($Recorded[0].Meta.session_type -eq 'diagnostic' -and @($Evidence | Where-Object { $_.session_id -eq $SessionId -and $_.phase -eq 'raw' }).Count -eq 0) { throw 'Diagnostic finalization requires structured raw evidence.' }
        $Linked = @($Plans | Where-Object { $_.plan_item_id -eq $Checkpoint.plan_item_id }); if ($Linked.Count -ne 1) { throw 'Checkpoint plan item is missing.' }
        $Linked[0].status = 'completed'; $Linked[0].completed_session_id = $SessionId; Write-TableRows -Path $PlanItemsPath -Rows $Plans -Headers $PlanHeaders
        $Checkpoint.status = 'completed'; $Checkpoint.updated_at = Get-StudyTimestamp; Write-AtomicText -Path $CheckpointPath -Text ($Checkpoint | ConvertTo-Json -Depth 8)
        $Metrics = Invoke-Rebuild; $Report = Get-ValidationReport
        if ($Report.status -ne 'valid') { throw "Finalization left validation errors: $($Report.errors -join '; ')" }
        [pscustomobject]@{
            status = 'completed'
            session_id = $SessionId
            next_plan_item = @(Get-NextPlanItem -PlanRows $Plans | Select-Object -First 1)
            archive = [pscustomobject]@{
                views_rebuilt = $true
                validation_status = $Report.status
                validation_errors = $Report.error_count
                validation_warnings = $Report.warning_count
            }
            metrics = $Metrics
        } | ConvertTo-Json -Depth 6
    }
    { $_ -in @('AbandonSession', 'AbandonCheckpoint') } {
        if ([string]::IsNullOrWhiteSpace($SessionId)) { throw 'AbandonSession requires -SessionId.' }
        if (-not (Test-Path -LiteralPath $CheckpointPath -PathType Leaf)) { throw 'No current-session checkpoint exists.' }
        $Checkpoint = ConvertFrom-StableJson -Text (Get-Content -Raw -Encoding UTF8 -LiteralPath $CheckpointPath)
        if ($Checkpoint.session_id -ne $SessionId) { throw 'Checkpoint belongs to another session.' }
        $Recorded = @($Sessions | Where-Object { $_.Meta.ContainsKey('session_id') -and $_.Meta.session_id -eq $SessionId })
        if ($Recorded.Count -ne 1 -or $Recorded[0].Meta.status -ne 'abandoned') { throw 'AbandonSession requires one matching abandoned session file.' }
        $Linked = @($Plans | Where-Object { $_.plan_item_id -eq $Checkpoint.plan_item_id }); if ($Linked.Count -eq 1 -and $Linked[0].status -eq 'in_progress') { $Linked[0].status = 'planned'; $Linked[0].completed_session_id = ''; Write-TableRows -Path $PlanItemsPath -Rows $Plans -Headers $PlanHeaders }
        $Checkpoint.status = 'abandoned'; $Checkpoint.updated_at = Get-StudyTimestamp; if (-not [string]::IsNullOrWhiteSpace($Note)) { $Checkpoint | Add-Member -NotePropertyName abandonment_note -NotePropertyValue $Note -Force }; Write-AtomicText -Path $CheckpointPath -Text ($Checkpoint | ConvertTo-Json -Depth 8)
        [void](Invoke-Rebuild); [pscustomobject]@{ status = 'abandoned'; session_id = $SessionId } | ConvertTo-Json
    }
    'CancelPlanItem' {
        if ([string]::IsNullOrWhiteSpace($PlanItemId) -or [string]::IsNullOrWhiteSpace($CancelReason)) { throw 'CancelPlanItem requires -PlanItemId and -CancelReason.' }
        $Next = @(Get-NextPlanItem -PlanRows $Plans); if ($Next.Count -ne 1 -or $Next[0].plan_item_id -ne $PlanItemId) { throw 'Only the next queued plan item can be cancelled.' }
        if ($Next[0].status -ne 'planned') { throw 'An in-progress plan item must be abandoned, not cancelled.' }
        $Next[0].status = 'cancelled'; $Next[0].completed_session_id = ''; Write-TableRows -Path $PlanItemsPath -Rows $Plans -Headers $PlanHeaders
        $Event = [pscustomobject]@{ event_id = ('P' + [guid]::NewGuid().ToString('N')); occurred_at = Get-StudyTimestamp; study_date = $StudyDate.ToString('yyyy-MM-dd'); plan_item_id = $PlanItemId; event = 'cancelled'; reason = $CancelReason }; Add-TableRow -Path $PlanEventsPath -Row $Event -Headers $PlanEventHeaders
        $Metrics = Invoke-Rebuild; [pscustomobject]@{ status = 'cancelled'; plan_item_id = $PlanItemId; next_plan_item_id = $Metrics.next_plan_item_id } | ConvertTo-Json
    }
    'Rebuild' { Invoke-Rebuild | ConvertTo-Json -Depth 6 }
    'MonthlySummary' { New-PeriodSummary -Kind month -Key $PeriodKey | ConvertTo-Json }
    'QuarterlySummary' { New-PeriodSummary -Kind quarter -Key $PeriodKey | ConvertTo-Json }
    'Validate' { $Report = Get-ValidationReport; $Report | ConvertTo-Json -Depth 7; if ($Report.status -ne 'valid') { exit 1 } }
}
