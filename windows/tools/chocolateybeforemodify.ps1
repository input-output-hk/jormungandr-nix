$CLI="jcli"
$NODE="jormungandr"

function Stop-Jormungandr {
	param ($NAME)

	[System.Diagnostics.Process[]]$PROCESSLIST = Get-Process -Name $NAME -ErrorAction SilentlyContinue
	ForEach ($Process in $PROCESSLIST) {
		$Process | Stop-Process -Force -Verbose
	}
}

Write-Output "Stopping any running jormungandr processes before upgrading or uninstalling..."
Stop-Jormungandr $CLI
Stop-Jormungandr $NODE
