import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Queue "mo:mutable-queue/Queue";
import Time "mo:base/Time";

shared (installation) actor class Faucet() = self {

    let OWNER = installation.caller;
    stable var ALLOWED = [OWNER];
    let ONE_SECOND = 1_000_000_000;
    let ONE_DAY = 24 * 60 * 60 * 1_000_000_000;
    let DEFAULT_EXPIRY = 7 * ONE_DAY; // 7 days to expire coupons
    let CREATION_EXPIRY = 30 * ONE_DAY; // 30 days to prune records of installation

    type Time = Time.Time;
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
      wallet_receive : () -> async ();
    };

    type Allocation = { coupon : Text; cycle : Cycle; expiry: Time };
    type Installed = { coupon : Text; controller : Principal; canister : CanisterId; cycle: Cycle; creation: Time };
    type Pruned = { coupons_expired : Nat; wallets_pruned : Nat; cycles_spent : Nat };

    // All coupons. Expired coupons are pruned from this queue when new coupons are added.
    stable var all_coupons = Queue.empty<Allocation>();

    // All wallets created. Past creations are pruned from this queue when new coupons are added.
    stable var all_wallets = Queue.empty<Installed>();

    // Spare canister ids to use for wallets. When these run out we'll call IC0.create_canister (on the same subnet as this canister).
    stable var canisters_reserve = Queue.empty<CanisterId>();

    // Stats of all past pruned coupons and wallets for record keeping.
    stable var all_pruned : Pruned = { coupons_expired = 0; wallets_pruned = 0; cycles_spent = 0 };

    // Binary of the wallet wasm module.
    stable var wasm_binary : ?Blob = null;

    func eqCoupon(code: Text) : { coupon : Text } -> Bool {
      func ({ coupon: Text }) : Bool { coupon == code }
    };

    public shared query func owner() : async { owner: Principal; allowed : [Principal] } {
      { owner = OWNER; allowed = ALLOWED }
    };

    func allowed(id: Principal) : Bool {
      Option.isSome(Array.find(ALLOWED, func (x: Principal) : Bool { x == id }))
    };

    public shared (args) func allow(ids: [Principal]) {
      assert(args.caller == OWNER or allowed(args.caller));
      ALLOWED := ids;
    };

    public shared query (args) func stats() : async Text {
      assert(allowed(args.caller));
      let now = Time.now();
      var coupons_allocated = 0;
      var cycles_allocated = 0;
      var coupons_expired = 0;
      var cycles_spent = 0;
      for (allocation in Queue.toIter(all_coupons)) {
        if (allocation.expiry < now) {
          coupons_expired := coupons_expired + 1;
        } else {
          coupons_allocated := coupons_allocated + 1;
          cycles_allocated := cycles_allocated + allocation.cycle;
        }
      };
      for (installed in Queue.toIter(all_wallets)) {
          cycles_spent := cycles_spent + installed.cycle;
      };

      let wallets_created = Queue.size(all_wallets);
      let reserved = Queue.size(canisters_reserve);
      debug_show({
        wallets = { reserved = reserved; created = wallets_created; cycles_spent = cycles_spent; };
        coupons = { expired = coupons_expired; allocated = coupons_allocated; };
        cycles = { allocated = cycles_allocated; balance = Cycles.balance(); };
        pruned = all_pruned;
      })
    };

    // TODO: Queue needs a more efficient filter function.
    func prune() {
        let now = Time.now();
        var coupons_expired = all_pruned.coupons_expired;
        var wallets_pruned = all_pruned.wallets_pruned;
        var cycles_spent = all_pruned.cycles_spent;
        let coupons_to_keep = Queue.empty<Allocation>();
        for (allocation in Queue.toIter(all_coupons)) {
           if (allocation.expiry >= now) {
              ignore Queue.pushBack(coupons_to_keep, allocation);
           } else {
              coupons_expired := coupons_expired + 1;
           }
        };
        all_coupons := coupons_to_keep;
        let wallets_to_keep = Queue.empty<Installed>();
        for (wallet in Queue.toIter(all_wallets)) {
            if (wallet.creation + CREATION_EXPIRY >= now) {
              ignore Queue.pushBack(wallets_to_keep, wallet);
            } else {
              wallets_pruned := wallets_pruned + 1;
            }
        };
        all_wallets := wallets_to_keep;
        all_pruned := { coupons_expired = coupons_expired; wallets_pruned = wallets_pruned; cycles_spent = cycles_spent; };
    };

    // Reserve canister ids for future wallet creation.
    public shared (args) func reserve(canisters: [CanisterId]) : async [CanisterId] {
      assert(allowed(args.caller));
      let IC0 : Management = actor("aaaaa-aa");
      let this = Principal.fromActor(self);
      let success = Queue.empty<CanisterId>();
      for (canister_id in Iter.fromArray(canisters)) {
        try {
          await IC0.update_settings({ canister_id = canister_id; settings = { controllers = ?[this] } });
          ignore Queue.pushBack(canisters_reserve, canister_id);
          ignore Queue.pushBack(success, canister_id);
        } catch(_) {};
      };
      Queue.toArray(success)
    };

    public shared (args) func add(allocations: [(Text, Cycle)]) : async [(Text, Nat)] {
      assert(allowed(args.caller));
      prune();
      let installed = Queue.empty<(Text, Nat)>();
      for ((code, cycle) in Iter.fromArray(allocations)) {
        if (Option.isNull(Queue.find(all_coupons, eqCoupon(code))) and
            Option.isNull(Queue.find(all_wallets, eqCoupon(code)))) {
          let expiry = Time.now() + DEFAULT_EXPIRY;
          ignore Queue.pushFront({ coupon = code; cycle = cycle; expiry = expiry }, all_coupons);
          ignore Queue.pushFront((code, cycle), installed);
        }
      };
      Queue.toArray(installed)
    };

    public shared (args) func update(allocations: [(Text, Cycle, Time)]) : async [Text] {
      assert(allowed(args.caller));
      let now = Time.now();
      let updated = Queue.empty<Text>();
      for ((code, cycle, expiry) in Iter.fromArray(allocations)) {
        switch (Queue.removeOne(all_coupons, eqCoupon(code))) {
          case (?(_)) {
            ignore Queue.pushFront({ coupon = code; cycle = cycle; expiry = now + expiry }, all_coupons);
            ignore Queue.pushFront(code, updated);
          };
          case null {}
        }
      };
      Queue.toArray(updated)
    };

    public shared (args) func install(wasm: Blob) {
      assert(allowed(args.caller));
      wasm_binary := ?wasm;
    };

    public shared query (args) func coupons() : async [Allocation] {
      assert(allowed(args.caller));
      Queue.toArray(all_coupons)
    };

    public shared query (args) func wallets() : async [Installed] {
      assert(allowed(args.caller));
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
          let now = Time.now();
          if (coupon.expiry < now) {
            throw(Error.reject("Code is expired"))
          };
          try {
            let IC0 : Management = actor("aaaaa-aa");
            let this = Principal.fromActor(self);
            var cycle_to_add = coupon.cycle;
            let canister_id = switch (Queue.popFront(canisters_reserve)) {
              case (?canister_id) { canister_id };
              case null {
                Cycles.add(cycle_to_add);
                cycle_to_add := 0;
                (await IC0.create_canister({ settings = ? { controllers = ?[this]; } })).canister_id;
              };
            };
            await IC0.install_code({ mode = #install; canister_id = canister_id; wasm_module = binary; arg = Blob.fromArray([]) });
            let wallet : Wallet = actor(Principal.toText(canister_id));
            if (cycle_to_add > 0) {
              Cycles.add(cycle_to_add);
              await wallet.wallet_receive();
            };
            await wallet.add_controller(caller);
            await IC0.update_settings({ canister_id = canister_id; settings = { controllers = ?[caller] } });
            await wallet.remove_controller(this);
            ignore Queue.pushFront({ coupon = coupon.coupon; controller = caller; canister = canister_id; cycle = coupon.cycle; creation = now }, all_wallets);
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
               throw(Error.reject("Code is expired or not redeemable"))
             }
          }
        }
      }
    };
};
