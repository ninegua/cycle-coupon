dfx canister --network=ic create faucet
dfx canister --network=ic update-settings faucet --controller $(dfx identity --network=ic get-wallet) --controller $(dfx identity get-principal)
dfx canister --network=ic --no-wallet install faucet --mode=reinstall
faucet=$(dfx canister --network=ic id faucet)
identity=$(dfx identity whoami)
ic-repl -r ic <<END
import faucet = "${faucet}"
identity ${identity} "~/.config/dfx/identity/${identity}/identity.pem"
call faucet.install(file "wallet.wasm")
END
