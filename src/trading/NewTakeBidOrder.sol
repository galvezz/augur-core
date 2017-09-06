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


library Trade {
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
        uint8 outcome;
        address maker;
        address taker;
        uint256 sharePriceRange;
        uint256 sharePriceLong;
        uint256 sharePriceShort;
        uint256 originalMakerSharesToSell;
        uint256 originalMakerSharesToBuy;
        uint256 originalTakerSharesToSell;
        uint256 originalTakerSharesToBuy;

        // maker
        Direction makerDirection;
        uint256 makerSharesToSell;
        uint256 makerSharesToBuy;

        // taker
        Direction takerDirection;
        uint256 takerSharesToSell;
        uint256 takerSharesToBuy;
    }

    //
    // Constructor
    //

    function create(IController _controller, bytes32 _orderId, address _taker, uint256 _takerSize) internal returns (Data) {
        // TODO: data validation
        IOrders _orders = IOrders(_controller.lookup("Orders"));
        IMarket _market = _orders.getMarket(_orderId);
        var (_longShareToken, _shortShareTokens, _outcome) = getShareTokens(_orders, _market, _orderId);
        uint256 _sharesEscrowed = _orders.getOrderSharesEscrowed(_orderId);
        var (_makerDirection, _takerDirection) = getDirections(_orders, _orderId);
        uint256 _makerSize = _orders.getAmount(_orderId);
        var (_sharePriceRange, _sharePriceLong, _sharePriceShort) = getSharePriceDetails(_market, _orders, _orderId);
        uint256 _takerSharesToSell = getTakerSharesToSell(_longShareToken, _shortShareTokens, _taker, _takerDirection, _takerSize);

        return Data({
            orders: _orders,
            market: _market,
            completeSets: ICompleteSets(_controller.lookup("CompleteSets")),
            denominationToken: _market.getDenominationToken(),
            longShareToken: _longShareToken,
            shortShareTokens: _shortShareTokens,
            orderId: _orderId,
            outcome: _outcome,
            maker: _orders.getOrderOwner(_orderId),
            taker: _taker,
            sharePriceRange: _sharePriceRange,
            sharePriceLong: _sharePriceLong,
            sharePriceShort: _sharePriceShort,
            originalMakerSharesToSell: _sharesEscrowed,
            originalMakerSharesToBuy: _makerSize.sub(_sharesEscrowed),
            originalTakerSharesToSell: _takerSharesToSell,
            originalTakerSharesToBuy: _takerSize.sub(_takerSharesToSell),
            makerDirection: _makerDirection,
            makerSharesToSell: _sharesEscrowed,
            makerSharesToBuy: _makerSize.sub(_sharesEscrowed),
            takerDirection: _takerDirection,
            takerSharesToSell: _takerSharesToSell,
            takerSharesToBuy: _takerSize.sub(_takerSharesToSell)
        });
    }

    //
    // "public" functions
    //

    function tradeMakerSharesForTakerShares(Data _data) internal returns (bool) {
        uint256 _numberOfCompleteSets = _data.makerSharesToSell.min(_data.takerSharesToSell);
        if (_numberOfCompleteSets == 0) {
            return true;
        }

        // transfer shares to this contract from each participant
        address _longSeller = getLongShareSeller(_data);
        address _shortSeller = getShortShareSeller(_data);
        _data.longShareToken.transferFrom(_longSeller, this, _numberOfCompleteSets);
        for (uint8 _i = 0; _i < _data.shortShareTokens.length; ++_i) {
            _data.shortShareTokens[_i].transferFrom(_shortSeller, this, _numberOfCompleteSets);
        }

        // sell complete sets
        _data.completeSets.sellCompleteSets(this, _data.market, _numberOfCompleteSets);

        // distribute payout proportionately (fees will have been deducted)
        uint256 _payout = _data.denominationToken.balanceOf(this);
        uint256 _longShare = _payout.mul(_data.sharePriceLong).div(_data.sharePriceRange);
        uint256 _shortShare = _payout.sub(_longShare);
        _data.denominationToken.transfer(getLongShareSeller(_data), _longShare);
        _data.denominationToken.transfer(getShortShareSeller(_data), _shortShare);

        // update available shares for maker and taker
        _data.makerSharesToSell -= _numberOfCompleteSets;
        _data.takerSharesToSell -= _numberOfCompleteSets;
    }

    function tradeMakerSharesForTakerTokens(Data _data) internal returns (bool) {
        uint256 _numberOfSharesToTrade = _data.makerSharesToSell.min(_data.takerSharesToBuy);
        if (_numberOfSharesToTrade == 0) {
            return true;
        }

        // transfer shares from maker to taker
        if (_data.makerDirection == Direction.Selling) {
            _data.longShareToken.transferFrom(_data.maker, _data.taker, _numberOfSharesToTrade);
        } else {
            for (uint8 _i = 0; _i < _data.shortShareTokens.length; ++_i) {
                _data.shortShareTokens[_i].transferFrom(_data.maker, _data.taker, _numberOfSharesToTrade);
            }
        }

        // transfer tokens from taker to maker
        uint256 _tokensToCover = getTokensToCover(_data, _data.takerDirection, _numberOfSharesToTrade);
        _data.denominationToken.transferFrom(_data.taker, _data.maker, _tokensToCover);

        // update available assets for maker and taker
        _data.makerSharesToSell -= _numberOfSharesToTrade;
        _data.takerSharesToBuy -= _numberOfSharesToTrade;
    }

    function tradeMakerTokensForTakerShares(Data _data) internal returns (bool) {
        uint256 _numberOfSharesToTrade = _data.takerSharesToSell.min(_data.makerSharesToBuy);
        if (_numberOfSharesToTrade == 0) {
            return true;
        }

        // transfer shares from taker to maker
        if (_data.takerDirection == Direction.Selling) {
            _data.longShareToken.transferFrom(_data.taker, _data.maker, _numberOfSharesToTrade);
        } else {
            for (uint8 _i = 0; _i < _data.shortShareTokens.length; ++_i) {
                _data.shortShareTokens[_i].transferFrom(_data.taker, _data.maker, _numberOfSharesToTrade);
            }
        }

        // transfer tokens from taker to maker
        uint256 _tokensToCover = getTokensToCover(_data, _data.makerDirection, _numberOfSharesToTrade);
        _data.denominationToken.transferFrom(_data.maker, _data.taker, _tokensToCover);

        // update available assets for maker and taker
        _data.makerSharesToBuy -= _numberOfSharesToTrade;
        _data.takerSharesToSell -= _numberOfSharesToTrade;
    }

    function tradeMakerTokensForTakerTokens(Data _data) internal returns (bool) {
        uint256 _numberOfCompleteSets = _data.makerSharesToBuy.min(_data.takerSharesToBuy);
        if (_numberOfCompleteSets == 0) {
            return true;
        }

        // transfer tokens to this contract
        uint256 _makerTokensToCover = getTokensToCover(_data, _data.makerDirection, _numberOfCompleteSets);
        uint256 _takerTokensToCover = getTokensToCover(_data, _data.takerDirection, _numberOfCompleteSets);
        _data.denominationToken.transferFrom(_data.maker, this, _makerTokensToCover);
        _data.denominationToken.transferFrom(_data.taker, this, _takerTokensToCover);

        // buy complete sets
        if (_data.denominationToken.allowance(this, _data.completeSets) < _numberOfCompleteSets) {
            _data.denominationToken.approve(_data.completeSets, _numberOfCompleteSets);
        }
        _data.completeSets.buyCompleteSets(this, _data.market, _numberOfCompleteSets);

        // distribute shares to participants
        address _longBuyer = getLongShareBuyer(_data);
        address _shortBuyer = getShortShareBuyer(_data);
        _data.longShareToken.transfer(_longBuyer, _numberOfCompleteSets);
        for (uint8 _i = 0; _i < _data.shortShareTokens.length; ++_i) {
            _data.shortShareTokens[_i].transfer(_shortBuyer, _numberOfCompleteSets);
        }

        // update available shares for maker and taker
        _data.makerSharesToBuy -= _numberOfCompleteSets;
        _data.takerSharesToBuy -= _numberOfCompleteSets;
    }

    //
    // Helpers
    //

    function getLongShareBuyer(Data _data) internal constant returns (address) {
        if (_data.makerDirection == Direction.Buying) {
            return _data.maker;
        } else {
            return _data.taker;
        }
    }

    function getShortShareBuyer(Data _data) internal constant returns (address) {
        if (_data.makerDirection == Direction.Selling) {
            return _data.maker;
        } else {
            return _data.taker;
        }
    }

    function getLongShareSeller(Data _data) internal constant returns (address) {
        if (_data.makerDirection == Direction.Buying) {
            return _data.taker;
        } else {
            return _data.maker;
        }
    }

    function getShortShareSeller(Data _data) internal constant returns (address) {
        if (_data.makerDirection == Direction.Selling) {
            return _data.taker;
        } else {
            return _data.maker;
        }
    }

    function getMakerSharesDepleted(Data _data) internal constant returns (uint256) {
        return _data.originalMakerSharesToSell.sub(_data.makerSharesToSell);
    }

    function getTakerSharesDepleted(Data _data) internal constant returns (uint256) {
        return _data.originalTakerSharesToSell.sub(_data.takerSharesToSell);
    }

    function getMakerTokensDepleted(Data _data) internal constant returns (uint256) {
        return getTokensDepleted(_data, _data.makerDirection, _data.originalMakerSharesToBuy, _data.makerSharesToBuy);
    }

    function getTakerTokensDepleted(Data _data) internal constant returns (uint256) {
        return getTokensDepleted(_data, _data.takerDirection, _data.originalTakerSharesToBuy, _data.takerSharesToBuy);
    }

    function getTokensDepleted(Data _data, Direction _direction, uint256 _startingSharesToBuy, uint256 _endingSharesToBuy) internal constant returns (uint256) {
        if (_direction == Direction.Buying) {
            return _startingSharesToBuy.sub(_endingSharesToBuy).mul(_data.sharePriceLong).div(_data.sharePriceRange);
        } else {
            return _startingSharesToBuy.sub(_endingSharesToBuy).mul(_data.sharePriceShort).div(_data.sharePriceRange);
        }
    }

    function getTokensToCover(Data _data, Direction _direction, uint256 _numShares) internal constant returns (uint256) {
        return getTokensToCover(_direction, _data.sharePriceRange, _data.sharePriceLong, _data.sharePriceShort, _numShares);
    }

    //
    // Construction helpers
    //

    function getTokensToCover(Direction _direction, uint256 _sharePriceRange, uint256 _sharePriceLong, uint256 _sharePriceShort, uint256 _numShares) internal constant returns (uint256) {
        if (_direction == Direction.Buying) {
            return _numShares.mul(_sharePriceLong).div(_sharePriceRange);
        } else {
            return _numShares.mul(_sharePriceShort).div(_sharePriceRange);
        }
    }

    function getShareTokens(IOrders _orders, IMarket _market, bytes32 _orderId) private constant returns (IShareToken _longShareToken, IShareToken[] memory _shortShareTokens, uint8 _outcome) {
        _outcome = _orders.getOutcome(_orderId);
        _longShareToken = _market.getShareToken(_outcome);
        _shortShareTokens = getShortShareTokens(_market, _outcome);
        return (_longShareToken, _shortShareTokens, _outcome);
    }

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

    function getDirections(IOrders _orders, bytes32 _orderId) private constant returns (Direction _makerDirection, Direction _takerDirection) {
        if (_orders.getTradeType(_orderId) == Trading.TradeTypes.Bid) {
            return (Direction.Buying, Direction.Selling);
        } else {
            return (Direction.Selling, Direction.Buying);
        }
    }

    function getTakerSharesToSell(IShareToken _longShareToken, IShareToken[] memory _shortShareTokens, address _taker, Direction _takerDirection, uint256 _takerSize) private constant returns (uint256) {
        uint256 _sharesAvailable = 2**256-1;
        if (_takerDirection == Direction.Selling) {
            _sharesAvailable = _longShareToken.balanceOf(_taker);
        } else {
            for (uint8 _outcome = 0; _outcome < _shortShareTokens.length; ++_outcome) {
                _sharesAvailable = _shortShareTokens[_outcome].balanceOf(_taker).min(_sharesAvailable);
            }
        }
        return _sharesAvailable.min(_takerSize);
    }
}


