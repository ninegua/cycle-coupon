USAGE="USAGE: $0 <number of coupons> <trillion cycle per coupon>"
n=$1
cycle=$2
test -z "$n" && echo "$USAGE" && exit 1
test -z "$cycle" && echo "$USAGE" && exit 1
cycle=$(( cycle * 1000000000000 ))

e8s=${3:-800000}
FAUCET=fg7gi-vyaaa-aaaal-qadca-cai
OUTPUT=coupons.txt

echo -e "==========\nStep 0: Checking if we are authorized\n=========="
dfx canister --network=ic call --query $FAUCET stats 2>&1 > /dev/null || (echo "You are not authorized by the faucet to add coupons. Abort!" && exit 1)

echo -e "\n==========\nStep 1: Getting ICP to Cycle conversion rate\n=========="

million_cycles_per_icp=$(dfx canister --network=ic call --query rkp4c-7iaaa-aaaaa-aaaca-cai get_icp_xdr_conversion_rate |grep 2_214_623_967|sed -e 's/^.*= //' -e 's/ :.*$//' -e 's/_//g' -e 's/$/00/')
test $? = 0 || exit 1
echo "1 ICP = $million_cycles_per_icp million cycles"
e8s=$((100000000 * 200000 / million_cycles_per_icp))
topup=$((cycle * 100 / million_cycles_per_icp))
cycle_readable=$(printf "%021d" $cycle|sed -e 's/\(...\)/\1_/g' -e 's/^[0_]*//' -e 's/_$//')
echo "About to create $n coupon(s), each of $cycle_readable cycles, and will cost $e8s e8s (to create a canister id)"
echo "Successfully created coupons will be appended to file '$OUTPUT'"
echo -n "Does it look right to you? (y/N) "
read answer
test "$answer" != y && test "$answer" != Y && echo Abort! && exit 1

for i in $(seq 1 $n); do
  while true; do
    coupon=$(uuidgen -r|sed -s 's/-//g'|tr '[:lower:]' '[:upper:]' |sed -e 's/...../&-/g'|cut -c1-17)
    echo $coupon | grep -q '[1I0OZ2]' || break
  done

  echo -e "\n==========\nStep 2: Creating canister id for coupon $i\n=========="
  tmpfile=$(mktemp)
  dfx ledger --network=ic create-canister --e8s "$e8s" "$(dfx identity get-principal)" | tee $tmpfile
  test $? = 0 || exit 1
  canister_id=$(cat $tmpfile | grep Canister | cut -d\" -f2)
  rm $tmpfile

  echo -e "\n==========\nStep 3: Setting canister controller of $canister_id to $FAUCET\n=========="
  tmpdir=$(mktemp -d)
  pushd $tmpdir
  echo "{\"canister\":{\"ic\":\"$canister_id\"}}" > canister_ids.json
  echo '{"canisters":{"canister":{}}}' > dfx.json
  dfx canister --network=ic update-settings canister --add-controller $FAUCET && popd
  test $? = 0 || exit 1
  rm -rf $tmpdir

  echo -e "\n==========\nStep 4: Reserving canister $canister_id with the faucet \n=========="
  dfx canister --network=ic call --update $FAUCET reserve "(vec { principal \"$canister_id\" })"
  test $? = 0 || exit 1

  echo -e "\n==========\nStep 5: Adding coupon $coupon to faucet \n=========="
  tmpfile=$(mktemp)
  dfx canister --network=ic call --update $FAUCET add "(vec { record { \"$coupon\"; $cycle : nat } })" | tee $tmpfile
  test $? = 0 || exit 1
  date --utc >> $OUTPUT
  cat $tmpfile >> $OUTPUT
  rm $tmpfile
done

echo -e "\nAll done! Please check the following stats and run 'dfx ledger --network=ic top-up $FAUCET' if necessary.\n"
dfx canister --network=ic call --query $FAUCET stats | sed -e 's/ *"{/"{\n /' -e 's/};/};\n/g' -e 's/}"/\n}"/'
