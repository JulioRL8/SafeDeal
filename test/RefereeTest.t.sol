// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import "lib/forge-std/src/Test.sol";
import "src/Referee.sol";
import "src/SafeDeal.sol";

contract RefereeTest is Test {
    Referee referee;
    SafeDeal safeDeal;
    address arbitrator = vm.addr(2);
    address factory;

    function setUp() public {
        factory = address(this);
        referee = new Referee(arbitrator);
        safeDeal = new SafeDeal(vm.addr(1), vm.addr(2), address(referee), 5, 5);
    }

    // Constructor

    function testNoArbitratorConstructorError() public {
        vm.expectRevert(Referee.ArbitratorAddressNotValid.selector);
        referee = new Referee(address(0));
    }

    // Provide Deal

    function testProvideDealErrorDueToNotFactory() public {
        vm.startPrank(arbitrator);

        vm.expectRevert(Referee.NotTheFactory.selector);
        referee.provideDeal(address(safeDeal));

        vm.stopPrank();
    }

    function testProvideDealErrorDueToDealWithNoSameReferee() public {
        vm.startPrank(factory);

        safeDeal = new SafeDeal(vm.addr(1), vm.addr(2), vm.addr(3), 5, 5);
        vm.expectRevert(Referee.DealRefereeIsNotMe.selector);
        referee.provideDeal(address(safeDeal));

        vm.stopPrank();
    }

    function testProvideDeal() public {
        injectDeal();
        assertEq(referee.deal(), address(safeDeal));
    }

    // disputeOpened
    function testDisputeOpenedFailedDueToNotDeal() public {
        injectDeal();
        vm.expectRevert(Referee.NotTheDeal.selector);
        referee.disputeOpened();
    }

    function testDisputeOpened() public {
        injectDeal();
        vm.startPrank(address(safeDeal));

        vm.expectEmit(true, false, false, true, address(referee));
        emit Referee.DisputeOpened(address(safeDeal));

        referee.disputeOpened();
        vm.stopPrank();
    }

    // Helpers
    function injectDeal() internal {
        referee.provideDeal(address(safeDeal));
    }
}