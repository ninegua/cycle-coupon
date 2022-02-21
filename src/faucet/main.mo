import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Queue "mo:mutable-queue/Queue";

shared (installation) actor class Faucet() = self {

    let OWNER = installation.caller;
    let DEFAULT_CYCLES = 1_000_000_000_000;
   
    type Cycle = Nat;
    type CanisterId = Principal;
    type CanisterSettings = { controllers : ?[Principal] };

    type Management = actor {
      create_canister : ({ settings : ?CanisterSettings }) -> async ({ canister_id : CanisterId });
      install_code : ({ mode : { #install; #reinstall; #upgrade }; canister_id : CanisterId; wasm_module : Blob; arg : Blob; }) -> async ();
      update_settings : ({ canister_id : CanisterId; settings : CanisterSettings; }) -> async ();
    };

    type Wallet = actor {
      add_controller : (Principal) -> async ();
      remove_controller : (Principal) -> async ();
    };

    type Allocation = { coupon : Text; cycle : Cycle };
    type Installed = { coupon : Text; controller : Principal; canister : CanisterId };

    stable var all_coupons = Queue.empty<Allocation>();

    stable var all_wallets = Queue.empty<Installed>();

    stable var wasm_binary : ?Blob = null;

    func eqCoupon(code: Text) : { coupon : Text } -> Bool {
      func ({ coupon: Text }) : Bool { coupon == code }
    };

    public shared (args) func add(allocations: [(Text, ?Cycle)]) : async [Text] {
      assert(args.caller == OWNER);
      let installed = Queue.empty<Text>();
      for ((code, cycle) in Iter.fromArray(allocations)) {
        if (Option.isNull(Queue.find(all_coupons, eqCoupon(code))) and
            Option.isNull(Queue.find(all_wallets, eqCoupon(code)))) {
          ignore Queue.pushFront({ coupon = code; cycle = Option.get(cycle, DEFAULT_CYCLES) }, all_coupons);
          ignore Queue.pushFront(code, installed);
        }
      };
      Queue.toArray(installed)
    };

    public shared (args) func install(wasm: Blob) {
      assert(args.caller == OWNER);
      wasm_binary := ?wasm;
    };

    public shared query (args) func coupons() : async [Allocation] {
      assert(args.caller == OWNER);
      Queue.toArray(all_coupons)
    };

    public shared query (args) func wallets() : async [Installed] {
      assert(args.caller == OWNER);
      Queue.toArray(all_wallets)
    };

    public shared (args) func wallet_receive() {
      let amount = Cycles.available();
      ignore Cycles.accept(amount);
    };

    // Redeem couple code to create a cycle wallet
    public shared (args) func redeem(code: Text) : async CanisterId {
      let caller = args.caller;
      switch (wasm_binary, Queue.removeOne(all_coupons, eqCoupon(code))) {
        case (?binary, ?coupon) {
          try {
            let IC0 : Management = actor("aaaaa-aa");
            let this = Principal.fromActor(self);
            Cycles.add(coupon.cycle);
            let result = await IC0.create_canister({ settings = ? { controllers = ?[this]; } });
            let canister_id = result.canister_id;
            await IC0.install_code({ mode = #install; canister_id = canister_id; wasm_module = binary; arg = Blob.fromArray([]) });
            let wallet : Wallet = actor(Principal.toText(canister_id));
            await wallet.add_controller(caller);
            await IC0.update_settings({ canister_id = canister_id; settings = { controllers = ?[caller] } });
            await wallet.remove_controller(this);
            ignore Queue.pushFront({ coupon = coupon.coupon; controller = caller; canister = canister_id }, all_wallets);
            canister_id
          } catch(e) {
            // Put the coupon code back if there is any error
            ignore Queue.pushFront(coupon, all_coupons);
            throw(e)
          }
        };
        case (null, ?coupon) {
          ignore Queue.pushFront(coupon, all_coupons);
          throw(Error.reject("Wasm binary is not provided yet"))
        };
        case (_, null) {
          switch (Queue.find(all_wallets, eqCoupon(code))) {
             case (?wallet) {
               throw(Error.reject("Code is already redeemed: " # debug_show(wallet)))
             };
             case null {
               throw(Error.reject("Code is not redeemable"))
             }
          }
        }
      }
    };
};
