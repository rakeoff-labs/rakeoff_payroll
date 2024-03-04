# `RakeoffPayroll()`

This repo contains the smart contract code (canister) for the Rakeoff payroll smart contract that processes the Rakeoff protocol fees to the dev team and tops up all the Rakeoff protocol canisters with cycles.

This canister was created so that the Rakeoff protocol can be more autonomous - devs get paid and canisters get topped up automatically. This canister is needed because of ICP's reverse gas model - devs pay to run canisters. So, as of writing there is currently enough cycles in this canister (259T) to top up the Rakeoff canister cluster for around 8 years - 0.6T a week or 31.2T a year. Leaving a minimum of 10T cycles in this canister so it can continue to process fees.

*This canister existing doesn't mean the Rakeoff protocol will not need to be topped up with extra cycles from the dev team (or others) for 8 years (as mentioned above). If the amount of canisters in the cluster increases, the usage of the dApp increases by a lot or the ICP protocol itself changes; cycles may be used faster than they are topped up. However, this is still a nice canister to have and it ensures minimal intervention from the team.*

## Overview of the tech stack

- [Motoko](https://react.dev/](https://internetcomputer.org/docs/current/motoko/main/motoko?source=nav)) is used for the smart contract programming language.
- The IC SDK: [DFX](https://internetcomputer.org/docs/current/developer-docs/setup/install) is used to make this an ICP project.

### How does it work?

The canister is designed to be minimal. It doesn't need to be a controller of any of the canisters in the cluster like https://cycleops.dev/ or do any more work than neccessary. It runs on two timers, one for the payroll and one for the cluster top up:

- The payroll timer runs every 24 hours to check *if the fee balance is above 1 ICP* and then sends the fee allocations to the dev team.
- The cluster top up timer runs every 7 days and tops up every canister with 0.1 Trillion cycles (100 billion).

### If you want to clone onto your local machine

Make sure you have `git` and `dfx` installed
```bash
# clone the repo
git clone #<get the repo ssh>

# change directory
cd rakeoff_payroll

# set up the dfx local server
dfx start --background --clean

# deploy the canisters locally
dfx deploy

# ....
# when you are done make sure to stop the local server:
dfx stop
```

## License

The `RakeoffPayroll()` smart contract code is currently All Rights Reserved

