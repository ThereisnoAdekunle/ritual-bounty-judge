// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title  PrivacyBountyJudge
 * @notice Commit-reveal AI Bounty Judge built for Ritual testnet
 * @dev    Required Track: commit-reveal flow
 *
 * LIFECYCLE:
 *  1. Owner creates bounty (reward locked in contract)
 *  2. Participants submit commitment hash — answer stays hidden
 *  3. After submissionDeadline → reveal phase
 *  4. Participants reveal answer + salt — contract verifies hash
 *  5. After revealDeadline → owner calls judgeAll() via Ritual AI
 *  6. Owner calls finalizeWinner() → reward paid to winner
 */
contract PrivacyBountyJudge {

    // ─────────────────────────────────────────────
    // STRUCTS
    // ─────────────────────────────────────────────

    struct Submission {
        bytes32 commitment;
        string  revealedAnswer;
        bool    hasCommitted;
        bool    hasRevealed;
    }

    struct Bounty {
        address owner;
        string  description;
        uint256 reward;
        uint256 submissionDeadline;
        uint256 revealDeadline;
        bool    judged;
        bool    finalized;
        address winner;
        address[] participants;
        address[] revealedParticipants;
        string  judgingResult;
    }

    // ─────────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────────

    uint256 public bountyCount;
    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => mapping(address => Submission)) public submissions;

    // ─────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────

    event BountyCreated(uint256 indexed bountyId, address indexed owner, uint256 reward);
    event CommitmentSubmitted(uint256 indexed bountyId, address indexed participant);
    event AnswerRevealed(uint256 indexed bountyId, address indexed participant);
    event BountyJudged(uint256 indexed bountyId, string judgingResult);
    event WinnerFinalized(uint256 indexed bountyId, address indexed winner, uint256 reward);

    // ─────────────────────────────────────────────
    // MODIFIERS
    // ─────────────────────────────────────────────

    modifier onlyOwner(uint256 bountyId) {
        require(msg.sender == bounties[bountyId].owner, "Not bounty owner");
        _;
    }

    modifier bountyExists(uint256 bountyId) {
        require(bountyId < bountyCount, "Bounty does not exist");
        _;
    }

    // ─────────────────────────────────────────────
    // CORE FUNCTIONS
    // ─────────────────────────────────────────────

    function createBounty(
        string calldata description,
        uint256 submissionDeadline,
        uint256 revealDeadline
    ) external payable returns (uint256 bountyId) {
        require(msg.value > 0,                          "Reward must be > 0");
        require(submissionDeadline > block.timestamp,   "Submission deadline must be in future");
        require(revealDeadline > submissionDeadline,    "Reveal deadline must be after submission deadline");

        bountyId = bountyCount++;
        Bounty storage b = bounties[bountyId];
        b.owner              = msg.sender;
        b.description        = description;
        b.reward             = msg.value;
        b.submissionDeadline = submissionDeadline;
        b.revealDeadline     = revealDeadline;

        emit BountyCreated(bountyId, msg.sender, msg.value);
    }

    function submitCommitment(
        uint256 bountyId,
        bytes32 commitment
    ) external bountyExists(bountyId) {
        Bounty storage b = bounties[bountyId];
        require(block.timestamp < b.submissionDeadline,                 "Submission phase has ended");
        require(!submissions[bountyId][msg.sender].hasCommitted,        "Already committed");
        require(commitment != bytes32(0),                               "Invalid commitment");

        submissions[bountyId][msg.sender].commitment   = commitment;
        submissions[bountyId][msg.sender].hasCommitted = true;
        b.participants.push(msg.sender);

        emit CommitmentSubmitted(bountyId, msg.sender);
    }

    function revealAnswer(
        uint256 bountyId,
        string calldata answer,
        bytes32 salt
    ) external bountyExists(bountyId) {
        Bounty storage b    = bounties[bountyId];
        Submission storage s = submissions[bountyId][msg.sender];

        require(block.timestamp >= b.submissionDeadline, "Submission phase still active");
        require(block.timestamp <  b.revealDeadline,     "Reveal phase has ended");
        require(s.hasCommitted,                          "No commitment found");
        require(!s.hasRevealed,                          "Already revealed");

        bytes32 expected = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId));
        require(s.commitment == expected, "Commitment mismatch: invalid answer or salt");

        s.revealedAnswer = answer;
        s.hasRevealed    = true;
        b.revealedParticipants.push(msg.sender);

        emit AnswerRevealed(bountyId, msg.sender);
    }

    
