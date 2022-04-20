# Claim a new cycles wallet with coupon code


New developers coming to the [Internet Computer] do not have an easy way to start deploying canisters to the public block chain, because they either need someone else to help create a cycles wallet for them, or they need some ICP tokens (purchased through cryptocurrency exchanges, which is a daunting process for beginners too).

This project allows a controller to create coupon codes to give to developers, who can later redeem a coupon code to get their own [cycles wallet].

Coupon Cycle Canister: [fg7gi-vyaaa-aaaal-qadca-cai](https://ic.rocks/principal/fg7gi-vyaaa-aaaal-qadca-cai)

## Steps

**1. Download and install [DFINITY SDK].**

Please follow instructions in the above link.
A successful installation should give you a command line tool called `dfx`.

**2. Know your identity.**

The installation of `dfx` will create a new identity called "default".
Most if not all development activities will require using your own identity for authentication purpose.
Its private key can be found in `~/.config/dfx/identity/default/identity.pem`.
Please backup this file, because losing it or overwriting its content means that you will no longer have access to this identity.

You can print the principal id of your identity by:
```
dfx identity get-principal
```

Note that this identity is the same regardless of whether you are doing local or remote deployment.

You can also get the wallet canister id (on main net) that is associated with your identity by:

```
dfx identity --network=ic get-wallet
```

If this is the first time you use `dfx`, depending on its version, you may be greeted with a very cryptic (or even misleading) error like below:

```
Creating a wallet canister on the ic network.
The replica returned an HTTP Error: Http Error: status 404 Not Found, content type "text/html", content: <html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx/1.21.3</center>
</body>
</html>
```

But don't worry, all it means is that you don't have a cycles wallet on the main net.
In the next step you will create a cycles wallet by redeeming a coupon code.

**3. Claim the cycles wallet canister.**

Needless to say, you will need a coupon code before you proceed.
Suppose you are already given one, then the following command will create a new cycles wallet:

```
CODE=xxxxx-yyyyy-zzzzz
dfx canister --network=ic call fg7gi-vyaaa-aaaal-qadca-cai redeem "(\"$CODE\")"
```

It should take less than 10 seconds, and if everything goes well, the output is something like this:

```
(principal "qsgjb-riaaa-aaaaa-aaaga-cai")
```

This means a new cycles wallet with canister id `qsgjb-riaaa-aaaaa-aaaga-cai` has been created for you.

You can check its canister status using:

```
dfx canister --network=ic status qsgjb-riaaa-aaaaa-aaaga-cai
```

It should output something like this:

```
Canister status call result for qsgjb-riaaa-aaaaa-aaaga-cai.
Status: Running
Controllers: d6rkl-arkua-nkeao-rwond-53anf-g2eij-zc2n7-wgzx7-z5y4x-26u7r-4ae
Memory allocation: 0
Compute allocation: 0
Freezing threshold: 2_592_000
Memory Size: Nat(2812290)
Balance: 1_000_000_000_000 Cycles
Module hash: 0x53ec1b030f1891bf8fd3877773b15e66ca040da539412cc763ff4ebcaf4507c5
```

You will get different values for `Controllers`, `Balance` and `Module hash`.
But the controller should be your principal id from **Step 2**.

**4. Setup your cycles wallet**

Finally, you can set up your cycles wallet by:

```
dfx identity --network=ic set-wallet CANISTER_ID
```

Replace that `CANISTER_ID` argument with the output from step 3.

You can also verify if your cycles wallet is working:

```
dfx wallet --network=ic balance
```

It should print the remaining cycles in your wallet.
Congratulations! You have just finished setting up your first cycles wallet.

## Reminders

- One coupon code can be redeemed only once.
- If you have multiple codes, it is best to redeem each of them with a newly created identity.
  This is because step 4 will detach your identity from the current wallet canister if you had one, and you will lose access if you haven't written down its canister id.
- When you use cycles wallet to deploy your project, you should specify the amount of cycles by `dfx deploy --network=ic --with-cycles=...`. Usually 1 trillion cycles is enough for most purposes.
- Please make sure you reclaim unused cycles when you no longer need the canisters you have deployed through the cycles wallet.
  `dfx canister --network=ic stop CANISTER_ID && dfx canister --network=ic delete CANISTER_ID` will do the trick.

## How can I get a coupon code?

You might get a free coupon code by going through [Cycle Faucet].
Or you may get one through private channels if you have signed up for Internet Computer related development courses.
I personally will only give out code if you have signed up my classes.

## For administrators

If you are an authorized administrator, you may add new coupons to the faucet by running the [add-coupons.sh](./add-coupons.sh) script.
Please also make sure you have some ICP balance (use `dfx ledger --network=ic balance` to check) before creating new coupons.
This because each coupon will require creating a new canister id through the ICP Ledger.

[Internet Computer]: https://internetcomputer.org
[DFINITY SDK]: https://smartcontracts.org
[cycles wallet]: https://smartcontracts.org/docs/developers-guide/default-wallet.html
[Cycle Faucet]: https://faucet.dfinity.org
