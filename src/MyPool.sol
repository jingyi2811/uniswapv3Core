pragma solidity 0.8.15;

import "v3-periphery/contracts/libraries/OracleLibrary.sol";
import "v3-core/contracts/libraries/FullMath.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {UniswapV3OracleHelper as OracleHelper} from "./Oracle.sol";
import "./Deviation.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";
import '../src/IERC20.sol';
import "forge-std/console.sol";

contract MyPool {
    using FullMath for uint256;

    struct UniswapV3Params {
        IUniswapV3Pool pool;
        uint32 observationWindowSeconds;
        uint16 maxDeviationBps;
    }

    uint8 internal constant BASE_10_MAX_EXPONENT = 30;

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;
    uint16 internal constant DEVIATION_BASE = 10_000;

    error UniswapV3_AssetDecimalsOutOfBounds(
        address asset_,
        uint8 assetDecimals_,
        uint8 maxDecimals_
    );

    error UniswapV3_LookupTokenNotFound(address pool_, address asset_);
    error UniswapV3_OutputDecimalsOutOfBounds(uint8 outputDecimals_, uint8 maxDecimals_);
    error UniswapV3_ParamsPoolInvalid(uint8 paramsIndex_, address pool_);
    error UniswapV3_PoolTokensInvalid(address pool_, uint8 tokenIndex_, address token_);
    error UniswapV3_PoolTypeInvalid(address pool_);
    error UniswapV3_PoolReentrancy(address pool_);
    error UniswapV3_PriceMismatch(
        address pool_,
        uint256 baseInQuoteTWAP_,
        uint256 baseInQuotePrice_
    );

    address public firstAddress = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public secondAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public factoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    IUniswapV3Factory factory;
    IUniswapV3Pool public pool;

    constructor() public {
        factory = IUniswapV3Factory(factoryAddress);
        //pool = IUniswapV3Pool(factory.getPool(firstAddress, secondAddress, 3000));
        pool = IUniswapV3Pool(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8);
        console.log(address(pool));

        console.log(IERC20(firstAddress).symbol());
        console.log(IERC20(secondAddress).symbol());

    }

    function getTokenTWAP(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        UniswapV3Params memory params = abi.decode(params_, (UniswapV3Params));
        (
        address quoteToken,
        uint8 quoteTokenDecimals,
        uint8 lookupTokenDecimals
        ) = _checkPoolAndTokenParams(lookupToken_, outputDecimals_, params.pool);

        uint256 baseInQuotePrice = OracleHelper.getTWAPRatio(
            address(params.pool),
            params.observationWindowSeconds,
            lookupToken_,
            quoteToken,
            lookupTokenDecimals
        );

        uint256 quoteInUsdPrice = 1e18;
        return baseInQuotePrice.mulDiv(quoteInUsdPrice, 10 ** quoteTokenDecimals);
    }

    function getTokenPrice(
        address lookupToken_,
        uint8 outputDecimals_,
        bytes calldata params_
    ) external view returns (uint256) {
        UniswapV3Params memory params = abi.decode(params_, (UniswapV3Params));
        (
        address quoteToken,
        uint8 quoteTokenDecimals,
        uint8 lookupTokenDecimals
        ) = _checkPoolAndTokenParams(lookupToken_, outputDecimals_, params.pool);

        uint256 baseInQuoteTWAP = OracleHelper.getTWAPRatio(
            address(params.pool),
            params.observationWindowSeconds,
            lookupToken_,
            quoteToken,
            lookupTokenDecimals
        );

        (, int24 currentTick, , , , , bool unlocked) = params.pool.slot0();
        if (unlocked == false) revert UniswapV3_PoolReentrancy(address(params.pool));

        uint256 baseInQuotePrice = OracleLibrary.getQuoteAtTick(
            currentTick,
            uint128(10 ** lookupTokenDecimals),
            lookupToken_,
            quoteToken
        );

        if (
            Deviation.isDeviatingWithBpsCheck(
                baseInQuotePrice,
                baseInQuoteTWAP,
                params.maxDeviationBps,
                DEVIATION_BASE
            )
        ) {
            revert UniswapV3_PriceMismatch(address(params.pool), baseInQuoteTWAP, baseInQuotePrice);
        }

        uint quoteInUsdPrice = 1e18;
        return baseInQuotePrice.mulDiv(quoteInUsdPrice, 10 ** quoteTokenDecimals);
    }

    function _checkPoolAndTokenParams(
        address lookupToken_,
        uint8 outputDecimals_,
        IUniswapV3Pool pool_
    ) internal view returns (address, uint8, uint8) {
        if (address(pool_) == address(0)) revert UniswapV3_ParamsPoolInvalid(0, address(pool_));

        try pool_.slot0() returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
            // Do nothing
        } catch (bytes memory) {
            // Handle a non-UniswapV3 pool
            revert UniswapV3_PoolTypeInvalid(address(pool_));
        }

        address quoteToken;
        {
            bool lookupTokenFound;
            try pool_.token0() returns (address token) {
                if (token == address(0))
                    revert UniswapV3_PoolTokensInvalid(address(pool_), 0, token);

                if (token == lookupToken_) {
                    lookupTokenFound = true;
                } else {
                    quoteToken = token;
                }
            } catch (bytes memory) {
                // Handle a non-UniswapV3 pool
                revert UniswapV3_PoolTypeInvalid(address(pool_));
            }
            try pool_.token1() returns (address token) {
                // Check if token is zero address, revert if so
                if (token == address(0))
                    revert UniswapV3_PoolTokensInvalid(address(pool_), 1, token);

                if (token == lookupToken_) {
                    lookupTokenFound = true;
                } else {
                    quoteToken = token;
                }
            } catch (bytes memory) {
                // Handle a non-UniswapV3 pool
                revert UniswapV3_PoolTypeInvalid(address(pool_));
            }

            // If lookup token wasn't found, revert
            if (!lookupTokenFound)
                revert UniswapV3_LookupTokenNotFound(address(pool_), lookupToken_);
        }

        // Validate output decimals are not too high
        if (outputDecimals_ > BASE_10_MAX_EXPONENT)
            revert UniswapV3_OutputDecimalsOutOfBounds(outputDecimals_, BASE_10_MAX_EXPONENT);

        uint8 quoteTokenDecimals = ERC20(quoteToken).decimals();
        uint8 lookupTokenDecimals = ERC20(lookupToken_).decimals();

        // Avoid overflows with decimal normalisation
        if (quoteTokenDecimals > BASE_10_MAX_EXPONENT)
            revert UniswapV3_AssetDecimalsOutOfBounds(
                quoteToken,
                quoteTokenDecimals,
                BASE_10_MAX_EXPONENT
            );

        // lookupTokenDecimals must be less than 38 to avoid overflow when cast to uint128
        // BASE_10_MAX_EXPONENT is less than 38, so this check is safe
        if (lookupTokenDecimals > BASE_10_MAX_EXPONENT)
            revert UniswapV3_AssetDecimalsOutOfBounds(
                lookupToken_,
                lookupTokenDecimals,
                BASE_10_MAX_EXPONENT
            );

        return (quoteToken, quoteTokenDecimals, lookupTokenDecimals);
    }

    uint32 internal constant TWAP_MIN_OBSERVATION_WINDOW = 19; // seconds

    error UniswapV3OracleHelper_ObservationTooShort(
        address pool_,
        uint32 observationWindow_,
        uint32 minObservationWindow_
    );

    error UniswapV3OracleHelper_InvalidObservation(address pool_, uint32 observationWindow_);

    error UniswapV3OracleHelper_TickOutOfBounds(
        address pool_,
        int56 timeWeightedTick_,
        int24 minTick_,
        int24 maxTick_
    );

    function getTimeWeightedTick(address pool_, uint32 period_) public view returns (int56) {
        //IUniswapV3Pool pool = IUniswapV3Pool(pool_);

        // Ensure the observation window is long enough
//        if (period_ < TWAP_MIN_OBSERVATION_WINDOW)
//            revert UniswapV3OracleHelper_ObservationTooShort(
//                pool_,
//                period_,
//                TWAP_MIN_OBSERVATION_WINDOW
//            );

        // Get tick and liquidity from the TWAP
        uint32[] memory observationWindow = new uint32[](2);
        observationWindow[0] = period_;
        observationWindow[1] = 0;

        int56 timeWeightedTick;
        try pool.observe(observationWindow) returns (
            int56[] memory tickCumulatives,
            uint160[] memory
        ) {
            timeWeightedTick = (tickCumulatives[1] - tickCumulatives[0]) / int32(period_);
        } catch (bytes memory) {
            // This function will revert if the observation window is longer than the oldest observation in the pool
            // https://github.com/Uniswap/v3-core/blob/d8b1c635c275d2a9450bd6a78f3fa2484fef73eb/contracts/libraries/Oracle.sol#L226C30-L226C30
            revert UniswapV3OracleHelper_InvalidObservation(pool_, period_);
        }

        // Ensure the time-weighted tick is within the bounds of permissible ticks
        // Otherwise getQuoteAtTick will revert: https://docs.uniswap.org/contracts/v3/reference/error-codes
        if (timeWeightedTick > TickMath.MAX_TICK || timeWeightedTick < TickMath.MIN_TICK)
            revert UniswapV3OracleHelper_TickOutOfBounds(
                pool_,
                timeWeightedTick,
                TickMath.MIN_TICK,
                TickMath.MAX_TICK
            );

        return timeWeightedTick;
    }
}
