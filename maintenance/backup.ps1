[CmdletBinding()]
param(
    [ValidateSet('Backup','Verify','Restore')][string]$Action='Backup',
    [string]$ProjectRoot=(Split-Path $PSScriptRoot -Parent),
    [string]$ArchivePath,
    [string]$Destination
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-BackupHash([byte[]]$Bytes) {
    $Hasher=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($Hasher.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $Hasher.Dispose() }
}

function Assert-PlainPath([string]$Path) {
    $Cursor=[IO.Path]::GetFullPath($Path)
    while ($Cursor) {
        if (Test-Path -LiteralPath $Cursor) {
            if ((Get-Item -LiteralPath $Cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked paths are not supported: $Cursor" }
        }
        $Cursor=Split-Path $Cursor -Parent
    }
}

function Get-BackupFiles([string]$Root) {
    $Queue=[Collections.Generic.Queue[string]]::new()
    $Queue.Enqueue($Root)
    while ($Queue.Count) {
        $Directory=$Queue.Dequeue()
        foreach ($Item in Get-ChildItem -LiteralPath $Directory -Force) {
            $Relative=$Item.FullName.Substring($Root.Length+1).Replace('\','/')
            if ($Relative -match '^(\.git|\.cache|backups)(/|$)' -or $Item.Name -match '\.(tmp|lock)$') { continue }
            if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked files require an explicit backup decision: $Relative" }
            if ($Item.PSIsContainer) { $Queue.Enqueue($Item.FullName) }
            else { [pscustomobject]@{path=$Relative;full_path=$Item.FullName} }
        }
    }
}

function Read-BackupEntry($Entry) {
    $Stream=$Entry.Open(); $Buffer=[IO.MemoryStream]::new()
    try { $Stream.CopyTo($Buffer); return ,$Buffer.ToArray() }
    finally { $Stream.Dispose(); $Buffer.Dispose() }
}

function Assert-BackupName([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Contains('\') -or $Name.StartsWith('/')) { throw "Unsafe archive path: $Name" }
    foreach ($Part in $Name.Split('/')) {
        if ($Part -in @('','.','..') -or $Part -match '[<>:"|?*\x00-\x1f]' -or $Part -match '[. ]$' -or $Part -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') { throw "Unsafe archive path: $Name" }
    }
}

if ($Action -eq 'Backup') {
    $Root=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ProjectRoot).Path).TrimEnd('\','/')
    Assert-PlainPath $Root
    foreach ($Required in @('learner/settings.json','.agents/skills/english-coach/scripts/tracker.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $Required) -PathType Leaf)) { throw "Not an English Learning project: missing $Required" }
    }
    if (-not $ArchivePath) { $ArchivePath=Join-Path $Root ('backups/english-learning-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)+'.zip') }
    $ArchivePath=[IO.Path]::GetFullPath($ArchivePath)
    Assert-PlainPath $ArchivePath
    $UnderRoot=$ArchivePath.StartsWith($Root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
    if ($UnderRoot -and -not $ArchivePath.StartsWith((Join-Path $Root 'backups')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Inside the project, store archives only in backups/.' }
    if (Test-Path -LiteralPath $ArchivePath) { throw 'Archive already exists; choose a new filename.' }
    [void][IO.Directory]::CreateDirectory((Split-Path $ArchivePath -Parent))
    $Partial=$ArchivePath+'.partial'
    $Lock=$null; $Zip=$null; $Output=$null
    try {
        # Share the v4 writer lock; no Bootstrap or recovery runs against the source.
        $State=Join-Path $Root '.state'
        if (Test-Path -LiteralPath $State) {
            Assert-PlainPath (Join-Path $State 'tracker-v4.lock')
            $Lock=[IO.File]::Open((Join-Path $State 'tracker-v4.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        }
        $Files=@(Get-BackupFiles $Root | Sort-Object path)
        if (@($Files | Where-Object path -eq 'backup-manifest.json').Count) { throw 'backup-manifest.json is reserved for the archive inventory.' }
        $Output=[IO.File]::Open($Partial,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $Zip=[IO.Compression.ZipArchive]::new($Output,[IO.Compression.ZipArchiveMode]::Create,$true)
        $Inventory=@(foreach ($File in $Files) {
            Assert-BackupName $File.path
            $Bytes=[IO.File]::ReadAllBytes($File.full_path)
            $Entry=$Zip.CreateEntry($File.path,[IO.Compression.CompressionLevel]::Optimal)
            $Stream=$Entry.Open()
            try { $Stream.Write($Bytes,0,$Bytes.Length) } finally { $Stream.Dispose() }
            [pscustomobject]@{path=$File.path;bytes=$Bytes.Length;sha256=(Get-BackupHash $Bytes)}
        })
        # Detect edits by tools that do not participate in the tracker lock.
        $After=@(Get-BackupFiles $Root | Sort-Object path)
        if (($After.path -join "`n") -ne ($Files.path -join "`n")) { throw 'Project changed during backup; retry when idle.' }
        foreach ($Row in $Inventory) {
            if ((Get-BackupHash ([IO.File]::ReadAllBytes((Join-Path $Root $Row.path)))) -ne $Row.sha256) { throw "File changed during backup: $($Row.path)" }
        }
        $Manifest=[pscustomobject]@{format_version=1;created_at=[DateTime]::UtcNow.ToString('o');files=$Inventory}
        $Bytes=[Text.Encoding]::UTF8.GetBytes(($Manifest | ConvertTo-Json -Depth 6))
        $Stream=$Zip.CreateEntry('backup-manifest.json').Open()
        try { $Stream.Write($Bytes,0,$Bytes.Length) } finally { $Stream.Dispose() }
    }
    finally {
        if ($Zip) { $Zip.Dispose() }; if ($Output) { $Output.Dispose() }; if ($Lock) { $Lock.Dispose() }
    }
    [IO.File]::Move($Partial,$ArchivePath)
    [pscustomobject]@{status='backed_up';archive=$ArchivePath;file_count=$Inventory.Count}
    return
}

if (-not $ArchivePath) { throw 'Verify and Restore require -ArchivePath.' }
$ArchivePath=[IO.Path]::GetFullPath($ArchivePath)
$Zip=[IO.Compression.ZipFile]::OpenRead($ArchivePath)
try {
    $Entries=@{}
    foreach ($Entry in $Zip.Entries) {
        Assert-BackupName $Entry.FullName
        if ($Entries.ContainsKey($Entry.FullName)) { throw "Duplicate archive path: $($Entry.FullName)" }
        $Entries[$Entry.FullName]=$Entry
    }
    if (-not $Entries.ContainsKey('backup-manifest.json')) { throw 'Backup inventory is missing.' }
    $Manifest=[Text.Encoding]::UTF8.GetString((Read-BackupEntry $Entries['backup-manifest.json'])) | ConvertFrom-Json
    if ($Manifest.format_version -ne 1) { throw 'Unsupported backup format.' }
    $Seen=@{}
    foreach ($Row in $Manifest.files) {
        Assert-BackupName $Row.path
        if ($Row.path -eq 'backup-manifest.json' -or $Seen.ContainsKey($Row.path) -or -not $Entries.ContainsKey($Row.path)) { throw "Invalid inventory entry: $($Row.path)" }
        $Seen[$Row.path]=$true
        $Bytes=Read-BackupEntry $Entries[$Row.path]
        if ($Bytes.Length -ne $Row.bytes -or (Get-BackupHash $Bytes) -ne $Row.sha256) { throw "Backup integrity check failed: $($Row.path)" }
    }
    if ($Entries.Count -ne $Seen.Count+1) { throw 'Archive contains files outside its inventory.' }
    if ($Action -eq 'Restore') {
        if (-not $Destination) { throw 'Restore requires a new -Destination directory.' }
        $Destination=[IO.Path]::GetFullPath($Destination)
        Assert-PlainPath $Destination
        if (Test-Path -LiteralPath $Destination) { throw 'Restore destination must not already exist; existing projects are never overwritten.' }
        [void][IO.Directory]::CreateDirectory($Destination)
        foreach ($Row in $Manifest.files) {
            $Path=Join-Path $Destination $Row.path
            [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
            $Stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try { $Bytes=Read-BackupEntry $Entries[$Row.path]; $Stream.Write($Bytes,0,$Bytes.Length) } finally { $Stream.Dispose() }
        }
    }
    [pscustomobject]@{status=$(if ($Action -eq 'Restore') {'restored'} else {'verified'});archive=$ArchivePath;destination=$Destination;file_count=$Seen.Count}
}
finally { $Zip.Dispose() }