library DirectionExtensions {
    function toTradeType(Trade.Direction _direction) internal constant returns (Trading.TradeTypes) {
        if (_direction == Trade.Direction.Buying) {
            return Trading.TradeTypes.Bid;
        } else {
            return Trading.TradeTypes.Ask;
        }
    }
}


contract NewTakeBidOrder is Controlled, ITakeBidOrder {
    using SafeMathUint256 for uint256;
    using Trade for Trade.Data;
    using DirectionExtensions for Trade.Direction;

    function takeBidOrder(address _taker, bytes32 _orderId, IMarket _market, uint256 _amountTakerWants, uint256 _tradeGroupId) external onlyWhitelistedCallers returns (uint256) {
        Trade.Data memory _tradeData = Trade.create(controller, _orderId, _taker, _amountTakerWants);
        _tradeData.tradeMakerSharesForTakerShares();
        _tradeData.tradeMakerSharesForTakerTokens();
        _tradeData.tradeMakerTokensForTakerShares();
        _tradeData.tradeMakerTokensForTakerTokens();

        // AUDIT: is there a reentry risk here?  we executing all of the above code, which includes transferring tokens around, before we mark the order as willed
        _tradeData.orders.fillOrder(_orderId, _tradeData.makerDirection.toTradeType(), _market, _tradeData.outcome, _tradeData.getMakerSharesDepleted(), _tradeData.getMakerTokensDepleted());
        _tradeData.orders.takeOrderLog(_tradeData.market, _tradeData.outcome, _tradeData.makerDirection.toTradeType(), _tradeData.orderId, _tradeData.taker, _tradeData.getMakerSharesDepleted(), _tradeData.getMakerTokensDepleted(), _tradeData.getTakerSharesDepleted(), _tradeData.getTakerTokensDepleted(), _tradeGroupId);

        return _tradeData.takerSharesToSell.add(_tradeData.takerSharesToBuy);
    }
}
