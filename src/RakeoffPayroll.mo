import Result "mo:base/Result";
import Hex "mo:encoding/Hex";
import Blob "mo:base/Blob";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Time "mo:base/Time";
import Text "mo:base/Text";
import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Timer "mo:base/Timer";
import Set "mo:map/Set";
import Map "mo:map/Map";
import Cycles "mo:base/ExperimentalCycles";
import ManagementInterface "./management_interface/ManagementInterface";
import IcpLedgerInterface "./ledger_interface/ledger";
import IcpAccountTools "./ledger_interface/account";

shared ({ caller = owner }) actor class RakeoffPayroll() = thisCanister {

  /////////////////
  // Constants ////
  /////////////////

  // ICP management canster
  let IcpManagement = actor ("aaaaa-aa") : ManagementInterface.Self;

  // ICP ledger canister
  let IcpLedger = actor "ryjl3-tyaaa-aaaaa-aaaba-cai" : IcpLedgerInterface.Self;

  // The standard ICP transaction fee
  let ICP_PROTOCOL_FEE : Nat64 = 10_000;

  // The minimum amount of ICP needed to disburse any fees
  let MINIMUM_WITHDRAWAL_THRESHOLD : Nat64 = 100_000_000; // 1 ICP

  // The refresh rate of the fee disbursement
  let PAYROLL_REFRESH_TIME_NANOS : Nat = (24 * 60 * 60 * 1_000_000_000); // 24 hours

  // The refresh rate of the cluster cycle timer
  let CLUSTER_REFRESH_TIME_NANOS : Nat = (7 * 24 * 60 * 60 * 1_000_000_000); // 7 days

  // The amount of cycles each canister is topped up by
  let CYCLE_TOPUP_AMOUNT : Nat = 100_000_000_000; // 0.1 Trillion cycles

  // The minimum amount of cycles this canister must have in order to top up the cluster
  let MINIMUM_CYCLE_THRESHOLD : Nat = 10_000_000_000_000; // 10 Trillion

  /////////////
  // Types ////
  /////////////

  public type CanisterAccountsResult = Result.Result<{ icp_address : Text; icp_balance : Nat64 }, Text>;

  public type WithdrawIcpResult = Result.Result<IcpLedgerInterface.TransferResult, Text>;

  public type AddCanisterToClusterResult = Result.Result<Text, Text>;

  public type AddFeeAddressesResult = Result.Result<Text, Text>;

  public type CanisterClusterResult = Result.Result<[Text], ()>;

  public type FeeAddressesResult = Result.Result<[(Text, Nat64)], ()>;

  //////////////////////
  // Canister State ////
  //////////////////////

  // The cluster of Rakeoff canisters and amount of cycles to top up by
  private stable var _rakeoffCanisterCluster = Set.new<Text>();

  // The map of addresses and their percentage of fees
  private stable var _rakeoffFeeAddresses = Map.new<Text, Nat64>();

  private stable var _payrollFeeTimerId : Nat = 0;

  private stable var _clusterCycleTimerId : Nat = 0;

  system func postupgrade() {
    ignore setFeeTimer();
    ignore setClusterTimer();
  };

  ////////////////////////
  // Public Functions ////
  ////////////////////////

  public shared ({ caller }) func controller_get_canister_accounts() : async CanisterAccountsResult {
    assert (caller == owner);
    return await getCanisterAccounts(caller);
  };

  public shared ({ caller }) func controller_canister_withdraw_icp(transfer_amount : Nat64, account_id : Text) : async WithdrawIcpResult {
    assert (caller == owner);
    return await canisterWithdrawIcp(caller, transfer_amount, account_id);
  };

  public shared ({ caller }) func controller_init_payroll_fee_timer() : async Text {
    assert (caller == owner);
    return setFeeTimer();
  };

  public shared ({ caller }) func controller_init_cycles_cluster_timer() : async Text {
    assert (caller == owner);
    return setClusterTimer();
  };

  public shared ({ caller }) func controller_add_cycles_to_cluster() : async () {
    assert (caller == owner);
    return await addCyclesToCluster();
  };

  public shared ({ caller }) func controller_disburse_rakeoff_fees() : async () {
    assert (caller == owner);
    return await disburseRakeoffFees();
  };

  public shared ({ caller }) func controller_add_canister_to_cluster(canisterId : Text) : async AddCanisterToClusterResult {
    assert (caller == owner);
    return addCanisterToCluster(canisterId);
  };

  public shared ({ caller }) func controller_add_fee_address(address : Text, percentage : Nat64) : async AddFeeAddressesResult {
    assert (caller == owner);
    return addFeeAddress(address, percentage);
  };

  public shared query ({ caller }) func controller_get_canister_cluster() : async CanisterClusterResult {
    assert (caller == owner);
    return getCanisterCluster();
  };

  public shared query ({ caller }) func controller_get_fee_addresses() : async FeeAddressesResult {
    assert (caller == owner);
    return getAllFeeAddresses();
  };

  ////////////////////////////
  // Fee Helper Functions ////
  ////////////////////////////

  private func disburseRakeoffFees() : async () {
    let balance = await getCanisterIcpBalance();

    if (balance > MINIMUM_WITHDRAWAL_THRESHOLD) {
      for ((address, percentage) in Map.entries(_rakeoffFeeAddresses)) {
        let decodedAddress : [Nat8] = switch (Hex.decode(address)) {
          case (#ok decoded_address) { decoded_address };
          case _ { Debug.trap("Address failed to decode") };
        };

        ignore await canisterTransferIcp(decodedAddress, (balance * percentage) / 100);
      };
    };
  };

  private func setFeeTimer() : Text {
    // Safety cancel
    Timer.cancelTimer(_payrollFeeTimerId);

    // Set the timer again
    let timerId = Timer.recurringTimer(
      #nanoseconds(PAYROLL_REFRESH_TIME_NANOS),
      disburseRakeoffFees,
    );

    _payrollFeeTimerId := timerId;

    return "Reccuring timer set with ID: " # debug_show _payrollFeeTimerId;
  };

  private func addFeeAddress(newAddress : Text, newPercentage : Nat64) : AddFeeAddressesResult {
    // guard clause
    if (newAddress.size() != 64) {
      return #err("Invalid address");
    };

    // check if the address exists
    switch (Map.get(_rakeoffFeeAddresses, (Text.hash, Text.equal), newAddress)) {
      case (?oldPercentage) {
        let totalPercentage = calculateNewTotalPercentage(_rakeoffFeeAddresses, newPercentage) - oldPercentage;

        // if the new fee address percentage is ok we can now update it
        if (totalPercentage <= 100) {
          ignore Map.put(_rakeoffFeeAddresses, (Text.hash, Text.equal), newAddress, newPercentage);
          return #ok("Fee address: " # debug_show newAddress # " updated with " # debug_show newPercentage # " percent of fees");
        } else {
          return #err("Updating this fee address would exceed the maximum total percentage allowed");
        };
      };
      case _ {
        let totalPercentage = calculateNewTotalPercentage(_rakeoffFeeAddresses, newPercentage);

        // if the new fee address percentage is ok we can add it
        if (totalPercentage <= 100) {
          let res = Map.put(_rakeoffFeeAddresses, (Text.hash, Text.equal), newAddress, newPercentage);
          return #ok("New fee address: " # debug_show newAddress # " added with " # debug_show newPercentage # " percent of fees");
        } else {
          return #err("Adding this fee address would exceed the maximum total percentage allowed");
        };
      };
    };
  };

  private func calculateNewTotalPercentage(map : Map.Map<Text, Nat64>, newFeePercentage : Nat64) : Nat64 {
    // The map must never exceed 100 percent
    var totalPercentage : Nat64 = 0;

    for (fee in Map.vals(map)) {
      totalPercentage += fee;
    };

    return newFeePercentage + totalPercentage;
  };

  private func getAllFeeAddresses() : FeeAddressesResult {
    return #ok(Map.toArray(_rakeoffFeeAddresses));
  };

  ////////////////////////////////
  // Cluster Helper Functions ////
  ////////////////////////////////

  private func addCyclesToCluster() : async () {
    let cyclesAvailable = Cycles.balance();

    // The payroll canister needs to maintain sufficient cycles
    if (cyclesAvailable > MINIMUM_CYCLE_THRESHOLD) {
      // loop through the set of canisters
      for (canister in Set.keys(_rakeoffCanisterCluster)) {
        // top up each canister
        Cycles.add(CYCLE_TOPUP_AMOUNT);
        await IcpManagement.deposit_cycles({
          canister_id = Principal.fromText(canister);
        });
      };
    };
  };

  private func setClusterTimer() : Text {
    // Safety cancel
    Timer.cancelTimer(_clusterCycleTimerId);

    // Set the timer again
    let timerId = Timer.recurringTimer(
      #nanoseconds(CLUSTER_REFRESH_TIME_NANOS),
      addCyclesToCluster,
    );

    _clusterCycleTimerId := timerId;
    return "Reccuring timer set with ID: " # debug_show _clusterCycleTimerId;

  };

  private func addCanisterToCluster(canisterId : Text) : AddCanisterToClusterResult {
    if (Set.put(_rakeoffCanisterCluster, (Text.hash, Text.equal), canisterId)) {
      return #err("Failed to add canister. It already exists in the cluster.");
    } else {
      return #ok("Canister " # canisterId # " successfully added to the cluster.");
    };
  };

  private func getCanisterCluster() : CanisterClusterResult {
    return #ok(Set.toArray(_rakeoffCanisterCluster));
  };

  /////////////////////////
  // Canister Functions ///
  /////////////////////////

  private func getCanisterAccounts(caller : Principal) : async CanisterAccountsResult {
    let canister_icp_balance = await getCanisterIcpBalance();

    return #ok({
      icp_address = Hex.encode(getCanisterIcpAddress());
      icp_balance = canister_icp_balance;
    });
  };

  private func canisterWithdrawIcp(caller : Principal, transfer_amount : Nat64, account_id : Text) : async WithdrawIcpResult {
    if (account_id.size() != 64) {
      return #err("Invalid address");
    };

    let address_decoded = Hex.decode(account_id); // returns a decode or fails

    switch (address_decoded) {
      case (#ok address_decoded) {
        return #ok(
          await canisterTransferIcp(address_decoded, transfer_amount)
        );
      };
      case (#err address_decoded) {
        return #err("Address failed to decode");
      };
    };
  };

  private func getCanisterIcpAddress() : [Nat8] {
    let ownerAccount = Principal.fromActor(thisCanister);
    let subAccount = IcpAccountTools.defaultSubaccount();

    return Blob.toArray(IcpAccountTools.accountIdentifier(ownerAccount, subAccount));
  };

  private func getCanisterIcpBalance() : async Nat64 {
    let balance = await IcpLedger.account_balance({
      account = getCanisterIcpAddress();
    });

    return balance.e8s;
  };

  private func canisterTransferIcp(transfer_to : [Nat8], transfer_amount : Nat64) : async IcpLedgerInterface.TransferResult {
    return await IcpLedger.transfer({
      memo : Nat64 = 0;
      from_subaccount = ?Blob.toArray(IcpAccountTools.defaultSubaccount());
      to = transfer_to;
      amount = { e8s = transfer_amount - ICP_PROTOCOL_FEE };
      fee = { e8s = ICP_PROTOCOL_FEE };
      created_at_time = ?{
        timestamp_nanos = Nat64.fromNat(Int.abs(Time.now()));
      };
    });
  };
};
