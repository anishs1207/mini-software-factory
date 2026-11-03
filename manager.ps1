$ErrorActionPreference = 'Stop'
$infraDir = Join-Path $PSScriptRoot 'infra'
$ip = & terraform "-chdir=$infraDir" output -raw public_ip
if ($LASTEXITCODE -ne 0) { throw 'Read the VM address from Terraform state after a successful apply.' }
$key = & terraform "-chdir=$infraDir" output -raw ssh_private_key_path
if ($LASTEXITCODE -ne 0) { throw 'Read the SSH key path from Terraform state after a successful apply.' }
& ssh -t -i $key "ubuntu@$ip" 'cd ~/briefing-repo && bash agents/manager-chat.sh'
exit $LASTEXITCODE
