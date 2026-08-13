[CmdletBinding()]
param(
    [ValidateSet('Due', 'Review', 'Summary', 'Validate', 'Checkpoint', 'CloseCheckpoint', 'AbandonCheckpoint', 'Rebuild', 'MonthlySummary', 'QuarterlySummary')]
    [string]$Action = 'Due', # Legacy date-based tracker retained for migration rollback.
    [string]$ProjectRoot,
    [datetime]$Date,
    [ValidateSet('vocabulary', 'error')][string]$Collection,
    [string]$Id,
    [ValidateSet('again', 'hard', 'good', 'easy')][string]$Result,
    [string]$SessionId,
    [string]$PlanItemId,
    [ValidateSet('review', 'input', 'output', 'feedback', 'recording')][string]$Stage,
    [string]$PrimarySkill,
    [string]$SessionType,
    [string]$Note,
    [string]$PeriodKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..')).Path
}
else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

$SettingsPath = Join-Path $ProjectRoot 'learner\settings.json'
$VocabularyPath = Join-Path $ProjectRoot 'learner\vocabulary.tsv'
$ErrorLogPath = Join-Path $ProjectRoot 'learner\error-log.tsv'
$ReviewHistoryPath = Join-Path $ProjectRoot 'learner\review-history.tsv'
$PlanItemsPath = Join-Path $ProjectRoot 'learner\plan-items.tsv'
$DashboardPath = Join-Path $ProjectRoot 'learner\dashboard.md'
$CurrentPlanPath = Join-Path $ProjectRoot 'learner\current-plan.md'
$ProfilePath = Join-Path $ProjectRoot 'learner\profile.md'
$SessionPath = Join-Path $ProjectRoot 'sessions'
$SummaryPath = Join-Path $ProjectRoot 'learner\summaries'
$CheckpointPath = Join-Path $ProjectRoot '.state\current-session.json'
$Intervals = @(1, 3, 7, 14, 30, 60)

$VocabularyHeaders = @('id', 'item', 'meaning', 'context', 'status', 'level', 'next_review', 'last_review', 'source_session')
$ErrorHeaders = @('id', 'category', 'original', 'corrected', 'explanation', 'status', 'level', 'next_review', 'last_review', 'source_session')
$ReviewHeaders = @('event_id', 'reviewed_at', 'study_date', 'session_id', 'item_type', 'item_id', 'result', 'old_level', 'new_level', 'previous_due', 'next_review')
$PlanHeaders = @('plan_item_id', 'plan_id', 'planned_date', 'sequence', 'title', 'session_type', 'primary_skill', 'required', 'status', 'completed_session_id')

function Write-AtomicText {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Text)
    $Directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Force -Path $Directory)
    }
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
    if (($ActualHeaders -join '|') -ne ($RequiredHeaders -join '|')) {
        throw "Unexpected headers in $Path. Expected: $($RequiredHeaders -join ', ')"
    }
    return @(Import-Csv -LiteralPath $Path -Delimiter "`t" -Encoding UTF8)
}

function Write-TableRows {
    param([string]$Path, [object[]]$Rows, [string[]]$Headers)
    if ($Rows.Count -eq 0) {
        Write-AtomicText -Path $Path -Text (($Headers -join "`t") + "`r`n")
        return
    }
    $Directory = Split-Path -Parent $Path
    $TemporaryPath = Join-Path $Directory ((Split-Path -Leaf $Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $Rows | Select-Object -Property $Headers | Export-Csv -LiteralPath $TemporaryPath -Delimiter "`t" -Encoding UTF8 -NoTypeInformation
    Move-Item -LiteralPath $TemporaryPath -Destination $Path -Force
}

function Test-DateValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    try {
        [void][datetime]::ParseExact($Value, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        return $true
    }
    catch { return $false }
}

function Test-StudyTimestamp {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $Parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$Parsed)) { return $false }
    return $Parsed.Offset -eq [TimeSpan]::FromHours(8)
}

