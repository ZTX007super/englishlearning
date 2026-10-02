function Assert-BackupThrows {
    param([Parameter(ValueFromPipeline=$true)][scriptblock]$Operation)
    process {
        $DidThrow=$false
        try { & $Operation | Out-Null } catch { $DidThrow=$true }
        $DidThrow | Should Be $true
    }
}

$BackupTool=Join-Path (Split-Path $PSScriptRoot -Parent) 'maintenance/backup.ps1'

function New-BackupFixture {
    $Root=Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    foreach ($Folder in @('learner','sessions','.state/packages','.agents/skills/english-coach/scripts','.cache','.git','backups')) {
        [void][IO.Directory]::CreateDirectory((Join-Path $Root $Folder))
    }
    foreach ($Name in @('learner/settings.json','sessions/lesson.md','.state/runtime.json','.state/current-session.json','.state/current-session.json.previous','.state/packages/main.json','.agents/skills/english-coach/scripts/tracker.ps1','.cache/discard','.git/discard','backups/old.zip','draft.tmp')) {
        [IO.File]::WriteAllText((Join-Path $Root $Name),"fixture: $Name")
    }
    return $Root
}

Describe 'Complete project backup and safe restoration' {
    It 'preserves runtime, pending recovery and current code byte for byte without nested archives' {
        $Root=New-BackupFixture
        $Backup=& $BackupTool -ProjectRoot $Root
        $Backup.status | Should Be 'backed_up'
        (& $BackupTool -Action Verify -ArchivePath $Backup.archive).status | Should Be 'verified'
        $Destination=Join-Path $TestDrive 'restored'
        (& $BackupTool -Action Restore -ArchivePath $Backup.archive -Destination $Destination).status | Should Be 'restored'
        foreach ($Path in @('learner/settings.json','sessions/lesson.md','.state/runtime.json','.state/current-session.json','.state/current-session.json.previous','.state/packages/main.json','.agents/skills/english-coach/scripts/tracker.ps1')) {
            (Get-FileHash (Join-Path $Root $Path)).Hash | Should Be (Get-FileHash (Join-Path $Destination $Path)).Hash
        }
        foreach ($Path in @('.git','.cache','backups','draft.tmp','.state/tracker-v4.lock')) { (Test-Path (Join-Path $Destination $Path)) | Should Be $false }
        (& $BackupTool -ProjectRoot $Destination).status | Should Be 'backed_up'
    }

    It 'refuses to overwrite a project or an existing archive' {
        $Root=New-BackupFixture
        $Backup=& $BackupTool -ProjectRoot $Root
        { & $BackupTool -Action Restore -ArchivePath $Backup.archive -Destination $Root } | Assert-BackupThrows
        { & $BackupTool -ProjectRoot $Root -ArchivePath $Backup.archive } | Assert-BackupThrows
        { & $BackupTool -ProjectRoot $Root -ArchivePath (Join-Path $Root 'unsafe.zip') } | Assert-BackupThrows
    }

    It 'rejects damaged content before creating the restoration directory' {
        $Root=New-BackupFixture
        $Backup=& $BackupTool -ProjectRoot $Root
        $Zip=[IO.Compression.ZipFile]::Open($Backup.archive,[IO.Compression.ZipArchiveMode]::Update)
        try {
            $Stream=$Zip.GetEntry('.state/runtime.json').Open()
            try { $Stream.SetLength(0); $Stream.WriteByte(0) } finally { $Stream.Dispose() }
        } finally { $Zip.Dispose() }
        $Destination=Join-Path $TestDrive 'damaged-restore'
        { & $BackupTool -Action Restore -ArchivePath $Backup.archive -Destination $Destination } | Assert-BackupThrows
        (Test-Path $Destination) | Should Be $false
    }

    It 'rejects paths that escape the restore directory' {
        $Root=New-BackupFixture
        $Backup=& $BackupTool -ProjectRoot $Root
        $Zip=[IO.Compression.ZipFile]::Open($Backup.archive,[IO.Compression.ZipArchiveMode]::Update)
        try { [void]$Zip.CreateEntry('../escaped.txt') } finally { $Zip.Dispose() }
        { & $BackupTool -Action Verify -ArchivePath $Backup.archive } | Assert-BackupThrows
    }

    It 'does not snapshot while a tracker transaction owns the lock' {
        $Root=New-BackupFixture
        $Lock=[IO.File]::Open((Join-Path $Root '.state/tracker-v4.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try { { & $BackupTool -ProjectRoot $Root } | Assert-BackupThrows }
        finally { $Lock.Dispose() }
    }
}