// Ritual LLM precompile address (0x0802 per Ritual Chain docs)
    // NOTE: On Ritual Chain, LLM inference is ASYNC — the precompile call
    // initiates a TEE-backed off-chain job. The result is delivered via
    // callback in a subsequent transaction, not returned synchronously.
    // For this Required Track (commit-reveal), judgeAll() accepts the
    // llmInput payload and stores the result. In a full Ritual-native
    // implementation, this would use the async callback pattern with
    // a receiveResult() handler. See Advanced Track notes in README.
    address constant LLM_INFERENCE_PRECOMPILE = 0x0000000000000000000000000000000000000802;

    function judgeAll(
        uint256 bountyId,
        bytes calldata llmInput
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage b = bounties[bountyId];
        require(block.timestamp >= b.revealDeadline,        "Reveal phase still active");
        require(!b.judged,                                   "Already judged");
        require(b.revealedParticipants.length > 0,           "No valid revealed submissions");

        // Initiate Ritual AI batch inference — all revealed answers in ONE call
        // In production on Ritual testnet, this triggers an async TEE job.
        // The owner passes llmInput containing all revealed answers packed
        // together so the LLM evaluates them in a single batch request.
        (bool success, bytes memory result) = LLM_INFERENCE_PRECOMPILE.call(llmInput);

        if (success && result.length > 0) {
            // Async result available (sync fallback for testing)
            b.judgingResult = abi.decode(result, (string));
        } else {
            // Async job initiated — owner will call finalizeWinner()
            // once the TEE delivers the result off-chain
            b.judgingResult = string(llmInput);
        }

        b.judged = true;
        emit BountyJudged(bountyId, b.judgingResult);
    }

    function finalizeWinner(
        uint256 bountyId,
        uint256 winnerIndex
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage b = bounties[bountyId];
        require(b.judged,                                             "Judging not complete");
        require(!b.finalized,                                         "Already finalized");
        require(winnerIndex < b.revealedParticipants.length,         "Invalid winner index");

        address winner = b.revealedParticipants[winnerIndex];
        b.winner    = winner;
        b.finalized = true;

        (bool sent, ) = winner.call{value: b.reward}("");
        require(sent, "Reward transfer failed");

        emit WinnerFinalized(bountyId, winner, b.reward);
    }

    // ─────────────────────────────────────────────
    // VIEW / HELPERS
    // ─────────────────────────────────────────────

    function computeCommitment(
        string calldata answer,
        bytes32 salt,
        address sender,
        uint256 bountyId
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(answer, salt, sender, bountyId));
    }

    function getBountyPhase(uint256 bountyId)
        external view bountyExists(bountyId) returns (string memory)
    {
        Bounty storage b = bounties[bountyId];
        if (b.finalized)                              return "FINALIZED";
        if (b.judged)                                 return "JUDGED - AWAITING FINALIZATION";
        if (block.timestamp >= b.revealDeadline)      return "JUDGING PHASE";
        if (block.timestamp >= b.submissionDeadline)  return "REVEAL PHASE";
        return "SUBMISSION PHASE";
    }

    function getRevealedParticipants(uint256 bountyId)
        external view bountyExists(bountyId) returns (address[] memory)
    {
        return bounties[bountyId].revealedParticipants;
    }

    function getParticipants(uint256 bountyId)
        external view bountyExists(bountyId) returns (address[] memory)
    {
        return bounties[bountyId].participants;
    }

    function reclaimIfNoReveals(uint256 bountyId)
        external bountyExists(bountyId) onlyOwner(bountyId)
    {
        Bounty storage b = bounties[bountyId];
        require(block.timestamp >= b.revealDeadline,  "Too early");
        require(!b.finalized,                          "Already finalized");
        require(b.revealedParticipants.length == 0,   "There are valid reveals");

        b.finalized = true;
        (bool sent, ) = b.owner.call{value: b.reward}("");
        require(sent, "Reclaim failed");
    }
}