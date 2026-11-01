// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "src/IReferee.sol";

contract SafeDeal {
    address public immutable seller;
    address public immutable client;
    address public immutable referee;

    uint256 price;
    uint256 duration;

    bool finalized = false;
    DealState state = DealState.AwaitingPayment;

    uint256 workDoneDate;
    uint256 startDate;
    uint256 openDisputeDate;

    // Constants
    uint256 constant disputeTime = 3 days;
    uint256 constant refereeTime = 3 days;

    enum DealState {
        AwaitingPayment,
        Funded,
        WorkDone,
        PaidOut,
        Refunded,
        Canceled,
        Disputed,
        DisputeRefunded,
        DisputeRejected
    }

    // Errors
    error SellerAddresNotValid();
    error ClientAddressNotValid();
    error RefereeAddressNotValid();
    error BothAddressAreEquals();
    error DurationNotValid();
    error PriceNotValid();
    error AlreadyPayed();
    error AmountNotCorrect();
    error ClientDidNotPay();
    error DeadLineReached();
    error PaymentFailed();
    error DisputeTimeReached();

    error RetireNotAvailable();
    error ReturnNotAvailable();

    error InvalidState();

    error OnlyAvailableForClient();
    error OnlyAvailableForSeller();
    error OnlyAvailableForReferee();

    // Modifiers
    modifier onlyClient {
        require(msg.sender == client, OnlyAvailableForClient());
        _;
    }

    modifier onlySeller {
        require(msg.sender == seller, OnlyAvailableForSeller());
        _;
    }

    modifier onlyReferee {
        require(msg.sender == referee, OnlyAvailableForReferee());
        _;
    }

    modifier checkReturn {
        if (state == DealState.DisputeRefunded) {
            _;
        } else if (canReturnFunds()) {
            _;
        } else {
            revert ReturnNotAvailable();
        }
    }

    modifier checkRetire {
        if (state  == DealState.DisputeRejected) {
            _;
        } else if (state == DealState.WorkDone && disputeTimePassed()) {
            _;
        } else if (state == DealState.Disputed && refereeResponseNotReceived()) {
            _;
        } else {
            revert RetireNotAvailable();
        }
    }

    // Events
    event ClientPayed(uint256 amount);
    event WorkMarkedAsDone();

    constructor(address seller_,
                address client_,
                address referee_,
                uint256 price_,
                uint256 duration_) {
        require(seller_ != address(0), SellerAddresNotValid());
        require(client_ != address(0), ClientAddressNotValid());
        require(referee_ != address(0), RefereeAddressNotValid());
        require(client_ != seller_, BothAddressAreEquals());
        require(duration_ > 0, DurationNotValid());
        require(price_ > 0, PriceNotValid());

        seller = seller_;
        client = client_;
        referee = referee_;
        price = price_;
        duration = duration_;
        startDate = block.timestamp;
    }

    function pay() external payable onlyClient {
        require(state == DealState.AwaitingPayment, InvalidState());
        require(msg.value == price, AmountNotCorrect());

        startDate = block.timestamp;
        state = DealState.Funded;

        emit ClientPayed(msg.value);
    }

    function workDone() external onlySeller {
        require(state == DealState.Funded, ClientDidNotPay());
        require(block.timestamp < endDate(), DeadLineReached());

        state = DealState.WorkDone;
        workDoneDate = block.timestamp;

        emit WorkMarkedAsDone();
    }

    function retireFunds() external onlySeller checkRetire {
        state = DealState.PaidOut;

        (bool success, ) = msg.sender.call{value: price}("");
        require(success, PaymentFailed());
    }

    function returnFunds() external onlyClient checkReturn {
        state = DealState.Refunded;

        (bool success, ) = msg.sender.call{value: price}("");
        require(success, PaymentFailed());
    }

    function cancelTransaction() external onlyClient {
        require(state == DealState.AwaitingPayment, AlreadyPayed());

        state = DealState.Canceled;
    }

    function openDispute() external onlyClient {
        require(state == DealState.WorkDone, InvalidState());
        require(!disputeTimePassed(), DisputeTimeReached());

        openDisputeDate = block.timestamp;
        state = DealState.Disputed;
        IReferee(referee).disputeOpened();
    }

    function resolveDispute(bool refund) external onlyReferee {
        require(state == DealState.Disputed, InvalidState());
        require(!refereeResponseNotReceived(), DisputeTimeReached());

        state = refund ? DealState.DisputeRefunded : DealState.DisputeRejected;
    }

    // Internal
    function endDate() internal view returns(uint256) {
        return startDate + duration;
    }

    function canReturnFunds() internal view returns(bool) {
        return block.timestamp >= endDate() && state == DealState.Funded;
    }

    function disputeTimePassed() internal view returns(bool) {
        return block.timestamp >= workDoneDate + disputeTime;
    }

    function refereeResponseNotReceived() internal view returns(bool) {
        return block.timestamp > openDisputeDate + refereeTime;
    }
}