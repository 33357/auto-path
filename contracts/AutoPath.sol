//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "./interfaces/IUniswapV3Factory.sol";
import "./interfaces/IQuoter.sol";

contract AutoPath {
    address[] public TokenList = [
        0xdAC17F958D2ee523a2206206994597C13D831ec7,
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
        0x4Fabb145d64652a948d72533023f6E7A623C7C53,
        0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
        0x6B175474E89094C44Da98b954EedeAC495271d0F,
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ];

    uint24[4] public FeeList = [100, 500, 3000, 10000];

    uint256 public constant maxTokenLength = 10;

    IUniswapV3Factory public UniswapV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    IQuoter public Quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    constructor() {}

    /* ================ UTIL FUNCTIONS ================ */

    /* ================ VIEW FUNCTIONS ================ */

    /* ================ TRANSACTION FUNCTIONS ================ */

    function getPathquoteExactInput(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    )
        public
        returns (
            address[maxTokenLength + 2] memory pathList,
            uint24[maxTokenLength + 1] memory feeList,
            uint256 amountOutMax
        )
    {
        (uint24 singleFee, uint256 singleAmountOutMax) = getAmountOutMax(tokenIn, tokenOut, amountIn);
        (
            address[maxTokenLength + 2][] memory pathListArray,
            uint24[maxTokenLength + 1][] memory feeListArray,
            uint256[] memory amountOutMaxTokenList
        ) = getAmountOutTokenMax(tokenIn, amountIn);
        (pathListArray, feeListArray, amountOutMaxTokenList) = getAmountOutTokenMaxPath(
            pathListArray,
            feeListArray,
            amountOutMaxTokenList
        );
        (pathList, feeList, amountOutMax) = getAmountOutMaxPath(
            tokenIn,
            tokenOut,
            singleFee,
            singleAmountOutMax,
            pathListArray,
            feeListArray,
            amountOutMaxTokenList
        );
    }

    function getAmountOutTokenMax(address tokenIn, uint256 amountIn)
        public
        returns (
            address[maxTokenLength + 2][] memory pathListArray,
            uint24[maxTokenLength + 1][] memory feeListArray,
            uint256[] memory amountOutMaxTokenList
        )
    {
        pathListArray = new address[maxTokenLength + 2][](TokenList.length);
        feeListArray = new uint24[maxTokenLength + 1][](TokenList.length);
        amountOutMaxTokenList = new uint256[](TokenList.length);
        for (uint256 i = 0; i < TokenList.length; i++) {
            pathListArray[i][0] = tokenIn;
            pathListArray[i][1] = TokenList[i];
            (feeListArray[i][0], amountOutMaxTokenList[i]) = getAmountOutMax(tokenIn, TokenList[i], amountIn);
        }
    }

    function getAmountOutMaxPath(
        address tokenIn,
        address tokenOut,
        uint24 singleFee,
        uint256 singleAmountOutMax,
        address[maxTokenLength + 2][] memory pathListArray,
        uint24[maxTokenLength + 1][] memory feeListArray,
        uint256[] memory amountOutMaxTokenList
    )
        public
        returns (
            address[maxTokenLength + 2] memory pathList,
            uint24[maxTokenLength + 1] memory feeList,
            uint256 amountOutMax
        )
    {
        pathList = [
            tokenIn,
            tokenOut,
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        ];
        feeList = [singleFee, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        amountOutMax = singleAmountOutMax;
        for (uint256 i = 0; i < TokenList.length; i++) {
            (uint24 fee, uint256 muxAmountOutMax) = getAmountOutMax(TokenList[i], tokenOut, amountOutMaxTokenList[i]);
            if (muxAmountOutMax > amountOutMax) {
                amountOutMax = muxAmountOutMax;
                pathList = pathListArray[i];
                for (uint256 j = 0; j < pathList.length; j++) {
                    if (pathList[j] == address(0)) {
                        pathList[j] = tokenOut;
                        break;
                    }
                }
                feeList = feeListArray[i];
                for (uint256 j = 0; j < feeList.length; j++) {
                    if (feeList[j] == 0) {
                        feeList[j] = fee;
                        break;
                    }
                }
            }
        }
    }

    function getAmountOutTokenMaxPath(
        address[maxTokenLength + 2][] memory pathListArray,
        uint24[maxTokenLength + 1][] memory feeListArray,
        uint256[] memory amountOutMaxTokenList
    )
        public
        returns (
            address[maxTokenLength + 2][] memory,
            uint24[maxTokenLength + 1][] memory,
            uint256[] memory
        )
    {
        for (uint256 i = 0; i < TokenList.length; i++) {
            for (uint256 j = 0; j < TokenList.length; j++) {
                if (i != j) {
                    (uint24 fee, uint256 amountOutMaxToken) = getAmountOutMax(
                        TokenList[j],
                        TokenList[i],
                        amountOutMaxTokenList[j]
                    );
                    if (amountOutMaxToken > amountOutMaxTokenList[i]) {
                        amountOutMaxTokenList[i] = amountOutMaxToken;
                        pathListArray[i] = pathListArray[j];
                        feeListArray[i] = feeListArray[j];
                        for (uint256 k = 0; k < pathListArray[i].length; k++) {
                            if (feeListArray[i][k] == 0) {
                                feeListArray[i][k] = fee;
                                pathListArray[i][k + 1] = TokenList[j];
                                break;
                            }
                        }
                    }
                }
            }
        }
        return (pathListArray, feeListArray, amountOutMaxTokenList);
    }

    function getAmountOutMax(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public returns (uint24 fee, uint256 amountOutMax) {
        for (uint256 i = 0; i < FeeList.length; i++) {
            if (UniswapV3Factory.getPool(tokenIn, tokenOut, FeeList[i]) != address(0)) {
                uint256 amountOut = Quoter.quoteExactInputSingle(tokenIn, tokenOut, FeeList[i], amountIn, 0);
                if (amountOut > amountOutMax) {
                    amountOutMax = amountOut;
                    fee = FeeList[i];
                }
            }
        }
    }

    /* ================ ADMIN FUNCTIONS ================ */
}
