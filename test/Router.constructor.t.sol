// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {GridExRouter} from "../src/GridExRouter.sol";
import {AdminFacet} from "../src/facets/AdminFacet.sol";
import {IProtocolErrors} from "../src/interfaces/IProtocolErrors.sol";

contract RouterConstructorTest is Test {
    function test_revertWhenOwnerIsZero() public {
        AdminFacet adminFacet = new AdminFacet();
        vm.expectRevert(IProtocolErrors.InvalidAddress.selector);
        new GridExRouter(address(0), address(0x1234), address(adminFacet));
    }

    function test_revertWhenVaultIsZero() public {
        AdminFacet adminFacet = new AdminFacet();
        vm.expectRevert(IProtocolErrors.InvalidAddress.selector);
        new GridExRouter(address(this), address(0), address(adminFacet));
    }

    function test_revertWhenAdminFacetIsZero() public {
        vm.expectRevert(IProtocolErrors.InvalidAddress.selector);
        new GridExRouter(address(this), address(0x1234), address(0));
    }
}
