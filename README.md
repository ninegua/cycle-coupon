# Claim a new cycles wallet with coupon code

New developers coming to the [Internet Computer] do not have an easy way to start deploying canisters to the public block chain.

This project allows a controller to create coupon codes to give to developers, who can later redeem a coupon code to get their own [cycle wallet].

## Steps

**1. Download and install [DFINITY SDK]**

Please follow the steps in the link.
A successful installation should give you a command line tool called `dfx`.

**2. Create an identity**

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
dfx identity get-wallet --network=ic
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

But don't worry, all it means is that you don't have a cycle wallet on the main net.
In the next step you will create a cycle wallet by redeeming a coupon code.

**3. Claim the cycle wallet canister**

Needless to say, you will need a coupon code before proceed.
Suppose you are already given one, then the following command will create a new cycle wallet for you.

```
CODE=xxxxx-yyyyy-zzzzz
dfx canister --network=ic --no-wallet call fg7gi-vyaaa-aaaal-qadca-cai redeem "(\"$CODE\")"
```

If everything goes well, the above command will output something like:

```
(principal "qsgjb-riaaa-aaaaa-aaaga-cai")
```

This means a new cycle wallet with canister id `qsgjb-riaaa-aaaaa-aaaga-cai` has been created for you.

You can check its canister status using:

```
dfx canister --network=ic --no-wallet status qsgjb-riaaa-aaaaa-aaaga-cai
```

It should output something like:

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

You might get different values for `Controllers`, `Balance` and `Module hash`.
But the controller should be your principal id.

**4. Setup your cycle wallet**

Finally, you can set up your cycle wallet by:

```
dfx identity --network=ic set-wallet CANISTER_ID
```

Replace that `CANISTER_ID` argument with the output from step 3.

You can also verify if your cycle wallet is working:

```
dfx wallet --network balance
```

It should print the remaining cycles in your wallet.
Congratulations! You have just finished setting up your first cycle wallet.

## How can I get a coupon code?

Coupon codes are usually given to students who signed for Internet Computer related development courses.
I personally will only give out code if you have signed up my classes.

[Internet Computer]: https://internetcomputer.org
[DFINITY SDK]: https://smartcontracts.org
[cycle wallet]: https://smartcontracts.org/docs/developers-guide/default-wallet.html
