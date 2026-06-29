# Privacy-Preserving AI Bounty Judge

Built on Ritual Testnet (Chain ID 1979) as part of the Ritual AI Bounty Judge Workshop Homework.

**Deployed Contract:** `0x131cfaf918F4F6F97810615eF6b293aF8EF1B396`  
**Explorer:** https://explorer.ritualfoundation.org/address/0x131cfaf918F4F6F97810615eF6b293aF8EF1B396

---

## The Problem

In the original workshop contract, answers are public the moment they are submitted. This means a later participant can read an earlier submission, copy it, improve it, and win unfairly.

## The Solution: Commit-Reveal Flow

Answers stay hidden during the submission phase. Only a hash is stored on-chain. The real answer is revealed after the submission deadline — and verified cryptographically before being eligible for AI judging.

---

## Bounty Lifecycle


Phase 1 — SUBMISSION (before submissionDeadline)

Participant computes:

commitment = keccak256(answer + salt + walletAddress + bountyId)

Submits only the hash — answer stays completely hidden.
Phase 2 — REVEAL (after submissionDeadline, before revealDeadline)

Participant submits real answer + salt.

Contract verifies hash matches. Only valid reveals are eligible.
Phase 3 — JUDGING (after revealDeadline)

Owner calls judgeAll() — sends ALL answers to Ritual AI in ONE batch call.
Phase 4 — FINALIZATION

Owner reviews AI output and calls finalizeWinner().

Contract pays reward to winner automatically.

---

## Contract Functions

| Function | Phase | Who |
|---|---|---|
| `createBounty(description, subDeadline, revealDeadline)` | Setup | Owner |
| `submitCommitment(bountyId, commitment)` | Submission | Participants |
| `revealAnswer(bountyId, answer, salt)` | Reveal | Participants |
| `judgeAll(bountyId, llmInput)` | Judging | Owner |
| `finalizeWinner(bountyId, winnerIndex)` | Finalization | Owner |

---

## Commitment Formula

```solidity
bytes32 commitment = keccak256(
    abi.encodePacked(answer, salt, msg.sender, bountyId)
);
```

Including `msg.sender` and `bountyId` prevents copy attacks — another participant cannot reuse someone else's commitment hash.

---

## Security Features

- One commitment per participant per bounty
- Reveal must match commitment hash exactly
- Unrevealed submissions ineligible for judging
- `judgeAll()` only callable after reveal deadline
- `finalizeWinner()` only callable after judging
- Copy attack prevention tested and verified
- Emergency `reclaimIfNoReveals()` if zero valid reveals exist
- Human-in-the-loop finalization — AI recommends, owner confirms

---

## Test Results

Ran 25 tests for test/PrivacyBountyJudge.t.sol

25 passed, 0 failed
Tests cover:
- Valid bounty creation and revert cases
- Valid commitment submission and double-commit protection
- Valid reveal and wrong answer/salt revert cases
- Copy attack prevention
- Full happy path: commit → reveal → judge → finalize
- Phase helper verification

---

## Architecture: Commit-Reveal vs Ritual-Native TEE

| Property | Commit-Reveal (This Contract) | Ritual-Native TEE |
|---|---|---|
| Works on any EVM | ✅ | ❌ Ritual only |
| Answers hidden during submission | ✅ | ✅ |
| Answers hidden during reveal | ❌ | ✅ |
| Complexity | Low | High |

---

## Reflection

What should be public, what should stay hidden, and what should be decided by AI versus by a human in a bounty system?

The bounty description and reward should always be public so participants can make informed decisions. Individual submissions must stay hidden during the submission phase to prevent copying — and ideally through the reveal phase as well. The commitment hash can be public because it reveals nothing about the answer content. The final ranking and reasoning should become public after judging for transparency. AI is well-suited to evaluate submissions consistently and without bias, but the final payout decision should remain with a human owner who can verify the AI output before funds are transferred. This human-in-the-loop design ensures a buggy or manipulated AI result cannot automatically drain the contract. The combination of cryptographic hiding, AI evaluation, and human finalization creates a system that is both fair and trustworthy.

---

## How to Run

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone and build
git clone https://github.com/ThereisnoAdekunle/ritual-bounty-judge
cd ritual-bounty-judge
forge install
forge build

# Run tests
forge test -v

# Deploy to Ritual Testnet
printf 'PRIVATE_KEY=0xYOUR_KEY' > .env
source .env
forge script script/Deploy.s.sol:DeployPrivacyBountyJudge \
  --rpc-url https://rpc.ritualfoundation.org \
  --broadcast
```

---

## Built With

- [Foundry](https://getfoundry.sh)
- [Ritual Testnet](https://ritualfoundation.org)
- Solidity 0.8.20