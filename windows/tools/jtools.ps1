# jtools version 0.1.1 (powershell port)
#
# based on scripts from @Gufmar, @NicolasDP, @disassembler

[CmdletBinding()]
Param (
  [Parameter(Mandatory=$false, Position = 1)] [string] $OPERATION,
  [Parameter(Mandatory=$false, Position = 2)] [string] $SUBCOMMAND = $null,
  [Parameter(Mandatory=$false, Position = 3)] [string] $3 = $null,
  [Parameter(Mandatory=$false, Position = 4)] [string] $4 = $null,
  [Parameter(Mandatory=$false, Position = 5)] [string] $5 = $null,
  [Parameter(Mandatory=$false, Position = 6)] [string] $6 = $null,
  [Parameter(Mandatory=$false, Position = 7)] [string] $7 = $null,
  [Parameter(Mandatory=$false, Position = 8)] [string] $8 = $null,
  [Parameter(Mandatory=$false, Position = 9)] [string] $9 = $null,
  [Parameter(Mandatory=$false, Position = 10)] [string] $10 = $null,
  [Parameter(Mandatory=$false, Position = 11, ValueFromRemainingArguments=$true)] [string[]] $LISTARGS = $null,
  [Parameter(Mandatory=$false)] [string] $a,
  [Parameter(Mandatory=$false)] [string] $l,
  [Parameter(Mandatory=$false)] [string] $r,
  [Parameter(Mandatory=$false)] [string] $f,
  [Parameter(Mandatory=$false)] [switch] $o,
  [Parameter(Mandatory=$false)] [switch] $p
)

### Parameters ####################################################

$OPT_PARAMS=0
$ALL_PARAMS=$PSBoundParameters.count
foreach($boundParam in $PSBoundParameters.GetEnumerator()) {
  #"Key={0} Value={1}" -f $boundParam.Key,$boundParam.Value
  switch($boundParam.key) {
    "a"        { $OPT_PARAMS++ }
    "l"        { $OPT_PARAMS++ }
    "r"        { $OPT_PARAMS++ }
    "f"        { $OPT_PARAMS++ }
    "o"        { $OPT_PARAMS++ }
    "p"        { $OPT_PARAMS++ }
    "LISTARGS" { $OPT_PARAMS++ }
  }
}

$PARAMS=$ALL_PARAMS - $OPT_PARAMS

$CLI="jcli"
$NODE="jormungandr"
$NODE_REST_URL=if ($Env:NODE_REST_URL) { $Env:NODE_REST_URL } else { "http://127.0.0.1:3001/api" }
$BASE_FOLDER=$Env:USERPROFILE + "\jormungandr\"
$WALLET_FOLDER=$BASE_FOLDER + "wallet"
$POOL_FOLDER=$BASE_FOLDER + "pool"
$JTOOLS_LOG=$BASE_FOLDER + "\jtools.log"
$CURL="curl.exe"
$JQ="jq.exe"

###################################################################

function version() {
  Write-Output "`njtools Version:        0.2.0"
  Write-Output "jormungandr Version:   $(& $NODE --version | ForEach-Object { $_ -replace `"jormungandr `", `"`" })"
  Write-Output "jcli Version:          $(& $CLI --version | ForEach-Object { $_ -replace `"jcli `", `"`" })"
  Write-Output "PS Version:            $($PSVersionTable.PSVersion)"
  Write-Output "Base Folder:           $BASE_FOLDER"
  Write-Output "Node Rest Url:         $NODE_REST_URL`n"
  Exit 1
}


function usage() {
  Write-Output "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
  Write-Output "Usage:"
  Write-Output ""
  Write-Output "    jtools wallet new    <WALLET_NAME>"
  Write-Output "    jtools wallet show   <WALLET_ADDRESS|WALLET_NAME>"
  Write-Output "    jtools wallet remove <WALLET_NAME>"
  Write-Output ""
  Write-Output "    jtools funds send <SOURCE_WALLET> <AMOUNT> <DEST_ADDRESS|DEST_WALLET>"
  Write-Output "            Note: Amount is an Integer value in Lovelaces"
  Write-Output ""
  Write-Output "    jtools pool show"
  Write-Output "    jtools pool register <POOL_NAME> <WALLET_NAME> <POOL_TICKER> <POOL_URL> [-a <REWARD_ACCOUNT>] [-l <TAX_LIMIT>] [-r <TAX_RATIO>] [-f <TAX_FIXED>]"
  Write-Output "            Note: The <WALLET_NAME> wallet is only used to pay the registration fee"
  Write-Output "                  The <POOL_TICKER> must be limited to 5 uppercase alphanumeric characters or less"
  Write-Output "                  The <REWARD_ACCOUNT> will default to the pool account if not specified"
  Write-Output "                  The <TAX_*> parameters will default to 0 if not specified"
  Write-Output ""
  Write-Output "    jtools stake delegate <POOL_NAME> <WALLET_NAME> [-o] [-p]"
  Write-Output "            Note: Entire Wallet balance, less the fee, is delegated"
  Write-Output "                  The optional -o switch will overwrite any preexisting staking certificate"
  Write-Output "                  The optional -p switch will utilize a pledge address from a pool with name <WALLET_NAME>"
  Write-Output ""
  Write-Output "    jtools check tx   <TX_ID>"
  Write-Output "    jtools check node stats"
  Write-Output "    jtools check node settings"
  Write-Output ""
  Write-Output "    jtools version"
  Write-Output ""
  Write-Output "    jtools update"
  Write-Output ""
  Write-Output "REST-API:"
  Write-Output ""
  Write-Output "    The rest API in use is ${NODE_REST_URL}."
  Write-Output "    This can be changed by setting a Powershell environment variable."
  Write-Output "    An example command would be:"
  Write-Output "            `$Env:NODE_REST_URL=`"http://127.0.0.1:3001/api`""
  Write-Output "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
  Exit 1
}

