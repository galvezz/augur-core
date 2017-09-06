pragma solidity ^0.4.13;

import 'ROOT/trading/ITakeBidOrder.sol';
import 'ROOT/Controlled.sol';
import 'ROOT/libraries/math/SafeMathUint256.sol';
import 'ROOT/libraries/math/SafeMathInt256.sol';
import 'ROOT/reporting/IMarket.sol';
import 'ROOT/trading/ICash.sol';
import 'ROOT/trading/ICompleteSets.sol';
import 'ROOT/trading/IOrders.sol';
import 'ROOT/trading/IShareToken.sol';
import 'ROOT/trading/Trading.sol';


library Trader {
    using SafeMathUint256 for uint256;

    enum Direction {
        Buying,
        Selling
    }

    struct Data {
        // contracts
        IOrders orders;
        IMarket market;
        ICompleteSets completeSets;
        ICash denominationToken;
        IShareToken longShareToken;
        IShareToken[] shortShareTokens;

        // order
        bytes32 orderId;
        address maker;
        address taker;
        uint8 outcome;
        uint256 sharePriceRange;
        uint256 sharePriceLong;
        uint256 sharePriceShort;
        uint256 originalSharesEscrowed;
        uint256 originalTokensEscrowed;

        // maker
        Direction makerDirection;
        uint256 makerSize;
        uint256 makerSharesAvailable;
        uint256 makerTokensAvailable;

        // taker
        Direction takerDirection;
        uint256 takerSize;
        uint256 takerSharesAvailable;
        uint256 takerTokensAvailable;
    }

    //
    // Constructor
    //

    function create(IController _controller, bytes32 _orderId, address _taker, uint256 _takerSize) internal returns (Data) {
        Data memory data;
        data.orderId = _orderId;
        data.orders = IOrders(_controller.lookup("Orders"));
        data.completeSets = ICompleteSets(_controller.lookup("CompleteSets"));
        data.market = data.orders.getMarket(data.orderId);
        data.denominationToken = data.market.getDenominationToken();
        data.outcome = data.orders.getOutcome(data.orderId);
        data.longShareToken = data.market.getShareToken(data.outcome);
        data.shortShareTokens = getShortShareTokens(data.market, data.outcome);
        data.maker = data.orders.getOrderOwner(data.orderId);
        data.taker = _taker;
        (data.sharePriceRange, data.sharePriceLong, data.sharePriceShort) = getSharePriceDetails(data.market, data.orders, data.orderId);
        data.originalSharesEscrowed = data.orders.getOrderSharesEscrowed(data.orderId);
        data.originalTokensEscrowed = data.orders.getOrderMoneyEscrowed(data.orderId);
        data.makerDirection = getMakerDirection(data.orders, data.orderId);
        data.makerSize = data.orders.getAmount(data.orderId);
        data.makerSharesAvailable = data.originalSharesEscrowed;
        data.makerTokensAvailable = data.originalTokensEscrowed;
        data.takerDirection = getTakerDirection(data.makerDirection);
        data.takerSize = _takerSize;
        data.takerSharesAvailable = getTakerSharesAvailable(data.longShareToken, data.shortShareTokens, data.taker, data.takerDirection, data.takerSize);
        data.takerTokensAvailable = getTakerTokensAvailable(data.takerDirection, data.sharePriceLong, data.sharePriceShort, data.sharePriceRange, data.takerSize, data.takerSharesAvailable);
    }

    //
    // "public" functions
    //

    function tradeMakerSharesForTakerShares(Data _data) internal returns (bool) {
        if (_data.makerSharesAvailable == 0 || _data.takerSharesAvailable == 0) {
            return true;
        }
        // TODO: transfer shares to this contract
        // TODO: sell complete sets
        // TODO: distribute payout proportionately (fees will have been deducted)
        // TODO: update available shares for maker and taker
    }

    function tradeMakerSharesForTakerTokens(Data _data) internal returns (bool) {
        // TODO: implement
    }

    function tradeMakerTokensForTakerShares(Data _data) internal returns (bool) {
        // TODO: implement
    }

    function tradeMakerTokensForTakerTokens(Data _data) internal returns (bool) {
        // TODO: implement
    }

    //
    // Construction helpers
    //

    function getShortShareTokens(IMarket _market, uint8 _longOutcome) private constant returns (IShareToken[]) {
        IShareToken[] memory _shortShareTokens = new IShareToken[](_market.getNumberOfOutcomes() - 1);
        for (uint8 _outcome = 0; _outcome < _shortShareTokens.length; ++_outcome) {
            if (_outcome == _longOutcome) {
                continue;
            }
            _shortShareTokens[_outcome] = _market.getShareToken(_outcome);
        }
    }

    function getSharePriceDetails(IMarket _market, IOrders _orders, bytes32 _orderId) private constant returns (uint256 _sharePriceRange, uint256 _sharePriceLong, uint256 _sharePriceShort) {
        int256 _maxDisplayPrice = _market.getMaxDisplayPrice();
        int256 _minDisplayPrice = _market.getMinDisplayPrice();
        int256 _orderDisplayPrice = _orders.getPrice(_orderId);
        _sharePriceRange = uint256(_maxDisplayPrice - _minDisplayPrice);
        _sharePriceLong = uint256(_orderDisplayPrice - _minDisplayPrice);
        _sharePriceShort = uint256(_maxDisplayPrice - _orderDisplayPrice);
        return (_sharePriceRange, _sharePriceLong, _sharePriceShort);
    }

    function getMakerDirection(IOrders _orders, bytes32 _orderId) private constant returns (Direction) {
        if (_orders.getTradeType(_orderId) == Trading.TradeTypes.Bid) {
            return Direction.Buying;
        } else {
            return Direction.Selling;
        }
    }

    function getTakerDirection(Direction _makerDirection) private constant returns (Direction) {
        if (_makerDirection == Direction.Buying) {
            return Direction.Selling;
        } else {
            return Direction.Buying;
        }
    }

    function getTakerSharesAvailable(IShareToken _longShareToken, IShareToken[] memory _shortShareTokens, address _taker, Direction _takerDirection, uint256 _takerSize) private constant returns (uint256) {
        // FIXME: this should actually be 2**256 - 1
        uint256 _sharesAvailable = 2**255;
        if (_takerDirection == Direction.Selling) {
            _sharesAvailable = _longShareToken.balanceOf(_taker);
        } else {
            for (uint8 _outcome = 0; _outcome < _shortShareTokens.length; ++_outcome) {
                _sharesAvailable = _shortShareTokens[_outcome].balanceOf(_taker).min(_sharesAvailable);
            }
        }
        return _sharesAvailable.min(_takerSize);
    }

    function getTakerTokensAvailable(Direction _takerDirection, uint256 _sharePriceLong, uint256 _sharePriceShort, uint256 _sharePriceRange, uint256 _takerSize, uint256 _takerSharesAvailable) private constant returns (uint256) {
        uint256 _price = 0;
        if (_takerDirection == Direction.Buying) {
            _price = _sharePriceLong;
        } else {
            _price = _sharePriceShort;
        }
        return _takerSize.sub(_takerSharesAvailable).mul(_price).div(_sharePriceRange);
    }
}


