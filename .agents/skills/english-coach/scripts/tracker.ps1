[CmdletBinding()]
param(
    [ValidateSet('Due', 'Review', 'Summary', 'Validate')]
    [string]$Action = 'Due',

    [string]$ProjectRoot,

    [datetime]$Date = (Get-Date),

    [ValidateSet('vocabulary', 'error')]
    [string]$Collection,

    [string]$Id,

    [ValidateSet('again', 'hard', 'good', 'easy')]
    [string]$Result
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..')).Path
}
else {
    $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
}

$VocabularyPath = Join-Path $ProjectRoot 'learner\vocabulary.tsv'
$ErrorLogPath = Join-Path $ProjectRoot 'learner\error-log.tsv'
$SessionPath = Join-Path $ProjectRoot 'sessions'
$Intervals = @(1, 3, 7, 14, 30, 60)

function Get-TableRows {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$RequiredHeaders
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing data file: $Path"
    }

    $HeaderLine = Get-Content -LiteralPath $Path -Encoding UTF8 -TotalCount 1
    if ([string]::IsNullOrWhiteSpace($HeaderLine)) {
        throw "Empty data file: $Path"
    }

    $ActualHeaders = @(($HeaderLine -split "`t") | ForEach-Object { $_.Trim().Trim('"') })
    if (($ActualHeaders -join '|') -ne ($RequiredHeaders -join '|')) {
        throw "Unexpected headers in $Path. Expected: $($RequiredHeaders -join ', ')"
    }

    return @(Import-Csv -LiteralPath $Path -Delimiter "`t" -Encoding UTF8)
}

function Get-AllRows {
    $VocabularyHeaders = @('id', 'item', 'meaning', 'context', 'status', 'level', 'next_review', 'last_review', 'source_session')
    $ErrorHeaders = @('id', 'category', 'original', 'corrected', 'explanation', 'status', 'level', 'next_review', 'last_review', 'source_session')

    return [pscustomobject]@{
        Vocabulary = @(Get-TableRows -Path $VocabularyPath -RequiredHeaders $VocabularyHeaders)
        Errors = @(Get-TableRows -Path $ErrorLogPath -RequiredHeaders $ErrorHeaders)
    }
}

function Get-DueRows {
    param([object[]]$Rows)

    $TargetDate = $Date.Date
    return @($Rows | Where-Object {
        $_.status -eq 'active' -and
        -not [string]::IsNullOrWhiteSpace($_.next_review) -and
        ([datetime]::ParseExact($_.next_review, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)).Date -le $TargetDate
    } | Sort-Object next_review, id)
}

function Assert-UniqueIds {
    param([object[]]$Rows, [string]$Label)

    $Duplicates = @($Rows | Group-Object id | Where-Object { $_.Count -gt 1 -or [string]::IsNullOrWhiteSpace($_.Name) })
    if ($Duplicates.Count -gt 0) {
        throw "$Label contains duplicate or empty IDs: $($Duplicates.Name -join ', ')"
    }
}

$Tables = Get-AllRows