function need_cmd([string]$cmd) {
  if (!(check_cmd $cmd)) {
    $chocoPkg=$cmd -replace "\..*", ""
    Write-Output "`nERROR: The command '$cmd' is needed but not found"
    Write-Output "       Try 'choco install $chocoPkg' from an administrative PowerShell`n"
    Exit 1
  }
}

function check_cmd([string]$cmd) {
  Get-Command $cmd -ErrorAction SilentlyContinue | Out-Null
  return $?
}

function say([string]$out, [string]$method) {
  Write-Output $out
  if ($method -eq "log") {
    Add-Content $JTOOLS_LOG "$(Get-Date -UFormat "%Y-%m-%dT%H:%M:%S%Z") - $out"
  }
}

function wallet() {
  if ($PARAMS -lt 3) {
    usage
  }

  $WALLET_NAME=$3

  Switch($SUBCOMMAND) {
    # jtools wallet new <WALLET_NAME>
    "new" {
      if (Test-Path -Path "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.key") {
        Write-Output "`nERROR: A wallet named `"$WALLET_NAME`" already exists"
        Write-Output "       Choose another name or remove the existing one`n"
        Exit 1
      }
      New-Item -ItemType Directory -Force -Path "${WALLET_FOLDER}\$WALLET_NAME" | Out-Null

      # Create a personal wallet key
      $MY_ED25519_file="${WALLET_FOLDER}\${WALLET_NAME}\ed25519.key"
      & $CLI key generate --type=Ed25519 | Tee-Object -Variable MY_ED25519_key |  Out-File -Encoding Default $MY_ED25519_file

      $MY_ED25519_pubfile="${WALLET_FOLDER}\${WALLET_NAME}\ed25519.pub"
      $MY_ED25519_key | & $CLI key to-public | Tee-Object -Variable MY_ED25519_pub | Out-File -Encoding Default $MY_ED25519_pubfile

      # Extract account address from wallet key
      $MY_ED25519_addrfile="${WALLET_FOLDER}\${WALLET_NAME}\ed25519.account"
      & $CLI address account --prefix addr $MY_ED25519_pub --testing | Tee-Object -Variable MY_ED25519_address | Out-File -Encoding Default $MY_ED25519_addrfile

      say "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
      say "New wallet named `"$WALLET_NAME`":" "log"
      say "  public key:  $MY_ED25519_pub" "log"
      say "  address:     $MY_ED25519_address" "log"
      say "" "log"
      say "Stored at path: ${WALLET_FOLDER}\$WALLET_NAME" "log"
      say "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
      Break
    }
    # jtools wallet show <WALLET_ADDRESS|WALLET_NAME>
    "show" {
      # The wallet name parameter appears to match an address
      if (($WALLET_NAME.length -eq 62) -or ($WALLET_NAME.length -eq 64)) {
        $WALLET_ADDRESS=$WALLET_NAME
      }
      # Look for a local wallet account address
      elseif (Test-Path -Path "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.account") {
        $WALLET_ADDRESS=Get-Content "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.account"
      }
      else {
        Write-Output "`nERROR: No wallet `"$WALLET_NAME`" found (${WALLET_FOLDER}\${WALLET_NAME}\ed25519.account)`n"
        Exit 1
      }
      $RESULT=& $CLI rest v0 account get $WALLET_ADDRESS --host $NODE_REST_URL 2> $null
      $WALLET_BALANCE=$RESULT | Select-String -Pattern "^value:" | ForEach-Object { $_ -replace "value: ", "" } 2> $null
      $WALLET_BALANCE_NICE=$WALLET_BALANCE -as [uint64] | ForEach-Object { '{0:N0} Lovelaces' -f $_ }
      say "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
      say "Address: $WALLET_ADDRESS" "log"
      say "Balance: $WALLET_BALANCE_NICE" "log"
      if ($null -eq $WALLET_BALANCE) {
        say "Balance not (yet) found on the blockchain for this address" "log"
      }
      say "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
      Write-Output "Raw wallet info:`n"
      if ($null -ne $RESULT) {
        Write-Output $RESULT
        Write-Output ""
      }
      else {
        Write-Output "ERROR: Not available`n"
      }
      Break
    }
    # jtools wallet remove <WALLET_NAME>
    "remove" {
      if (Test-Path -Path "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.account") {
        $WALLET_ADDRESS=Get-Content "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.account"
        $RESULT=& $CLI rest v0 account get $WALLET_ADDRESS --host $NODE_REST_URL 2> $null
        $WALLET_BALANCE=$RESULT | Select-String -Pattern "^value:" | ForEach-Object { $_ -replace "value: ", "" } 2> $null
        $WALLET_BALANCE_NICE=$WALLET_BALANCE -as [uint64] | ForEach-Object { '{0:N0} Lovelaces' -f $_ }
        if ($null -eq $WALLET_BALANCE) {
          Write-Output "`nINFO: Found local wallet file but cannot (yet) verify its balance on blockchain`n"
        }
        elseif ($WALLET_BALANCE -eq "0") {
          Write-Output "`nINFO: Found local wallet file with current balance 0`n"
        }
        else {
          Write-Output "`nWARN: This wallet file has a balance of $WALLET_BALANCE_NICE`n"
        }

        $Readhost = Read-Host "Are you sure to delete secret/public key pairs (y/N)?"
        Switch -CaseSensitive ($ReadHost) {
          "y" {
            Remove-Item -Path ${WALLET_FOLDER}\$WALLET_NAME -Confirm:$false -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
            say "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
            say "Removed wallet: `"${WALLET_NAME}`"" "log"
            say "Deleted directory: `"${WALLET_FOLDER}\$WALLET_NAME`"" "log"
            say "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
            Break
          }
          Default {
            Write-Output "`nSkipped removal process for `"$WALLET_NAME`"`n"
            Break
          }
        }
      }
      else {
        Write-Output "`nINFO: No wallet `"$WALLET_NAME`" found`n"
        Exit 1
      }
      Break
    }
    Default {
      Write-Output "`nNo such subcommand: $SUBCOMMAND`n"
      usage
      Break
    }
  }
}

