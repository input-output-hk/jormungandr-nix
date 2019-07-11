$CLI="jcli"
$NODE="jormungandr"

Write-Output "Checking for any running jormungandr processes before uninstalling..."
$PROCESS1 = Get-Process $CLI -ErrorAction SilentlyContinue
$PROCESS2 = Get-Process $NODE -ErrorAction SilentlyContinue

if ($PROCESS1) {
        Write-Output "Founding $CLI running.  Shutting down..."
        $PROCESS1 | Stop-Process -Force
}
if ($PROCESS2) {
        Write-Output "Founding $NODE running.  Shutting down..."
        $PROCESS2 | Stop-Process -Force
}
