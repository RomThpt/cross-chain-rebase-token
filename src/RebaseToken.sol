// SDPX-Licence-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract RebaseToken is ERC20 {
    constructor() ERC20("RebaseToken", "RBT") {}
}
