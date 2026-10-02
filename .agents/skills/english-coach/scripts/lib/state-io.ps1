Set-StrictMode -Version Latest

function ConvertFrom-StableJson {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Json)

    $Command = Get-Command ConvertFrom-Json -ErrorAction Stop
    if ($Command.Parameters.ContainsKey('DateKind')) {
        return $Json | ConvertFrom-Json -DateKind String
    }
    return $Json | ConvertFrom-Json
}

function Read-StableJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowMissing
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if ($AllowMissing) { return $null }
        throw "Missing JSON file: $Path"
    }
    return ConvertFrom-StableJson -Json (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
}

function ConvertTo-CanonicalNode {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [char] -or $Value -is [bool] -or
        $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or $Value -is [single] -or
        $Value -is [double] -or $Value -is [decimal]) {
        return $Value
    }
    if ($Value -is [datetimeoffset]) { return $Value.ToString('o') }
    if ($Value -is [datetime]) { return $Value.ToString('o') }

    if ($Value -is [System.Collections.IDictionary]) {
        $Ordered = [ordered]@{}
        foreach ($Key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
            $Ordered[$Key] = ConvertTo-CanonicalNode -Value $Value[$Key]
        }
        return [pscustomobject]$Ordered
    }

    $Properties = @($Value.PSObject.Properties | Where-Object {
        $_.MemberType -in @('NoteProperty', 'Property', 'AliasProperty', 'ScriptProperty')
    })
    if ($Properties.Count -gt 0 -and -not ($Value -is [System.Collections.IEnumerable])) {
        $Ordered = [ordered]@{}
        foreach ($Property in @($Properties | Sort-Object Name)) {
            $Ordered[$Property.Name] = ConvertTo-CanonicalNode -Value $Property.Value
        }
        return [pscustomobject]$Ordered
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $Items = [System.Collections.Generic.List[object]]::new()
        foreach ($Item in $Value) { $Items.Add((ConvertTo-CanonicalNode -Value $Item)) }
        return ,$Items.ToArray()
    }

    return [string]$Value
}

function ConvertTo-CanonicalJson {
    param([AllowNull()][object]$Value)
    return (ConvertTo-CanonicalNode -Value $Value) | ConvertTo-Json -Depth 100 -Compress
}

function Get-Sha256Text {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $Bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($Hasher.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $Hasher.Dispose() }
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-PayloadHash {
    param([AllowNull()][object]$Payload)
    return Get-Sha256Text -Text (ConvertTo-CanonicalJson -Value $Payload)
}

function Add-StateIntegrity {
    param([Parameter(Mandatory = $true)][object]$Value)

    $Core = [ordered]@{}
    foreach ($Property in @($Value.PSObject.Properties | Sort-Object Name)) {
        if ($Property.Name -ne 'integrity_sha256') { $Core[$Property.Name] = $Property.Value }
    }
    $Protected = [ordered]@{}
    foreach ($Key in $Core.Keys) { $Protected[$Key] = $Core[$Key] }
    $Protected.integrity_sha256 = Get-PayloadHash -Payload ([pscustomobject]$Core)
    return [pscustomobject]$Protected
}

function Test-StateIntegrity {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value -or 'integrity_sha256' -notin $Value.PSObject.Properties.Name) { return $false }
    $Expected = [string]$Value.integrity_sha256
    $Core = [ordered]@{}
    foreach ($Property in @($Value.PSObject.Properties | Sort-Object Name)) {
        if ($Property.Name -ne 'integrity_sha256') { $Core[$Property.Name] = $Property.Value }
    }
    return $Expected -eq (Get-PayloadHash -Payload ([pscustomobject]$Core))
}

function Write-FlushedUtf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    $Directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Force -Path $Directory)
    }
    $Bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $Stream = [IO.FileStream]::new(
        $Path,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None,
        4096,
        [IO.FileOptions]::WriteThrough
    )
    try {
        $Stream.Write($Bytes, 0, $Bytes.Length)
        $Stream.Flush($true)
    }
    finally { $Stream.Dispose() }
}

