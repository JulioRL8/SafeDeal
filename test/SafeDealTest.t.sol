// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "lib/forge-std/src/Test.sol";
import "src/SafeDeal.sol";
import "src/Referee.sol";

// A recipient that can reject ETH or attempt a second withdrawal during payment.
contract DealRecipient {
    bool public rejectPayment;
    bool public reenter;
    bool public reentrySucceeded;
    bool public refund;
    SafeDeal public target;

    function configure(SafeDeal target_, bool reject_, bool reenter_, bool refund_) external {
        target = target_;
        rejectPayment = reject_;
        reenter = reenter_;
        refund = refund_;
    }

    receive() external payable {
        require(!rejectPayment, "Payment rejected");
        if (reenter) {
            (reentrySucceeded,) = address(target)
                .call(refund ? abi.encodeCall(SafeDeal.returnFunds, ()) : abi.encodeCall(SafeDeal.retireFunds, ()));
        }
    }
}

contract SafeDealTest is Test {
    SafeDeal safeDeal;
    Referee referee;
    address seller = vm.addr(1);
    address client = vm.addr(2);
    address arbitrator = vm.addr(8);
    uint256 constant PRICE = 5 wei;
    uint256 constant DURATION = 5 days;
    uint256 constant REVIEW_TIME = 3 days;

    function setUp() public {
        vm.warp(10 days);
        referee = new Referee(arbitrator);
        safeDeal = new SafeDeal(seller, client, address(referee), PRICE, DURATION);
        referee.provideDeal(address(safeDeal));
        vm.deal(client, 100 ether);
    }

    function testConstructorStoresParticipants() public view {
        assertEq(safeDeal.seller(), seller);
        assertEq(safeDeal.client(), client);
        assertEq(safeDeal.referee(), address(referee));
    }

    function testConstructorRejectsZeroSeller() public {
        vm.expectRevert(SafeDeal.SellerAddresNotValid.selector);
        new SafeDeal(address(0), client, address(referee), PRICE, DURATION);
    }

    function testConstructorRejectsZeroClient() public {
        vm.expectRevert(SafeDeal.ClientAddressNotValid.selector);
        new SafeDeal(seller, address(0), address(referee), PRICE, DURATION);
    }

    function testConstructorRejectsZeroReferee() public {
        vm.expectRevert(SafeDeal.RefereeAddressNotValid.selector);
        new SafeDeal(seller, client, address(0), PRICE, DURATION);
    }

    function testConstructorRejectsEqualParticipants() public {
        vm.expectRevert(SafeDeal.BothAddressAreEquals.selector);
        new SafeDeal(client, client, address(referee), PRICE, DURATION);
    }

    function testConstructorRejectsZeroPrice() public {
        vm.expectRevert(SafeDeal.PriceNotValid.selector);
        new SafeDeal(seller, client, address(referee), 0, DURATION);
    }

    function testConstructorRejectsZeroDuration() public {
        vm.expectRevert(SafeDeal.DurationNotValid.selector);
        new SafeDeal(seller, client, address(referee), PRICE, 0);
    }

    function testPayTransfersExactPriceAndEmitsEvent() public {
        uint256 beforeBalance = client.balance;
        vm.expectEmit(false, false, false, true, address(safeDeal));
        emit SafeDeal.ClientPayed(PRICE);
        _pay();
        assertEq(address(safeDeal).balance, PRICE);
        assertEq(client.balance, beforeBalance - PRICE);
    }

    function testPayOnlyClient() public {
        vm.deal(seller, PRICE);
        vm.prank(seller);
        vm.expectRevert(SafeDeal.OnlyAvailableForClient.selector);
        safeDeal.pay{value: PRICE}();
    }

    function testFuzzPayRejectsIncorrectAmount(uint96 amount) public {
        vm.assume(amount != PRICE);
        vm.deal(client, uint256(amount));
        vm.prank(client);
        vm.expectRevert(SafeDeal.AmountNotCorrect.selector);
        safeDeal.pay{value: amount}();
        assertEq(address(safeDeal).balance, 0);
    }

    function testCannotPayTwice() public {
        _pay();
        vm.prank(client);
        vm.expectRevert(SafeDeal.InvalidState.selector);
        safeDeal.pay{value: PRICE}();
    }

    function testDurationStartsAtPaymentRatherThanDeployment() public {
        vm.warp(block.timestamp + DURATION + 1);
        _pay();
        vm.warp(block.timestamp + DURATION - 1);
        _workDone();
    }

    function testCancelPreventsPaymentAndDelivery() public {
        vm.prank(client);
        safeDeal.cancelTransaction();
        vm.prank(client);
        vm.expectRevert(SafeDeal.InvalidState.selector);
        safeDeal.pay{value: PRICE}();
        vm.prank(seller);
        vm.expectRevert(SafeDeal.ClientDidNotPay.selector);
        safeDeal.workDone();
    }

    function testCancelOnlyClient() public {
        vm.expectRevert(SafeDeal.OnlyAvailableForClient.selector);
        safeDeal.cancelTransaction();
    }

    function testCannotCancelAfterPayment() public {
        _pay();
        vm.prank(client);
        vm.expectRevert(SafeDeal.AlreadyPayed.selector);
        safeDeal.cancelTransaction();
    }

    function testWorkDoneEmitsEvent() public {
        _pay();
        vm.expectEmit(false, false, false, true, address(safeDeal));
        emit SafeDeal.WorkMarkedAsDone();
        _workDone();
    }

    function testWorkDoneOnlySeller() public {
        _pay();
        vm.prank(client);
        vm.expectRevert(SafeDeal.OnlyAvailableForSeller.selector);
        safeDeal.workDone();
    }

    function testCannotDeliverBeforePayment() public {
        vm.prank(seller);
        vm.expectRevert(SafeDeal.ClientDidNotPay.selector);
        safeDeal.workDone();
    }

    function testCannotDeliverTwice() public {
        _deliver();
        vm.prank(seller);
        vm.expectRevert(SafeDeal.ClientDidNotPay.selector);
        safeDeal.workDone();
    }

    function testDeadlineAllowsRefundButNotDelivery() public {
        _pay();
        vm.warp(block.timestamp + DURATION);
        vm.prank(seller);
        vm.expectRevert(SafeDeal.DeadLineReached.selector);
        safeDeal.workDone();
        uint256 beforeBalance = client.balance;
        vm.prank(client);
        safeDeal.returnFunds();
        assertEq(client.balance, beforeBalance + PRICE);
        assertEq(address(safeDeal).balance, 0);
        vm.prank(client);
        vm.expectRevert(SafeDeal.ReturnNotAvailable.selector);
        safeDeal.returnFunds();
    }

    function testCannotRefundBeforeDeadlineOrWithoutPayment() public {
        vm.prank(client);
        vm.expectRevert(SafeDeal.ReturnNotAvailable.selector);
        safeDeal.returnFunds();
        _pay();
        vm.warp(block.timestamp + DURATION - 1);
        vm.prank(client);
        vm.expectRevert(SafeDeal.ReturnNotAvailable.selector);
        safeDeal.returnFunds();
    }

    function testReturnFundsOnlyClient() public {
        vm.expectRevert(SafeDeal.OnlyAvailableForClient.selector);
        safeDeal.returnFunds();
    }

    function testDeliveryPreventsOrdinaryRefundEvenAfterWorkDeadline() public {
        _deliver();
        vm.warp(block.timestamp + DURATION);
        vm.prank(client);
        vm.expectRevert(SafeDeal.ReturnNotAvailable.selector);
        safeDeal.returnFunds();
    }

    function testCannotWithdrawBeforeDelivery() public {
        _pay();
        vm.prank(seller);
        vm.expectRevert(SafeDeal.RetireNotAvailable.selector);
        safeDeal.retireFunds();
    }

    function testRetireFundsOnlySeller() public {
        vm.expectRevert(SafeDeal.OnlyAvailableForSeller.selector);
        safeDeal.retireFunds();
    }

    function testReviewDeadlineAllowsWithdrawalButNotDispute() public {
        _deliver();
        uint256 deliveredAt = block.timestamp;
        vm.warp(deliveredAt + REVIEW_TIME - 1);
        vm.prank(seller);
        vm.expectRevert(SafeDeal.RetireNotAvailable.selector);
        safeDeal.retireFunds();
        vm.warp(deliveredAt + REVIEW_TIME);
        vm.prank(client);
        vm.expectRevert(SafeDeal.DisputeTimeReached.selector);
        safeDeal.openDispute();
        uint256 beforeBalance = seller.balance;
        vm.prank(seller);
        safeDeal.retireFunds();
        assertEq(seller.balance, beforeBalance + PRICE);
        assertEq(address(safeDeal).balance, 0);
        vm.prank(seller);
        vm.expectRevert(SafeDeal.RetireNotAvailable.selector);
        safeDeal.retireFunds();
    }

    function testOpenDisputeNotifiesRefereeAndBlocksBothWithdrawals() public {
        _deliver();
        vm.expectCall(address(referee), abi.encodeCall(IReferee.disputeOpened, ()));
        vm.expectEmit(true, false, false, true, address(referee));
        emit Referee.DisputeOpened(address(safeDeal));
        _openDispute();
        vm.prank(seller);
        vm.expectRevert(SafeDeal.RetireNotAvailable.selector);
        safeDeal.retireFunds();
        vm.prank(client);
        vm.expectRevert(SafeDeal.ReturnNotAvailable.selector);
        safeDeal.returnFunds();
        vm.prank(client);
        vm.expectRevert(SafeDeal.InvalidState.selector);
        safeDeal.openDispute();
    }

    function testOpenDisputeOnlyClient() public {
        _deliver();
        vm.expectRevert(SafeDeal.OnlyAvailableForClient.selector);
        safeDeal.openDispute();
    }

    function testCannotDisputeBeforeDelivery() public {
        _pay();
        vm.prank(client);
        vm.expectRevert(SafeDeal.InvalidState.selector);
        safeDeal.openDispute();
    }

    function testResolveDisputeOnlyRefereeEvenForArbitrator() public {
        _dispute();
        vm.prank(arbitrator);
        vm.expectRevert(SafeDeal.OnlyAvailableForReferee.selector);
        safeDeal.resolveDispute(true);
        vm.prank(client);
        vm.expectRevert(Referee.NotTheArbitrator.selector);
        referee.resolveDispute(true);
    }

    function testCannotResolveWithoutDispute() public {
        vm.prank(arbitrator);
        vm.expectRevert(SafeDeal.InvalidState.selector);
        referee.resolveDispute(true);
    }

    function testArbitratorRefundAllowsOnlyClientToCollectOnce() public {
        _dispute();
        _resolve(true);
        vm.prank(seller);
        vm.expectRevert(SafeDeal.RetireNotAvailable.selector);
        safeDeal.retireFunds();
        uint256 beforeBalance = client.balance;
        vm.prank(client);
        safeDeal.returnFunds();
        assertEq(client.balance, beforeBalance + PRICE);
        assertEq(address(safeDeal).balance, 0);
        vm.prank(client);
        vm.expectRevert(SafeDeal.ReturnNotAvailable.selector);
        safeDeal.returnFunds();
        vm.prank(arbitrator);
        vm.expectRevert(SafeDeal.InvalidState.selector);
        referee.resolveDispute(false);
    }

    function testRejectedDisputeAllowsImmediateSellerWithdrawal() public {
        _dispute();
        _resolve(false);
        vm.prank(client);
        vm.expectRevert(SafeDeal.ReturnNotAvailable.selector);
        safeDeal.returnFunds();
        vm.prank(seller);
        safeDeal.retireFunds();
        assertEq(seller.balance, PRICE);
        assertEq(address(safeDeal).balance, 0);
    }

    function testRefereeWindowStartsAtDisputeRatherThanDelivery() public {
        _deliver();
        vm.warp(block.timestamp + REVIEW_TIME - 1);
        _openDispute();
        vm.warp(block.timestamp + REVIEW_TIME - 1);
        _resolve(true);
        vm.prank(client);
        safeDeal.returnFunds();
        assertEq(address(safeDeal).balance, 0);
    }

    // Current policy includes the exact referee deadline in the resolution window.
    function testRefereeCanResolveExactlyAtDeadline() public {
        _dispute();
        vm.warp(block.timestamp + REVIEW_TIME);
        vm.prank(seller);
        vm.expectRevert(SafeDeal.RetireNotAvailable.selector);
        safeDeal.retireFunds();
        _resolve(false);
    }

    function testAfterRefereeDeadlineOnlySellerCanCollect() public {
        _dispute();
        vm.warp(block.timestamp + REVIEW_TIME + 1);
        vm.prank(arbitrator);
        vm.expectRevert(SafeDeal.DisputeTimeReached.selector);
        referee.resolveDispute(true);
        vm.prank(client);
        vm.expectRevert(SafeDeal.ReturnNotAvailable.selector);
        safeDeal.returnFunds();
        vm.prank(seller);
        safeDeal.retireFunds();
        assertEq(seller.balance, PRICE);
        vm.prank(arbitrator);
        vm.expectRevert(SafeDeal.InvalidState.selector);
        referee.resolveDispute(true);
    }

    function testNotificationFailureRollsBackDispute() public {
        _deliver();
        vm.mockCallRevert(address(referee), abi.encodeCall(IReferee.disputeOpened, ()), "Notification failed");
        vm.prank(client);
        vm.expectRevert(bytes("Notification failed"));
        safeDeal.openDispute();
        vm.clearMockedCalls();
        _openDispute();
        _resolve(false);
    }

    function testSellerPaymentFailureCanBeRetried() public {
        DealRecipient recipient = new DealRecipient();
        SafeDeal other = new SafeDeal(address(recipient), client, address(referee), PRICE, DURATION);
        recipient.configure(other, true, false, false);
        vm.prank(client);
        other.pay{value: PRICE}();
        vm.prank(address(recipient));
        other.workDone();
        vm.warp(block.timestamp + REVIEW_TIME);
        vm.prank(address(recipient));
        vm.expectRevert(SafeDeal.PaymentFailed.selector);
        other.retireFunds();
        assertEq(address(other).balance, PRICE);
        recipient.configure(other, false, false, false);
        vm.prank(address(recipient));
        other.retireFunds();
        assertEq(address(recipient).balance, PRICE);
        assertEq(address(other).balance, 0);
    }

    function testClientRefundFailureCanBeRetried() public {
        DealRecipient recipient = new DealRecipient();
        SafeDeal other = new SafeDeal(seller, address(recipient), address(referee), PRICE, DURATION);
        recipient.configure(other, true, false, true);
        vm.deal(address(recipient), PRICE);
        vm.prank(address(recipient));
        other.pay{value: PRICE}();
        vm.warp(block.timestamp + DURATION);
        vm.prank(address(recipient));
        vm.expectRevert(SafeDeal.PaymentFailed.selector);
        other.returnFunds();
        assertEq(address(other).balance, PRICE);
        recipient.configure(other, false, false, true);
        vm.prank(address(recipient));
        other.returnFunds();
        assertEq(address(recipient).balance, PRICE);
        assertEq(address(other).balance, 0);
    }

    function testSellerCannotReenterWithdrawal() public {
        DealRecipient recipient = new DealRecipient();
        SafeDeal other = new SafeDeal(address(recipient), client, address(referee), PRICE, DURATION);
        recipient.configure(other, false, true, false);
        vm.prank(client);
        other.pay{value: PRICE}();
        vm.prank(address(recipient));
        other.workDone();
        vm.warp(block.timestamp + REVIEW_TIME);
        vm.prank(address(recipient));
        other.retireFunds();
        assertFalse(recipient.reentrySucceeded());
        assertEq(address(recipient).balance, PRICE);
        assertEq(address(other).balance, 0);
    }

    function testClientCannotReenterRefund() public {
        DealRecipient recipient = new DealRecipient();
        SafeDeal other = new SafeDeal(seller, address(recipient), address(referee), PRICE, DURATION);
        recipient.configure(other, false, true, true);
        vm.deal(address(recipient), PRICE);
        vm.prank(address(recipient));
        other.pay{value: PRICE}();
        vm.warp(block.timestamp + DURATION);
        vm.prank(address(recipient));
        other.returnFunds();
        assertFalse(recipient.reentrySucceeded());
        assertEq(address(recipient).balance, PRICE);
        assertEq(address(other).balance, 0);
    }

    function _pay() internal {
        vm.prank(client);
        safeDeal.pay{value: PRICE}();
    }

    function _workDone() internal {
        vm.prank(seller);
        safeDeal.workDone();
    }

    function _deliver() internal {
        _pay();
        _workDone();
    }

    function _openDispute() internal {
        vm.prank(client);
        safeDeal.openDispute();
    }

    function _dispute() internal {
        _deliver();
        _openDispute();
    }

    function _resolve(bool refund) internal {
        vm.prank(arbitrator);
        referee.resolveDispute(refund);
    }
}
