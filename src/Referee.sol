// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import "src/SafeDeal.sol";

contract Referee is IReferee {
    address public immutable factory;
    address public immutable arbitrator;
    address public deal;

    // Error
    error NotTheFactory();
    error NotTheDeal();
    error NotTheArbitrator();
    error DealAlreadyProvided();
    error DealAddressNotValid();
    error DealNotProvided();
    error DealRefereeIsNotMe();
    error ArbitratorAddressNotValid();

    // Events
    event DisputeOpened(address indexed deal);

    modifier onlyDeal {
        require(deal != address(0), DealNotProvided());
        require(msg.sender == deal, NotTheDeal());
        _;
    }

    modifier onlyFactory {
        require(msg.sender == factory, NotTheFactory());
        _;
    }

    modifier onlyArbitrator {
        require(msg.sender == arbitrator, NotTheArbitrator());
        _;
    }

    constructor(address arbitrator_) {
        require(arbitrator_ != address(0), ArbitratorAddressNotValid());
        arbitrator = arbitrator_;
        factory = msg.sender;
    }

    function provideDeal(address deal_) external onlyFactory {
        require(deal == address(0), DealAlreadyProvided());
        require(deal_ != address(0), DealAddressNotValid());
        require(SafeDeal(deal_).referee() == address(this), DealRefereeIsNotMe());

        deal = deal_;
    }

    function disputeOpened() external onlyDeal {
        emit DisputeOpened(msg.sender);
    }

    function resolveDispute(bool refund) external onlyArbitrator {
        SafeDeal(deal).resolveDispute(refund);
    }
}