switch ($Action) {
    'Due' {
        $DueVocabulary = @(Get-DueRows -Rows $Tables.Vocabulary)
        $DueErrors = @(Get-DueRows -Rows $Tables.Errors)
        [pscustomobject]@{
            date = $Date.ToString('yyyy-MM-dd')
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
            $Rows = @($Tables.Vocabulary)
            $Path = $VocabularyPath
        }
        else {
            $Rows = @($Tables.Errors)
            $Path = $ErrorLogPath
        }

        $Matches = @($Rows | Where-Object { $_.id -eq $Id })
        if ($Matches.Count -ne 1) {
            throw "Expected exactly one item with ID $Id in $Collection; found $($Matches.Count)."
        }

        $Item = $Matches[0]
        $CurrentLevel = [Math]::Max(0, [Math]::Min(5, [int]$Item.level))
        switch ($Result) {
            'again' { $NewLevel = 0 }
            'hard'  { $NewLevel = $CurrentLevel }
            'good'  { $NewLevel = [Math]::Min(5, $CurrentLevel + 1) }
            'easy'  { $NewLevel = [Math]::Min(5, $CurrentLevel + 2) }
        }

        $Item.level = [string]$NewLevel
        $Item.last_review = $Date.ToString('yyyy-MM-dd')
        $Item.next_review = $Date.Date.AddDays($Intervals[$NewLevel]).ToString('yyyy-MM-dd')
        $Rows | Export-Csv -LiteralPath $Path -Delimiter "`t" -Encoding UTF8 -NoTypeInformation

        [pscustomobject]@{
            id = $Id
            result = $Result
            level = $NewLevel
            next_review = $Item.next_review
        } | ConvertTo-Json
    }

    'Summary' {
        $Cutoff = $Date.Date.AddDays(-27)
        $SessionFiles = @()
        if (Test-Path -LiteralPath $SessionPath -PathType Container) {
            $SessionFiles = @(Get-ChildItem -LiteralPath $SessionPath -Recurse -File -Filter '*.md')
        }

        $Completed = 0
        $Minutes = 0
        foreach ($File in $SessionFiles) {
            $Lines = @(Get-Content -LiteralPath $File.FullName -Encoding UTF8 -TotalCount 30)
            $DateLine = @($Lines | Where-Object { $_ -match '^date:\s*\d{4}-\d{2}-\d{2}\s*$' } | Select-Object -First 1)
            $StatusLine = @($Lines | Where-Object { $_ -match '^status:\s*completed\s*$' } | Select-Object -First 1)
            $DurationLine = @($Lines | Where-Object { $_ -match '^duration_minutes:\s*\d+\s*$' } | Select-Object -First 1)
            if ($DateLine.Count -eq 1 -and $StatusLine.Count -eq 1) {
                $SessionDate = [datetime]::ParseExact(($DateLine[0] -replace '^date:\s*', '').Trim(), 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                if ($SessionDate.Date -ge $Cutoff -and $SessionDate.Date -le $Date.Date) {
                    $Completed++
                    if ($DurationLine.Count -eq 1) {
                        $Minutes += [int](($DurationLine[0] -replace '^duration_minutes:\s*', '').Trim())
                    }
                }
            }
        }

        [pscustomobject]@{
            window_start = $Cutoff.ToString('yyyy-MM-dd')
            window_end = $Date.ToString('yyyy-MM-dd')
            completed_sessions = $Completed
            total_minutes = $Minutes
            due_vocabulary = @(Get-DueRows -Rows $Tables.Vocabulary).Count
            due_errors = @(Get-DueRows -Rows $Tables.Errors).Count
        } | ConvertTo-Json
    }

    'Validate' {
        Assert-UniqueIds -Rows $Tables.Vocabulary -Label 'Vocabulary table'
        Assert-UniqueIds -Rows $Tables.Errors -Label 'Error table'

        foreach ($Row in @($Tables.Vocabulary) + @($Tables.Errors)) {
            if ([int]$Row.level -lt 0 -or [int]$Row.level -gt 5) {
                throw "Invalid level for $($Row.id): $($Row.level)"
            }
            foreach ($DateValue in @($Row.next_review, $Row.last_review)) {
                if (-not [string]::IsNullOrWhiteSpace($DateValue)) {
                    [void][datetime]::ParseExact($DateValue, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                }
            }
        }

        $RequiredFiles = @(
            'learner\profile.md',
            'learner\current-plan.md',
            'learner\dashboard.md'
        )
        foreach ($RelativePath in $RequiredFiles) {
            if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $RelativePath) -PathType Leaf)) {
                throw "Missing required file: $RelativePath"
            }
        }

        [pscustomobject]@{
            status = 'valid'
            vocabulary_rows = $Tables.Vocabulary.Count
            error_rows = $Tables.Errors.Count
            session_files = @(Get-ChildItem -LiteralPath $SessionPath -Recurse -File -Filter '*.md').Count
        } | ConvertTo-Json
    }
}