function Move-AtomicWithPrevious {
    param(
        [Parameter(Mandatory = $true)][string]$TemporaryPath,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$PreviousPath
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        [IO.File]::Move($TemporaryPath, $Path)
        return
    }
    $KeepPrevious = -not [string]::IsNullOrWhiteSpace($PreviousPath)
    if ($KeepPrevious) {
        try {
            [IO.File]::Replace($TemporaryPath, $Path, $PreviousPath, $true)
            return
        }
        catch [PlatformNotSupportedException] { }
        catch [IOException] { }
    }
    if ($KeepPrevious) { [IO.File]::Copy($Path, $PreviousPath, $true) }
    [IO.File]::Move($TemporaryPath, $Path, $true)
}

function Write-DurableJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value,
        [int]$MaximumBytes = 262144,
        [switch]$WithoutPrevious
    )

    $Protected = Add-StateIntegrity -Value $Value
    $Json = $Protected | ConvertTo-Json -Depth 100
    if ([Text.Encoding]::UTF8.GetByteCount($Json) -gt $MaximumBytes) {
        throw "State payload exceeds the $MaximumBytes byte limit: $Path"
    }
    $Directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Force -Path $Directory)
    }
    $TemporaryPath = Join-Path $Directory ((Split-Path -Leaf $Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Write-FlushedUtf8File -Path $TemporaryPath -Text $Json
        $PreviousPath = if ($WithoutPrevious) { '' } else { $Path + '.previous' }
        Move-AtomicWithPrevious -TemporaryPath $TemporaryPath -Path $Path -PreviousPath $PreviousPath
    }
    finally {
        if (Test-Path -LiteralPath $TemporaryPath -PathType Leaf) { Remove-Item -LiteralPath $TemporaryPath -Force }
    }
    return $Protected
}

function Read-DurableJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowMissing
    )

    foreach ($Candidate in @($Path, ($Path + '.previous'))) {
        if (-not (Test-Path -LiteralPath $Candidate -PathType Leaf)) { continue }
        try {
            $Value = Read-StableJsonFile -Path $Candidate
            if (Test-StateIntegrity -Value $Value) {
                return [pscustomobject]@{
                    status = 'valid'
                    source = $(if ($Candidate -eq $Path) { 'current' } else { 'previous' })
                    path = $Candidate
                    value = $Value
                }
            }
        }
        catch { }
    }
    if ($AllowMissing -and -not (Test-Path -LiteralPath $Path -PathType Leaf) -and
        -not (Test-Path -LiteralPath ($Path + '.previous') -PathType Leaf)) {
        return $null
    }
    return [pscustomobject]@{ status = 'invalid'; source = 'none'; path = $Path; value = $null }
}

function Write-DurableText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    $Directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Force -Path $Directory)
    }
    $TemporaryPath = Join-Path $Directory ((Split-Path -Leaf $Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        Write-FlushedUtf8File -Path $TemporaryPath -Text $Text
        Move-AtomicWithPrevious -TemporaryPath $TemporaryPath -Path $Path -PreviousPath ($Path + '.previous')
    }
    finally {
        if (Test-Path -LiteralPath $TemporaryPath -PathType Leaf) { Remove-Item -LiteralPath $TemporaryPath -Force }
    }
}

function New-StableIdentifier {
    param(
        [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9_-]*$')][string]$Prefix,
        [Parameter(Mandatory = $true)][string]$Seed,
        [ValidateRange(8, 48)][int]$HashLength = 24
    )
    $Hash = Get-Sha256Text -Text $Seed
    return $Prefix + $Hash.Substring(0, $HashLength)
}

function Invoke-WithFileLock {
    param(
        [Parameter(Mandatory = $true)][string]$LockPath,
        [Parameter(Mandatory = $true)][scriptblock]$Script,
        [ValidateRange(0, 10000)][int]$TimeoutMilliseconds = 2000
    )

    $Directory = Split-Path -Parent $LockPath
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Force -Path $Directory)
    }
    $Started = [Diagnostics.Stopwatch]::StartNew()
    $Handle = $null
    while ($null -eq $Handle) {
        try {
            $Handle = [IO.FileStream]::new($LockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        }
        catch [IO.IOException] {
            if ($Started.ElapsedMilliseconds -ge $TimeoutMilliseconds) { throw "State is busy: $LockPath" }
            Start-Sleep -Milliseconds 25
        }
    }
    try { return & $Script }
    finally { $Handle.Dispose() }
}

