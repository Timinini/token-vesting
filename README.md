Token-Vesting
The Token Vesting contract is a Clarity smart contract for gradual token distribution on the Stacks blockchain.
It allows tokens to be locked for beneficiaries and released over time according to vesting schedules.

Features
Linear vesting release
Optional cliff period before unlocking
Beneficiaries can claim vested tokens anytime
Transparent on-chain vesting data
Event logs for all claims and completions

Technical Overview
Language: Clarity
Standards: SIP-010 fungible tokens
Core Functions:
create-vesting – create vesting schedule
claim-vested – claim vested tokens
get-vesting-info – view schedule details
