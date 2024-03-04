# Helpful commands

# dfx deploy --network ic RakeoffPayroll
# dfx canister --network ic install --mode reinstall RakeoffPayroll
# dfx canister --network ic status RakeoffPayroll

# 
# canister functions:
# 

# dfx canister --network ic call RakeoffPayroll controller_get_canister_accounts
# dfx canister --network ic call RakeoffPayroll controller_canister_withdraw_icp '(<amount>, "<address>")'
# dfx canister --network ic call RakeoffPayroll controller_add_canister_to_cluster '("<canisterId>")'
# dfx canister --network ic call RakeoffPayroll controller_add_fee_address '("<address>", <percentage>)'
# dfx canister --network ic call RakeoffPayroll controller_get_canister_cluster
# dfx canister --network ic call RakeoffPayroll controller_get_fee_addresses