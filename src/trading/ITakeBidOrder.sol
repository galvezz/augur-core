pragma solidity ^0.4.13;

import 'ROOT/reporting/IMarket.sol';


contract ITakeBidOrder {
    function takeBidOrder(address _taker, bytes32 _orderId, IMarket _market, uint8 _outcome, uint256 _amountTakerWants, uint256 _tradeGroupID) external returns (uint256 _unfilledAmount);
}
