pragma solidity ^0.4.13;

import 'ROOT/reporting/IMarket.sol';
import 'ROOT/trading/Trading.sol';


contract IOrders {
    function removeOrder(bytes32 _orderId, Trading.TradeTypes _type, IMarket _market, uint8 _outcome) public returns (bool);
    function getOrders(bytes32 _orderId) public constant returns (uint256 _amount, int256 _price, address _owner, uint256 _sharesEscrowed, uint256 _tokensEscrowed, bytes32 _betterOrderId, bytes32 _worseOrderId);
    function getMarket(bytes32 _orderId) public constant returns (IMarket);
    function getTradeType(bytes32 _orderId) public constant returns (Trading.TradeTypes);
    function getOutcome(bytes32 _orderId) public constant returns (uint8);
    function getAmount(bytes32 _orderId) public constant returns (uint256);
    function getPrice(bytes32 _orderId) public constant returns (int256);
    function getOrderOwner(bytes32 _orderId) public constant returns (address);
    function getOrderSharesEscrowed(bytes32 _orderId) public constant returns (uint256);
    function getOrderMoneyEscrowed(bytes32 _orderId) public constant returns (uint256);
    function getBetterOrderId(bytes32 _orderId) public constant returns (bytes32);
    function getWorseOrderId(bytes32 _orderId) public constant returns (bytes32);
    function getBestOrderId(Trading.TradeTypes _type, IMarket _market, uint8 _outcome) public constant returns (bytes32);
    function getWorstOrderId(Trading.TradeTypes _type, IMarket _market, uint8 _outcome) public constant returns (bytes32);
    function isBetterPrice(Trading.TradeTypes _type, int256 _fxpPrice, bytes32 _orderId) public constant returns (bool);
    function isWorsePrice(Trading.TradeTypes _type, int256 _fxpPrice, bytes32 _orderId) public constant returns (bool);
    function assertIsNotBetterPrice(Trading.TradeTypes _type, int256 _fxpPrice, bytes32 _betterOrderId) public constant returns (bool);
    function assertIsNotWorsePrice(Trading.TradeTypes _type, int256 _fxpPrice, bytes32 _worseOrderId) public returns (bool);
    function fillOrder(bytes32 _orderId, Trading.TradeTypes _orderType, IMarket _market, uint8 _orderOutcome, uint256 _sharesFilled, uint256 _tokensFilled) public returns (bool);
    function buyCompleteSetsLog(address _sender, IMarket _market, uint256 _fxpAmount, uint256 _numOutcomes) public constant returns (bool);
    function sellCompleteSetsLog(address _sender, IMarket _market, uint256 _fxpAmount, uint256 _numOutcomes, uint256 _marketCreatorFee, uint256 _reportingFee) public constant returns (bool);
    function cancelOrderLog(IMarket _market, address _sender, int256 _fxpPrice, uint256 _fxpAmount, bytes32 _orderId, uint8 _outcome, Trading.TradeTypes _type, uint256 _fxpMoneyEscrowed, uint256 _fxpSharesEscrowed) public constant returns (bool);
    function takeOrderLog(IMarket _market, uint8 _orderOutcome, Trading.TradeTypes _orderType, bytes32 _orderId, address _taker, uint256 _makerSharesFilled, uint256 _makerTokensFilled, uint256 _takerSharesFilled, uint256 _takerTokensFilled, uint256 _tradeGroupId) public constant returns (bool);
}