function Get-TsvRows {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Headers,
        [switch]$AllowMissing
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if ($AllowMissing) { return @() }
        throw "Missing TSV file: $Path"
    }
    $HeaderLine = Get-Content -LiteralPath $Path -Encoding UTF8 -TotalCount 1
    $Actual = @(($HeaderLine -split "`t") | ForEach-Object { $_.Trim().Trim('"') })
    if (($Actual -join '|') -ne ($Headers -join '|')) {
        throw "Unexpected headers in $Path. Expected: $($Headers -join ', ')"
    }
    return @(Import-Csv -LiteralPath $Path -Delimiter "`t" -Encoding UTF8)
}

function ConvertTo-TsvField {
    param([AllowNull()][object]$Value)
    $Text = if ($null -eq $Value) { '' } else { [string]$Value }
    if ($Text.Contains("`t") -or $Text.Contains("`r") -or $Text.Contains("`n") -or $Text.Contains('"')) {
        return '"' + $Text.Replace('"', '""') + '"'
    }
    return $Text
}

function ConvertTo-TsvText {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory = $true)][string[]]$Headers
    )

    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add(($Headers -join "`t"))
    foreach ($Row in @($Rows)) {
        $Values = foreach ($Header in $Headers) {
            $Property = $Row.PSObject.Properties[$Header]
            ConvertTo-TsvField -Value $(if ($null -eq $Property) { '' } else { $Property.Value })
        }
        $Lines.Add(($Values -join "`t"))
    }
    return ($Lines -join "`r`n") + "`r`n"
}

function Write-TsvRowsAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory = $true)][string[]]$Headers
    )
    Write-DurableText -Path $Path -Text (ConvertTo-TsvText -Rows $Rows -Headers $Headers)
}

function Add-TsvRowsIdempotent {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Rows,
        [Parameter(Mandatory = $true)][string[]]$Headers,
        [Parameter(Mandatory = $true)][string]$IdColumn
    )

    $Existing = @(Get-TsvRows -Path $Path -Headers $Headers)
    $Known = @{}
    foreach ($Row in $Existing) { $Known[[string]$Row.$IdColumn] = $true }
    $Added = 0
    foreach ($Row in @($Rows)) {
        $Id = [string]$Row.$IdColumn
        if ([string]::IsNullOrWhiteSpace($Id)) { throw "TSV row has an empty $IdColumn." }
        if ($Known.ContainsKey($Id)) {
            $ExistingRow = @($Existing | Where-Object { [string]$_.$IdColumn -eq $Id } | Select-Object -First 1)
            $Old = [ordered]@{}; $New = [ordered]@{}
            foreach ($Header in $Headers) {
                $Old[$Header] = [string]$ExistingRow[0].$Header
                $New[$Header] = [string]$Row.$Header
            }
            if ((Get-PayloadHash -Payload ([pscustomobject]$Old)) -ne (Get-PayloadHash -Payload ([pscustomobject]$New))) {
                throw "Idempotency conflict for $IdColumn=$Id in $Path"
            }
            continue
        }
        $Existing += $Row
        $Known[$Id] = $true
        $Added++
    }
    if ($Added -gt 0) { Write-TsvRowsAtomic -Path $Path -Rows $Existing -Headers $Headers }
    return $Added
}

function Invoke-FaultPoint {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$RequestedFault
    )
    $Effective = if (-not [string]::IsNullOrWhiteSpace($RequestedFault)) {
        $RequestedFault
    }
    else {
        [Environment]::GetEnvironmentVariable('ENGLISH_COACH_FAULT_AFTER')
    }
    if ($Effective -eq $Name) { throw "Injected fault after phase: $Name" }
}

function New-TrackerResponse {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$NextAction,
        [AllowNull()][object]$Receipt = $null,
        [string]$ReasonCode = 'ok',
        [AllowNull()][object]$PreparedStep = $null
    )
    return [pscustomobject]@{
        status = $Status
        next_action = $NextAction
        receipt = $Receipt
        reason_code = $ReasonCode
        prepared_step = $PreparedStep
    }
}