contract NewTakeBidOrder is Controlled, ITakeBidOrder {
    using SafeMathUint256 for uint256;
    using SafeMathInt256 for int256;

    function takeBidOrder(address _taker, bytes32 _orderId, IMarket _market, uint8 _outcome, uint256 _amountTakerWants, uint256 _tradeGroupId) external onlyWhitelistedCallers returns (uint256 _unfilledAmount) {
        IOrders _orders = IOrders(controller.lookup("Orders"));
        ICompleteSets _completeSets = ICompleteSets(controller.lookup("CompleteSets"));
        IShareToken _shareToken = _market.getShareToken(_outcome);
        ICash _denominationToken = _market.getDenominationToken();
        address _maker = _orders.getOrderOwner(_orderId);
        // CONSIDER: why are we checking this?  Is there a security reason for disallowing someone to take their own order?
        require(_maker != _taker);
        uint256 _orderSizeInShares = _orders.getAmount(_orderId);
        uint256 _amountLeftToFill = _amountTakerWants.min(_orderSizeInShares);
        int256 _orderDisplayPrice = _orders.getPrice(_orderId);
        uint256 _makerSharesEscrowed = _orders.getOrderSharesEscrowed(_orderId).min(_amountTakerWants);
        uint256 _sharePriceShort = uint256(_market.getMaxDisplayPrice() - _orderDisplayPrice);
        uint256 _sharePriceLong = uint256(_orderDisplayPrice - _market.getMinDisplayPrice());
        uint256 _sharePriceRange = uint256(_market.getMaxDisplayPrice() - _market.getMinDisplayPrice());
        uint8 _numberOfOutcomes = _market.getNumberOfOutcomes();

        // figure out how much of the taker's target will be leftover at the end
        _unfilledAmount = _amountTakerWants.sub(_amountLeftToFill);
        // figure out how many shares taker has available to complete this bid
        uint256 _takerSharesAvailable = _amountLeftToFill.min(_shareToken.balanceOf(_taker));
        uint256 _makerSharesDepleted = 0;
        uint256 _makerTokensDepleted = 0;
        uint256 _takerSharesDepleted = 0;
        uint256 _takerTokensDepleted = 0;

        // maker is closing a short, taker is closing a long
        if (_makerSharesEscrowed != 0 && _takerSharesAvailable != 0) {
            // figure out how many complete sets exist between the maker and taker
            uint256 _numCompleteSets = _makerSharesEscrowed.min(_takerSharesAvailable);
            // transfer the appropriate amount of shares from taker to this contract
            _shareToken.transferFrom(_taker, this, _numCompleteSets);
            // transfer the appropriate amount of shares from maker (escrowed in market) to this contract
            for (uint8 _j; _j < _numberOfOutcomes; ++_j) {
                if (_j == _outcome) {
                    continue;
                }
                IShareToken _tempShareToken = _market.getShareToken(_j);
                if (_tempShareToken.allowance(this, _completeSets) < _numCompleteSets) {
                    _tempShareToken.approve(_completeSets, 2**255);
                }
                _tempShareToken.transferFrom(_market, this, _numCompleteSets);
            }
            // sell the complete sets (this will pay fees)
            _completeSets.sellCompleteSets(this, _market, _numCompleteSets);
            // reverse engineer the fee
            uint256 _payout = _denominationToken.balanceOf(this);
            uint256 _completeSetSaleFee = _numCompleteSets - _payout;
            // maker gets their share minus proportional fee
            uint256 _shortFee = _completeSetSaleFee.mul(_sharePriceShort).div(_sharePriceRange);
            uint256 _makerShare = _numCompleteSets.mul(_sharePriceShort).sub(_shortFee);
            _denominationToken.transfer(_maker, _makerShare);
            // taker gets remainder
            uint256 _takerShare = _denominationToken.balanceOf(this);
            _denominationToken.transfer(_taker, _takerShare);
            // adjust internal accounting
            _makerSharesDepleted += _numCompleteSets;
            _makerTokensDepleted += 0;
            _takerSharesDepleted += _numCompleteSets;
            _takerTokensDepleted += 0;
            _takerSharesAvailable = _takerSharesAvailable.sub(_numCompleteSets);
            _makerSharesEscrowed = _makerSharesEscrowed.sub(_numCompleteSets);
            _amountLeftToFill = _amountLeftToFill.sub(_numCompleteSets);
        }

        //  maker is closing a short, taker is opening a short
        if (_makerSharesEscrowed != 0 &&  _amountLeftToFill != 0) {
            // transfer shares from maker (escrowed in market) to taker
            for (uint8 _k = 0; _k < _numberOfOutcomes; ++_k) {
                if (_k == _outcome) {
                    continue;
                }
                _market.getShareToken(_k).transferFrom(_market, _taker, _makerSharesEscrowed);
            }
            // transfer tokens from taker to maker
            uint256 _tokensRequiredToCoverTaker = _makerSharesEscrowed.mul(_sharePriceShort);
            _denominationToken.transferFrom(_taker, _maker, _tokensRequiredToCoverTaker);
            // adjust internal accounting
            _makerSharesDepleted += _makerSharesEscrowed;
            _makerTokensDepleted += 0;
            _takerSharesDepleted += 0;
            _takerTokensDepleted += _tokensRequiredToCoverTaker;
            _amountLeftToFill = _amountLeftToFill.sub(_makerSharesEscrowed);
            _makerSharesEscrowed = 0;
        }

        // maker is opening a long, taker is closing a long
        if (_takerSharesAvailable != 0 && _amountLeftToFill != 0) {
            // transfer shares from taker to maker
            _shareToken.transferFrom(_taker, _maker, _takerSharesAvailable);
            // transfer tokens from maker (escrowed in market) to taker
            _tokensRequiredToCoverTaker = _takerSharesAvailable.mul(_sharePriceLong);
            _denominationToken.transferFrom(_market, _taker, _tokensRequiredToCoverTaker);
            // adjust internal accounting
            _makerSharesDepleted += 0;
            _makerTokensDepleted += _tokensRequiredToCoverTaker;
            _takerSharesDepleted += _takerSharesAvailable;
            _takerTokensDepleted += 0;
            _amountLeftToFill = _amountLeftToFill.sub(_takerSharesAvailable);
            _takerSharesAvailable = 0;
        }

        // maker is opening a long, taker is opening a short
        if (_amountLeftToFill != 0) {
            // transfer tokens from both parties into this contract for complete set purchase
            uint256 _takerPortionOfCompleteSetCosts = _amountLeftToFill.mul(_sharePriceShort).div(_sharePriceRange);
            _denominationToken.transferFrom(_taker, this, _takerPortionOfCompleteSetCosts);
            uint256 _makerPortionOfCompleteSetCost = _amountLeftToFill.sub(_takerPortionOfCompleteSetCosts);
            _denominationToken.transferFrom(_market, this, _makerPortionOfCompleteSetCost);
            // buy a complete set
            if (_denominationToken.allowance(this, _completeSets) < _amountLeftToFill) {
                _denominationToken.approve(_completeSets, 2**255);
            }
            _completeSets.buyCompleteSets(this, _market, _amountLeftToFill);
            // send outcome share to maker and all other shares to taker
            _shareToken.transfer(_maker, _amountLeftToFill);
            for (uint8 _l; _l < _numberOfOutcomes; ++_l) {
                if (_l == _outcome) {
                    continue;
                }
                _market.getShareToken(_l).transfer(_taker, _amountLeftToFill);
            }
            // adjust internal accounting
            _makerSharesDepleted += 0;
            _makerTokensDepleted += _makerPortionOfCompleteSetCost;
            _takerSharesDepleted += 0;
            _takerTokensDepleted += _takerPortionOfCompleteSetCosts;
            _amountLeftToFill = 0;
        }

        _orders.takeOrderLog(_market, _outcome, Trading.TradeTypes.Bid, _orderId, _taker, _makerSharesDepleted, _makerTokensDepleted, _takerSharesDepleted, _takerTokensDepleted, _tradeGroupId);
        _orders.fillOrder(_orderId, Trading.TradeTypes.Bid, _market, _outcome, _makerSharesDepleted, _makerTokensDepleted);

        // make sure we didn't accidentally leave anything behind
        require(_denominationToken.balanceOf(this) == 0);
        for (uint8 _m = 0; _m < _numberOfOutcomes; ++_m) {
            require(_market.getShareToken(_m).balanceOf(this) == 0);
        }

        return _unfilledAmount;
    }
}