function funds() {
  if ($PARAMS -lt 5) {
    usage
  }

  $WALLET_NAME=$3
  $AMOUNT=$4 -as [uint64]
  $DEST=$5

  Switch($SUBCOMMAND) {
    # jtools funds send <SOURCE_WALLET> <AMOUNT> <DEST_WALLET|DEST_ADDRESS>
    "send" {
      if (Test-Path -Path "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.account") {
        $SOURCE_ADDRESS=Get-Content "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.account"
        $SOURCE_KEY=Get-Content "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.key"
      }
      else {
        Write-Output "`nINFO: No wallet `"$WALLET_NAME`" found`n"
        Exit 1
      }

      if ($null -ne $AMOUNT) {
        $AMOUNT_NICE=$AMOUNT -as [uint64] | ForEach-Object { '{0:N0} Lovelaces' -f $_ }
      }
      else {
        Write-Output "`nINFO: $4 is not a valid unsigned integer amount`n"
        Exit 1
      }

      # The destination parameter appears to match an address
      if (($DEST.length -eq 62) -or ($DEST.length -eq 64)) {
        $DEST_ADDRESS=$DEST
      }
      # Look for a local wallet account address
      elseif (Test-Path -Path "${WALLET_FOLDER}\${DEST}\ed25519.account") {
        $DEST_ADDRESS=Get-Content "${WALLET_FOLDER}\${DEST}\ed25519.account"
      }
      else {
        Write-Output "`nERROR: No wallet `"$WALLET_NAME`" found (${WALLET_FOLDER}\${WALLET_NAME}\ed25519.account)`n"
        Exit 1
      }

      # Get the source wallet's state
      $RESULT=& $CLI rest v0 account get $SOURCE_ADDRESS --host $NODE_REST_URL 2> $null
      $SOURCE_BALANCE=$RESULT | Select-String -Pattern "^value:" | ForEach-Object { $_ -replace "value: ", "" }
      $SOURCE_BALANCE_NICE=$SOURCE_BALANCE -as [uint64] | ForEach-Object { '{0:N0} Lovelaces' -f $_ }
      if ($null -eq $SOURCE_BALANCE) {
        Write-Output "`nERROR: Cannot (yet) verify the source address balance on the blockchain`n"
        Exit 1
      }
      elseif ($SOURCE_BALANCE -eq "0") {
        Write-Output "`nERROR: The source address balance is 0`n"
        Exit 1
      }
      else {
        Write-Output "`nINFO: This wallet file has a balance of $SOURCE_BALANCE_NICE`n"
      }

      $SOURCE_COUNTER=$RESULT | Select-String -Pattern "^counter:" | ForEach-Object { $_ -replace "counter: ", "" }

      # Read the node's blockchain settings (parameters are required for the next transactions)
      $SETTINGS=& $CURL -s ${NODE_REST_URL}/v0/settings
      $FEE_CONSTANT=$SETTINGS | jq -r .fees.constant | ForEach-Object { $_ -as [uint64] }
      $FEE_COEFFICIENT=$SETTINGS | jq -r .fees.coefficient | ForEach-Object { $_ -as [uint64] }
      $BLOCK0_HASH=$SETTINGS | jq -r .block0Hash
      $FEES=$FEE_CONSTANT + 2 * $FEE_COEFFICIENT
      $FEES_NICE=$FEES -as [uint64] | ForEach-Object { '{0:N0} Lovelaces' -f $_ }
      $AMOUNT_WITH_FEES=$AMOUNT + $FEES

      if ($AMOUNT_WITH_FEES -gt $SOURCE_BALANCE) {
        Write-Output "`nERROR: Source wallet `"$WALLET_NAME`" has a balance of: $SOURCE_BALANCE_NICE"
        Write-Output "ERROR: This is not enough to send $AMOUNT_NICE and pay $FEES_NICE in fees`n"
        Exit 1
      }

      $STAGING_FILE=New-TemporaryFile
      $WITNESS_SECRET_FILE=New-TemporaryFile
      $WITNESS_OUTPUT_FILE=New-TemporaryFile
      & $CLI transaction new --staging $STAGING_FILE
      & $CLI transaction add-account $SOURCE_ADDRESS $AMOUNT_WITH_FEES --staging $STAGING_FILE
      & $CLI transaction add-output $DEST_ADDRESS $AMOUNT --staging $STAGING_FILE
      & $CLI transaction finalize --staging $STAGING_FILE
      $TRANSACTION_ID=& $CLI transaction data-for-witness --staging $STAGING_FILE

      $SOURCE_KEY | Out-File -Encoding Default $WITNESS_SECRET_FILE

      & $CLI transaction make-witness $TRANSACTION_ID `
        --genesis-block-hash $BLOCK0_HASH `
        --type "account" --account-spending-counter $SOURCE_COUNTER `
        $WITNESS_OUTPUT_FILE $WITNESS_SECRET_FILE
      & $CLI transaction add-witness $WITNESS_OUTPUT_FILE --staging $STAGING_FILE

      # Finalize the transaction and send it
      & $CLI transaction seal --staging $STAGING_FILE
      $TXID=& $CLI transaction to-message --staging $STAGING_FILE | & $CLI rest v0 message post --host $NODE_REST_URL

      Remove-Item -Path $STAGING_FILE -Confirm:$false -Force -ErrorAction SilentlyContinue | Out-Null
      Remove-Item -Path $WITNESS_SECRET_FILE -Confirm:$false -Force -ErrorAction SilentlyContinue | Out-Null
      Remove-Item -Path $WITNESS_OUTPUT_FILE -Confirm:$false -Force -ErrorAction SilentlyContinue | Out-Null

      say "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
      say "Send transaction with wallet `"$WALLET_NAME`"" "log"
      say "  From:       $SOURCE_ADDRESS" "log"
      say "  Balance:    $SOURCE_BALANCE_NICE" "log"
      say "  Amount:     $AMOUNT_NICE" "log"
      say "  To:         $DEST_ADDRESS" "log"
      say "  Fees:       $FEES_NICE" "log"
      say "  TX-ID:      $TXID" "log"
      say "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
      Break
    }
    Default {
      Write-Output "`nNo such subcommand: $SUBCOMMAND`n"
      usage
      Break
    }
  }
}

