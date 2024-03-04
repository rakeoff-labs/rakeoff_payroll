module {
    public type Self = actor {
        deposit_cycles : shared { canister_id : Principal } -> async ();
    };
};
