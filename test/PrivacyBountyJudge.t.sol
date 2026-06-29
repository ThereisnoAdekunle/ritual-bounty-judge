// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PrivacyBountyJudge.sol";

contract PrivacyBountyJudgeTest is Test {

    PrivacyBountyJudge public judge;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob   = makeAddr("bob");
    address carol = makeAddr("carol");

    address constant PRECOMPILE = 0x0000000000000000000000000000000000000065;

    uint256 constant REWARD    = 1 ether;
    uint256 constant ONE_HOUR  = 3600;
    uint256 constant TWO_HOURS = 7200;

    uint256 submissionDeadline;
    uint256 revealDeadline;

    function setUp() public {
        judge = new PrivacyBountyJudge();

        vm.deal(owner, 10 ether);
        vm.deal(alice, 1 ether);
        vm.deal(bob,   1 ether);
        vm.deal(carol, 1 ether);

        submissionDeadline = block.timestamp + ONE_HOUR;
        revealDeadline     = block.timestamp + TWO_HOURS;

        vm.prank(owner);
        judge.createBounty{value: REWARD}(
            "What is the best use case for Ritual AI?",
            submissionDeadline,
            revealDeadline
        );
    }

    function makeCommitment(
        address participant,
        string memory answer,
        bytes32 salt,
        uint256 bountyId
    ) internal view returns (bytes32) {
        return judge.computeCommitment(answer, salt, participant, bountyId);
    }

    // Mock Ritual AI precompile to return a valid response
    function mockRitualAI(string memory response) internal {
        vm.mockCall(
            PRECOMPILE,
            bytes(""),
            abi.encode(response)
        );
    }
    // ─── createBounty ───────────────────────────────────────────

    function test_CreateBounty_Success() public view {
        (
            address _owner,
            ,
            uint256 _reward,
            ,
            ,
            bool _judged,
            bool _finalized,
            address _winner,
        ) = judge.bounties(0);

        assertEq(_owner,     owner);
        assertEq(_reward,    REWARD);
        assertEq(_judged,    false);
        assertEq(_finalized, false);
        assertEq(_winner,    address(0));
    }

    function test_CreateBounty_RevertIfRewardZero() public {
        vm.prank(owner);
        vm.expectRevert("Reward must be > 0");
        judge.createBounty{value: 0}(
            "Test",
            block.timestamp + 100,
            block.timestamp + 200
        );
    }

    function test_CreateBounty_RevertIfSubDeadlineInPast() public {
        vm.prank(owner);
        vm.expectRevert("Submission deadline must be in future");
        judge.createBounty{value: 1 ether}(
            "Test",
            block.timestamp - 1,
            block.timestamp + 200
        );
    }

    function test_CreateBounty_RevertIfRevealBeforeSub() public {
        vm.prank(owner);
        vm.expectRevert("Reveal deadline must be after submission deadline");
        judge.createBounty{value: 1 ether}(
            "Test",
            block.timestamp + 200,
            block.timestamp + 100
        );
    }

    // ─── submitCommitment ────────────────────────────────────────

    function test_SubmitCommitment_Success() public {
        bytes32 salt       = keccak256("alicesalt");
        bytes32 commitment = makeCommitment(alice, "My answer", salt, 0);

        vm.prank(alice);
        judge.submitCommitment(0, commitment);

        (bytes32 _comm, , bool _hasCommitted, bool _hasRevealed) =
            judge.submissions(0, alice);

        assertEq(_comm,         commitment);
        assertEq(_hasCommitted, true);
        assertEq(_hasRevealed,  false);
    }

    function test_SubmitCommitment_RevertIfPhaseEnded() public {
        vm.warp(submissionDeadline + 1);

        bytes32 salt       = keccak256("alicesalt");
        bytes32 commitment = makeCommitment(alice, "My answer", salt, 0);

        vm.prank(alice);
        vm.expectRevert("Submission phase has ended");
        judge.submitCommitment(0, commitment);
    }

    function test_SubmitCommitment_RevertIfDoubleCommit() public {
        bytes32 salt       = keccak256("alicesalt");
        bytes32 commitment = makeCommitment(alice, "My answer", salt, 0);

        vm.prank(alice);
        judge.submitCommitment(0, commitment);

        vm.prank(alice);
        vm.expectRevert("Already committed");
        judge.submitCommitment(0, commitment);
    }

    function test_SubmitCommitment_RevertIfZeroCommitment() public {
        vm.prank(alice);
        vm.expectRevert("Invalid commitment");
        judge.submitCommitment(0, bytes32(0));
    }

    // ─── revealAnswer ────────────────────────────────────────────

    function test_RevealAnswer_Success() public {
        bytes32 salt         = keccak256("alicesalt");
        string memory answer = "On-chain AI privacy via TEE";
        bytes32 commitment   = makeCommitment(alice, answer, salt, 0);

        vm.prank(alice);
        judge.submitCommitment(0, commitment);

        vm.warp(submissionDeadline + 1);

        vm.prank(alice);
        judge.revealAnswer(0, answer, salt);

        (, string memory _revealed, , bool _hasRevealed) =
            judge.submissions(0, alice);

        assertEq(_hasRevealed, true);
        assertEq(_revealed,    answer);
    }

    function test_RevealAnswer_RevertIfWrongAnswer() public {
        bytes32 salt       = keccak256("alicesalt");
        bytes32 commitment = makeCommitment(alice, "Real answer", salt, 0);

        vm.prank(alice);
        judge.submitCommitment(0, commitment);

        vm.warp(submissionDeadline + 1);

        vm.prank(alice);
        vm.expectRevert("Commitment mismatch: invalid answer or salt");
        judge.revealAnswer(0, "WRONG answer", salt);
    }

    function test_RevealAnswer_RevertIfWrongSalt() public {
        bytes32 salt       = keccak256("correctsalt");
        bytes32 wrongSalt  = keccak256("wrongsalt");
        bytes32 commitment = makeCommitment(alice, "My answer", salt, 0);

        vm.prank(alice);
        judge.submitCommitment(0, commitment);

        vm.warp(submissionDeadline + 1);

        vm.prank(alice);
        vm.expectRevert("Commitment mismatch: invalid answer or salt");
        judge.revealAnswer(0, "My answer", wrongSalt);
    }

    function test_RevealAnswer_RevertIfBeforeSubDeadline() public {
        bytes32 salt       = keccak256("alicesalt");
        bytes32 commitment = makeCommitment(alice, "Answer", salt, 0);

        vm.prank(alice);
        judge.submitCommitment(0, commitment);

        vm.prank(alice);
        vm.expectRevert("Submission phase still active");
        judge.revealAnswer(0, "Answer", salt);
    }

    function test_RevealAnswer_RevertIfAfterRevealDeadline() public {
        bytes32 salt       = keccak256("alicesalt");
        bytes32 commitment = makeCommitment(alice, "Answer", salt, 0);

        vm.prank(alice);
        judge.submitCommitment(0, commitment);

        vm.warp(revealDeadline + 1);

        vm.prank(alice);
        vm.expectRevert("Reveal phase has ended");
        judge.revealAnswer(0, "Answer", salt);
    }

    function test_RevealAnswer_CopyAttackFails() public {
        bytes32 salt            = keccak256("alicesalt");
        string memory answer    = "Original answer";
        bytes32 aliceCommitment = makeCommitment(alice, answer, salt, 0);

        vm.prank(alice);
        judge.submitCommitment(0, aliceCommitment);

        vm.prank(bob);
        judge.submitCommitment(0, aliceCommitment);

        vm.warp(submissionDeadline + 1);

        vm.prank(bob);
        vm.expectRevert("Commitment mismatch: invalid answer or salt");
        judge.revealAnswer(0, answer, salt);
    }

    // ─── judgeAll ────────────────────────────────────────────────

    function test_JudgeAll_Success() public {
        bytes32 salt         = keccak256("alicesalt");
        string memory answer = "Ritual enables private AI inference";
        bytes32 commitment   = makeCommitment(alice, answer, salt, 0);

        vm.prank(alice);
        judge.submitCommitment(0, commitment);

        vm.warp(submissionDeadline + 1);

        vm.prank(alice);
        judge.revealAnswer(0, answer, salt);

        vm.warp(revealDeadline + 1);

        mockRitualAI('{"winnerIndex":0,"summary":"Alice wins"}');

        vm.prank(owner);
        judge.judgeAll(0, bytes('{"winnerIndex":0,"summary":"Alice wins"}'));

        (, , , , , bool _judged, , ,) = judge.bounties(0);
        assertEq(_judged, true);
    }

    function test_JudgeAll_RevertIfBeforeRevealDeadline() public {
        vm.prank(owner);
        vm.expectRevert("Reveal phase still active");
        judge.judgeAll(0, bytes("input"));
    }

    function test_JudgeAll_RevertIfNotOwner() public {
        vm.warp(revealDeadline + 1);

        vm.prank(alice);
        vm.expectRevert("Not bounty owner");
        judge.judgeAll(0, bytes("input"));
    }

    function test_JudgeAll_RevertIfNoReveals() public {
        vm.warp(revealDeadline + 1);

        vm.prank(owner);
        vm.expectRevert("No valid revealed submissions");
        judge.judgeAll(0, bytes("input"));
    }

    // ─── finalizeWinner ──────────────────────────────────────────

    function test_FullHappyPath() public {
        bytes32 salt         = keccak256("alicesalt");
        string memory answer = "Ritual enables private AI inference";
        bytes32 commitment   = makeCommitment(alice, answer, salt, 0);

        vm.prank(alice);
        judge.submitCommitment(0, commitment);

        vm.warp(submissionDeadline + 1);

        vm.prank(alice);
        judge.revealAnswer(0, answer, salt);

        vm.warp(revealDeadline + 1);

        mockRitualAI('{"winnerIndex":0}');

        vm.prank(owner);
        judge.judgeAll(0, bytes('{"winnerIndex":0}'));

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(owner);
        judge.finalizeWinner(0, 0);

        uint256 aliceBalanceAfter = alice.balance;
        assertGt(aliceBalanceAfter, aliceBalanceBefore);

        (, , , , , , bool _finalized, address _winner,) = judge.bounties(0);
        assertEq(_finalized, true);
        assertEq(_winner,    alice);
    }

    function test_FinalizeWinner_RevertIfNotJudged() public {
        vm.prank(owner);
        vm.expectRevert("Judging not complete");
        judge.finalizeWinner(0, 0);
    }

    function test_FinalizeWinner_RevertIfAlreadyFinalized() public {
        bytes32 salt         = keccak256("alicesalt");
        string memory answer = "Answer";
        bytes32 commitment   = makeCommitment(alice, answer, salt, 0);

        vm.prank(alice);
        judge.submitCommitment(0, commitment);

        vm.warp(submissionDeadline + 1);

        vm.prank(alice);
        judge.revealAnswer(0, answer, salt);

        vm.warp(revealDeadline + 1);

        mockRitualAI("Alice wins");

        vm.prank(owner);
        judge.judgeAll(0, bytes("result"));

        vm.prank(owner);
        judge.finalizeWinner(0, 0);

        vm.prank(owner);
        vm.expectRevert("Already finalized");
        judge.finalizeWinner(0, 0);
    }

    function test_FinalizeWinner_RevertIfInvalidIndex() public {
        bytes32 salt         = keccak256("alicesalt");
        string memory answer = "Answer";
        bytes32 commitment   = makeCommitment(alice, answer, salt, 0);

        vm.prank(alice);
        judge.submitCommitment(0, commitment);

        vm.warp(submissionDeadline + 1);

        vm.prank(alice);
        judge.revealAnswer(0, answer, salt);

        vm.warp(revealDeadline + 1);

        mockRitualAI("Alice wins");

        vm.prank(owner);
        judge.judgeAll(0, bytes("result"));

        vm.prank(owner);
        vm.expectRevert("Invalid winner index");
        judge.finalizeWinner(0, 99);
    }

    // ─── getBountyPhase ──────────────────────────────────────────

    function test_Phase_Submission() public view {
        assertEq(judge.getBountyPhase(0), "SUBMISSION PHASE");
    }

    function test_Phase_Reveal() public {
        vm.warp(submissionDeadline + 1);
        assertEq(judge.getBountyPhase(0), "REVEAL PHASE");
    }

    function test_Phase_Judging() public {
        vm.warp(revealDeadline + 1);
        assertEq(judge.getBountyPhase(0), "JUDGING PHASE");
    }
}