function Get-Frontmatter {
    param([string]$Path)
    $Lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $Metadata = @{}
    if ($Lines.Count -lt 3 -or $Lines[0].Trim() -ne '---') { return $Metadata }
    for ($Index = 1; $Index -lt $Lines.Count; $Index++) {
        if ($Lines[$Index].Trim() -eq '---') { break }
        $Separator = $Lines[$Index].IndexOf(':')
        if ($Separator -gt 0) {
            $Key = $Lines[$Index].Substring(0, $Separator).Trim()
            $Metadata[$Key] = $Lines[$Index].Substring($Separator + 1).Trim()
        }
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

function Get-DueRows {
    param([object[]]$Rows)
    return @($Rows | Where-Object {
        $_.status -eq 'active' -and (Test-DateValue $_.next_review) -and
        ([datetime]::ParseExact($_.next_review, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)).Date -le $script:StudyDate
    } | Sort-Object next_review, id)
}

function Replace-MarkedBlock {
    param([string]$Path, [string]$StartMarker, [string]$EndMarker, [string]$Body)
    $Content = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
    $StartIndex = $Content.IndexOf($StartMarker)
    $EndIndex = $Content.IndexOf($EndMarker)
    if ($StartIndex -lt 0 -or $EndIndex -lt $StartIndex) { throw "Missing generated block markers in $Path" }
    $SuffixStart = $EndIndex + $EndMarker.Length
    $Replacement = $StartMarker + "`r`n" + $Body.TrimEnd() + "`r`n" + $EndMarker
    Write-AtomicText -Path $Path -Text ($Content.Substring(0, $StartIndex) + $Replacement + $Content.Substring($SuffixStart))
}

function Get-StudyTimestamp {
    $Offset = $script:StudyTimeZone.GetUtcOffset($script:StudyNow)
    $Unspecified = [DateTime]::SpecifyKind($script:StudyNow, [DateTimeKind]::Unspecified)
    return ([DateTimeOffset]::new($Unspecified, $Offset)).ToString('yyyy-MM-ddTHH:mm:sszzz')
}

function Get-Metrics {
    param([object[]]$VocabularyRows, [object[]]$ErrorRows, [object[]]$PlanRows, [object[]]$SessionRows)
    $CompletionWindow = [int]$script:Settings.completion_window_days
    $PlanWindowStart = $script:StudyDate.AddDays(-($CompletionWindow - 1))
    $SessionWindowStart = $script:StudyDate.AddDays(-27)
    $CompletedByPlan = @{}
    $CompletedDates = @{}
    $CompletedSessions28 = @()
    $TotalMinutes28 = 0
    foreach ($Session in $SessionRows) {
        if (-not $Session.Meta.ContainsKey('date') -or -not (Test-DateValue $Session.Meta.date)) { continue }
        if (-not $Session.Meta.ContainsKey('status') -or $Session.Meta.status -ne 'completed') { continue }
        $SessionDate = [datetime]::ParseExact($Session.Meta.date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date
        $CompletedDates[$Session.Meta.date] = $true
        if ($Session.Meta.ContainsKey('plan_item_id') -and $Session.Meta.plan_item_id -ne 'none') { $CompletedByPlan[$Session.Meta.plan_item_id] = $Session }
        if ($SessionDate -ge $SessionWindowStart -and $SessionDate -le $script:StudyDate) {
            $CompletedSessions28 += $Session
            if ($Session.Meta.ContainsKey('duration_minutes') -and $Session.Meta.duration_minutes -match '^\d+$') { $TotalMinutes28 += [int]$Session.Meta.duration_minutes }
        }
    }
    $ElapsedPlans = @($PlanRows | Where-Object {
        $_.required -eq 'true' -and $_.status -ne 'cancelled' -and (Test-DateValue $_.planned_date) -and
        ([datetime]::ParseExact($_.planned_date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -ge $PlanWindowStart) -and
        (([datetime]::ParseExact($_.planned_date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -lt $script:StudyDate) -or $CompletedByPlan.ContainsKey($_.plan_item_id))
    })
    $CompletedPlans = @($ElapsedPlans | Where-Object { $CompletedByPlan.ContainsKey($_.plan_item_id) })
    $Streak = 0
    $Cursor = $script:StudyDate
    if (-not $CompletedDates.ContainsKey($Cursor.ToString('yyyy-MM-dd'))) { $Cursor = $Cursor.AddDays(-1) }
    while ($CompletedDates.ContainsKey($Cursor.ToString('yyyy-MM-dd'))) { $Streak++; $Cursor = $Cursor.AddDays(-1) }
    $Rate = $null
    if ($ElapsedPlans.Count -gt 0) { $Rate = [Math]::Round(($CompletedPlans.Count * 100.0) / $ElapsedPlans.Count, 1) }
    return [pscustomobject]@{
        study_date = $script:StudyDate.ToString('yyyy-MM-dd')
        study_timezone = [string]$script:Settings.study_timezone
        plan_window_start = $PlanWindowStart.ToString('yyyy-MM-dd')
        plan_window_days = $CompletionWindow
        planned_elapsed = $ElapsedPlans.Count
        planned_completed = $CompletedPlans.Count
        completion_rate = $Rate
        session_window_start = $SessionWindowStart.ToString('yyyy-MM-dd')
        completed_sessions_28d = $CompletedSessions28.Count
        total_minutes_28d = $TotalMinutes28
        streak_days = $Streak
        due_vocabulary = @(Get-DueRows -Rows $VocabularyRows).Count
        due_errors = @(Get-DueRows -Rows $ErrorRows).Count
    }
}

function Get-DashboardBlock {
    param([object]$Metrics)
    $RateText = if ($null -eq $Metrics.completion_rate) { '尚无到期计划' } else { ([string]$Metrics.completion_rate + '%') }
    return @(
        "- 自动统计日期：$($Metrics.study_date)（$($Metrics.study_timezone)）",
        "- 连续学习：$($Metrics.streak_days) 天",
        "- 最近 $($Metrics.plan_window_days) 天计划完成：$($Metrics.planned_completed)/$($Metrics.planned_elapsed)",
        "- 最近 $($Metrics.plan_window_days) 天完成率：$RateText",
        "- 最近 28 天完成：$($Metrics.completed_sessions_28d) 课次 / $($Metrics.total_minutes_28d) 分钟",
        "- 到期词汇：$($Metrics.due_vocabulary)",
        "- 到期错误：$($Metrics.due_errors)"
    ) -join "`r`n"
}

function Get-PlanBlock {
    param([object[]]$PlanRows)
    if ($PlanRows.Count -eq 0) { return "| 日期 | 日次 | 内容 | 类型 | 状态 |`r`n| --- | --- | --- | --- | --- |" }
    $CurrentPlanId = ($PlanRows | Sort-Object planned_date, sequence | Select-Object -Last 1).plan_id
    $CurrentRows = @($PlanRows | Where-Object { $_.plan_id -eq $CurrentPlanId } | Sort-Object { [int]$_.sequence })
    $Lines = @('| 日期 | 日次 | 内容 | 类型 | 状态 |', '| --- | --- | --- | --- | --- |')
    $StatusLabels = @{ planned = '待开始'; in_progress = '进行中'; completed = '已完成'; missed = '未完成'; cancelled = '已取消' }
    foreach ($Row in $CurrentRows) {
        $Label = if ($StatusLabels.ContainsKey($Row.status)) { $StatusLabels[$Row.status] } else { $Row.status }
        if ($Row.status -eq 'completed' -and -not [string]::IsNullOrWhiteSpace($Row.completed_session_id)) { $Label += "（$($Row.completed_session_id)）" }
        $Lines += "| $($Row.planned_date) | $($Row.sequence) | $($Row.title) | $($Row.session_type) | $Label |"
    }
    return $Lines -join "`r`n"
}

function Sync-PlanState {
    param([object[]]$PlanRows, [object[]]$SessionRows)
    $SessionByPlan = @{}
    foreach ($Session in $SessionRows) {
        if ($Session.Meta.ContainsKey('status') -and $Session.Meta.status -eq 'completed' -and $Session.Meta.ContainsKey('plan_item_id') -and $Session.Meta.plan_item_id -ne 'none') { $SessionByPlan[$Session.Meta.plan_item_id] = $Session }
    }
    foreach ($Plan in $PlanRows) {
        if ($SessionByPlan.ContainsKey($Plan.plan_item_id)) {
            $Plan.status = 'completed'
            $Plan.completed_session_id = $SessionByPlan[$Plan.plan_item_id].Meta.session_id
        }
        elseif ((Test-DateValue $Plan.planned_date) -and [datetime]::ParseExact($Plan.planned_date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -lt $script:StudyDate -and $Plan.status -in @('planned', 'in_progress')) {
            $Plan.status = 'missed'
            $Plan.completed_session_id = ''
        }
    }
    return @($PlanRows)
}

function Add-ReviewEvent {
    param([object]$Event)
    $Values = @()
    foreach ($Header in $ReviewHeaders) {
        $Value = [string]$Event.$Header
        if ($Value.Contains("`t") -or $Value.Contains("`r") -or $Value.Contains("`n")) { throw "Review history value for $Header contains a forbidden control character." }
        $Values += $Value
    }
    $Utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::AppendAllText($ReviewHistoryPath, (($Values -join "`t") + "`r`n"), $Utf8)
}

function New-PeriodSummary {
    param([ValidateSet('month', 'quarter')][string]$Kind, [string]$Key)
    if ($Kind -eq 'month') {
        if ($Key -notmatch '^\d{4}-\d{2}$') { throw 'MonthlySummary requires -PeriodKey YYYY-MM.' }
        $Start = [datetime]::ParseExact(($Key + '-01'), 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        $End = $Start.AddMonths(1).AddDays(-1)
    }
    else {
        if ($Key -notmatch '^(\d{4})-Q([1-4])$') { throw 'QuarterlySummary requires -PeriodKey YYYY-Q1 through YYYY-Q4.' }
        $Start = [datetime]::new([int]$Matches[1], (([int]$Matches[2] - 1) * 3) + 1, 1)
        $End = $Start.AddMonths(3).AddDays(-1)
    }
    $PeriodSessions = @($script:Sessions | Where-Object {
        $_.Meta.ContainsKey('date') -and (Test-DateValue $_.Meta.date) -and
        ([datetime]::ParseExact($_.Meta.date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -ge $Start) -and
        ([datetime]::ParseExact($_.Meta.date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -le $End) -and $_.Meta.status -eq 'completed'
    })
    $Minutes = 0
    foreach ($Session in $PeriodSessions) { if ($Session.Meta.ContainsKey('duration_minutes') -and $Session.Meta.duration_minutes -match '^\d+$') { $Minutes += [int]$Session.Meta.duration_minutes } }
    $PeriodPlans = @($script:Plans | Where-Object { (Test-DateValue $_.planned_date) -and ([datetime]::ParseExact($_.planned_date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -ge $Start) -and ([datetime]::ParseExact($_.planned_date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -le $End) -and $_.required -eq 'true' -and $_.status -ne 'cancelled' })
    $CompletedPlanCount = @($PeriodPlans | Where-Object { $_.status -eq 'completed' }).Count
    $PeriodReviews = @($script:ReviewHistory | Where-Object { (Test-DateValue $_.study_date) -and ([datetime]::ParseExact($_.study_date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -ge $Start) -and ([datetime]::ParseExact($_.study_date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -le $End) })
    $ReviewGroups = @($PeriodReviews | Group-Object result | Sort-Object Name)
    $ReviewText = if ($ReviewGroups.Count -eq 0) { '尚无复习事件' } else { ($ReviewGroups | ForEach-Object { "$($_.Name): $($_.Count)" }) -join '；' }
    $SkillGroups = @($PeriodSessions | ForEach-Object { if ($_.Meta.ContainsKey('primary_skill')) { $_.Meta.primary_skill } } | Group-Object | Sort-Object Name)
    $SkillText = if ($SkillGroups.Count -eq 0) { '尚无数据' } else { ($SkillGroups | ForEach-Object { "$($_.Name): $($_.Count)" }) -join '；' }
    $RateText = if ($PeriodPlans.Count -eq 0) { '尚无计划' } else { ([Math]::Round(($CompletedPlanCount * 100.0) / $PeriodPlans.Count, 1)).ToString() + '%' }
    $Text = @"
# $Key 自动统计摘要

- 统计时区：$($script:Settings.study_timezone)
- 统计范围：$($Start.ToString('yyyy-MM-dd')) 至 $($End.ToString('yyyy-MM-dd'))
- 完成课次：$($PeriodSessions.Count)
- 学习分钟：$Minutes
- 计划完成：$CompletedPlanCount/$($PeriodPlans.Count)（$RateText）
- 能力分布：$SkillText
- 复习结果：$ReviewText
- 当前词汇：$($script:Vocabulary.Count)
- 当前错误项：$($script:Errors.Count)

## 教师分析

- 本节由 AI 在月度或季度复盘时根据原始 session 和以上统计补充。
"@
    $OutputPath = Join-Path $SummaryPath ($Key + '.md')
    Write-AtomicText -Path $OutputPath -Text $Text
    return [pscustomobject]@{ status = 'written'; path = $OutputPath; sessions = $PeriodSessions.Count; minutes = $Minutes }
}

if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { throw "Missing settings file: $SettingsPath" }
$Settings = Get-Content -Raw -Encoding UTF8 -LiteralPath $SettingsPath | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$Settings.windows_timezone_id)) { throw 'settings.json is missing windows_timezone_id.' }
$StudyTimeZone = [TimeZoneInfo]::FindSystemTimeZoneById([string]$Settings.windows_timezone_id)
if ($PSBoundParameters.ContainsKey('Date')) {
    $StudyNow = [DateTime]::SpecifyKind($Date, [DateTimeKind]::Unspecified)
}
else {
    $StudyNow = [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $StudyTimeZone)
}
$StudyDate = $StudyNow.Date

$Vocabulary = @(Get-TableRows -Path $VocabularyPath -RequiredHeaders $VocabularyHeaders)
$Errors = @(Get-TableRows -Path $ErrorLogPath -RequiredHeaders $ErrorHeaders)
$ReviewHistory = @(Get-TableRows -Path $ReviewHistoryPath -RequiredHeaders $ReviewHeaders)
$Plans = @(Get-TableRows -Path $PlanItemsPath -RequiredHeaders $PlanHeaders)
$Sessions = @(Get-SessionRecords)

switch ($Action) {
    'Due' {
        $DueVocabulary = @(Get-DueRows -Rows $Vocabulary)
        $DueErrors = @(Get-DueRows -Rows $Errors)
        [pscustomobject]@{
            study_date = $StudyDate.ToString('yyyy-MM-dd')
            study_timezone = [string]$Settings.study_timezone
            vocabulary_count = $DueVocabulary.Count
            vocabulary = $DueVocabulary
            error_count = $DueErrors.Count
            errors = $DueErrors
        } | ConvertTo-Json -Depth 6
    }

    'Review' {
        if ([string]::IsNullOrWhiteSpace($Collection) -or [string]::IsNullOrWhiteSpace($Id) -or [string]::IsNullOrWhiteSpace($Result)) {
            throw 'Review requires -Collection, -Id, and -Result.'
        }
        if ($Collection -eq 'vocabulary') {
            $Rows = @($Vocabulary); $Path = $VocabularyPath; $Headers = $VocabularyHeaders
        }
        else {
            $Rows = @($Errors); $Path = $ErrorLogPath; $Headers = $ErrorHeaders
        }
        $Matches = @($Rows | Where-Object { $_.id -eq $Id })
        if ($Matches.Count -ne 1) { throw "Expected exactly one item with ID $Id in $Collection; found $($Matches.Count)." }
        $Item = $Matches[0]
        $CurrentLevel = [Math]::Max(0, [Math]::Min(5, [int]$Item.level))
        switch ($Result) {
            'again' { $NewLevel = 0 }
            'hard'  { $NewLevel = $CurrentLevel }
            'good'  { $NewLevel = [Math]::Min(5, $CurrentLevel + 1) }
            'easy'  { $NewLevel = [Math]::Min(5, $CurrentLevel + 2) }
        }
        if ([string]::IsNullOrWhiteSpace($SessionId)) {
            if (Test-Path -LiteralPath $CheckpointPath -PathType Leaf) {
                $Checkpoint = Get-Content -Raw -Encoding UTF8 -LiteralPath $CheckpointPath | ConvertFrom-Json
                if ($Checkpoint.status -eq 'in_progress') { $SessionId = [string]$Checkpoint.session_id }
            }
            if ([string]::IsNullOrWhiteSpace($SessionId)) { throw 'Review requires -SessionId or an in-progress current-session checkpoint.' }
        }
        $NextReview = $StudyDate.AddDays($Intervals[$NewLevel]).ToString('yyyy-MM-dd')
        $Event = [pscustomobject][ordered]@{
            event_id = 'R' + $StudyNow.ToString('yyyyMMddTHHmmssfff') + '-' + $Id + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6)
            reviewed_at = Get-StudyTimestamp
            study_date = $StudyDate.ToString('yyyy-MM-dd')
            session_id = $SessionId
            item_type = $Collection
            item_id = $Id
            result = $Result
            old_level = [string]$CurrentLevel
            new_level = [string]$NewLevel
            previous_due = [string]$Item.next_review
            next_review = $NextReview
        }
        Add-ReviewEvent -Event $Event
        $Item.level = [string]$NewLevel
        $Item.last_review = $StudyDate.ToString('yyyy-MM-dd')
        $Item.next_review = $NextReview
        Write-TableRows -Path $Path -Rows $Rows -Headers $Headers
        $Event | ConvertTo-Json
    }

    'Summary' {
        Get-Metrics -VocabularyRows $Vocabulary -ErrorRows $Errors -PlanRows $Plans -SessionRows $Sessions | ConvertTo-Json -Depth 5
    }

    'Checkpoint' {
        if ([string]::IsNullOrWhiteSpace($SessionId) -or [string]::IsNullOrWhiteSpace($Stage) -or [string]::IsNullOrWhiteSpace($PrimarySkill) -or [string]::IsNullOrWhiteSpace($SessionType)) {
            throw 'Checkpoint requires -SessionId, -Stage, -PrimarySkill, and -SessionType.'
        }
        $Timestamp = Get-StudyTimestamp
        $Checkpoint = $null
        if (Test-Path -LiteralPath $CheckpointPath -PathType Leaf) {
            $Checkpoint = Get-Content -Raw -Encoding UTF8 -LiteralPath $CheckpointPath | ConvertFrom-Json
            if ($Checkpoint.status -eq 'in_progress' -and $Checkpoint.session_id -ne $SessionId) {
                throw "Another session is still in progress: $($Checkpoint.session_id). Resume or finalize it first."
            }
        }
        if ($null -eq $Checkpoint -or $Checkpoint.session_id -ne $SessionId -or $Checkpoint.status -in @('completed', 'abandoned')) {
            $Checkpoint = [pscustomobject][ordered]@{
                schema_version = 1
                status = 'in_progress'
                session_id = $SessionId
                plan_item_id = $(if ([string]::IsNullOrWhiteSpace($PlanItemId)) { 'none' } else { $PlanItemId })
                study_date = $StudyDate.ToString('yyyy-MM-dd')
                study_timezone = [string]$Settings.study_timezone
                session_type = $SessionType
                primary_skill = $PrimarySkill
                started_at = $Timestamp
                updated_at = $Timestamp
                last_completed_stage = ''
                checkpoints = @()
            }
        }
        $Entry = [pscustomobject][ordered]@{ stage = $Stage; saved_at = $Timestamp; note = [string]$Note }
        $Checkpoint.checkpoints = @($Checkpoint.checkpoints) + $Entry
        $Checkpoint.last_completed_stage = $Stage
        $Checkpoint.updated_at = $Timestamp
        Write-AtomicText -Path $CheckpointPath -Text ($Checkpoint | ConvertTo-Json -Depth 8)
        [pscustomobject]@{ status = 'saved'; session_id = $SessionId; stage = $Stage; path = $CheckpointPath } | ConvertTo-Json
    }

    'CloseCheckpoint' {
        if ([string]::IsNullOrWhiteSpace($SessionId)) { throw 'CloseCheckpoint requires -SessionId.' }
        if (-not (Test-Path -LiteralPath $CheckpointPath -PathType Leaf)) { throw 'No current-session checkpoint exists.' }
        $Checkpoint = Get-Content -Raw -Encoding UTF8 -LiteralPath $CheckpointPath | ConvertFrom-Json
        if ($Checkpoint.session_id -ne $SessionId) { throw "Checkpoint belongs to $($Checkpoint.session_id), not $SessionId." }
        $RecordedSessions = @($Sessions | Where-Object { $_.Meta.ContainsKey('session_id') -and $_.Meta.session_id -eq $SessionId })
        if ($RecordedSessions.Count -ne 1 -or $RecordedSessions[0].Meta.status -ne 'completed') { throw 'CloseCheckpoint requires one matching completed session file.' }
        $Checkpoint.status = 'completed'
        $Checkpoint.updated_at = Get-StudyTimestamp
        $Checkpoint.last_completed_stage = 'recording'
        Write-AtomicText -Path $CheckpointPath -Text ($Checkpoint | ConvertTo-Json -Depth 8)
        [pscustomobject]@{ status = 'completed'; session_id = $SessionId } | ConvertTo-Json
    }

    'AbandonCheckpoint' {
        if ([string]::IsNullOrWhiteSpace($SessionId)) { throw 'AbandonCheckpoint requires -SessionId.' }
        if (-not (Test-Path -LiteralPath $CheckpointPath -PathType Leaf)) { throw 'No current-session checkpoint exists.' }
        $Checkpoint = Get-Content -Raw -Encoding UTF8 -LiteralPath $CheckpointPath | ConvertFrom-Json
        if ($Checkpoint.session_id -ne $SessionId) { throw "Checkpoint belongs to $($Checkpoint.session_id), not $SessionId." }
        $RecordedSessions = @($Sessions | Where-Object { $_.Meta.ContainsKey('session_id') -and $_.Meta.session_id -eq $SessionId })
        if ($RecordedSessions.Count -ne 1 -or $RecordedSessions[0].Meta.status -ne 'abandoned') { throw 'AbandonCheckpoint requires one matching abandoned session file.' }
        $Checkpoint.status = 'abandoned'
        $Checkpoint.updated_at = Get-StudyTimestamp
        if (-not [string]::IsNullOrWhiteSpace($Note)) { $Checkpoint | Add-Member -NotePropertyName abandonment_note -NotePropertyValue $Note -Force }
        Write-AtomicText -Path $CheckpointPath -Text ($Checkpoint | ConvertTo-Json -Depth 8)
        [pscustomobject]@{ status = 'abandoned'; session_id = $SessionId } | ConvertTo-Json
    }

    'Rebuild' {
        $Plans = @(Sync-PlanState -PlanRows $Plans -SessionRows $Sessions)
        Write-TableRows -Path $PlanItemsPath -Rows $Plans -Headers $PlanHeaders
        $Metrics = Get-Metrics -VocabularyRows $Vocabulary -ErrorRows $Errors -PlanRows $Plans -SessionRows $Sessions
        Replace-MarkedBlock -Path $DashboardPath -StartMarker '<!-- AUTO:METRICS:START -->' -EndMarker '<!-- AUTO:METRICS:END -->' -Body (Get-DashboardBlock -Metrics $Metrics)
        Replace-MarkedBlock -Path $CurrentPlanPath -StartMarker '<!-- AUTO:PLAN:START -->' -EndMarker '<!-- AUTO:PLAN:END -->' -Body (Get-PlanBlock -PlanRows $Plans)
        $Dashboard = Get-Content -Raw -Encoding UTF8 -LiteralPath $DashboardPath
        $Dashboard = [regex]::Replace($Dashboard, '(?m)^- 最后更新：.*$', ('- 最后更新：' + $StudyDate.ToString('yyyy-MM-dd')), 1)
        Write-AtomicText -Path $DashboardPath -Text $Dashboard
        $PlanStatus = if (@($Plans | Where-Object { $_.status -in @('planned', 'in_progress', 'missed') }).Count -gt 0) { '进行中' } else { '已完成' }
        $PlanDocument = Get-Content -Raw -Encoding UTF8 -LiteralPath $CurrentPlanPath
        $PlanDocument = [regex]::Replace($PlanDocument, '(?m)^- 状态：.*$', ('- 状态：' + $PlanStatus), 1)
        Write-AtomicText -Path $CurrentPlanPath -Text $PlanDocument
        $Metrics | ConvertTo-Json -Depth 5
    }

    'MonthlySummary' { New-PeriodSummary -Kind month -Key $PeriodKey | ConvertTo-Json }
    'QuarterlySummary' { New-PeriodSummary -Kind quarter -Key $PeriodKey | ConvertTo-Json }

    'Validate' {
        $ValidationErrors = New-Object System.Collections.Generic.List[string]
        $ValidationWarnings = New-Object System.Collections.Generic.List[string]
        if ([string]$Settings.study_timezone -ne 'Asia/Shanghai') { $ValidationErrors.Add('settings.json study_timezone must be Asia/Shanghai.') }
        if ([string]$Settings.windows_timezone_id -ne 'China Standard Time') { $ValidationErrors.Add('settings.json windows_timezone_id must be China Standard Time.') }
        if ([int]$Settings.schema_version -lt 2) { $ValidationErrors.Add('settings.json schema_version must be at least 2.') }
        if ([string]$Settings.completion_window_days -notmatch '^\d+$' -or [int]$Settings.completion_window_days -lt 1) { $ValidationErrors.Add('settings.json completion_window_days must be a positive integer.') }
        if ([string]$Settings.daily_target_minutes -notmatch '^\d+$' -or [int]$Settings.daily_target_minutes -lt 1) { $ValidationErrors.Add('settings.json daily_target_minutes must be a positive integer.') }

        foreach ($Definition in @(
            [pscustomobject]@{ Label = 'Vocabulary'; Rows = $Vocabulary; Id = 'id' },
            [pscustomobject]@{ Label = 'Error log'; Rows = $Errors; Id = 'id' },
            [pscustomobject]@{ Label = 'Review history'; Rows = $ReviewHistory; Id = 'event_id' },
            [pscustomobject]@{ Label = 'Plan items'; Rows = $Plans; Id = 'plan_item_id' }
        )) {
            $Duplicates = @($Definition.Rows | Group-Object -Property $Definition.Id | Where-Object { $_.Count -gt 1 -or [string]::IsNullOrWhiteSpace($_.Name) })
            if ($Duplicates.Count -gt 0) { $ValidationErrors.Add("$($Definition.Label) contains duplicate or empty IDs: $($Duplicates.Name -join ', ')") }
        }

        foreach ($Row in @($Vocabulary) + @($Errors)) {
            if ($Row.status -notin @('active', 'mastered', 'paused')) { $ValidationErrors.Add("Invalid item status for $($Row.id): $($Row.status)") }
            if ($Row.level -notmatch '^\d+$' -or [int]$Row.level -lt 0 -or [int]$Row.level -gt 5) { $ValidationErrors.Add("Invalid level for $($Row.id): $($Row.level)") }
            foreach ($DateValue in @($Row.next_review, $Row.last_review)) {
                if (-not [string]::IsNullOrWhiteSpace($DateValue) -and -not (Test-DateValue $DateValue)) { $ValidationErrors.Add("Invalid date for $($Row.id): $DateValue") }
            }
        }

        $SessionById = @{}
        $PlanById = @{}
        foreach ($Plan in $Plans) { $PlanById[$Plan.plan_item_id] = $Plan }
        $RequiredSessionFields = @('session_id', 'date', 'plan_item_id', 'session_type', 'status', 'duration_minutes', 'primary_skill', 'study_timezone', 'source_type')
        foreach ($Session in $Sessions) {
            foreach ($Field in $RequiredSessionFields) {
                if (-not $Session.Meta.ContainsKey($Field) -or [string]::IsNullOrWhiteSpace([string]$Session.Meta[$Field])) { $ValidationErrors.Add("$($Session.RelativeFile) is missing frontmatter field: $Field") }
            }
            if (-not $Session.Meta.ContainsKey('session_id')) { continue }
            $CurrentSessionId = [string]$Session.Meta.session_id
            if ($SessionById.ContainsKey($CurrentSessionId)) { $ValidationErrors.Add("Duplicate session_id: $CurrentSessionId") } else { $SessionById[$CurrentSessionId] = $Session }
            if ($Session.Meta.ContainsKey('date') -and -not (Test-DateValue $Session.Meta.date)) { $ValidationErrors.Add("Invalid session date in $($Session.RelativeFile): $($Session.Meta.date)") }
            if ($Session.Meta.ContainsKey('status') -and $Session.Meta.status -notin @('in_progress', 'completed', 'abandoned')) { $ValidationErrors.Add("Invalid session status in $($Session.RelativeFile): $($Session.Meta.status)") }
            if ($Session.Meta.ContainsKey('session_type') -and $Session.Meta.session_type -notin @('daily', 'diagnostic', 'review', 'assessment', 'extra')) { $ValidationErrors.Add("Invalid session_type in $($Session.RelativeFile): $($Session.Meta.session_type)") }
            if ($Session.Meta.ContainsKey('primary_skill') -and $Session.Meta.primary_skill -notin @('listening', 'speaking', 'reading', 'writing', 'mixed', 'review')) { $ValidationErrors.Add("Invalid primary_skill in $($Session.RelativeFile): $($Session.Meta.primary_skill)") }
            if ($Session.Meta.ContainsKey('source_type') -and $Session.Meta.source_type -notin @('network', 'user-provided', 'fallback', 'none')) { $ValidationErrors.Add("Invalid source_type in $($Session.RelativeFile): $($Session.Meta.source_type)") }
            if ($Session.Meta.ContainsKey('study_timezone') -and $Session.Meta.study_timezone -ne [string]$Settings.study_timezone) { $ValidationErrors.Add("Timezone mismatch in $($Session.RelativeFile): $($Session.Meta.study_timezone)") }
            if ($Session.Meta.ContainsKey('duration_minutes') -and $Session.Meta.duration_minutes -notmatch '^\d+$') { $ValidationErrors.Add("Invalid duration_minutes in $($Session.RelativeFile): $($Session.Meta.duration_minutes)") }
            if ($Session.Meta.ContainsKey('plan_item_id') -and $Session.Meta.plan_item_id -ne 'none' -and -not $PlanById.ContainsKey($Session.Meta.plan_item_id)) { $ValidationErrors.Add("Unknown plan_item_id in $($Session.RelativeFile): $($Session.Meta.plan_item_id)") }
            if ($Session.Meta.ContainsKey('source_type') -and $Session.Meta.source_type -eq 'network' -and $Session.Content -notmatch '(?m)^- URL：https?://') { $ValidationWarnings.Add("Network session lacks a recognizable URL line: $($Session.RelativeFile)") }
            if ($Session.Meta.ContainsKey('date') -and (Test-DateValue $Session.Meta.date)) {
                $ExpectedFolder = 'sessions/' + $Session.Meta.date.Substring(0, 4) + '/' + $Session.Meta.date.Substring(5, 2) + '/'
                if (-not $Session.RelativeFile.StartsWith($ExpectedFolder)) { $ValidationErrors.Add("Session path does not match its date: $($Session.RelativeFile)") }
            }
        }

        foreach ($Plan in $Plans) {
            if (-not (Test-DateValue $Plan.planned_date)) { $ValidationErrors.Add("Invalid planned_date for $($Plan.plan_item_id): $($Plan.planned_date)") }
            if ($Plan.required -notin @('true', 'false')) { $ValidationErrors.Add("Invalid required value for $($Plan.plan_item_id): $($Plan.required)") }
            if ($Plan.status -notin @('planned', 'in_progress', 'completed', 'missed', 'cancelled')) { $ValidationErrors.Add("Invalid plan status for $($Plan.plan_item_id): $($Plan.status)") }
            if ($Plan.sequence -notmatch '^\d+$') { $ValidationErrors.Add("Invalid sequence for $($Plan.plan_item_id): $($Plan.sequence)") }
            if ($Plan.status -eq 'completed') {
                if ([string]::IsNullOrWhiteSpace($Plan.completed_session_id) -or -not $SessionById.ContainsKey($Plan.completed_session_id)) { $ValidationErrors.Add("Completed plan item lacks a valid session: $($Plan.plan_item_id)") }
                elseif ($SessionById[$Plan.completed_session_id].Meta.plan_item_id -ne $Plan.plan_item_id) { $ValidationErrors.Add("Plan/session mismatch for $($Plan.plan_item_id) and $($Plan.completed_session_id)") }
            }
            elseif (-not [string]::IsNullOrWhiteSpace($Plan.completed_session_id)) { $ValidationErrors.Add("Non-completed plan item has a completed_session_id: $($Plan.plan_item_id)") }
            if ((Test-DateValue $Plan.planned_date) -and $Plan.status -eq 'planned' -and [datetime]::ParseExact($Plan.planned_date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -lt $StudyDate) { $ValidationErrors.Add("Past plan item is still planned; run Rebuild: $($Plan.plan_item_id)") }
            if ((Test-DateValue $Plan.planned_date) -and $Plan.status -eq 'missed' -and [datetime]::ParseExact($Plan.planned_date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture).Date -ge $StudyDate) { $ValidationErrors.Add("Future or current plan item cannot be missed: $($Plan.plan_item_id)") }
        }
        foreach ($Session in $Sessions) {
            if ($Session.Meta.ContainsKey('status') -and $Session.Meta.status -eq 'completed' -and $Session.Meta.ContainsKey('plan_item_id') -and $Session.Meta.plan_item_id -ne 'none' -and $PlanById.ContainsKey($Session.Meta.plan_item_id)) {
                $LinkedPlan = $PlanById[$Session.Meta.plan_item_id]
                if ($LinkedPlan.status -ne 'completed' -or $LinkedPlan.completed_session_id -ne $Session.Meta.session_id) { $ValidationErrors.Add("Completed session is not linked back from its plan item: $($Session.Meta.session_id)") }
            }
        }
        foreach ($Row in @($Vocabulary) + @($Errors)) {
            if (-not [string]::IsNullOrWhiteSpace($Row.source_session) -and -not $SessionById.ContainsKey($Row.source_session)) { $ValidationErrors.Add("$($Row.id) references an unknown source_session: $($Row.source_session)") }
        }

        foreach ($Event in $ReviewHistory) {
            if ($Event.result -notin @('again', 'hard', 'good', 'easy')) { $ValidationErrors.Add("Invalid review result for $($Event.event_id): $($Event.result)") }
            if ($Event.item_type -eq 'vocabulary') { $KnownItem = @($Vocabulary | Where-Object { $_.id -eq $Event.item_id }) }
            elseif ($Event.item_type -eq 'error') { $KnownItem = @($Errors | Where-Object { $_.id -eq $Event.item_id }) }
            else { $KnownItem = @(); $ValidationErrors.Add("Invalid review item_type for $($Event.event_id): $($Event.item_type)") }
            if ($KnownItem.Count -ne 1) { $ValidationErrors.Add("Review event references unknown item: $($Event.event_id) -> $($Event.item_id)") }
            if (-not (Test-DateValue $Event.study_date) -or -not (Test-DateValue $Event.next_review)) { $ValidationErrors.Add("Review event has an invalid date: $($Event.event_id)") }
            if (-not [string]::IsNullOrWhiteSpace($Event.previous_due) -and -not (Test-DateValue $Event.previous_due)) { $ValidationErrors.Add("Review event has an invalid previous_due: $($Event.event_id)") }
            if (-not (Test-StudyTimestamp $Event.reviewed_at)) { $ValidationErrors.Add("Review event has an invalid Shanghai timestamp: $($Event.event_id)") }
            else {
                $ReviewedAt = [DateTimeOffset]::Parse($Event.reviewed_at, [Globalization.CultureInfo]::InvariantCulture)
                if ($ReviewedAt.ToOffset([TimeSpan]::FromHours(8)).ToString('yyyy-MM-dd') -ne $Event.study_date) { $ValidationErrors.Add("Review timestamp/date mismatch: $($Event.event_id)") }
            }
            if ([string]::IsNullOrWhiteSpace($Event.session_id) -or -not $SessionById.ContainsKey($Event.session_id)) { $ValidationErrors.Add("Review event references an unknown session: $($Event.event_id) -> $($Event.session_id)") }
            if ($Event.old_level -notmatch '^\d+$' -or $Event.new_level -notmatch '^\d+$' -or [int]$Event.old_level -gt 5 -or [int]$Event.new_level -gt 5) { $ValidationErrors.Add("Review event has an invalid level: $($Event.event_id)") }
        }
        foreach ($HistoryGroup in @($ReviewHistory | Group-Object item_id)) {
            $OrderedEvents = @($HistoryGroup.Group | Sort-Object reviewed_at)
            for ($Index = 1; $Index -lt $OrderedEvents.Count; $Index++) {
                if ($OrderedEvents[$Index].old_level -ne $OrderedEvents[$Index - 1].new_level -or $OrderedEvents[$Index].previous_due -ne $OrderedEvents[$Index - 1].next_review) { $ValidationErrors.Add("Review history is discontinuous for $($HistoryGroup.Name) at $($OrderedEvents[$Index].event_id)") }
            }
        }
        foreach ($Item in @($Vocabulary) + @($Errors)) {
            $Latest = @($ReviewHistory | Where-Object { $_.item_id -eq $Item.id } | Sort-Object reviewed_at | Select-Object -Last 1)
            if ($Latest.Count -eq 1 -and ($Item.level -ne $Latest[0].new_level -or $Item.next_review -ne $Latest[0].next_review -or $Item.last_review -ne $Latest[0].study_date)) { $ValidationErrors.Add("Current state disagrees with latest review event for $($Item.id)") }
        }

        if (Test-Path -LiteralPath $CheckpointPath -PathType Leaf) {
            try {
                $Checkpoint = Get-Content -Raw -Encoding UTF8 -LiteralPath $CheckpointPath | ConvertFrom-Json
                foreach ($Field in @('schema_version', 'status', 'session_id', 'plan_item_id', 'study_date', 'study_timezone', 'session_type', 'primary_skill', 'started_at', 'updated_at', 'last_completed_stage', 'checkpoints')) {
                    if ($Field -notin $Checkpoint.PSObject.Properties.Name) { $ValidationErrors.Add("current-session is missing field: $Field") }
                }
                if ($Checkpoint.status -notin @('in_progress', 'completed', 'abandoned')) { $ValidationErrors.Add("Invalid current-session status: $($Checkpoint.status)") }
                if ($Checkpoint.study_timezone -ne [string]$Settings.study_timezone) { $ValidationErrors.Add('current-session timezone does not match settings.json.') }
                if (-not (Test-DateValue $Checkpoint.study_date)) { $ValidationErrors.Add('current-session has an invalid study_date.') }
                if (-not (Test-StudyTimestamp $Checkpoint.started_at) -or -not (Test-StudyTimestamp $Checkpoint.updated_at)) { $ValidationErrors.Add('current-session has an invalid Shanghai timestamp.') }
                if ($Checkpoint.session_type -notin @('daily', 'diagnostic', 'review', 'assessment', 'extra')) { $ValidationErrors.Add("Invalid current-session session_type: $($Checkpoint.session_type)") }
                if ($Checkpoint.primary_skill -notin @('listening', 'speaking', 'reading', 'writing', 'mixed', 'review')) { $ValidationErrors.Add("Invalid current-session primary_skill: $($Checkpoint.primary_skill)") }
                if ($Checkpoint.plan_item_id -ne 'none' -and -not $PlanById.ContainsKey([string]$Checkpoint.plan_item_id)) { $ValidationErrors.Add("current-session references an unknown plan item: $($Checkpoint.plan_item_id)") }
                if ($Checkpoint.last_completed_stage -notin @('', 'review', 'input', 'output', 'feedback', 'recording')) { $ValidationErrors.Add("Invalid current-session last_completed_stage: $($Checkpoint.last_completed_stage)") }
                foreach ($Entry in @($Checkpoint.checkpoints)) {
                    if ($Entry.stage -notin @('review', 'input', 'output', 'feedback', 'recording')) { $ValidationErrors.Add("Invalid checkpoint stage: $($Entry.stage)") }
                    if (-not (Test-StudyTimestamp $Entry.saved_at)) { $ValidationErrors.Add("Invalid checkpoint saved_at for stage: $($Entry.stage)") }
                }
                if ($Checkpoint.status -eq 'in_progress' -and $SessionById.ContainsKey([string]$Checkpoint.session_id) -and $SessionById[[string]$Checkpoint.session_id].Meta.status -eq 'completed') { $ValidationErrors.Add('current-session is in progress but the same session is already completed.') }
                if ($Checkpoint.status -eq 'completed' -and (-not $SessionById.ContainsKey([string]$Checkpoint.session_id) -or $SessionById[[string]$Checkpoint.session_id].Meta.status -ne 'completed')) { $ValidationErrors.Add('completed current-session lacks a matching completed session file.') }
                if ($Checkpoint.status -eq 'abandoned' -and (-not $SessionById.ContainsKey([string]$Checkpoint.session_id) -or $SessionById[[string]$Checkpoint.session_id].Meta.status -ne 'abandoned')) { $ValidationErrors.Add('abandoned current-session lacks a matching abandoned session file.') }
            }
            catch { $ValidationErrors.Add("current-session checkpoint is not valid JSON: $($_.Exception.Message)") }
        }

        $Metrics = Get-Metrics -VocabularyRows $Vocabulary -ErrorRows $Errors -PlanRows $Plans -SessionRows $Sessions
        $ExpectedDashboardBlock = Get-DashboardBlock -Metrics $Metrics
        if (-not (Get-Content -Raw -Encoding UTF8 -LiteralPath $DashboardPath).Contains($ExpectedDashboardBlock)) { $ValidationWarnings.Add('Dashboard metrics are stale; run tracker Rebuild.') }
        $ExpectedPlanBlock = Get-PlanBlock -PlanRows $Plans
        if (-not (Get-Content -Raw -Encoding UTF8 -LiteralPath $CurrentPlanPath).Contains($ExpectedPlanBlock)) { $ValidationWarnings.Add('Current plan view is stale; run tracker Rebuild.') }

        $Report = [pscustomobject]@{
            status = $(if ($ValidationErrors.Count -eq 0) { 'valid' } else { 'invalid' })
            study_date = $StudyDate.ToString('yyyy-MM-dd')
            study_timezone = [string]$Settings.study_timezone
            error_count = $ValidationErrors.Count
            warning_count = $ValidationWarnings.Count
            errors = @($ValidationErrors)
            warnings = @($ValidationWarnings)
            counts = [pscustomobject]@{ sessions = $Sessions.Count; plan_items = $Plans.Count; vocabulary = $Vocabulary.Count; errors = $Errors.Count; review_events = $ReviewHistory.Count }
        }
        $Report | ConvertTo-Json -Depth 6
        if ($ValidationErrors.Count -gt 0) { exit 1 }
    }
}
