//SPDX-License-Identifier:Unlicensed

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
contract JVRCoin is ERC20 {
    uint256 private constant INITIAL_SUPPLY = 500000000 ether;
    string private constant NAME = "jvr";
    string private constant SYMBOL = "JVR";

    constructor(address _admin) ERC20(NAME, SYMBOL) {
        _mint(_admin, INITIAL_SUPPLY);
    }
}
