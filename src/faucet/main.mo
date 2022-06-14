import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Option "mo:base/Option";
import Prim "mo:prim";
import Principal "mo:base/Principal";
import Queue "mo:mutable-queue/Queue";
import StableMemory "mo:base/ExperimentalStableMemory";
import Text "mo:base/Text";
import Time "mo:base/Time";
import SHA256 "mo:sha256/SHA256";

shared (installation) actor class Faucet() = self {

    // The secret API key shared between Prometheus and this canister
    // to authorize access to the metrics endpoint
    let METRICS_API_KEY = "MySecretKey";

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

    type Allocation = { hash: ?Blob; coupon : ?Text; cycle : Cycle; expiry: Time };
    type Installed = { hash: ?Blob; coupon : ?Text; controller : Principal; canister : CanisterId; cycle: Cycle; creation: Time };
    type Pruned = { coupons_expired : Nat; wallets_pruned : Nat; cycles_spent : Nat };

    type WalletStats = { reserved: Nat; created: Nat; cycles_spent: Nat };
    type CouponStats = { expired: Nat; allocated: Nat };
    type CycleStats = { allocated: Nat; balance: Nat };

    type Stats =  { wallets: WalletStats; coupons: CouponStats; cycles: CycleStats; pruned: Pruned; };

    type HeaderField = (Text, Text);

    type HttpResponse = {
      status_code: Nat16;
      headers: [HeaderField];
      body: Blob;
    };
  
    type HttpRequest = {
      method: Text;
      url: Text;
      headers: [HeaderField];
      body: Blob;
    };

    let permission_denied: HttpResponse = {
      status_code = 403;
      headers = [];
      body = "";
    };

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

    func sha256(code: Text) : Blob {
      Blob.fromArray(SHA256.sha256(Blob.toArray(Text.encodeUtf8(code))))
    };

    func eqCoupon(code: Text) : { coupon: ?Text; hash: ?Blob } -> Bool {
      let image = sha256(code);
      func ({ coupon: ?Text; hash: ?Blob }) : Bool { coupon == ?code or hash == ?image }
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

    func _stats() : Stats {

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


      let wallet_stats = {
        reserved = reserved; 
        created = wallets_created; 
        cycles_spent = cycles_spent;
      };

      let coupon_stats = {
        expired = coupons_expired; 
        allocated = coupons_allocated;
      };

      let cycle_stats = {
        allocated = cycles_allocated;
        balance = Cycles.balance();
      };

      { wallets = wallet_stats; coupons = coupon_stats; cycles = cycle_stats; pruned = all_pruned };

    };

    public shared query (args) func stats() : async Text {
      assert(allowed(args.caller));
      debug_show(_stats());
    };

      public query func http_request(req : HttpRequest) : async HttpResponse {
      // Strip query params and get only path
      let ?path = Text.split(req.url, #char '?').next();
      Debug.print(req.url);
      Debug.print(path);
      switch (req.method, path) {
        // Endpoint that serves metrics to be consumed with Prometheseus
        case ("GET", "/metrics") {
          Debug.print("GET: /metrics");
          
          // Handle authz
         
          let key = get_api_key(req.headers);
          switch(key) {
            case(null) return permission_denied;
            case(?v) let key = v;
          };
          if (key != "Bearer " # METRICS_API_KEY) {
            return permission_denied;
          };

          // We'll arrive here only if authz was successful
          let m = metrics();
          Debug.print(m);
          {
            status_code =  200;
            headers = [ ("content-type", "text/plain") ];
            body =  Text.encodeUtf8(m);
          }
        };
        case _ {
          Debug.print("Invalid request");
          {
            status_code = 400;
            headers = [];
            body = "Invalid request";
          }
        };
      } 
    };

    // Returns the api key from the authz header
    func get_api_key(headers: [HeaderField]) : ?Text {
      let key = "";
      let authz_header : ?HeaderField = Array.find(headers, func((header, val): (Text, Text)) : Bool { header == "authorization" });
        switch authz_header {
          case(null) null;
          case(?header) {
            ?header.1;
          };
        };
    };

    // Returns a set of metrics encoded in Prometheus text-based exposition format
    // https://github.com/prometheus/docs/blob/main/content/docs/instrumenting/exposition_formats.md
    // More info on the specific metrics can be found in the following forum threads:
    // https://forum.dfinity.org/t/motoko-get-canisters-sizes-limits/2092
    // https://forum.dfinity.org/t/motoko-array-memory/5324/4
    func metrics() : Text {

      // Prometheus expects timestamps in ms. Time.now() returns ns.
      let timestamp = Int.toText(Time.now()/1000000);
      let stats = _stats();

      "# HELP coupons_allocated The number of allocated coupons \n" #
      "coupons_allocated{} " # Nat.toText(stats.coupons.allocated) # " " # timestamp # "\n" #
      "# HELP coupons_expired The number of expired coupons \n" #
      "coupons_expired{} " # Nat.toText(stats.coupons.expired) # " " # timestamp # "\n" #
      "# HELP wallets_created The number of wallets created \n" #
      "wallets_created{} " # Nat.toText(stats.wallets.created) # " " # timestamp # "\n" #
      "# HELP wallets_cycles_spent The total number of cycles spent for wallets \n" #
      "wallets_cycles_spent{} " # Nat.toText(stats.wallets.cycles_spent) # " " # timestamp # "\n" #
      "# HELP balance The current balance in cycles \n" #
      "balance{} " # Nat.toText(Cycles.balance()) # " " # timestamp # "\n" #
      "# HELP heap_size The current size of the wasm heap in pages of 64KiB \n" #
      "heap_size{} " # Nat.toText(Prim.rts_heap_size()) # " " # timestamp # "\n" #
      "# HELP mem_size The current size of the wasm memory in pages of 64KiB \n" #
      "mem_size{} " # Nat.toText(Prim.rts_memory_size()) # " " # timestamp # "\n" #
      "# HELP mem_size The current size of the stable memory in pages of 64KiB \n" #
      "stable_mem_size{} " # Nat64.toText(StableMemory.size()) # " " # timestamp;

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
          ignore Queue.pushFront({ hash = ?sha256(code); coupon = null; cycle = cycle; expiry = expiry }, all_coupons);
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
            ignore Queue.pushFront({ hash = ?sha256(code); coupon = null; cycle = cycle; expiry = now + expiry }, all_coupons);
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
            ignore Queue.pushFront({ hash = null; coupon = ?code; controller = caller; canister = canister_id; cycle = coupon.cycle; creation = now }, all_wallets);
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
