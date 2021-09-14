pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

///@title A simplified Uniswap-V1 exchange in Solidity
///@author Varun Vasudevan
contract Uniswap is ERC20{

    using SafeMath for uint256;
    

    //These are the events that are emitted after a write function is called
    event TokenPurchase(address indexed buyer, uint256 indexed eth_sold, uint256 indexed tokens_bought);
    event EthPurchase(address indexed buyer, uint256 indexed eth_bought, uint256 indexed tokens_sold);
    event AddLiquidity(address indexed provider, uint256 indexed eth_amount, uint256 indexed token_amount);
    event RemoveLiquidity(address indexed provider, uint256 indexed eth_amount, uint256 indexed token_amount);
    

    ///@notice This is the token that ETH will be exchanged with
    ERC20 public token;

    /**
     * @notice Creates an exchange based on an ERC20 token
     * @dev In this contract, UNI is the LP token 
     * @param token_address The address of the ERC20 token that the exchange is based on
     */
    constructor(address token_address) public ERC20("Uniswap", "UNI") {
        require(token_address != address(0), "the token address cannot be null");
        
        //initialize token
        token = ERC20(token_address);
    }

    /**
     *@notice getTokenReserve() returns the Token balance of this contract
     */
    function getTokenReserve() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice addLiquidity lets the user provide a liquidity pool between ETH and any Token. 
     * @dev The user gets rewarded with LP tokens for providing liquidity.
     * @param amount_tokens The amount of Tokens to provide liquidity with.
     */

    function addLiquidity(uint256 amount_tokens) public payable returns(uint256){
        uint256 tokenReserve = getTokenReserve();
       
        if(tokenReserve >0){
            //You need to subtract msg.value from this contract's balance to get the ETH reserve
            uint256 ethReserve = address(this).balance.sub(msg.value);

            //The token amount needed is calculated by multiplying the msg.value and token reserve values, and dividing by the ETH reserve 
            uint256 token_amount_needed = (msg.value.mul(tokenReserve)).div((ethReserve));

            //amount_tokens must be greater than token_amount_needed
            require(amount_tokens > token_amount_needed, "The token amount is insufficient");

            //Transfers tokens from the user to the contract
            token.transferFrom(msg.sender, address(this), amount_tokens);

            //If there are tokens in the reserve, then the LP tokens are proportional to the amount of ETH in the reserve
            uint256 liquidity_tokens = (msg.value.mul(totalSupply())).div(ethReserve);

            //Minting liquidity tokens to the sender
            _mint(msg.sender, liquidity_tokens);

            //Emit event
            emit AddLiquidity(msg.sender, msg.value, amount_tokens);

            //Returns the LP tokens
            return liquidity_tokens;   
        }
        else{
            require(tokenReserve == 0);
            //Transfer tokens from the user to the Uniswap contract
            token.transferFrom(msg.sender, address(this), amount_tokens);
            
            //When the tokenReserve is 0, the liquidity tokens minted is == the ETH that is paid into the contract
            uint256 liquidity_tokens = address(this).balance;

            //Minting liquidity tokens to sender
            _mint(msg.sender, liquidity_tokens);
            
            //Emit event
            emit AddLiquidity(msg.sender, msg.value, amount_tokens);

            //Returns the liquidity tokens minted
            return liquidity_tokens;
        }

    }

    /**
     * @notice removeLiquidity lets the user remove their liquidity pool between ETH and a Token 
     * @dev The user specifies the amount of LP tokens to remove
     * @param liquidity_to_remove The amount of LP tokens to remove
     */
    function removeLiquidity(uint256 liquidity_to_remove) public returns(uint256,uint256){
        require(liquidity_to_remove > 0, "You can't remove 0 liquidity");
        require(totalSupply() > 0, "The total supply of LP tokens must be > 0");

        uint256 tokenReserve = getTokenReserve();

        //The eth_amount to remove is the (contract's ETH balance * LP tokens input) / (total supply of LP tokens)
        uint256 eth_amount = (address(this).balance.mul(liquidity_to_remove)).div(totalSupply());

        //The token_amount to remove is the (contract's token balance * LP tokens input) / (total supply of LP tokens)
        uint256 token_amount = (tokenReserve.mul(liquidity_to_remove)).div(totalSupply());

        //Burns the LP tokens
        _burn(msg.sender, liquidity_to_remove);

        //Transfer the ETH and Tokens from the liquidity pool to the sender
        payable(msg.sender).transfer(eth_amount);
        token.transfer(msg.sender, token_amount);

        //Emit event
        emit RemoveLiquidity(msg.sender, eth_amount, token_amount);
        
        //Return the eth and token amounts
        return (eth_amount, token_amount);

    }


    /**
     * @notice returns the price of the Token when converting ETH
     * @param eth_to_sell The amount of ETH to convert
     */
    function getEthToTokenPrice(uint256 eth_to_sell) public view returns (uint256) {
        require(eth_to_sell > 0, "You can't sell ETH that is 0 or negative");

        uint256 tokenReserve = getTokenReserve();

        //Returns the Token price calculated with the 3 parameters
        return getPrice(eth_to_sell, address(this).balance, tokenReserve);
    }

    /**
     * @notice returns the price of ETH when converting Tokens
     * @param tokens_to_sell The amount of Tokens to convert
     */
    function getTokenToEthPrice(uint256 tokens_to_sell) public view returns (uint256) {
        require(tokens_to_sell > 0, "You can't sell a token amount that is 0 or negative");

        uint256 tokenReserve = getTokenReserve();

        //Returns the ETH price calculated with the 3 parameters
        return getPrice(tokens_to_sell, tokenReserve, address(this).balance);
    }

    /**
     * @notice Swaps ETH to Tokens
     * @param min_tokens The amount of Tokens user would like to buy
     *        Would ideally be the result of getEthToTokenPrice function
     */
    function swapEthToTokens(uint256 min_tokens) public payable {
        uint256 tokenReserve = getTokenReserve();

        //Calculates the tokens to be bought using the getPrice function
        //msg.value is subtracted since it is added to the balance when the function is initially called
        uint256 tokensBought = getPrice(
            msg.value,
            address(this).balance.sub(msg.value),
            tokenReserve
        );
        //tokensBought can't be less than min_tokens
        require(tokensBought >= min_tokens, "min_tokens input is too large");

        //transfers tokens to the sender
        token.transfer(msg.sender, tokensBought);

        //Emit event
        emit TokenPurchase(msg.sender, msg.value, tokensBought);
    }

    /**
     * @notice Swaps Tokens to ETH
     * @param tokens_to_sell The amount of tokens the user would like to sell
     * @param min_eth The amount of ETH the user would like to buy
     *        Would ideally be the result of getTokenToEthPrice function
     */
    function swapTokensToEth(uint256 tokens_to_sell, uint256 min_eth) public {
        uint256 tokenReserve = getTokenReserve();

        //Calculates the ETH to be bought using the getPrice function
        uint256 ethBought = getPrice(
            tokens_to_sell,
            tokenReserve,
            address(this).balance
        );

        //ethBought can't be less than min_eth
        require(ethBought >= min_eth, "min_eth input is too large");

        //Transfers token from user to the contract
        token.transferFrom(
            msg.sender,
            address(this),
            tokens_to_sell
        );

        //Pays the user for the tokens sold
        payable(msg.sender).transfer(ethBought);

        //Emit event
        emit EthPurchase(msg.sender, ethBought, tokens_to_sell);
    }


    /**
     * @dev This function gets the price of either ETH or a Token in relation to the other
     * @param inputAmount the amount of either ETH or Tokens to be inputted
     * @param inputReserve the reserve of the input that the contract has stored
     * @param outputReserve the reserve of the output that the contract has stored
     */
    function getPrice(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve
    ) private pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "Reserves must be greater than 0");

        //Calculates a 0.3% fee to incentivize liquidity providers to pool their tokens
        uint256 inputAmountWithFee = inputAmount * 997;

        uint256 numerator = inputAmountWithFee * outputReserve;

        //Input reserve is multiplied by 1000 in order to balance out the numerator
        uint256 denominator = (inputReserve * 1000) + inputAmountWithFee;

        //calculated based on the constant product formula: x * y = k
        return numerator / denominator;
    }


}