function stake() {
  if ($PARAMS -lt 4) {
    usage
  }

  $POOL_NAME=$3
  $WALLET_NAME=$4

  Switch($SUBCOMMAND) {
    # jtools stake delegate <POOL_NAME> <WALLET_NAME> [-o] [-p]
    "delegate" {
      $POOL_ID_file="${POOL_FOLDER}\${POOL_NAME}\stake_pool.id"
      if (Test-Path -Path $POOL_ID_file) {
        $POOL_ID=Get-Content $POOL_ID_file
      }
      else {
        Write-Output "`nERROR: No pool `"$POOL_NAME`" found ($POOL_ID_file)`n"
        Exit 1
      }

      if ((Test-Path -Path "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.account") -And ($p -eq $false)) {
        $SOURCE_ADDRESS=Get-Content "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.account"
        $SOURCE_KEY=Get-Content "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.key"
        $SOURCE_KEY_FILE="${WALLET_FOLDER}\${WALLET_NAME}\ed25519.key"
        $SOURCE_PUB=Get-Content "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.pub"
        $STAKE_DLG_certfile="${WALLET_FOLDER}\${WALLET_NAME}\${POOL_NAME}_stake_delegation.cert"
        $STAKE_DLG_signedfile="${WALLET_FOLDER}\${WALLET_NAME}\${POOL_NAME}_stake_delegation.signcert"
      }
      elseif ((Test-Path -Path "${POOL_FOLDER}\${WALLET_NAME}\stake_pool_owner_wallet.address") -And ($p -eq $true)) {
        $SOURCE_ADDRESS=Get-Content "${POOL_FOLDER}\${WALLET_NAME}\stake_pool_owner_wallet.address"
        $SOURCE_KEY=Get-Content "${POOL_FOLDER}\${WALLET_NAME}\stake_pool_owner_wallet.key"
        $SOURCE_KEY_FILE="${POOL_FOLDER}\${WALLET_NAME}\stake_pool_owner_wallet.key"
        $SOURCE_PUB=Get-Content "${POOL_FOLDER}\${WALLET_NAME}\stake_pool_owner_wallet.pub"
        $STAKE_DLG_certfile="${POOL_FOLDER}\${WALLET_NAME}\${POOL_NAME}_stake_delegation.cert"
        $STAKE_DLG_signedfile="${POOL_FOLDER}\${WALLET_NAME}\${POOL_NAME}_stake_delegation.signcert"
      }
      else {
        Write-Output "`nINFO: No wallet `"$WALLET_NAME`" found"
        Write-Output "Did you intend to specify a pledge address from a pool?  If so, re-run with ``-p```n"
        Exit 1
      }

      # Get the source wallet's state
      $RESULT=& $CLI rest v0 account get $SOURCE_ADDRESS --host $NODE_REST_URL 2> $null
      $SOURCE_BALANCE=$RESULT | Select-String -Pattern "^value:" | ForEach-Object { $_ -replace "value: ", "" }
      $SOURCE_BALANCE_NICE=$SOURCE_BALANCE -as [uint64] | ForEach-Object { '{0:N0} Lovelaces' -f $_ }
      if ($null -eq $SOURCE_BALANCE) {
        Write-Output "`nERROR: Cannot (yet) verify the source address balance on the blockchain`n"
        Exit 1
      }
      elseif ($SOURCE_BALANCE -eq "0") {
        Write-Output "`nERROR: The source address balance is 0`n"
        Exit 1
      }
      else {
        Write-Output "`nINFO: This wallet file has a balance of $SOURCE_BALANCE_NICE`n"
      }

      $SOURCE_COUNTER=$RESULT | Select-String -Pattern "^counter:" | ForEach-Object { $_ -replace "counter: ", "" }

      # Read the node's blockchain settings (parameters are required for the next transactions)
      $SETTINGS=& $CURL -s ${NODE_REST_URL}/v0/settings
      $FEE_CONSTANT=$SETTINGS | jq -r .fees.constant | ForEach-Object { $_ -as [uint64] }
      $FEE_COEFFICIENT=$SETTINGS | jq -r .fees.coefficient | ForEach-Object { $_ -as [uint64] }
      $FEE_CERTIFICATE_STAKE_DELEGATION=$SETTINGS | jq -r .fees.per_certificate_fees.certificate_stake_delegation | ForEach-Object { $_ -as [uint64] }
      $BLOCK0_HASH=$SETTINGS | jq -r .block0Hash
      $FEES=$FEE_CONSTANT + $FEE_COEFFICIENT + $FEE_CERTIFICATE_STAKE_DELEGATION
      $FEES_NICE=$FEES -as [uint64] | ForEach-Object { '{0:N0} Lovelaces' -f $_ }
      $AMOUNT_WITH_FEES=$FEES
      $AMOUNT_WITH_FEES_NICE=$FEES_NICE

      if ($AMOUNT_WITH_FEES -gt $SOURCE_BALANCE) {
        Write-Output "`nERROR: Source wallet `"$WALLET_NAME`" has a balance of: $SOURCE_BALANCE_NICE"
        Write-Output "ERROR: This is not enough to pay the delegation fee: $FEES_NICE in fees`n"
        Exit 1
      }

      # Test for a pre-existing stake delegation certificate and warn if needed
      if ((Test-Path -Path $STAKE_DLG_certfile) -And ($o -eq $false)) {
        Write-Output "`nERROR: A pre-existing stake delegation certification for this wallet exists at:"
        Write-Output "  $STAKE_DLG_certfile"
        Write-Output "`nRe-run this command with the ``-o`` option to overwrite to create and submit a new delegation certificate`n"
        Exit 1
      }

      # Build stake delegation certificate
      & $CLI certificate new stake-delegation $SOURCE_PUB $POOL_ID | `
        Tee-Object -Variable STAKE_DLG_cert | Out-File -Encoding Default $STAKE_DLG_certfile

      # The signed delegation certificate is only used if including the delegation in the genesis block
      $STAKE_DLG_cert | & $CLI certificate sign -k $SOURCE_KEY_file | `
        Tee-Object -Variable STAKE_DLG_signed | Out-File -Encoding Default $STAKE_DLG_signedfile

      $STAGING_FILE=New-TemporaryFile
      $WITNESS_SECRET_FILE=New-TemporaryFile
      $WITNESS_OUTPUT_FILE=New-TemporaryFile
      & $CLI transaction new --staging $STAGING_FILE
      & $CLI transaction add-account $SOURCE_ADDRESS $AMOUNT_WITH_FEES --staging $STAGING_FILE
      & $CLI transaction add-certificate --staging $STAGING_FILE $STAKE_DLG_cert
      & $CLI transaction finalize --staging $STAGING_FILE
      $TRANSACTION_ID=& $CLI transaction data-for-witness --staging $STAGING_FILE
      $SOURCE_KEY | Out-File -Encoding Default $WITNESS_SECRET_FILE

      & $CLI transaction make-witness $TRANSACTION_ID `
        --genesis-block-hash $BLOCK0_HASH `
        --type "account" --account-spending-counter $SOURCE_COUNTER `
        $WITNESS_OUTPUT_FILE $WITNESS_SECRET_FILE
      & $CLI transaction add-witness $WITNESS_OUTPUT_FILE --staging $STAGING_FILE

      # Finalize the transaction and send it
      & $CLI transaction seal --staging $STAGING_FILE
      & $CLI transaction auth --staging $STAGING_FILE -k $SOURCE_KEY_FILE
      $TXID=& $CLI transaction to-message --staging $STAGING_FILE | & $CLI rest v0 message post --host $NODE_REST_URL

      Remove-Item -Path $STAGING_FILE -Confirm:$false -Force -ErrorAction SilentlyContinue | Out-Null
      Remove-Item -Path $WITNESS_SECRET_FILE -Confirm:$false -Force -ErrorAction SilentlyContinue | Out-Null
      Remove-Item -Path $WITNESS_OUTPUT_FILE -Confirm:$false -Force -ErrorAction SilentlyContinue | Out-Null

      say "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
      say "Delegate wallet `"${WALLET_NAME}`" to pool `"${POOL_NAME}`"" "log"
      say "  Pool-ID:    $POOL_ID" "log"
      say "  Source:     $SOURCE_ADDRESS" "log"
      say "  Stake:      $SOURCE_BALANCE_NICE" "log"
      say "  Fees:       $AMOUNT_WITH_FEES_NICE" "log"
      say "  TX-ID:      $TXID" "log"
      say "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
      Break
    }
    Default {
      Write-Output "`nNo such subcommand: $SUBCOMMAND`n"
      usage
      Break
    }
  }
}

