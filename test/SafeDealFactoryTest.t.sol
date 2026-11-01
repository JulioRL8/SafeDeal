// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "lib/forge-std/src/Test.sol";
import "src/SafeDealFactory.sol";

contract SafeDealFactoryTest is Test {
    SafeDealFactory factory;

    function setUp() public {
        factory = new SafeDealFactory();
    }

    // createDeal

    function testCreateDeal() public {
        address dealAddress = factory.createDeal(
            vm.addr(1), 
            vm.addr(2), 
            vm.addr(3), 
            5, 
            5 days);
            assertNotEq(dealAddress, address(0));
    }
}