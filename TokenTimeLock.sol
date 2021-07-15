// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libs/BEP20.sol";

contract TokenTimeLock {
    using SafeMath for uint256;

    address public owner = msg.sender;
    address public receiver;

    uint256 public releaseTime;

    IBEP20 token;

    constructor(
        address _teamAddress,
        IBEP20 _token,
        uint256 lockDays
    ) public {
        receiver = _teamAddress;
        token = _token;
        releaseTime = now.add(lockDays * 1 days);
    }

    modifier onlyReceiver() {
        require(
            msg.sender == receiver,
            "This function is restricted to the contract's receiver"
        );
        _;
    }

    function canRelease() public returns (bool) {
        return now >= releaseTime;
    }

    function releaseToken() public onlyReceiver {
        require(canRelease() == true, "Cannot release until releaseTime");

        IBEP20(token).transfer(
            receiver,
            IBEP20(token).balanceOf(address(this))
        );
    }
}