function pool() {
  Switch($SUBCOMMAND) {
    # jtools pool register <POOL_NAME> <WALLET_NAME> <POOL_TICKER> <POOL_URL> [-a <REWARD_ACCOUNT>] [-l <TAX_LIMIT>] [-r <TAX_RATIO>] [-f <TAX_FIXED>]"
    "register" {
      if ($PARAMS -lt 6) {
        usage
      }

      $POOL_NAME=$3
      $WALLET_NAME=$4
      $POOL_TICKER=$5
      $POOL_URL=$6

      $POOL_OPTIONS=""
      if ($a -ne "") { $POOL_OPTIONS+=" --reward-account $a" }
      if ($l -ne "") { $POOL_OPTIONS+=" --tax-limit $l"      }
      if ($r -ne "") { $POOL_OPTIONS+=" --tax-ratio $r"      }
      if ($f -ne "") { $POOL_OPTIONS+=" --tax-fixed $f"      }

      if (Test-Path -Path "${POOL_FOLDER}\${POOL_NAME}\stake_pool.id") {
        Write-Output "`nERROR: Pool `"$POOL_NAME`" already exists (${POOL_FOLDER}\${POOL_NAME}\stake_pool.id)`n"
        Exit 1
      }

      if (Test-Path -Path "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.account") {
        $SOURCE_ADDRESS=Get-Content "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.account"
        $SOURCE_KEY=Get-Content "${WALLET_FOLDER}\${WALLET_NAME}\ed25519.key"
        $SOURCE_KEY_FILE="${WALLET_FOLDER}\${WALLET_NAME}\ed25519.key"
      }
      else {
        Write-Output "`nINFO: No wallet `"$WALLET_NAME`" found (${WALLET_FOLDER}\${WALLET_NAME}\ed25519.account)`n"
        Exit 1
      }

      # Get the source wallet's state
      $RESULT=& $CLI rest v0 account get $SOURCE_ADDRESS --host $NODE_REST_URL 2> $null
      $SOURCE_BALANCE=$RESULT | Select-String -Pattern "^value:" | ForEach-Object { $_ -replace "value: ", "" }
      $SOURCE_BALANCE_NICE=$SOURCE_BALANCE -as [uint64] | ForEach-Object { '{0:N0} Lovelaces' -f $_ }
      if ($null -eq $SOURCE_BALANCE) {
        Write-Output "`nERROR: Cannot (yet) verify the source address balance on the blockchain`n"
        Exit 1
      }
      elseif ($SOURCE_BALANCE -eq "0") {
        Write-Output "`nERROR: The source address balance is 0`n"
        Exit 1
      }
      else {
        Write-Output "`nINFO: This wallet file has a balance of $SOURCE_BALANCE_NICE`n"
      }

      $SOURCE_COUNTER=$RESULT | Select-String -Pattern "^counter:" | ForEach-Object { $_ -replace "counter: ", "" }

      # Read the node's blockchain settings (parameters are required for the next transactions)
      $SETTINGS=& $CURL -s ${NODE_REST_URL}/v0/settings
      $FEE_CONSTANT=$SETTINGS | jq -r .fees.constant | ForEach-Object { $_ -as [uint64] }
      $FEE_COEFFICIENT=$SETTINGS | jq -r .fees.coefficient | ForEach-Object { $_ -as [uint64] }
      $FEE_POOL_REGISTRATION=$SETTINGS | jq -r .fees.per_certificate_fees.certificate_pool_registration | ForEach-Object { $_ -as [uint64] }
      $BLOCK0_HASH=$SETTINGS | jq -r .block0Hash
      $FEES=$FEE_CONSTANT + $FEE_COEFFICIENT + $FEE_POOL_REGISTRATION
      $FEES_NICE=$FEES -as [uint64] | ForEach-Object { '{0:N0} Lovelaces' -f $_ }
      $AMOUNT_WITH_FEES=$FEES
      $AMOUNT_WITH_FEES_NICE=$FEES_NICE

      if ($AMOUNT_WITH_FEES -gt $SOURCE_BALANCE) {
        Write-Output "`nERROR: Source wallet `"$WALLET_NAME`" has a balance of: $SOURCE_BALANCE_NICE"
        Write-Output "ERROR: This is not enough to pay the registration fee: $FEES_NICE in fees`n"
        Exit 1
      }

      New-Item -ItemType Directory -Force -Path "${POOL_FOLDER}\$POOL_NAME" | Out-Null

      # Create pool owner wallet
      $POOL_ED25519_file="${POOL_FOLDER}\${POOL_NAME}\stake_pool_owner_wallet.key"
      & $CLI key generate --type=Ed25519 | Tee-Object -Variable POOL_ED25519_key |  Out-File -Encoding Default $POOL_ED25519_file

      $POOL_ED25519_pubfile="${POOL_FOLDER}\${POOL_NAME}\stake_pool_owner_wallet.pub"
      $POOL_ED25519_key | & $CLI key to-public | Tee-Object -Variable POOL_ED25519_pub | Out-File -Encoding Default $POOL_ED25519_pubfile

      # Extract account address from wallet key
      $POOL_ED25519_addrfile="${POOL_FOLDER}\${POOL_NAME}\stake_pool_owner_wallet.address"
      & $CLI address account --prefix addr $POOL_ED25519_pub --testing | Tee-Object -Variable POOL_ED25519_address | Out-File -Encoding Default $POOL_ED25519_addrfile

      # Generate pool KES keys
      $POOL_KES_file="${POOL_FOLDER}\${POOL_NAME}\stake_pool_kes.key"
      & $CLI key generate --type=SumEd25519_12 | Tee-Object -Variable POOL_KES_key |  Out-File -Encoding Default $POOL_KES_file

      $POOL_KES_pubfile="${POOL_FOLDER}\${POOL_NAME}\stake_pool_kes.pub"
      $POOL_KES_key | & $CLI key to-public | Tee-Object -Variable POOL_KES_pub | Out-File -Encoding Default $POOL_KES_pubfile

      # Generate pool VRF keys
      $POOL_VRF_file="${POOL_FOLDER}\${POOL_NAME}\stake_pool_vrf.key"
      & $CLI key generate --type=Curve25519_2HashDH | Tee-Object -Variable POOL_VRF_key |  Out-File -Encoding Default $POOL_VRF_file

      $POOL_VRF_pubfile="${POOL_FOLDER}\${POOL_NAME}\stake_pool_vrf.pub"
      $POOL_VRF_key | & $CLI key to-public | Tee-Object -Variable POOL_VRF_pub | Out-File -Encoding Default $POOL_VRF_pubfile

      # Build stake pool certificate
      $POOL_CRT_certfile="${POOL_FOLDER}\${POOL_NAME}\stake_pool.cert"
      $CMD_STRING="$CLI certificate new stake-pool-registration"
      $CMD_STRING+=" --kes-key $POOL_KES_pub"
      $CMD_STRING+=" --vrf-key $POOL_VRF_pub"
      $CMD_STRING+=" --owner $POOL_ED25519_pub"
      $CMD_STRING+=" --management-threshold 1"
      $CMD_STRING+=" --start-validity 0"
      $CMD_STRING+=" $POOL_OPTIONS"
      Invoke-Expression $CMD_STRING | Tee-Object -Variable POOL_CRT_cert | Out-File -Encoding Default $POOL_CRT_certfile

      # Sign the stake pool certificate with the pool owner wallet
      # Note that the signed certificate is only needed if the stake pool will be used directly in a genesis block
      $POOL_CRT_signedfile="${POOL_FOLDER}\${POOL_NAME}\stake_pool.signcert"
      $POOL_CRT_cert | & $CLI certificate sign -k $POOL_ED25519_file | Tee-Object -Variable POOL_CRT_signed | Out-File -Encoding Default $POOL_CRT_signedfile
      # Get the stake pool ID
      $POOL_ID_file="${POOL_FOLDER}\${POOL_NAME}\stake_pool.id"
      $POOL_CRT_cert | & $CLI certificate get-stake-pool-id | Tee-Object -Variable POOL_ID | Out-File -Encoding Default $POOL_ID_file
      # Note pool-ID, vrf and KES keys into a secret file
      $SECRET_YAML_file="${POOL_FOLDER}\${POOL_NAME}\secret.yaml"
      & $JQ -n ".genesis.node_id = \`"$POOL_ID\`" | .genesis.vrf_key = \`"$POOL_VRF_key\`" | .genesis.sig_key = \`"$POOL_KES_key\`"" | `
        Tee-Object -Variable SECRET_YAML | Out-File -Encoding Default $SECRET_YAML_file
      $POOL_JSON_file="${POOL_FOLDER}\${POOL_NAME}\stake_pool_owner_wallet.json"
      $POOL_JSON_signedfile="${POOL_FOLDER}\${POOL_NAME}\stake_pool_owner_wallet.sig"
      & $JQ -n ".owner = \`"$POOL_ED25519_pub\`" | .name = \`"$POOL_NAME\`" | .ticker = \`"$POOL_TICKER\`" | .homepage = \`"$POOL_URL\`" | .pledge_address = \`"$POOL_ED25519_address\`"" | `
        Tee-Object -Variable POOL_JSON | Out-File -Encoding Default $POOL_JSON_file
      & $CLI key sign --secret-key $POOL_ED25519_file --output $POOL_JSON_signedfile $POOL_JSON_file
      $STAGING_FILE=New-TemporaryFile
      $WITNESS_SECRET_FILE=New-TemporaryFile
      $WITNESS_OUTPUT_FILE=New-TemporaryFile
      & $CLI transaction new --staging $STAGING_FILE
      & $CLI transaction add-account $SOURCE_ADDRESS $AMOUNT_WITH_FEES --staging $STAGING_FILE
      & $CLI transaction add-certificate --staging $STAGING_FILE $POOL_CRT_cert
      & $CLI transaction finalize `
        --fee-constant $FEE_CONSTANT `
        --fee-coefficient $FEE_COEFFICIENT `
        --fee-pool-registration $FEE_POOL_REGISTRATION `
        --staging $STAGING_FILE
      $TRANSACTION_ID=& $CLI transaction data-for-witness --staging $STAGING_FILE
      $SOURCE_KEY | Out-File -Encoding Default $WITNESS_SECRET_FILE
      & $CLI transaction make-witness $TRANSACTION_ID `
        --genesis-block-hash $BLOCK0_HASH `
        --type "account" --account-spending-counter $SOURCE_COUNTER `
        $WITNESS_OUTPUT_FILE $WITNESS_SECRET_FILE
      & $CLI transaction add-witness $WITNESS_OUTPUT_FILE --staging $STAGING_FILE

      # Finalize the transaction and send it
      & $CLI transaction seal --staging $STAGING_FILE
      & $CLI transaction auth --staging $STAGING_FILE -k $POOL_ED25519_file
      $TXID=& $CLI transaction to-message --staging $STAGING_FILE | & $CLI rest v0 message post --host $NODE_REST_URL

      Remove-Item -Path $STAGING_FILE -Confirm:$false -Force -ErrorAction SilentlyContinue | Out-Null
      Remove-Item -Path $WITNESS_SECRET_FILE -Confirm:$false -Force -ErrorAction SilentlyContinue | Out-Null
      Remove-Item -Path $WITNESS_OUTPUT_FILE -Confirm:$false -Force -ErrorAction SilentlyContinue | Out-Null

      say "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
      say "Registered a new pool: `"$POOL_NAME`"" "log"
      say "  Pool-ID:    $POOL_ID" "log"
      say "  Fees:       $AMOUNT_WITH_FEES_NICE" "log"
      say "  TX-ID:      $TXID" "log"
      say "" "log"
      say "Upload the following files to the stake pool registry:" "log"
      say "  `"$POOL_JSON_file`"" "log"
      say "  `"$POOL_JSON_signedfile`"" "log"
      say "`n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~`n"
      Break
    }
    "show" {
      if ($PARAMS -lt 2) {
        usage
      }
      $RESULT=& $CLI rest v0 stake-pools get --host $NODE_REST_URL --output-format json 2> $null
      Write-Output "`nRegistered stake pools are:`n"
      Write-Output ($RESULT | Out-String)
      Break
    }
    Default {
      Write-Output "`nNo such subcommand: $SUBCOMMAND`n"
      usage
      Break
    }
  }
}

