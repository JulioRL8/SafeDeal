// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "src/SafeDeal.sol";
import "src/Referee.sol";

contract SafeDealFactory {

    // Events
    event DealCreated(
        address indexed deal,
        address indexed referee
    );

    constructor() {}

    function createDeal(
        address seller,
        address client,
        address arbitrator,
        uint256 price,
        uint256 duration) external returns(address) {
        Referee referee = new Referee(arbitrator);

        SafeDeal safeDeal = new SafeDeal(
            seller, 
            client, 
            address(referee), 
            price, 
            duration);

        referee.provideDeal(address(safeDeal));

        emit DealCreated(address(safeDeal), address(referee));

        return address(safeDeal);
    }
}