function check() {
  Switch($SUBCOMMAND) {
    "tx" {
      if ($PARAMS -lt 3) {
        usage
      }
      $TX_ID = $3
      $RESULT=& $CLI rest v0 message logs --host $NODE_REST_URL --output-format json 2> $null
      $TX_STATUS=$RESULT | jq  ".[] | select (.fragment_id == \`"$TX_ID\`")" 2> $null
      Write-Output "`nStatus of TX_ID `"$TX_ID`" is:`n"
      if ($null -ne $TX_STATUS) {
        Write-Output ($TX_STATUS | Out-String)
      }
      else {
        Write-Output "ERROR: TX_ID not found`n"
      }
      Break
    }
    "node" {
      if ($PARAMS -lt 3) {
        usage
      }
      Switch($3) {
        "stats" {
          $RESULT=& $CLI rest v0 node stats get --host $NODE_REST_URL --output-format json 2> $null
          Write-Output "`nStatus of this node is:`n"
          if ($null -ne $RESULT) {
            Write-Output ($RESULT | Out-String)
          }
          else {
            Write-Output "ERROR: Node status not found`n"
          }
          Break
        }
        "settings" {
          $RESULT=& $CLI rest v0 settings get --host $NODE_REST_URL --output-format json 2> $null
          Write-Output "`nSettings of this node are:`n"
          if ($null -ne $RESULT) {
            Write-Output ($RESULT | Out-String)
          }
          else {
            Write-Output "ERROR: Node settings not found`n"
          }
          Break
        }
        Default {
          Write-Output "`nNo such `"check node`" subcommand: $3`n"
          usage
          Break
        }
      }
    }
    Default {
      Write-Output "`nNo such subcommand: $SUBCOMMAND`n"
      usage
      Break
    }
  }
}

function update() {
  Write-Output "`nTo update jtools and jormungandr on Windows, from an administrative PowerShell:`n"
  Write-Output "  choco upgrade jormungandr`n"
}

function main() {
  if ($PARAMS -lt 1) {
    usage
  }

  # Check for required command line tools
  need_cmd $CURL
  need_cmd $JQ

  Switch ($OPERATION) {
    "wallet"  { wallet; Break }
    "funds"   { funds;  Break }
    "check"   { check;  Break }
    "pool"    { pool;   Break }
    "stake"   { stake;  Break }
    "update"  { update;  Break }
    "version" { version; Break }
    Default {
      Write-Output "`nNo such operation: $OPERATION`n"
      usage
      Break
    }
  }
}

main
Exit
